SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

IF OBJECT_ID(N'dbo.ScannerImeiReserva', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.ScannerImeiReserva
    (
        Imei BIGINT NOT NULL,
        Token_Vinculacion VARCHAR(64) NOT NULL,
        Id_PedidoVendedor_EnRuta INT NOT NULL,
        Id_CodigoPedidoVendedor_EnRuta INT NOT NULL,
        Id_Usuario INT NOT NULL,
        Fecha_Reserva DATETIME NOT NULL CONSTRAINT DF_ScannerImeiReserva_Fecha DEFAULT (GETDATE()),
        Fecha_Expiracion DATETIME NOT NULL,
        CONSTRAINT PK_ScannerImeiReserva PRIMARY KEY (Imei)
    );

    CREATE NONCLUSTERED INDEX IX_ScannerImeiReserva_TokenPedido
        ON dbo.ScannerImeiReserva(Token_Vinculacion, Id_PedidoVendedor_EnRuta)
        INCLUDE (Id_CodigoPedidoVendedor_EnRuta, Id_Usuario, Fecha_Expiracion);
END;
GO

IF NOT EXISTS
(
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID(N'dbo.ScannerImeiReserva')
      AND name = N'IX_ScannerImeiReserva_Expiracion'
)
BEGIN
    CREATE NONCLUSTERED INDEX IX_ScannerImeiReserva_Expiracion
        ON dbo.ScannerImeiReserva(Fecha_Expiracion);
END;
GO

IF OBJECT_ID(N'dbo.spj_LoginGeneral_Scanner_ReservarContexto', N'P') IS NULL
    EXEC(N'CREATE PROCEDURE dbo.spj_LoginGeneral_Scanner_ReservarContexto AS BEGIN SET NOCOUNT ON; END');
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
    SET ARITHABORT ON;
    SET XACT_ABORT ON;

    DECLARE @Ahora DATETIME;
    DECLARE @Expira DATETIME;
    SET @Ahora = GETDATE();
    SET @Expira = DATEADD(HOUR, 1, @Ahora);

    DECLARE @Conservar TABLE (Imei BIGINT NOT NULL PRIMARY KEY);
    INSERT INTO @Conservar(Imei)
    SELECT nodo.valor.value('@v', 'BIGINT')
    FROM @ImeisConservarXml.nodes('/imeis/i') nodo(valor);

    BEGIN TRY
        BEGIN TRANSACTION;

        DELETE FROM dbo.ScannerImeiReserva WHERE Fecha_Expiracion <= @Ahora;

        IF NOT EXISTS
        (
            SELECT 1
            FROM dbo.tbl_CodigoPedidoVendedor_EnRuta d
            INNER JOIN dbo.tbl_PedidoVendedor_EnRuta p WITH (UPDLOCK, HOLDLOCK)
                ON p.Id_PedidoVendedor_EnRuta = d.Id_PedidoVendedor_EnRuta
            WHERE p.Id_PedidoVendedor_EnRuta = @IdPedido
              AND d.Id_CodigoPedidoVendedor_EnRuta = @IdDetalle
              AND p.E_Aprobado = 1
              AND p.E_Eliminado = 2
              AND d.E_Eliminado = 2
        )
            RAISERROR('El pedido o el detalle ya no estan disponibles para preparar.', 16, 1);

        DELETE reserva
        FROM dbo.ScannerImeiReserva reserva
        WHERE reserva.Token_Vinculacion = @TokenVinculacion
          AND reserva.Id_PedidoVendedor_EnRuta = @IdPedido
          AND reserva.Id_CodigoPedidoVendedor_EnRuta = @IdDetalle
          AND NOT EXISTS (SELECT 1 FROM @Conservar conservar WHERE conservar.Imei = reserva.Imei);

        UPDATE reserva
           SET reserva.Fecha_Expiracion = @Expira
        FROM dbo.ScannerImeiReserva reserva
        INNER JOIN @Conservar conservar ON conservar.Imei = reserva.Imei
        WHERE reserva.Token_Vinculacion = @TokenVinculacion
          AND reserva.Id_PedidoVendedor_EnRuta = @IdPedido
          AND reserva.Id_CodigoPedidoVendedor_EnRuta = @IdDetalle;

        COMMIT TRANSACTION;
        SELECT @IdPedido AS IdPedido, @IdDetalle AS IdDetalle, @Expira AS FechaExpiracion;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        DECLARE @ErrorMessage NVARCHAR(4000);
        SET @ErrorMessage = ERROR_MESSAGE();
        RAISERROR(@ErrorMessage, 16, 1);
    END CATCH;
END;
GO

IF OBJECT_ID(N'dbo.spj_LoginGeneral_Scanner_ValidarYReservarImeisPedido', N'P') IS NULL
    EXEC(N'CREATE PROCEDURE dbo.spj_LoginGeneral_Scanner_ValidarYReservarImeisPedido AS BEGIN SET NOCOUNT ON; END');
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
    SET ARITHABORT ON;
    SET XACT_ABORT ON;

    DECLARE @Ahora DATETIME;
    DECLARE @Expira DATETIME;
    DECLARE @IdProductoEsperado INT;
    DECLARE @ProductoEsperado NVARCHAR(100);
    DECLARE @CantidadSolicitada INT;
    SET @Ahora = GETDATE();
    SET @Expira = DATEADD(HOUR, 1, @Ahora);

    DECLARE @Solicitados TABLE
    (
        Orden INT IDENTITY(1,1) NOT NULL,
        Imei BIGINT NOT NULL PRIMARY KEY
    );

    DECLARE @Resultado TABLE
    (
        Orden INT NOT NULL,
        Imei VARCHAR(30) NOT NULL,
        Existe BIT NOT NULL,
        IdRuta INT NULL,
        Vendido INT NULL,
        IdProductoEncontrado INT NULL,
        ProductoEncontrado NVARCHAR(100) NULL,
        IdProductoEsperado INT NOT NULL,
        ProductoEsperado NVARCHAR(100) NOT NULL,
        CantidadSolicitada INT NOT NULL,
        Valido BIT NOT NULL,
        Motivo NVARCHAR(300) NULL
    );

    INSERT INTO @Solicitados(Imei)
    SELECT nodo.valor.value('@v', 'BIGINT')
    FROM @ImeisXml.nodes('/imeis/i') nodo(valor);

    BEGIN TRY
        BEGIN TRANSACTION;

        DELETE FROM dbo.ScannerImeiReserva WHERE Fecha_Expiracion <= @Ahora;

        SELECT
            @IdProductoEsperado = d.Id_Producto,
            @ProductoEsperado = producto.Nombre,
            @CantidadSolicitada = d.NvoPedido
        FROM dbo.tbl_CodigoPedidoVendedor_EnRuta d
        INNER JOIN dbo.tbl_PedidoVendedor_EnRuta p WITH (UPDLOCK, HOLDLOCK)
            ON p.Id_PedidoVendedor_EnRuta = d.Id_PedidoVendedor_EnRuta
        INNER JOIN dbo.tbl_Producto producto ON producto.Id_Producto = d.Id_Producto
        WHERE p.Id_PedidoVendedor_EnRuta = @IdPedido
          AND d.Id_CodigoPedidoVendedor_EnRuta = @IdDetalle
          AND p.E_Aprobado = 1 AND p.E_Eliminado = 2 AND d.E_Eliminado = 2;

        IF @IdProductoEsperado IS NULL
            RAISERROR('El detalle no pertenece al pedido o ya no esta disponible.', 16, 1);

        INSERT INTO @Resultado
        SELECT
            solicitado.Orden,
            CONVERT(VARCHAR(30), solicitado.Imei),
            CASE WHEN producto.Imei IS NULL THEN 0 ELSE 1 END,
            producto.Id_Ruta,
            producto.Vendido,
            producto.Id_Producto,
            productoCatalogo.Nombre,
            @IdProductoEsperado,
            @ProductoEsperado,
            @CantidadSolicitada,
            CASE
                WHEN producto.Imei IS NOT NULL
                 AND producto.Id_Producto = @IdProductoEsperado
                 AND ISNULL(producto.Id_Ruta,0) = 0
                 AND ISNULL(producto.Id_PedidoVendedor,0) = 0
                 AND ISNULL(producto.Vendido,0) = 0
                 AND ISNULL(producto.e_Eliminado,0) = 0
                 AND asignado.Imei IS NULL
                 AND (reserva.Imei IS NULL OR
                      (reserva.Token_Vinculacion = @TokenVinculacion
                       AND reserva.Id_PedidoVendedor_EnRuta = @IdPedido
                       AND reserva.Id_CodigoPedidoVendedor_EnRuta = @IdDetalle)) THEN 1
                ELSE 0
            END,
            CASE
                WHEN producto.Imei IS NULL THEN 'El IMEI no existe en tbl_Productos.'
                WHEN producto.Id_Producto <> @IdProductoEsperado THEN 'El IMEI corresponde a ' + ISNULL(productoCatalogo.Nombre,'otro producto') + '; se esperaba ' + @ProductoEsperado + '.'
                WHEN ISNULL(producto.e_Eliminado,0) <> 0 THEN 'El producto esta eliminado.'
                WHEN asignado.Imei IS NOT NULL THEN 'El IMEI ya fue asociado a otro pedido.'
                WHEN ISNULL(producto.Id_Ruta,0) <> 0 THEN 'El producto ya tiene una ruta asignada.'
                WHEN ISNULL(producto.Id_PedidoVendedor,0) <> 0 THEN 'El producto ya tiene un pedido asignado.'
                WHEN ISNULL(producto.Vendido,0) <> 0 THEN 'El producto no esta disponible (Vendido debe ser 0).'
                WHEN reserva.Imei IS NOT NULL AND reserva.Token_Vinculacion <> @TokenVinculacion THEN 'El IMEI esta reservado temporalmente por otro almacenero.'
                WHEN reserva.Imei IS NOT NULL AND (reserva.Id_PedidoVendedor_EnRuta <> @IdPedido OR reserva.Id_CodigoPedidoVendedor_EnRuta <> @IdDetalle) THEN 'El IMEI ya esta reservado para otro pedido o producto.'
                ELSE NULL
            END
        FROM @Solicitados solicitado
        OUTER APPLY
        (
            SELECT TOP (1) p.Imei,p.Id_Ruta,p.Id_Producto,p.Id_PedidoVendedor,p.Vendido,p.e_Eliminado
            FROM dbo.tbl_Productos p WITH (UPDLOCK, HOLDLOCK, INDEX(IX_tbl_Productos_Imei_Disponibilidad))
            WHERE p.Imei = solicitado.Imei
            ORDER BY CASE WHEN p.Id_Producto=@IdProductoEsperado AND ISNULL(p.Id_Ruta,0)=0
                                AND ISNULL(p.Id_PedidoVendedor,0)=0 AND ISNULL(p.Vendido,0)=0
                                AND ISNULL(p.e_Eliminado,0)=0 THEN 0 ELSE 1 END
        ) producto
        LEFT JOIN dbo.tbl_Producto productoCatalogo ON productoCatalogo.Id_Producto = producto.Id_Producto
        LEFT JOIN dbo.PedidoVendedor_EnRuta_ProductoFisico asignado
          ON asignado.Imei = solicitado.Imei AND asignado.E_Eliminado = 2
        LEFT JOIN dbo.ScannerImeiReserva reserva WITH (UPDLOCK, HOLDLOCK)
          ON reserva.Imei = solicitado.Imei;

        IF NOT EXISTS(SELECT 1 FROM @Resultado WHERE Valido = 0)
        BEGIN
            UPDATE reserva
               SET reserva.Fecha_Expiracion = @Expira,
                   reserva.Id_Usuario = @IdUsuario
            FROM dbo.ScannerImeiReserva reserva
            INNER JOIN @Solicitados solicitado ON solicitado.Imei = reserva.Imei
            WHERE reserva.Token_Vinculacion = @TokenVinculacion
              AND reserva.Id_PedidoVendedor_EnRuta = @IdPedido
              AND reserva.Id_CodigoPedidoVendedor_EnRuta = @IdDetalle;

            INSERT INTO dbo.ScannerImeiReserva
                (Imei,Token_Vinculacion,Id_PedidoVendedor_EnRuta,Id_CodigoPedidoVendedor_EnRuta,Id_Usuario,Fecha_Reserva,Fecha_Expiracion)
            SELECT solicitado.Imei,@TokenVinculacion,@IdPedido,@IdDetalle,@IdUsuario,@Ahora,@Expira
            FROM @Solicitados solicitado
            WHERE NOT EXISTS(SELECT 1 FROM dbo.ScannerImeiReserva reserva WHERE reserva.Imei=solicitado.Imei);
        END;

        COMMIT TRANSACTION;

        SELECT Imei,Existe,IdRuta,Vendido,IdProductoEncontrado,ProductoEncontrado,
               IdProductoEsperado,ProductoEsperado,CantidadSolicitada,Valido,Motivo
        FROM @Resultado ORDER BY Orden;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        DECLARE @ErrorMessage NVARCHAR(4000);
        SET @ErrorMessage = ERROR_MESSAGE();
        RAISERROR(@ErrorMessage,16,1);
    END CATCH;
END;
GO

IF OBJECT_ID(N'dbo.spj_LoginGeneral_Scanner_LiberarReservas', N'P') IS NULL
    EXEC(N'CREATE PROCEDURE dbo.spj_LoginGeneral_Scanner_LiberarReservas AS BEGIN SET NOCOUNT ON; END');
GO

ALTER PROCEDURE dbo.spj_LoginGeneral_Scanner_LiberarReservas
    @TokenVinculacion VARCHAR(64),
    @IdUsuario INT,
    @IdPedido INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET ARITHABORT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRANSACTION;
        DELETE FROM dbo.ScannerImeiReserva
        WHERE Token_Vinculacion=@TokenVinculacion AND Id_Usuario=@IdUsuario
          AND (@IdPedido IS NULL OR Id_PedidoVendedor_EnRuta=@IdPedido);
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        DECLARE @ErrorMessage NVARCHAR(4000);
        SET @ErrorMessage=ERROR_MESSAGE();
        RAISERROR(@ErrorMessage,16,1);
    END CATCH;
END;
GO

IF OBJECT_ID(N'dbo.spj_LoginGeneral_Almacen_AprobarPedidoReservado', N'P') IS NULL
    EXEC(N'CREATE PROCEDURE dbo.spj_LoginGeneral_Almacen_AprobarPedidoReservado AS BEGIN SET NOCOUNT ON; END');
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

    DECLARE @Ahora DATETIME;
    SET @Ahora=GETDATE();
    DECLARE @Asignados TABLE(IdDetalle INT NOT NULL,Imei BIGINT NOT NULL PRIMARY KEY);
    INSERT INTO @Asignados(IdDetalle,Imei)
    SELECT nodo.valor.value('@detalle','INT'),nodo.valor.value('@imei','BIGINT')
    FROM @ProductosXml.nodes('/productos/i') nodo(valor);

    BEGIN TRY
        BEGIN TRANSACTION;

        DELETE FROM dbo.ScannerImeiReserva WHERE Fecha_Expiracion<=@Ahora;

        IF NOT EXISTS
        (
            SELECT 1
            FROM dbo.tbl_PedidoVendedor_EnRuta WITH (UPDLOCK, HOLDLOCK)
            WHERE Id_PedidoVendedor_EnRuta = @IdPedido
              AND E_Aprobado = 1
              AND E_Eliminado = 2
        ) RAISERROR('El pedido no existe, fue eliminado o ya esta aprobado.',16,1);

        IF EXISTS
        (
            SELECT 1 FROM @Asignados asignado
            LEFT JOIN dbo.ScannerImeiReserva reserva WITH (UPDLOCK,HOLDLOCK)
              ON reserva.Imei=asignado.Imei
             AND reserva.Token_Vinculacion=@TokenVinculacion
             AND reserva.Id_PedidoVendedor_EnRuta=@IdPedido
             AND reserva.Id_CodigoPedidoVendedor_EnRuta=asignado.IdDetalle
             AND reserva.Id_Usuario=@IdUsuarioAlmacenero
             AND reserva.Fecha_Expiracion>@Ahora
            WHERE reserva.Imei IS NULL
        ) RAISERROR('Uno o mas IMEI no tienen una reserva activa para este pedido.',16,1);

        EXEC dbo.spj_LoginGeneral_Almacen_AprobarPedidoConProductos
            @IdPedido,@FechaEntrega,@AprobadoPor,@IdUsuarioAlmacenero,@ProductosXml;

        DELETE FROM dbo.ScannerImeiReserva
        WHERE Id_PedidoVendedor_EnRuta=@IdPedido;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        DECLARE @ErrorMessage NVARCHAR(4000);
        SET @ErrorMessage=ERROR_MESSAGE();
        RAISERROR(@ErrorMessage,16,1);
    END CATCH;
END;
GO
