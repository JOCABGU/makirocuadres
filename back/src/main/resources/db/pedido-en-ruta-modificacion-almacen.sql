USE BDAlmacenTarija_Prueba;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF COL_LENGTH(N'dbo.tbl_PedidoVendedor_EnRuta', N'ModificadoPorAlmacen') IS NULL
BEGIN
    ALTER TABLE dbo.tbl_PedidoVendedor_EnRuta
    ADD ModificadoPorAlmacen INT NOT NULL
        CONSTRAINT DF_PedidoVendedor_EnRuta_ModificadoPorAlmacen DEFAULT (2) WITH VALUES;
END;
GO

IF COL_LENGTH(N'dbo.tbl_PedidoVendedor_EnRuta', N'ComentarioAlmacen') IS NULL
BEGIN
    ALTER TABLE dbo.tbl_PedidoVendedor_EnRuta
    ADD ComentarioAlmacen VARCHAR(250) NOT NULL
        CONSTRAINT DF_PedidoVendedor_EnRuta_ComentarioAlmacen DEFAULT ('') WITH VALUES;
END;
GO

IF COL_LENGTH(N'dbo.tbl_PedidoVendedor_EnRuta', N'FechaModificacionAlmacen') IS NULL
BEGIN
    ALTER TABLE dbo.tbl_PedidoVendedor_EnRuta
    ADD FechaModificacionAlmacen DATETIME NULL;
END;
GO

IF OBJECT_ID(N'dbo.spj_LoginGeneral_Almacen_ModificarPedido', N'P') IS NULL
BEGIN
    EXEC(N'CREATE PROCEDURE dbo.spj_LoginGeneral_Almacen_ModificarPedido AS BEGIN SET NOCOUNT ON; END');
END;
GO

