SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID(N'dbo.spj_LoginGeneral_Scanner_ValidarContextoPedido', N'P') IS NULL
BEGIN
    EXEC(N'CREATE PROCEDURE dbo.spj_LoginGeneral_Scanner_ValidarContextoPedido
           AS BEGIN SET NOCOUNT ON; END');
END;
GO

ALTER PROCEDURE dbo.spj_LoginGeneral_Scanner_ValidarContextoPedido
    @IdPedido INT,
    @IdDetalle INT,
    @TokenVinculacion VARCHAR(64),
    @IdUsuario INT,
    @ImeisConservarXml XML
AS
BEGIN
    SET NOCOUNT ON;
    SET ARITHABORT ON;

    IF NOT EXISTS
    (
        SELECT 1
        FROM dbo.tbl_CodigoPedidoVendedor_EnRuta detalle
        INNER JOIN dbo.tbl_PedidoVendedor_EnRuta pedido
            ON pedido.Id_PedidoVendedor_EnRuta = detalle.Id_PedidoVendedor_EnRuta
        WHERE pedido.Id_PedidoVendedor_EnRuta = @IdPedido
          AND detalle.Id_CodigoPedidoVendedor_EnRuta = @IdDetalle
          AND pedido.E_Aprobado = 1
          AND pedido.E_Eliminado = 2
          AND detalle.E_Eliminado = 2
    )
    BEGIN
        RAISERROR('El pedido o el detalle ya no estan disponibles para preparar.', 16, 1);
        RETURN;
    END;

    SELECT
        @IdPedido AS IdPedido,
        @IdDetalle AS IdDetalle,
        DATEADD(HOUR, 1, GETDATE()) AS FechaExpiracion;
END;
GO

IF OBJECT_ID(N'dbo.spj_LoginGeneral_Scanner_ValidarImeisDisponiblesPedido', N'P') IS NULL
BEGIN
    EXEC(N'CREATE PROCEDURE dbo.spj_LoginGeneral_Scanner_ValidarImeisDisponiblesPedido
           AS BEGIN SET NOCOUNT ON; END');
END;
GO

ALTER PROCEDURE dbo.spj_LoginGeneral_Scanner_ValidarImeisDisponiblesPedido
    @IdPedido INT,
    @IdDetalle INT,
    @TokenVinculacion VARCHAR(64),
    @IdUsuario INT,
    @ImeisXml XML
AS
BEGIN
    SET NOCOUNT ON;
    SET ARITHABORT ON;

    DECLARE @IdProductoEsperado INT;
    DECLARE @ProductoEsperado NVARCHAR(100);
    DECLARE @CantidadSolicitada INT;

    DECLARE @Solicitados TABLE
    (
        Orden INT IDENTITY(1,1) NOT NULL,
        Imei BIGINT NOT NULL PRIMARY KEY
    );

    INSERT INTO @Solicitados(Imei)
    SELECT nodo.valor.value('@v', 'BIGINT')
    FROM @ImeisXml.nodes('/imeis/i') nodo(valor);

    SELECT
        @IdProductoEsperado = detalle.Id_Producto,
        @ProductoEsperado = producto.Nombre,
        @CantidadSolicitada = detalle.NvoPedido
    FROM dbo.tbl_CodigoPedidoVendedor_EnRuta detalle
    INNER JOIN dbo.tbl_PedidoVendedor_EnRuta pedido
        ON pedido.Id_PedidoVendedor_EnRuta = detalle.Id_PedidoVendedor_EnRuta
    INNER JOIN dbo.tbl_Producto producto
        ON producto.Id_Producto = detalle.Id_Producto
    WHERE pedido.Id_PedidoVendedor_EnRuta = @IdPedido
      AND detalle.Id_CodigoPedidoVendedor_EnRuta = @IdDetalle
      AND pedido.E_Aprobado = 1
      AND pedido.E_Eliminado = 2
      AND detalle.E_Eliminado = 2;

    IF @IdProductoEsperado IS NULL
    BEGIN
        RAISERROR('El detalle no pertenece al pedido o ya no esta disponible.', 16, 1);
        RETURN;
    END;

    SELECT
        CONVERT(VARCHAR(30), solicitado.Imei) AS Imei,
        CAST(CASE WHEN fisico.Imei IS NULL THEN 0 ELSE 1 END AS BIT) AS Existe,
        fisico.Id_Ruta AS IdRuta,
        fisico.Vendido,
        fisico.Id_Producto AS IdProductoEncontrado,
        catalogo.Nombre AS ProductoEncontrado,
        @IdProductoEsperado AS IdProductoEsperado,
        @ProductoEsperado AS ProductoEsperado,
        @CantidadSolicitada AS CantidadSolicitada,
        CAST(CASE
            WHEN fisico.Imei IS NOT NULL
             AND fisico.Id_Producto = @IdProductoEsperado
             AND ISNULL(fisico.Id_Ruta, 0) = 0
             AND ISNULL(fisico.Id_PedidoVendedor, 0) = 0
             AND ISNULL(fisico.Vendido, 0) = 0
             AND ISNULL(fisico.e_Eliminado, 0) = 0
             AND asignado.Imei IS NULL THEN 1 ELSE 0 END AS BIT) AS Valido,
        CASE
            WHEN fisico.Imei IS NULL THEN 'El IMEI no existe en tbl_Productos.'
            WHEN fisico.Id_Producto <> @IdProductoEsperado THEN 'El IMEI corresponde a ' + ISNULL(catalogo.Nombre, 'otro producto') + '; se esperaba ' + @ProductoEsperado + '.'
            WHEN ISNULL(fisico.e_Eliminado, 0) <> 0 THEN 'El producto esta eliminado.'
            WHEN asignado.Imei IS NOT NULL THEN 'El IMEI ya fue asociado a otro pedido.'
            WHEN ISNULL(fisico.Id_Ruta, 0) <> 0 THEN 'El producto ya tiene una ruta asignada.'
            WHEN ISNULL(fisico.Id_PedidoVendedor, 0) <> 0 THEN 'El producto ya tiene un pedido asignado.'
            WHEN ISNULL(fisico.Vendido, 0) <> 0 THEN 'El producto no esta disponible (Vendido debe ser 0).'
            ELSE NULL
        END AS Motivo
    FROM @Solicitados solicitado
    OUTER APPLY
    (
        SELECT TOP (1)
            producto.Imei,
            producto.Id_Ruta,
            producto.Id_Producto,
            producto.Id_PedidoVendedor,
            producto.Vendido,
            producto.e_Eliminado
        FROM dbo.tbl_Productos producto WITH (INDEX(IX_tbl_Productos_Imei_Disponibilidad))
        WHERE producto.Imei = solicitado.Imei
        ORDER BY CASE
            WHEN producto.Id_Producto = @IdProductoEsperado
             AND ISNULL(producto.Id_Ruta, 0) = 0
             AND ISNULL(producto.Id_PedidoVendedor, 0) = 0
             AND ISNULL(producto.Vendido, 0) = 0
             AND ISNULL(producto.e_Eliminado, 0) = 0 THEN 0 ELSE 1 END
    ) fisico
    LEFT JOIN dbo.tbl_Producto catalogo
        ON catalogo.Id_Producto = fisico.Id_Producto
    LEFT JOIN dbo.PedidoVendedor_EnRuta_ProductoFisico asignado
        ON asignado.Imei = solicitado.Imei
       AND asignado.E_Eliminado = 2
    ORDER BY solicitado.Orden;
END;
GO

ALTER PROCEDURE dbo.spj_LoginGeneral_Scanner_ReservarContexto
    @IdPedido INT,
    @IdDetalle INT,
    @TokenVinculacion VARCHAR(64),
    @IdUsuario INT,
    @ImeisConservarXml XML
AS
BEGIN
    SET NOCOUNT ON;
    EXEC dbo.spj_LoginGeneral_Scanner_ValidarContextoPedido
        @IdPedido, @IdDetalle, @TokenVinculacion, @IdUsuario, @ImeisConservarXml;
END;
GO

ALTER PROCEDURE dbo.spj_LoginGeneral_Scanner_ValidarYReservarImeisPedido
    @IdPedido INT,
    @IdDetalle INT,
    @TokenVinculacion VARCHAR(64),
    @IdUsuario INT,
    @ImeisXml XML
AS
BEGIN
    SET NOCOUNT ON;
    EXEC dbo.spj_LoginGeneral_Scanner_ValidarImeisDisponiblesPedido
        @IdPedido, @IdDetalle, @TokenVinculacion, @IdUsuario, @ImeisXml;
END;
GO

ALTER PROCEDURE dbo.spj_LoginGeneral_Scanner_LiberarReservas
    @TokenVinculacion VARCHAR(64),
    @IdUsuario INT,
    @IdPedido INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    -- Compatibilidad con el frontend: ya no existen reservas que liberar.
END;
GO

ALTER PROCEDURE dbo.spj_LoginGeneral_Almacen_AprobarPedidoReservado
    @IdPedido INT,
    @FechaEntrega DATE,
    @AprobadoPor VARCHAR(150),
    @IdUsuarioAlmacenero INT,
    @TokenVinculacion VARCHAR(64),
    @ProductosXml XML
AS
BEGIN
    SET NOCOUNT ON;
    SET ARITHABORT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        IF NOT EXISTS
        (
            SELECT 1
            FROM dbo.tbl_PedidoVendedor_EnRuta WITH (UPDLOCK, HOLDLOCK)
            WHERE Id_PedidoVendedor_EnRuta = @IdPedido
              AND E_Aprobado = 1
              AND E_Eliminado = 2
        )
            RAISERROR('El pedido no existe, fue eliminado o ya esta aprobado.', 16, 1);

        EXEC dbo.spj_LoginGeneral_Almacen_AprobarPedidoConProductos
            @IdPedido,
            @FechaEntrega,
            @AprobadoPor,
            @IdUsuarioAlmacenero,
            @ProductosXml;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        DECLARE @ErrorMessage NVARCHAR(4000);
        SET @ErrorMessage = ERROR_MESSAGE();
        RAISERROR(@ErrorMessage, 16, 1);
    END CATCH;
END;
GO

-- Elimina las reservas heredadas. Las tablas se conservan vacías por
-- compatibilidad y ya no participan en validaciones ni aprobaciones.
DELETE FROM dbo.ScannerImeiReserva;
IF OBJECT_ID(N'dbo.ScannerPedidoReserva', N'U') IS NOT NULL
    DELETE FROM dbo.ScannerPedidoReserva;
GO
