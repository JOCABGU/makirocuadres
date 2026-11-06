
CREATE PROCEDURE dbo.spj_LoginGeneral_Cuadre_Finalizar
    @IdRuta INT,
    @IdVendedor INT,
    @IdUsuario INT,
    @Observacion VARCHAR(100),
    @TirasXml XML
AS
BEGIN
    SET NOCOUNT ON;
    SET ARITHABORT ON;
    SET XACT_ABORT ON;

    DECLARE @Hoy DATE = CONVERT(DATE, GETDATE());
    DECLARE @IdCuadre INT;
    DECLARE @ResultadoBloqueo INT;
    DECLARE @RecursoBloqueoSistemas NVARCHAR(255);
    DECLARE @RecursoBloqueoVendedor NVARCHAR(255);
    DECLARE @RecursoBloqueoRuta NVARCHAR(255);
    SET @RecursoBloqueoSistemas = N'LoginGeneral:Sistemas:CascadaRuta:' + CONVERT(NVARCHAR(20), @IdRuta);
    -- El bloqueo es por vendedor: el almacenero (Id_Usuario) puede cuadrar varias rutas en el dia.
    SET @RecursoBloqueoVendedor = N'LoginGeneral:Cuadre:Vendedor:' + CONVERT(NVARCHAR(20), @IdVendedor)
        + N':' + CONVERT(CHAR(8), @Hoy, 112);
    SET @RecursoBloqueoRuta = N'LoginGeneral:Cuadre:Ruta:' + CONVERT(NVARCHAR(20), @IdRuta)
        + N':' + CONVERT(CHAR(8), @Hoy, 112);

    DECLARE @Tiras TABLE
    (
        IdProducto INT NOT NULL,
        NumeroTira INT NOT NULL,
        Modo VARCHAR(20) NOT NULL,
        CantidadManual INT NOT NULL,
        Efectivizacion INT NOT NULL,
        PRIMARY KEY (IdProducto, NumeroTira)
    );

    INSERT INTO @Tiras (IdProducto, NumeroTira, Modo, CantidadManual, Efectivizacion)
    SELECT
        tira.valor.value('@producto', 'INT'),
        tira.valor.value('@numero', 'INT'),
        tira.valor.value('@modo', 'VARCHAR(20)'),
        tira.valor.value('@cantidad', 'INT'),
        tira.valor.value('@efectivizacion', 'INT')
    FROM @TirasXml.nodes('/tiras/tira') tira(valor);

    DECLARE @Imeis TABLE
    (
        IdProducto INT NOT NULL,
        NumeroTira INT NOT NULL,
        Modo VARCHAR(20) NOT NULL,
        Imei BIGINT NOT NULL,
        PRIMARY KEY (Imei)
    );

    INSERT INTO @Imeis (IdProducto, NumeroTira, Modo, Imei)
    SELECT
        tira.valor.value('@producto', 'INT'),
        tira.valor.value('@numero', 'INT'),
        tira.valor.value('@modo', 'VARCHAR(20)'),
        imei.valor.value('@v', 'BIGINT')
    FROM @TirasXml.nodes('/tiras/tira') tira(valor)
    CROSS APPLY tira.valor.nodes('i') imei(valor);

    IF NOT EXISTS (SELECT 1 FROM @Tiras)
    BEGIN
        RAISERROR('Debes registrar al menos un producto sobrante.', 16, 1);
        RETURN;
    END;

    IF EXISTS
    (
        SELECT 1 FROM @Tiras
        WHERE NumeroTira < 1 OR Modo NOT IN ('individual', 'rango', 'cantidad', 'tigo_money', 'chip_cantidad')
    )
    BEGIN
        RAISERROR('La Lista Master contiene una tira no valida.', 16, 1);
        RETURN;
    END;

    IF EXISTS
    (
        SELECT 1 FROM @Tiras tira
        WHERE tira.Modo NOT IN ('tigo_money', 'chip_cantidad')
          AND NOT EXISTS
          (
              SELECT 1 FROM @Imeis imei
              WHERE imei.IdProducto = tira.IdProducto
                AND imei.NumeroTira = tira.NumeroTira
                AND imei.Modo = tira.Modo
          )
    )
    BEGIN
        RAISERROR('Una tira fisica no contiene IMEI.', 16, 1);
        RETURN;
    END;

    IF EXISTS (SELECT 1 FROM @Imeis WHERE Modo = 'tigo_money')
    BEGIN
        RAISERROR('Tigo Money se registra manualmente y no debe contener IMEI.', 16, 1);
        RETURN;
    END;

    IF (SELECT COUNT(*) FROM @Tiras WHERE Modo = 'tigo_money') > 1
    BEGIN
        RAISERROR('Tigo Money solo puede registrarse una vez en el cuadre.', 16, 1);
        RETURN;
    END;

    IF EXISTS (SELECT 1 FROM @Imeis WHERE Modo = 'chip_cantidad')
    BEGIN
        RAISERROR('El sobrante de chips se registra por cantidad y no debe contener IMEI.', 16, 1);
        RETURN;
    END;

    IF EXISTS (SELECT 1 FROM @Tiras WHERE Modo = 'chip_cantidad' GROUP BY IdProducto HAVING COUNT(*) > 1)
    BEGIN
        RAISERROR('Cada chip solo puede registrarse una vez por cantidad.', 16, 1);
        RETURN;
    END;

    BEGIN TRY
        BEGIN TRANSACTION;

        EXEC @ResultadoBloqueo = sys.sp_getapplock
            @Resource = @RecursoBloqueoSistemas,
            @LockMode = 'Shared',
            @LockOwner = 'Transaction',
            @LockTimeout = 15000;

        IF @ResultadoBloqueo < 0
            RAISERROR('La ruta esta siendo restaurada por Sistemas. Intenta nuevamente al finalizar.', 16, 1);

        EXEC @ResultadoBloqueo = sys.sp_getapplock
            @Resource = @RecursoBloqueoVendedor,
            @LockMode = 'Exclusive',
            @LockOwner = 'Transaction',
            @LockTimeout = 15000;

        IF @ResultadoBloqueo < 0
            RAISERROR('No se pudo bloquear al vendedor para realizar el cuadre. Intenta nuevamente.', 16, 1);

        EXEC @ResultadoBloqueo = sys.sp_getapplock
            @Resource = @RecursoBloqueoRuta,
            @LockMode = 'Exclusive',
            @LockOwner = 'Transaction',
            @LockTimeout = 15000;

        IF @ResultadoBloqueo < 0
            RAISERROR('No se pudo bloquear la ruta para realizar el cuadre. Intenta nuevamente.', 16, 1);

        IF EXISTS
        (
            SELECT 1 FROM dbo.tbl_Cuadre WITH (UPDLOCK, HOLDLOCK)
            WHERE (Id_Vendedor = @IdVendedor OR Id_Ruta = @IdRuta)
              AND E_Eliminado = 2
              AND Fecha >= @Hoy
              AND Fecha < DATEADD(DAY, 1, @Hoy)
        )
            RAISERROR('El vendedor o la ruta ya tiene un cuadre registrado hoy. Solo se permite un cuadre por dia.', 16, 1);

        IF NOT EXISTS
        (
            SELECT 1 FROM dbo.tbl_Ruta WITH (UPDLOCK, HOLDLOCK)
            WHERE Id_Ruta = @IdRuta AND Id_Vendedor = @IdVendedor AND E_Eliminado = 2
        )
            RAISERROR('La ruta ya no pertenece al vendedor autenticado.', 16, 1);

        IF EXISTS
        (
            SELECT 1
            FROM @Tiras tira
            LEFT JOIN dbo.tbl_Producto producto ON producto.Id_Producto = tira.IdProducto
            WHERE tira.Modo = 'tigo_money'
              AND (producto.Id_Producto IS NULL
                   OR producto.Id_TipoProducto <> 5
                   OR UPPER(LTRIM(RTRIM(producto.Nombre))) <> 'TM_VENTA'
                   OR tira.CantidadManual < 0
                   OR tira.Efectivizacion < 0)
        )
            RAISERROR('El sobrante y la efectivizacion de Tigo Money deben ser mayores o iguales a cero.', 16, 1);

        IF EXISTS
        (
            SELECT 1
            FROM dbo.tbl_SaldoTarjetas saldo WITH (UPDLOCK, HOLDLOCK)
            INNER JOIN dbo.tbl_Producto producto ON producto.Id_Producto = saldo.Id_Producto
            WHERE saldo.Id_Ruta = @IdRuta
              AND saldo.E_Eliminado = 2
              AND producto.Id_TipoProducto = 5
              AND UPPER(LTRIM(RTRIM(producto.Nombre))) = 'TM_VENTA'
              AND ISNULL(saldo.Cantidad, 0) > 0
              AND NOT EXISTS (SELECT 1 FROM @Tiras WHERE Modo = 'tigo_money')
        )
            RAISERROR('Debes ingresar manualmente cuanto Tigo Money sobro antes de finalizar el cuadre.', 16, 1);

        IF EXISTS
        (
            SELECT 1
            FROM @Imeis solicitado
            LEFT JOIN dbo.tbl_Productos fisico WITH (UPDLOCK, HOLDLOCK)
                ON fisico.Imei = solicitado.Imei
               AND fisico.Id_Producto = solicitado.IdProducto
               AND fisico.Id_Ruta = @IdRuta
               AND ISNULL(fisico.Vendido, 0) = 1
               AND ISNULL(fisico.e_Eliminado, 0) = 0
            WHERE fisico.Imei IS NULL
        )
            RAISERROR('Uno o mas IMEI ya no pertenecen a la ruta, al producto o dejaron de estar en Vendido = 1.', 16, 1);

        IF EXISTS
        (
            SELECT 1
            FROM @Tiras tira
            LEFT JOIN dbo.tbl_Producto producto ON producto.Id_Producto = tira.IdProducto
            WHERE tira.Modo = 'chip_cantidad'
              AND (producto.Id_Producto IS NULL
                   OR ISNULL(producto.Id_TipoProducto, 0) <> 2
                   OR ISNULL(tira.CantidadManual, -1) < 0
                   OR EXISTS (SELECT 1 FROM @Imeis imei WHERE imei.IdProducto = tira.IdProducto))
        )
            RAISERROR('El sobrante por cantidad solo aplica a chips, debe ser mayor o igual a cero y no puede mezclarse con IMEI del mismo chip.', 16, 1);

        IF EXISTS
        (
            SELECT 1 FROM @Imeis imei
            INNER JOIN dbo.tbl_Producto producto ON producto.Id_Producto = imei.IdProducto
            WHERE producto.Id_TipoProducto = 2
        )
            RAISERROR('Los chips se cuadran por cantidad sobrante, no por IMEI.', 16, 1);

        DECLARE @Productos TABLE
        (
            IdProducto INT NOT NULL PRIMARY KEY,
            SaldoInicial INT NOT NULL,
            Sobrantes INT NOT NULL,
            Vendidos INT NOT NULL,
            Precio DECIMAL(18,2) NOT NULL
        );

        INSERT INTO @Productos (IdProducto, SaldoInicial, Sobrantes, Vendidos, Precio)
        SELECT
            existencia.IdProducto,
            existencia.Cantidad,
            ISNULL(sobrante.Cantidad, 0),
            existencia.Cantidad - ISNULL(sobrante.Cantidad, 0),
            ISNULL(producto.PrecioVenta, 0)
        FROM
        (
            SELECT fisico.Id_Producto AS IdProducto, CONVERT(INT, COUNT_BIG(*)) AS Cantidad
            FROM dbo.tbl_Productos fisico WITH (UPDLOCK, HOLDLOCK)
            WHERE fisico.Id_Ruta = @IdRuta
              AND ISNULL(fisico.Vendido, 0) = 1
              AND ISNULL(fisico.e_Eliminado, 0) = 0
            GROUP BY fisico.Id_Producto
        ) existencia
        INNER JOIN dbo.tbl_Producto producto ON producto.Id_Producto = existencia.IdProducto
        OUTER APPLY
        (
            SELECT COUNT(*) AS Cantidad FROM @Imeis i WHERE i.IdProducto = existencia.IdProducto
        ) sobrante
        WHERE existencia.Cantidad > 0
          AND ISNULL(producto.Id_TipoProducto, 0) NOT IN (2, 5);

        -- Chips: el saldo es el de tbl_SaldoTarjetas y el vendido = saldo - sobrante ingresado.
        -- Un chip con saldo que no se ingreso en el cuadre queda con sobrante 0 (todo vendido).
        INSERT INTO @Productos (IdProducto, SaldoInicial, Sobrantes, Vendidos, Precio)
        SELECT
            saldoChip.IdProducto,
            saldoChip.Cantidad,
            ISNULL(sobranteManual.Cantidad, 0),
            saldoChip.Cantidad - ISNULL(sobranteManual.Cantidad, 0),
            ISNULL(producto.PrecioVenta, 0)
        FROM
        (
            SELECT saldo.Id_Producto AS IdProducto, CONVERT(INT, SUM(ISNULL(saldo.Cantidad, 0))) AS Cantidad
            FROM dbo.tbl_SaldoTarjetas saldo WITH (UPDLOCK, HOLDLOCK)
            INNER JOIN dbo.tbl_Producto tipoChip ON tipoChip.Id_Producto = saldo.Id_Producto
            WHERE saldo.Id_Ruta = @IdRuta
              AND saldo.E_Eliminado = 2
              AND tipoChip.Id_TipoProducto = 2
            GROUP BY saldo.Id_Producto
        ) saldoChip
        INNER JOIN dbo.tbl_Producto producto ON producto.Id_Producto = saldoChip.IdProducto
        OUTER APPLY
        (
            SELECT SUM(t.CantidadManual) AS Cantidad
            FROM @Tiras t
            WHERE t.Modo = 'chip_cantidad' AND t.IdProducto = saldoChip.IdProducto
        ) sobranteManual
        WHERE saldoChip.Cantidad > 0;

        IF EXISTS
        (
            SELECT 1 FROM @Productos cuadrado
            INNER JOIN dbo.tbl_Producto producto ON producto.Id_Producto = cuadrado.IdProducto
            WHERE producto.Id_TipoProducto = 2 AND cuadrado.Vendidos < 0
        )
            RAISERROR('El sobrante de chips no puede superar el saldo de la ruta.', 16, 1);

        IF EXISTS
        (
            SELECT 1 FROM @Tiras t
            WHERE t.Modo = 'chip_cantidad' AND t.CantidadManual > 0
              AND NOT EXISTS (SELECT 1 FROM @Productos p WHERE p.IdProducto = t.IdProducto)
        )
            RAISERROR('Un chip registrado por cantidad no tiene saldo en la ruta.', 16, 1);

        DECLARE @IdTmVenta INT, @IdTmCompra INT, @SaldoTm INT, @SobranteTm INT, @EfectivizacionTm INT;
        DECLARE @VendidoTotalTm INT, @TmESobrante INT, @TmEVendido INT, @TmVSobrante INT, @TmVVendido INT;
        SELECT TOP 1
            @IdTmVenta = tira.IdProducto,
            @IdTmCompra = tira.IdProducto + 1,
            @SobranteTm = tira.CantidadManual,
            @EfectivizacionTm = tira.Efectivizacion
        FROM @Tiras tira WHERE tira.Modo = 'tigo_money';

        IF @IdTmVenta IS NOT NULL
        BEGIN
            SELECT @SaldoTm = CONVERT(INT, SUM(ISNULL(saldo.Cantidad, 0)))
            FROM dbo.tbl_SaldoTarjetas saldo WITH (UPDLOCK, HOLDLOCK)
            WHERE saldo.Id_Producto = @IdTmVenta AND saldo.Id_Ruta = @IdRuta AND saldo.E_Eliminado = 2;
            SET @SaldoTm = ISNULL(@SaldoTm, 0);
            SET @VendidoTotalTm = @SaldoTm + @EfectivizacionTm - @SobranteTm;
            IF @VendidoTotalTm < 0
                RAISERROR('El sobrante de Tigo Money no puede ser mayor que el saldo mas la efectivizacion.', 16, 1);

            SET @TmESobrante = CASE WHEN @VendidoTotalTm > @EfectivizacionTm THEN 0 ELSE @EfectivizacionTm - @VendidoTotalTm END;
            SET @TmEVendido = CASE WHEN @VendidoTotalTm > @EfectivizacionTm THEN @EfectivizacionTm ELSE @VendidoTotalTm END;
            SET @TmVSobrante = @SobranteTm - @TmESobrante;
            SET @TmVVendido = @SaldoTm - @TmVSobrante;

            INSERT INTO @Productos (IdProducto, SaldoInicial, Sobrantes, Vendidos, Precio)
            SELECT @IdTmVenta, @SaldoTm, @TmVSobrante, @TmVVendido, ISNULL(PrecioVenta, 0)
            FROM dbo.tbl_Producto WHERE Id_Producto = @IdTmVenta;

            IF @TmESobrante + @TmEVendido > 0
            BEGIN
                IF NOT EXISTS (SELECT 1 FROM dbo.tbl_Producto WHERE Id_Producto=@IdTmCompra AND Id_TipoProducto=5 AND UPPER(LTRIM(RTRIM(Nombre)))='TM_COMPRA')
                    RAISERROR('No se encontro el producto TM_Compra asociado a TM_Venta.', 16, 1);
                INSERT INTO @Productos (IdProducto, SaldoInicial, Sobrantes, Vendidos, Precio)
                SELECT @IdTmCompra, @EfectivizacionTm, @TmESobrante, @TmEVendido, ISNULL(PrecioVenta, 0)
                FROM dbo.tbl_Producto WHERE Id_Producto = @IdTmCompra;
            END;
        END;

        IF EXISTS (SELECT 1 FROM @Productos WHERE Vendidos < 0)
            RAISERROR('Los sobrantes superan el saldo disponible de la ruta.', 16, 1);

        IF NOT EXISTS (SELECT 1 FROM @Productos)
            RAISERROR('La ruta no tiene productos fisicos con saldo para cuadrar.', 16, 1);

        IF EXISTS
        (
            SELECT 1 FROM @Imeis i
            WHERE NOT EXISTS (SELECT 1 FROM @Productos p WHERE p.IdProducto = i.IdProducto)
        )
            RAISERROR('La Lista Master contiene un producto sin saldo activo en la ruta.', 16, 1);

        INSERT INTO dbo.tbl_Cuadre
        (
            Id_Ruta, Id_Vendedor, Id_Usuario, Fecha, Observacion,
            Total, E_Cobrado, E_Eliminado
        )
        SELECT
            @IdRuta, @IdVendedor, @IdUsuario, GETDATE(), NULLIF(LTRIM(RTRIM(@Observacion)), ''),
            SUM(CONVERT(FLOAT, Vendidos * Precio)), 1, 2
        FROM @Productos;

        SET @IdCuadre = CONVERT(INT, SCOPE_IDENTITY());

        INSERT INTO dbo.tbl_CodigoCuadre
        (
            Id_Cuadre, Id_Producto, ItemsSobrantes, ItemsVendidos,
            Precio, TotalVendidos, E_Eliminado
        )
        SELECT
            @IdCuadre, IdProducto, Sobrantes, Vendidos,
            Precio, CONVERT(FLOAT, Vendidos * Precio), 2
        FROM @Productos;

        IF @IdTmVenta IS NOT NULL
        BEGIN
            INSERT INTO dbo.tbl_GiroTigo
            (
                Id_Cuadre,
                Id_Ruta,
                Fecha_Cuadre,
                GiroCompraSobrante,
                GiroCompraVendido,
                Bono,
                GiroVentaSobrante,
                GiroVentaVendido,
                E_Cobrado,
                E_Eliminado,
                Fecha_Registro,
                Id_Usuario
            )
            VALUES
            (
                @IdCuadre,
                @IdRuta,
                GETDATE(),
                ISNULL(@TmESobrante, 0),
                ISNULL(@TmEVendido, 0),
                0,
                ISNULL(@TmVSobrante, 0),
                ISNULL(@TmVVendido, 0),
                2,
                0,
                GETDATE(),
                @IdUsuario
            );
        END;

        INSERT INTO dbo.tbl_SaldoCuadre
        (
            Id_Cuadre, Id_Producto, Cantidad, Cod_Inicio, Cod_Final, E_Eliminado
        )
        SELECT
            @IdCuadre,
            IdProducto,
            1,
            CONVERT(NVARCHAR(100), Imei),
            CONVERT(NVARCHAR(100), Imei),
            0
        FROM @Imeis
        WHERE Modo = 'individual'

        UNION ALL

        -- Cada tramo consecutivo de una tira (rango/cantidad) se guarda por separado, asi una
        -- tira con IMEI quitados no reactiva los huecos al aplicar Cod_Inicio..Cod_Final.
        SELECT
            @IdCuadre,
            IdProducto,
            COUNT(*),
            CONVERT(NVARCHAR(100), MIN(Imei)),
            CONVERT(NVARCHAR(100), MAX(Imei)),
            0
        FROM
        (
            SELECT
                IdProducto, NumeroTira, Modo, Imei,
                Imei - ROW_NUMBER() OVER (PARTITION BY IdProducto, NumeroTira, Modo ORDER BY Imei) AS Tramo
            FROM @Imeis
            WHERE Modo <> 'individual'
        ) consecutivo
        GROUP BY IdProducto, NumeroTira, Modo, Tramo

        UNION ALL

        SELECT @IdCuadre, cuadrado.IdProducto, cuadrado.Sobrantes, N'0', N'0', 0
        FROM @Productos cuadrado
        INNER JOIN dbo.tbl_Producto producto ON producto.Id_Producto=cuadrado.IdProducto
        WHERE producto.Id_TipoProducto=5

        UNION ALL

        -- Chips registrados solo por cantidad: sin codigos, igual que Tigo Money.
        SELECT @IdCuadre, tira.IdProducto, tira.CantidadManual, N'0', N'0', 0
        FROM @Tiras tira
        WHERE tira.Modo = 'chip_cantidad' AND tira.CantidadManual > 0;

        DECLARE @ProductoActual INT;
        DECLARE productos_cursor CURSOR LOCAL FAST_FORWARD FOR
            SELECT cuadrado.IdProducto
            FROM @Productos cuadrado
            INNER JOIN dbo.tbl_Producto producto ON producto.Id_Producto = cuadrado.IdProducto
            WHERE ISNULL(producto.Id_TipoProducto, 0) <> 5;
        OPEN productos_cursor;
        FETCH NEXT FROM productos_cursor INTO @ProductoActual;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            EXEC dbo.spy_ModificarEstadoProductos_x_IdRuta_IdProducto_IdCuadre
                '0', '0', @ProductoActual, @IdRuta, @IdCuadre;
            FETCH NEXT FROM productos_cursor INTO @ProductoActual;
        END;
        CLOSE productos_cursor;
        DEALLOCATE productos_cursor;

        DECLARE @Inicio VARCHAR(25), @Final VARCHAR(25);
        DECLARE tiras_cursor CURSOR LOCAL FAST_FORWARD FOR
            SELECT CONVERT(VARCHAR(25), Cod_Inicio), CONVERT(VARCHAR(25), Cod_Final), Id_Producto
            FROM dbo.tbl_SaldoCuadre
            WHERE Id_Cuadre = @IdCuadre AND E_Eliminado = 0
              AND NOT (Cod_Inicio = N'0' AND Cod_Final = N'0');
        OPEN tiras_cursor;
        FETCH NEXT FROM tiras_cursor INTO @Inicio, @Final, @ProductoActual;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            EXEC dbo.spy_ModificarEstadoProductos_x_IdRuta_IdProducto_IdCuadre
                @Inicio, @Final, @ProductoActual, @IdRuta, @IdCuadre;
            FETCH NEXT FROM tiras_cursor INTO @Inicio, @Final, @ProductoActual;
        END;
        CLOSE tiras_cursor;
        DEALLOCATE tiras_cursor;

        -- Chips: el cursor anterior marco como vendidos todos los chips fisicos de la ruta.
        -- Quedan vendidos solo los mas antiguos (pedido mas antiguo, luego IMEI mas bajo),
        -- tantos como el vendido calculado contra tbl_SaldoTarjetas; el resto vuelve a Vendido = 1.
        ;WITH chipsPorAntiguedad AS
        (
            SELECT
                fisico.Vendido,
                cuadrado.Vendidos,
                ROW_NUMBER() OVER (
                    PARTITION BY fisico.Id_Producto
                    ORDER BY ISNULL(fisico.Id_PedidoVendedor, 0), fisico.Imei) AS Orden
            FROM dbo.tbl_Productos fisico
            INNER JOIN @Productos cuadrado ON cuadrado.IdProducto = fisico.Id_Producto
            INNER JOIN dbo.tbl_Producto producto
                ON producto.Id_Producto = fisico.Id_Producto
               AND producto.Id_TipoProducto = 2
            WHERE fisico.Id_Ruta = @IdRuta
              AND fisico.Id_Cuadre = @IdCuadre
              AND fisico.Vendido = 2
              AND ISNULL(fisico.e_Eliminado, 0) = 0
        )
        UPDATE chipsPorAntiguedad
        SET Vendido = 1
        WHERE Orden > Vendidos;

        UPDATE saldo
        SET saldo.Cantidad = producto.Sobrantes
        FROM dbo.tbl_SaldoTarjetas saldo
        INNER JOIN @Productos producto ON producto.IdProducto = saldo.Id_Producto
        WHERE saldo.Id_Ruta = @IdRuta AND saldo.E_Eliminado = 2;

        COMMIT TRANSACTION;

        SELECT
            @IdCuadre AS IdCuadre,
            @IdRuta AS IdRuta,
            GETDATE() AS Fecha,
            ISNULL((SELECT SUM(Sobrantes) FROM @Productos), 0) AS TotalSobrantes,
            ISNULL((SELECT SUM(Vendidos) FROM @Productos), 0) AS TotalVendidos,
            ISNULL((SELECT SUM(CONVERT(DECIMAL(18,2), Vendidos * Precio)) FROM @Productos), 0) AS Total;
    END TRY
    BEGIN CATCH
        IF CURSOR_STATUS('local', 'productos_cursor') > -1
            CLOSE productos_cursor;
        IF CURSOR_STATUS('local', 'productos_cursor') >= -1
        BEGIN
            DEALLOCATE productos_cursor;
        END;
        IF CURSOR_STATUS('local', 'tiras_cursor') > -1
            CLOSE tiras_cursor;
        IF CURSOR_STATUS('local', 'tiras_cursor') >= -1
        BEGIN
            DEALLOCATE tiras_cursor;
        END;
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        DECLARE @Mensaje NVARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR(@Mensaje, 16, 1);
    END CATCH;
END;