ALTER PROCEDURE dbo.spj_LoginGeneral_Almacen_ModificarPedido
    @IdPedido INT,
    @IdUsuarioAlmacenero INT,
    @ComentarioAlmacen VARCHAR(250),
    @Detalle XML
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET ARITHABORT ON;

    SET @ComentarioAlmacen = NULLIF(LTRIM(RTRIM(@ComentarioAlmacen)), '');
    IF @ComentarioAlmacen IS NULL
    BEGIN
        RAISERROR('Debe ingresar el motivo de la modificacion.', 16, 1);
        RETURN;
    END;

    DECLARE @Cambios TABLE
    (
        IdDetalle INT NOT NULL,
        Cantidad INT NOT NULL
    );

    INSERT INTO @Cambios (IdDetalle, Cantidad)
    SELECT
        T.Item.value('@idDetalle', 'INT'),
        T.Item.value('@cantidad', 'INT')
    FROM @Detalle.nodes('/detalles/item') AS T(Item);

    IF NOT EXISTS (SELECT 1 FROM @Cambios)
    BEGIN
        RAISERROR('Debe enviar el detalle completo del pedido.', 16, 1);
        RETURN;
    END;

    IF EXISTS (SELECT 1 FROM @Cambios WHERE Cantidad < 0)
    BEGIN
        RAISERROR('Las cantidades modificadas no pueden ser negativas.', 16, 1);
        RETURN;
    END;

    IF NOT EXISTS (SELECT 1 FROM @Cambios WHERE Cantidad > 0)
    BEGIN
        RAISERROR('El pedido debe conservar al menos un producto.', 16, 1);
        RETURN;
    END;

    IF EXISTS (SELECT IdDetalle FROM @Cambios GROUP BY IdDetalle HAVING COUNT(*) > 1)
    BEGIN
        RAISERROR('El detalle contiene productos repetidos.', 16, 1);
        RETURN;
    END;

    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE @EstadoAprobado INT;
        SELECT @EstadoAprobado = E_Aprobado
        FROM dbo.tbl_PedidoVendedor_EnRuta WITH (UPDLOCK, HOLDLOCK)
        WHERE Id_PedidoVendedor_EnRuta = @IdPedido
          AND E_Eliminado = 2;

        IF @EstadoAprobado IS NULL
        BEGIN
            RAISERROR('El pedido no existe o esta eliminado.', 16, 1);
        END;

        IF @EstadoAprobado <> 1
        BEGIN
            RAISERROR('Solo se pueden modificar pedidos pendientes.', 16, 1);
        END;

        IF NOT EXISTS (
            SELECT 1 FROM dbo.tbl_Usuario WITH (HOLDLOCK)
            WHERE Id = @IdUsuarioAlmacenero AND E_Eliminado = 2
        )
        BEGIN
            RAISERROR('El usuario de almacen no se encuentra activo.', 16, 1);
        END;

        IF (SELECT COUNT(*) FROM @Cambios) <>
           (SELECT COUNT(*)
            FROM dbo.tbl_CodigoPedidoVendedor_EnRuta WITH (UPDLOCK, HOLDLOCK)
            WHERE Id_PedidoVendedor_EnRuta = @IdPedido AND E_Eliminado = 2)
        BEGIN
            RAISERROR('Debe enviar todos los productos del pedido.', 16, 1);
        END;

        IF EXISTS (
            SELECT 1
            FROM @Cambios cambio
            LEFT JOIN dbo.tbl_CodigoPedidoVendedor_EnRuta detalle WITH (UPDLOCK, HOLDLOCK)
                ON detalle.Id_CodigoPedidoVendedor_EnRuta = cambio.IdDetalle
               AND detalle.Id_PedidoVendedor_EnRuta = @IdPedido
               AND detalle.E_Eliminado = 2
            WHERE detalle.Id_CodigoPedidoVendedor_EnRuta IS NULL
        )
        BEGIN
            RAISERROR('Uno de los productos no pertenece al pedido.', 16, 1);
        END;

        IF EXISTS (
            SELECT 1
            FROM @Cambios cambio
            INNER JOIN dbo.tbl_CodigoPedidoVendedor_EnRuta detalle WITH (UPDLOCK, HOLDLOCK)
                ON detalle.Id_CodigoPedidoVendedor_EnRuta = cambio.IdDetalle
            WHERE detalle.Id_PedidoVendedor_EnRuta = @IdPedido
              AND cambio.Cantidad > detalle.NvoPedido
        )
        BEGIN
            RAISERROR('Almacen solo puede disminuir las cantidades del pedido.', 16, 1);
        END;

        IF NOT EXISTS (
            SELECT 1
            FROM @Cambios cambio
            INNER JOIN dbo.tbl_CodigoPedidoVendedor_EnRuta detalle WITH (UPDLOCK, HOLDLOCK)
                ON detalle.Id_CodigoPedidoVendedor_EnRuta = cambio.IdDetalle
            WHERE detalle.Id_PedidoVendedor_EnRuta = @IdPedido
              AND cambio.Cantidad < detalle.NvoPedido
        )
        BEGIN
            RAISERROR('Debe disminuir al menos una cantidad para modificar el pedido.', 16, 1);
        END;

        UPDATE detalle
           SET detalle.NvoPedido = cambio.Cantidad,
               detalle.TotalParcial = ROUND(detalle.Precio * cambio.Cantidad, 2)
        FROM dbo.tbl_CodigoPedidoVendedor_EnRuta detalle
        INNER JOIN @Cambios cambio
            ON cambio.IdDetalle = detalle.Id_CodigoPedidoVendedor_EnRuta
        WHERE detalle.Id_PedidoVendedor_EnRuta = @IdPedido
          AND detalle.E_Eliminado = 2;

        UPDATE detalle
           SET detalle.E_Eliminado = 1
        FROM dbo.tbl_CodigoPedidoVendedor_EnRuta detalle
        INNER JOIN @Cambios cambio
            ON cambio.IdDetalle = detalle.Id_CodigoPedidoVendedor_EnRuta
        WHERE detalle.Id_PedidoVendedor_EnRuta = @IdPedido
          AND detalle.E_Eliminado = 2
          AND cambio.Cantidad = 0;

        DECLARE @Total DECIMAL(18,2);
        DECLARE @CantidadProductos INT;
        DECLARE @CantidadUnidades INT;
        SELECT
            @Total = ISNULL(SUM(TotalParcial), 0),
            @CantidadProductos = COUNT(*),
            @CantidadUnidades = SUM(NvoPedido)
        FROM dbo.tbl_CodigoPedidoVendedor_EnRuta
        WHERE Id_PedidoVendedor_EnRuta = @IdPedido
          AND E_Eliminado = 2;

        UPDATE dbo.tbl_PedidoVendedor_EnRuta
           SET Total = @Total,
               ModificadoPorAlmacen = 1,
               ComentarioAlmacen = @ComentarioAlmacen,
               FechaModificacionAlmacen = GETDATE()
        WHERE Id_PedidoVendedor_EnRuta = @IdPedido;

        COMMIT TRANSACTION;

        SELECT
            @IdPedido AS IdPedido,
            @Total AS Total,
            @CantidadProductos AS CantidadProductos,
            @CantidadUnidades AS CantidadUnidades,
            CAST(1 AS INT) AS ModificadoPorAlmacen,
            @ComentarioAlmacen AS ComentarioAlmacen;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        DECLARE @MensajeError NVARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('%s', 16, 1, @MensajeError);
    END CATCH;
END;
GO
