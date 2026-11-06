SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF COL_LENGTH(N'dbo.tbl_PedidoVendedor_EnRuta', N'Id_PedidoVendedorNormal') IS NULL
BEGIN
    ALTER TABLE dbo.tbl_PedidoVendedor_EnRuta
        ADD Id_PedidoVendedorNormal INT NOT NULL
            CONSTRAINT DF_PedidoVendedor_EnRuta_IdPedidoNormal DEFAULT (0) WITH VALUES;
END;
GO

IF OBJECT_ID(N'dbo.PedidoVendedor_EnRuta_ProductoFisico', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.PedidoVendedor_EnRuta_ProductoFisico
    (
        Id_PedidoProductoFisico INT IDENTITY(1,1) NOT NULL,
        Id_PedidoVendedor_EnRuta INT NOT NULL,
        Id_CodigoPedidoVendedor_EnRuta INT NOT NULL,
        Id_Producto INT NOT NULL,
        Imei BIGINT NOT NULL,
        Id_Ruta INT NOT NULL,
        Id_UsuarioAlmacenero INT NOT NULL,
        Fecha_Registro DATETIME NOT NULL
            CONSTRAINT DF_PedidoRutaProductoFisico_Fecha DEFAULT (GETDATE()),
        E_Eliminado INT NOT NULL
            CONSTRAINT DF_PedidoRutaProductoFisico_Eliminado DEFAULT (2),
        CONSTRAINT PK_PedidoVendedor_EnRuta_ProductoFisico
            PRIMARY KEY CLUSTERED (Id_PedidoProductoFisico),
        CONSTRAINT UQ_PedidoVendedor_EnRuta_ProductoFisico_Imei UNIQUE (Imei),
        CONSTRAINT FK_PedidoRutaProductoFisico_Pedido
            FOREIGN KEY (Id_PedidoVendedor_EnRuta)
            REFERENCES dbo.tbl_PedidoVendedor_EnRuta (Id_PedidoVendedor_EnRuta),
        CONSTRAINT FK_PedidoRutaProductoFisico_Detalle
            FOREIGN KEY (Id_CodigoPedidoVendedor_EnRuta)
            REFERENCES dbo.tbl_CodigoPedidoVendedor_EnRuta (Id_CodigoPedidoVendedor_EnRuta),
        CONSTRAINT FK_PedidoRutaProductoFisico_Producto
            FOREIGN KEY (Id_Producto)
            REFERENCES dbo.tbl_Producto (Id_Producto)
    );
END;
GO

IF COL_LENGTH(N'dbo.PedidoVendedor_EnRuta_ProductoFisico', N'Numero_Tira') IS NULL
BEGIN
    ALTER TABLE dbo.PedidoVendedor_EnRuta_ProductoFisico
        ADD Numero_Tira INT NOT NULL
            CONSTRAINT DF_PedidoRutaProductoFisico_NumeroTira DEFAULT (1);
END;
GO

IF COL_LENGTH(N'dbo.PedidoVendedor_EnRuta_ProductoFisico', N'Modo_Tira') IS NULL
BEGIN
    ALTER TABLE dbo.PedidoVendedor_EnRuta_ProductoFisico
        ADD Modo_Tira VARCHAR(20) NOT NULL
            CONSTRAINT DF_PedidoRutaProductoFisico_ModoTira DEFAULT ('individual');
END;
GO

IF NOT EXISTS
(
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID(N'dbo.PedidoVendedor_EnRuta_ProductoFisico')
      AND name = N'IX_PedidoRutaProductoFisico_PedidoDetalle'
)
BEGIN
    CREATE NONCLUSTERED INDEX IX_PedidoRutaProductoFisico_PedidoDetalle
        ON dbo.PedidoVendedor_EnRuta_ProductoFisico
        (Id_PedidoVendedor_EnRuta, Id_CodigoPedidoVendedor_EnRuta)
        INCLUDE (Imei, Id_Producto, Id_Ruta, E_Eliminado);
END;
GO

IF OBJECT_ID(N'dbo.spj_LoginGeneral_Scanner_ValidarImeisPedido', N'P') IS NULL
BEGIN
    EXEC(N'CREATE PROCEDURE dbo.spj_LoginGeneral_Scanner_ValidarImeisPedido AS BEGIN SET NOCOUNT ON; END');
END;
GO

ALTER PROCEDURE dbo.spj_LoginGeneral_Scanner_ValidarImeisPedido
    @IdPedido INT,
    @IdDetalle INT,
    @ImeisXml XML
AS
BEGIN
    SET NOCOUNT ON;
    SET ARITHABORT ON;

    DECLARE @IdProductoEsperado INT;
    DECLARE @ProductoEsperado NVARCHAR(100);
    DECLARE @CantidadSolicitada INT;

    SELECT
        @IdProductoEsperado = d.Id_Producto,
        @ProductoEsperado = producto.Nombre,
        @CantidadSolicitada = d.NvoPedido
    FROM dbo.tbl_CodigoPedidoVendedor_EnRuta d
    INNER JOIN dbo.tbl_PedidoVendedor_EnRuta p
        ON p.Id_PedidoVendedor_EnRuta = d.Id_PedidoVendedor_EnRuta
    INNER JOIN dbo.tbl_Producto producto
        ON producto.Id_Producto = d.Id_Producto
    WHERE p.Id_PedidoVendedor_EnRuta = @IdPedido
      AND d.Id_CodigoPedidoVendedor_EnRuta = @IdDetalle
      AND p.E_Aprobado = 1
      AND p.E_Eliminado = 2
      AND d.E_Eliminado = 2;

    IF @IdProductoEsperado IS NULL
    BEGIN
        RAISERROR('El detalle no existe, no pertenece al pedido o el pedido ya fue aprobado.', 16, 1);
        RETURN;
    END;

    DECLARE @Solicitados TABLE
    (
        Orden INT IDENTITY(1,1) NOT NULL,
        Imei BIGINT NOT NULL PRIMARY KEY
    );

    INSERT INTO @Solicitados (Imei)
    SELECT nodo.valor.value('@v', 'BIGINT')
    FROM @ImeisXml.nodes('/imeis/i') nodo(valor);

    SELECT
        CONVERT(VARCHAR(30), solicitado.Imei) AS Imei,
        CASE WHEN producto.Imei IS NULL THEN 0 ELSE 1 END AS Existe,
        producto.Id_Ruta AS IdRuta,
        producto.Vendido,
        producto.Id_Producto AS IdProductoEncontrado,
        productoCatalogo.Nombre AS ProductoEncontrado,
        @IdProductoEsperado AS IdProductoEsperado,
        @ProductoEsperado AS ProductoEsperado,
        @CantidadSolicitada AS CantidadSolicitada,
        CASE
            WHEN producto.Imei IS NOT NULL
             AND producto.Id_Producto = @IdProductoEsperado
             AND ISNULL(producto.Id_Ruta, 0) = 0
             AND ISNULL(producto.Id_PedidoVendedor, 0) = 0
             AND ISNULL(producto.Vendido, 0) = 0
             AND ISNULL(producto.e_Eliminado, 0) = 0
             AND asignado.Imei IS NULL THEN 1
            ELSE 0
        END AS Valido,
        CASE
            WHEN producto.Imei IS NULL THEN 'El IMEI no existe en tbl_Productos.'
            WHEN producto.Id_Producto <> @IdProductoEsperado THEN
                'El IMEI corresponde a ' + ISNULL(productoCatalogo.Nombre, 'otro producto')
                + '; se esperaba ' + @ProductoEsperado + '.'
            WHEN ISNULL(producto.e_Eliminado, 0) <> 0 THEN 'El producto esta eliminado.'
            WHEN asignado.Imei IS NOT NULL THEN 'El IMEI ya fue asociado a otro pedido.'
            WHEN ISNULL(producto.Id_Ruta, 0) <> 0 THEN 'El producto ya tiene una ruta asignada.'
            WHEN ISNULL(producto.Id_PedidoVendedor, 0) <> 0 THEN 'El producto ya tiene un pedido asignado.'
            WHEN ISNULL(producto.Vendido, 0) <> 0 THEN 'El producto no esta disponible (Vendido debe ser 0).'
            ELSE NULL
        END AS Motivo
    FROM @Solicitados solicitado
    OUTER APPLY
    (
        SELECT TOP (1)
            p.Imei, p.Id_Ruta, p.Id_Producto, p.Id_PedidoVendedor,
            p.Vendido, p.e_Eliminado
        FROM dbo.tbl_Productos p WITH (INDEX(IX_tbl_Productos_Imei_Disponibilidad))
        WHERE p.Imei = solicitado.Imei
        ORDER BY CASE
            WHEN p.Id_Producto = @IdProductoEsperado
             AND ISNULL(p.Id_Ruta, 0) = 0
             AND ISNULL(p.Id_PedidoVendedor, 0) = 0
             AND ISNULL(p.Vendido, 0) = 0
             AND ISNULL(p.e_Eliminado, 0) = 0 THEN 0 ELSE 1 END
    ) producto
    LEFT JOIN dbo.tbl_Producto productoCatalogo
        ON productoCatalogo.Id_Producto = producto.Id_Producto
    LEFT JOIN dbo.PedidoVendedor_EnRuta_ProductoFisico asignado
        ON asignado.Imei = solicitado.Imei
       AND asignado.E_Eliminado = 2
    ORDER BY solicitado.Orden;
END;
GO

IF OBJECT_ID(N'dbo.spj_LoginGeneral_Almacen_AprobarPedidoConProductos', N'P') IS NULL
BEGIN
    EXEC(N'CREATE PROCEDURE dbo.spj_LoginGeneral_Almacen_AprobarPedidoConProductos AS BEGIN SET NOCOUNT ON; END');
END;
GO

ALTER PROCEDURE dbo.spj_LoginGeneral_Almacen_AprobarPedidoConProductos
    @IdPedido INT,
    @FechaEntrega DATE,
    @AprobadoPor VARCHAR(150),
    @IdUsuarioAlmacenero INT,
    @ProductosXml XML
AS
BEGIN
    SET NOCOUNT ON;
    SET ARITHABORT ON;
    SET XACT_ABORT ON;

    IF @FechaEntrega IS NULL
    BEGIN
        RAISERROR('La fecha de entrega es requerida.', 16, 1);
        RETURN;
    END;

    IF @FechaEntrega < CONVERT(DATE, GETDATE())
    BEGIN
        RAISERROR('La fecha de entrega no puede ser anterior a la fecha actual.', 16, 1);
        RETURN;
    END;

    IF NULLIF(LTRIM(RTRIM(@AprobadoPor)), '') IS NULL
    BEGIN
        RAISERROR('No se identifico al almacenero que aprueba.', 16, 1);
        RETURN;
    END;

    DECLARE @Asignados TABLE
    (
        IdDetalle INT NOT NULL,
        Imei BIGINT NOT NULL,
        NumeroTira INT NOT NULL,
        ModoTira VARCHAR(20) NOT NULL,
        PRIMARY KEY (Imei)
    );

    INSERT INTO @Asignados (IdDetalle, Imei, NumeroTira, ModoTira)
    SELECT
        nodo.valor.value('@detalle', 'INT'),
        nodo.valor.value('@imei', 'BIGINT'),
        nodo.valor.value('@tira', 'INT'),
        nodo.valor.value('@modo', 'VARCHAR(20)')
    FROM @ProductosXml.nodes('/productos/i') nodo(valor);

    IF EXISTS (SELECT 1 FROM @Asignados WHERE NumeroTira < 1 OR ModoTira NOT IN ('individual', 'rango', 'cantidad'))
    BEGIN
        RAISERROR('Una de las tiras tiene datos invalidos.', 16, 1);
        RETURN;
    END;

    DECLARE @IdRuta INT;
    DECLARE @IdVendedor INT;
    DECLARE @Observacion VARCHAR(50);
    DECLARE @FechaConfirmacion DATETIME;
    DECLARE @IdPedidoVendedorNormal INT;
    DECLARE @IdAlmacenVendedor INT;
    DECLARE @TotalPedidoNormal DECIMAL(18,2);
    DECLARE @TotalAlmacen DECIMAL(18,2);
    DECLARE @TigoMoneyPedido DECIMAL(18,2);
    DECLARE @SaldoTigoMoney DECIMAL(18,2);
    DECLARE @ResultadoBloqueo INT;
    DECLARE @RecursoBloqueo VARCHAR(255);
    DECLARE @RecursoBloqueoSistemas VARCHAR(255);

    DECLARE @SaldosAlmacen TABLE
    (
        IdProducto INT,
        Producto NVARCHAR(200),
        Cantidad DECIMAL(18,2)
    );

    DECLARE @DetallePedidoNormal TABLE
    (
        IdDetalleRuta INT NOT NULL PRIMARY KEY,
        IdProducto INT NOT NULL,
        Saldo INT NOT NULL,
        NvoPedido INT NOT NULL,
        ItemsHoy INT NOT NULL,
        Precio DECIMAL(18,2) NOT NULL,
        TotalParcial FLOAT NOT NULL
    );

    SELECT @IdRuta = Id_Ruta
    FROM dbo.tbl_PedidoVendedor_EnRuta
    WHERE Id_PedidoVendedor_EnRuta = @IdPedido
      AND E_Aprobado = 1 AND E_Eliminado = 2;

    IF @IdRuta IS NULL
    BEGIN
        RAISERROR('El pedido no existe, fue eliminado o ya esta aprobado.', 16, 1);
        RETURN;
    END;

    SET @RecursoBloqueoSistemas = 'LoginGeneral:Sistemas:CascadaRuta:' + CONVERT(VARCHAR(20), @IdRuta);

    BEGIN TRY
        BEGIN TRANSACTION;

        EXEC @ResultadoBloqueo = sys.sp_getapplock
            @Resource = @RecursoBloqueoSistemas,
            @LockMode = 'Shared',
            @LockOwner = 'Transaction',
            @LockTimeout = 15000;

        IF @ResultadoBloqueo < 0
            RAISERROR('La ruta esta siendo restaurada por Sistemas. Intente nuevamente al finalizar.', 16, 1);

        SELECT
            @IdRuta = Id_Ruta,
            @IdVendedor = Id_Vendedor,
            @Observacion = Observacion
        FROM dbo.tbl_PedidoVendedor_EnRuta WITH (UPDLOCK, HOLDLOCK)
        WHERE Id_PedidoVendedor_EnRuta = @IdPedido
          AND E_Aprobado = 1
          AND E_Eliminado = 2;

        IF @IdRuta IS NULL
            RAISERROR('El pedido no existe, fue eliminado o ya esta aprobado.', 16, 1);

        IF EXISTS
        (
            SELECT 1
            FROM @Asignados a
            LEFT JOIN dbo.tbl_CodigoPedidoVendedor_EnRuta d
                ON d.Id_CodigoPedidoVendedor_EnRuta = a.IdDetalle
               AND d.Id_PedidoVendedor_EnRuta = @IdPedido
               AND d.E_Eliminado = 2
            WHERE d.Id_CodigoPedidoVendedor_EnRuta IS NULL
        )
            RAISERROR('Uno de los productos fue asociado a un detalle que no pertenece al pedido.', 16, 1);

        IF EXISTS
        (
            SELECT 1
            FROM dbo.tbl_CodigoPedidoVendedor_EnRuta d
            LEFT JOIN
            (
                SELECT IdDetalle, COUNT(*) AS Cantidad
                FROM @Asignados
                GROUP BY IdDetalle
            ) a ON a.IdDetalle = d.Id_CodigoPedidoVendedor_EnRuta
            WHERE d.Id_PedidoVendedor_EnRuta = @IdPedido
              AND d.E_Eliminado = 2
              AND d.Id_Producto <> 31
              AND ISNULL(a.Cantidad, 0) <> d.NvoPedido
        )
            RAISERROR('Las cantidades fisicas no completan exactamente todos los productos del pedido.', 16, 1);

        IF EXISTS
        (
            SELECT 1
            FROM @Asignados a
            INNER JOIN dbo.tbl_CodigoPedidoVendedor_EnRuta d
                ON d.Id_CodigoPedidoVendedor_EnRuta = a.IdDetalle
            LEFT JOIN dbo.tbl_Productos fisico WITH (UPDLOCK, HOLDLOCK, INDEX(IX_tbl_Productos_Imei_Disponibilidad))
                ON fisico.Imei = a.Imei
               AND fisico.Id_Producto = d.Id_Producto
               AND ISNULL(fisico.Id_Ruta, 0) = 0
               AND ISNULL(fisico.Id_PedidoVendedor, 0) = 0
               AND ISNULL(fisico.Vendido, 0) = 0
               AND ISNULL(fisico.e_Eliminado, 0) = 0
            LEFT JOIN dbo.PedidoVendedor_EnRuta_ProductoFisico previo WITH (UPDLOCK, HOLDLOCK)
                ON previo.Imei = a.Imei
               AND previo.E_Eliminado = 2
            WHERE fisico.Imei IS NULL OR previo.Imei IS NOT NULL
        )
            RAISERROR('Uno o mas IMEI no existen, no corresponden al producto o dejaron de estar disponibles.', 16, 1);

        SET @FechaConfirmacion = GETDATE();

        INSERT INTO @DetallePedidoNormal
        (
            IdDetalleRuta, IdProducto, Saldo, NvoPedido,
            ItemsHoy, Precio, TotalParcial
        )
        SELECT
            d.Id_CodigoPedidoVendedor_EnRuta,
            d.Id_Producto,
            ISNULL(saldo.Cantidad, 0),
            d.NvoPedido,
            ISNULL(saldo.Cantidad, 0) + d.NvoPedido,
            CONVERT(DECIMAL(18,2), ISNULL(d.Precio, producto.PrecioVenta)),
            CONVERT(FLOAT, (ISNULL(saldo.Cantidad, 0) + d.NvoPedido)
                * ISNULL(d.Precio, producto.PrecioVenta))
        FROM dbo.tbl_CodigoPedidoVendedor_EnRuta d
        INNER JOIN dbo.tbl_Producto producto
            ON producto.Id_Producto = d.Id_Producto
        LEFT JOIN dbo.tbl_SaldoTarjetas saldo WITH (UPDLOCK, HOLDLOCK)
            ON saldo.Id_Ruta = @IdRuta
           AND saldo.Id_Producto = d.Id_Producto
           AND saldo.E_Eliminado = 2
        WHERE d.Id_PedidoVendedor_EnRuta = @IdPedido
          AND d.E_Eliminado = 2;

        SELECT
            @TotalPedidoNormal = CONVERT(DECIMAL(18,2), SUM(TotalParcial)),
            @TotalAlmacen = CONVERT(DECIMAL(18,2), SUM(NvoPedido * Precio))
        FROM @DetallePedidoNormal;

        SELECT @TigoMoneyPedido = CONVERT(DECIMAL(18,2), ISNULL(SUM(NvoPedido), 0))
        FROM @DetallePedidoNormal
        WHERE IdProducto = 31;

        IF @TigoMoneyPedido > 0
        BEGIN
            SET @RecursoBloqueo = 'LoginGeneral:TigoMoney:'
                + CONVERT(VARCHAR(8), @FechaConfirmacion, 112);

            EXEC @ResultadoBloqueo = sys.sp_getapplock
                @Resource = @RecursoBloqueo,
                @LockMode = 'Exclusive',
                @LockOwner = 'Transaction',
                @LockTimeout = 15000;

            IF @ResultadoBloqueo < 0
                RAISERROR('No se pudo bloquear el saldo de Tigo Money. Intente nuevamente.', 16, 1);

            INSERT INTO @SaldosAlmacen (IdProducto, Producto, Cantidad)
            EXEC dbo.sp_Traer_Saldos_Productos_Almacen_X_Fecha @FechaConfirmacion;

            SELECT @SaldoTigoMoney = ISNULL(Cantidad, 0)
            FROM @SaldosAlmacen
            WHERE IdProducto = 31;

            SET @SaldoTigoMoney = ISNULL(@SaldoTigoMoney, 0);

            IF @SaldoTigoMoney - @TigoMoneyPedido < 0
            BEGIN
                DECLARE @MensajeSaldo VARCHAR(300);
                SET @MensajeSaldo = 'Saldo insuficiente de Tigo Money. Disponible: '
                    + CONVERT(VARCHAR(30), @SaldoTigoMoney)
                    + ', solicitado: ' + CONVERT(VARCHAR(30), @TigoMoneyPedido) + '.';
                RAISERROR(@MensajeSaldo, 16, 1);
            END;
        END;

        INSERT INTO dbo.tbl_PedidoVendedor
        (
            Id_Ruta, Id_Vendedor, Id_Usuario, Fecha, Fecha_Registro,
            Observacion, Total, E_Entregado, E_Pagado, E_Eliminado
        )
        VALUES
        (
            @IdRuta, @IdVendedor, @IdUsuarioAlmacenero,
            @FechaConfirmacion, @FechaConfirmacion, ISNULL(@Observacion, ''),
            @TotalPedidoNormal, 1, 2, 2
        );

        SET @IdPedidoVendedorNormal = CONVERT(INT, SCOPE_IDENTITY());

        INSERT INTO dbo.tbl_CodigoPedidoVendedor
        (
            Id_Producto, Id_PedidoVendedor, Saldo, NvoPedido,
            ItemsHoy, Precio, TotalParcial, E_Eliminado
        )
        SELECT
            IdProducto, @IdPedidoVendedorNormal, Saldo, NvoPedido,
            ItemsHoy, Precio, TotalParcial, 2
        FROM @DetallePedidoNormal;

        INSERT INTO dbo.tbl_AlmacenVendedor
        (
            Id_Ruta, Id_Vendedor, Id_PedidoVendedor, Id_Usuario,
            Fecha, Fecha_Registro, Observacion, Total, E_Eliminado
        )
        VALUES
        (
            @IdRuta, @IdVendedor, @IdPedidoVendedorNormal, @IdUsuarioAlmacenero,
            @FechaConfirmacion, @FechaConfirmacion, ISNULL(@Observacion, ''),
            @TotalAlmacen, 2
        );

        SET @IdAlmacenVendedor = CONVERT(INT, SCOPE_IDENTITY());

        INSERT INTO dbo.tbl_CodigoAlmacenVendedor
        (
            Id_Producto, Id_AlmacenVendedor, Cod_Inicio, Cod_Final,
            Cantidad, Precio, TotalParcial, E_Eliminado
        )
        SELECT
            detalle.IdProducto,
            @IdAlmacenVendedor,
            CONVERT(VARCHAR(50), MIN(asignado.Imei)),
            CONVERT(VARCHAR(50), MAX(asignado.Imei)),
            COUNT(*),
            detalle.Precio,
            CONVERT(FLOAT, COUNT(*) * detalle.Precio),
            2
        FROM @Asignados asignado
        INNER JOIN @DetallePedidoNormal detalle
            ON detalle.IdDetalleRuta = asignado.IdDetalle
        GROUP BY asignado.IdDetalle, asignado.NumeroTira,
                 detalle.IdProducto, detalle.Precio;

        INSERT INTO dbo.tbl_CodigoAlmacenVendedor
        (
            Id_Producto, Id_AlmacenVendedor, Cod_Inicio, Cod_Final,
            Cantidad, Precio, TotalParcial, E_Eliminado
        )
        SELECT
            IdProducto, @IdAlmacenVendedor, '0', '0',
            NvoPedido, Precio, CONVERT(FLOAT, NvoPedido * Precio), 2
        FROM @DetallePedidoNormal
        WHERE IdProducto = 31;

        INSERT INTO dbo.PedidoVendedor_EnRuta_ProductoFisico
        (
            Id_PedidoVendedor_EnRuta,
            Id_CodigoPedidoVendedor_EnRuta,
            Id_Producto,
            Imei,
            Id_Ruta,
            Id_UsuarioAlmacenero,
            Numero_Tira,
            Modo_Tira,
            Fecha_Registro,
            E_Eliminado
        )
        SELECT
            @IdPedido,
            d.Id_CodigoPedidoVendedor_EnRuta,
            d.Id_Producto,
            a.Imei,
            @IdRuta,
            @IdUsuarioAlmacenero,
            a.NumeroTira,
            a.ModoTira,
            GETDATE(),
            2
        FROM @Asignados a
        INNER JOIN dbo.tbl_CodigoPedidoVendedor_EnRuta d
            ON d.Id_CodigoPedidoVendedor_EnRuta = a.IdDetalle;

        UPDATE fisico
        SET fisico.Id_Ruta = @IdRuta,
            fisico.Id_PedidoVendedor = @IdPedidoVendedorNormal,
            fisico.Vendido = 1
        FROM dbo.tbl_Productos fisico
        INNER JOIN @Asignados a ON a.Imei = fisico.Imei
        INNER JOIN dbo.tbl_CodigoPedidoVendedor_EnRuta d
            ON d.Id_CodigoPedidoVendedor_EnRuta = a.IdDetalle
           AND d.Id_Producto = fisico.Id_Producto
        WHERE ISNULL(fisico.Id_Ruta, 0) = 0
          AND ISNULL(fisico.Id_PedidoVendedor, 0) = 0
          AND ISNULL(fisico.Vendido, 0) = 0
          AND ISNULL(fisico.e_Eliminado, 0) = 0;

        IF @@ROWCOUNT <> (SELECT COUNT(*) FROM @Asignados)
            RAISERROR('No se pudo actualizar exactamente un registro por cada IMEI asignado.', 16, 1);

        DECLARE @Cantidades TABLE
        (
            IdProducto INT NOT NULL PRIMARY KEY,
            Cantidad INT NOT NULL
        );

        INSERT INTO @Cantidades (IdProducto, Cantidad)
        SELECT movimiento.IdProducto, SUM(movimiento.Cantidad)
        FROM
        (
            SELECT d.Id_Producto AS IdProducto, COUNT(*) AS Cantidad
            FROM @Asignados a
            INNER JOIN dbo.tbl_CodigoPedidoVendedor_EnRuta d
                ON d.Id_CodigoPedidoVendedor_EnRuta = a.IdDetalle
            GROUP BY d.Id_Producto

            UNION ALL

            SELECT detalle.IdProducto, detalle.NvoPedido
            FROM @DetallePedidoNormal detalle
            WHERE detalle.IdProducto = 31
        ) movimiento
        GROUP BY movimiento.IdProducto;

        UPDATE saldo
        SET saldo.Cantidad = saldo.Cantidad + cantidad.Cantidad
        FROM dbo.tbl_SaldoTarjetas saldo
        INNER JOIN @Cantidades cantidad
            ON cantidad.IdProducto = saldo.Id_Producto
        WHERE saldo.Id_Ruta = @IdRuta
          AND saldo.E_Eliminado = 2;

        INSERT INTO dbo.tbl_SaldoTarjetas
        (
            Id_Producto, Id_Ruta, Cantidad, E_Eliminado
        )
        SELECT cantidad.IdProducto, @IdRuta, cantidad.Cantidad, 2
        FROM @Cantidades cantidad
        WHERE NOT EXISTS
        (
            SELECT 1
            FROM dbo.tbl_SaldoTarjetas saldo
            WHERE saldo.Id_Ruta = @IdRuta
              AND saldo.Id_Producto = cantidad.IdProducto
              AND saldo.E_Eliminado = 2
        );

        UPDATE dbo.tbl_PedidoVendedor_EnRuta
        SET Fecha = @FechaEntrega,
            E_Aprobado = 2,
            AprobadoPor = @AprobadoPor,
            Id_PedidoVendedorNormal = @IdPedidoVendedorNormal
        WHERE Id_PedidoVendedor_EnRuta = @IdPedido;

        COMMIT TRANSACTION;

        SELECT
            Id_PedidoVendedor_EnRuta AS IdPedido,
            Fecha AS FechaEntrega,
            E_Aprobado AS EstadoAprobado,
            AprobadoPor,
            @IdPedidoVendedorNormal AS IdPedidoVendedorNormal,
            @IdAlmacenVendedor AS IdAlmacenVendedor
        FROM dbo.tbl_PedidoVendedor_EnRuta
        WHERE Id_PedidoVendedor_EnRuta = @IdPedido;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        DECLARE @ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR(@ErrorMessage, 16, 1);
    END CATCH;
END;
GO
