SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET NUMERIC_ROUNDABORT OFF;
GO

-- El rollback necesita localizar por pedido unas pocas unidades dentro de
-- tbl_Productos. Esta tabla contiene millones de filas, por lo que el acceso
-- debe estar cubierto por Id_PedidoVendedor + Imei.
IF NOT EXISTS
(
    SELECT 1
    FROM sys.indexes
    WHERE object_id = OBJECT_ID(N'dbo.tbl_Productos')
      AND name = N'IX_tbl_Productos_IdPedidoVendedor_Imei'
)
BEGIN
    CREATE NONCLUSTERED INDEX IX_tbl_Productos_IdPedidoVendedor_Imei
        ON dbo.tbl_Productos (Id_PedidoVendedor, Imei);
END;
GO

-- ============================================================================
-- Panel de Sistemas: reversion en cascada de pedidos y cuadres por ruta.
--
-- Regla de negocio (impuesta por el negocio, no relajar):
--   No se puede "hacer puente". Si se necesita anular un movimiento de hace
--   3 dias, se anulan TODOS los movimientos (pedidos aprobados, cuadres
--   definitivos, cuadres preliminares y pedidos pendientes) de esa MISMA
--   ruta desde ese punto hasta hoy, sin dejar nada a medias en el intervalo.
--
-- Por eso la cascada siempre procesa del mas reciente al mas antiguo: en
-- cada paso, lo que se esta revirtiendo es garantizadamente lo ultimo que
-- toco esa ruta (todo lo posterior ya fue revertido en el mismo lote), asi
-- que restaurar tbl_Productos / tbl_SaldoTarjetas a su valor "justo antes
-- de este movimiento" es siempre correcto y no requiere casos especiales.
-- ============================================================================

IF OBJECT_ID(N'dbo.tbl_Sistemas_ReversionRuta', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.tbl_Sistemas_ReversionRuta
    (
        Id_ReversionRuta INT IDENTITY(1,1) NOT NULL,
        Id_Ruta INT NOT NULL,
        DesdeFecha DATETIME NOT NULL,
        Id_UsuarioSistemas INT NOT NULL,
        NombreUsuarioSistemas VARCHAR(150) NOT NULL,
        Justificacion VARCHAR(500) NOT NULL,
        CantidadMovimientos INT NOT NULL,
        DetalleJson NVARCHAR(MAX) NULL,
        Fecha_Registro DATETIME NOT NULL CONSTRAINT DF_Sistemas_ReversionRuta_Fecha DEFAULT (GETDATE()),
        CONSTRAINT PK_Sistemas_ReversionRuta PRIMARY KEY CLUSTERED (Id_ReversionRuta)
    );
END;
GO

IF COL_LENGTH('dbo.tbl_Sistemas_ReversionRuta', 'JobId') IS NULL
    ALTER TABLE dbo.tbl_Sistemas_ReversionRuta ADD JobId VARCHAR(100) NULL;
GO

IF EXISTS
(
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID(N'dbo.tbl_Sistemas_ReversionRuta')
      AND name = N'UX_Sistemas_ReversionRuta_JobId'
)
    DROP INDEX UX_Sistemas_ReversionRuta_JobId ON dbo.tbl_Sistemas_ReversionRuta;
GO

UPDATE dbo.tbl_Sistemas_ReversionRuta
SET JobId = 'legacy-' + CONVERT(VARCHAR(20), Id_ReversionRuta)
WHERE JobId IS NULL;
GO

ALTER TABLE dbo.tbl_Sistemas_ReversionRuta ALTER COLUMN JobId VARCHAR(100) NOT NULL;
GO

IF NOT EXISTS
(
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID(N'dbo.tbl_Sistemas_ReversionRuta')
      AND name = N'UX_Sistemas_ReversionRuta_JobId'
)
    CREATE UNIQUE INDEX UX_Sistemas_ReversionRuta_JobId
        ON dbo.tbl_Sistemas_ReversionRuta(JobId);
GO

-- El historial de una asignacion se conserva, pero un IMEI restaurado debe
-- poder asignarse nuevamente. La unicidad aplica solo a la asignacion activa.
IF EXISTS
(
    SELECT 1 FROM sys.key_constraints
    WHERE parent_object_id = OBJECT_ID(N'dbo.PedidoVendedor_EnRuta_ProductoFisico')
      AND name = N'UQ_PedidoVendedor_EnRuta_ProductoFisico_Imei'
)
    ALTER TABLE dbo.PedidoVendedor_EnRuta_ProductoFisico
        DROP CONSTRAINT UQ_PedidoVendedor_EnRuta_ProductoFisico_Imei;
GO

IF EXISTS
(
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID(N'dbo.PedidoVendedor_EnRuta_ProductoFisico')
      AND name = N'UQ_PedidoVendedor_EnRuta_ProductoFisico_Imei'
)
    DROP INDEX UQ_PedidoVendedor_EnRuta_ProductoFisico_Imei
        ON dbo.PedidoVendedor_EnRuta_ProductoFisico;
GO

IF EXISTS
(
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID(N'dbo.PedidoVendedor_EnRuta_ProductoFisico')
      AND name = N'UX_PedidoRutaProductoFisico_Imei_Activo'
)
    DROP INDEX UX_PedidoRutaProductoFisico_Imei_Activo
        ON dbo.PedidoVendedor_EnRuta_ProductoFisico;
GO

IF NOT EXISTS
(
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID(N'dbo.PedidoVendedor_EnRuta_ProductoFisico')
      AND name = N'IX_PedidoRutaProductoFisico_Imei_Estado'
)
    CREATE INDEX IX_PedidoRutaProductoFisico_Imei_Estado
        ON dbo.PedidoVendedor_EnRuta_ProductoFisico(Imei, E_Eliminado);
GO

IF OBJECT_ID(N'dbo.trg_PedidoRutaProductoFisico_ImeiActivoUnico', N'TR') IS NULL
    EXEC(N'CREATE TRIGGER dbo.trg_PedidoRutaProductoFisico_ImeiActivoUnico ON dbo.PedidoVendedor_EnRuta_ProductoFisico AFTER INSERT, UPDATE AS BEGIN SET NOCOUNT ON; END');
GO

ALTER TRIGGER dbo.trg_PedidoRutaProductoFisico_ImeiActivoUnico
ON dbo.PedidoVendedor_EnRuta_ProductoFisico
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS
    (
        SELECT asignacion.Imei
        FROM dbo.PedidoVendedor_EnRuta_ProductoFisico asignacion WITH (UPDLOCK, HOLDLOCK)
        INNER JOIN inserted nuevo ON nuevo.Imei = asignacion.Imei
        WHERE asignacion.E_Eliminado = 2
        GROUP BY asignacion.Imei
        HAVING COUNT(*) > 1
    )
    BEGIN
        RAISERROR('El IMEI ya tiene una asignacion activa en otro pedido.', 16, 1);
        ROLLBACK TRANSACTION;
        RETURN;
    END;
END;
GO

-- Indices de lectura para que la vista previa pueda reconstruir pedidos y
-- cuadres historicos sin recorrer completas las tablas operativas.
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.tbl_Productos') AND name = N'IX_Productos_CuadreProductoEstado')
    CREATE INDEX IX_Productos_CuadreProductoEstado
        ON dbo.tbl_Productos(Id_Cuadre, Id_Producto, Vendido, Id_Ruta);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.tbl_CodigoCuadre') AND name = N'IX_CodigoCuadre_CuadreEstadoProducto')
    CREATE INDEX IX_CodigoCuadre_CuadreEstadoProducto
        ON dbo.tbl_CodigoCuadre(Id_Cuadre, E_Eliminado, Id_Producto);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.tbl_SaldoCuadre') AND name = N'IX_SaldoCuadre_CuadreProductoEstado')
    CREATE INDEX IX_SaldoCuadre_CuadreProductoEstado
        ON dbo.tbl_SaldoCuadre(Id_Cuadre, Id_Producto, E_Eliminado);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.tbl_TransaccionCuadre') AND name = N'IX_TransaccionCuadre_Cuadre')
    CREATE INDEX IX_TransaccionCuadre_Cuadre ON dbo.tbl_TransaccionCuadre(Id_Cuadre);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.tbl_Deuda') AND name = N'IX_Deuda_Cuadre')
    CREATE INDEX IX_Deuda_Cuadre ON dbo.tbl_Deuda(Id_Cuadre);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.tbl_CodigoPedidoVendedor') AND name = N'IX_CodigoPedidoVendedor_PedidoEstadoProducto')
    CREATE INDEX IX_CodigoPedidoVendedor_PedidoEstadoProducto
        ON dbo.tbl_CodigoPedidoVendedor(Id_PedidoVendedor, E_Eliminado, Id_Producto);
GO

-- ----------------------------------------------------------------------------
-- Listado de rutas con su ultimo movimiento (para elegir la ruta en el panel).
-- ----------------------------------------------------------------------------
IF OBJECT_ID(N'dbo.spj_LoginGeneral_Sistemas_ListarRutas', N'P') IS NULL
    EXEC(N'CREATE PROCEDURE dbo.spj_LoginGeneral_Sistemas_ListarRutas AS BEGIN SET NOCOUNT ON; END');
GO

ALTER PROCEDURE dbo.spj_LoginGeneral_Sistemas_ListarRutas
AS
BEGIN
    SET NOCOUNT ON;
    SET ARITHABORT ON;

    SELECT
        ruta.Id_Ruta AS IdRuta,
        ruta.Nombre AS Ruta,
        ruta.Id_Vendedor AS IdVendedor,
        ISNULL(vendedor.Nombre, 'Sin tecnico asignado') AS Tecnico,
        ultimo.UltimoMovimiento
    FROM dbo.tbl_Ruta ruta
    LEFT JOIN dbo.tbl_Vendedor vendedor ON vendedor.Id_Vendedor = ruta.Id_Vendedor
    OUTER APPLY
    (
        SELECT MAX(fecha) AS UltimoMovimiento
        FROM
        (
            SELECT MAX(c.Fecha) AS fecha FROM dbo.tbl_Cuadre c WHERE c.Id_Ruta = ruta.Id_Ruta AND c.E_Eliminado = 2
            UNION ALL
            SELECT MAX(p.Fecha_Registro) FROM dbo.tbl_PedidoVendedor_EnRuta p WHERE p.Id_Ruta = ruta.Id_Ruta AND p.E_Eliminado = 2
        ) todo
    ) ultimo
    WHERE ruta.E_Eliminado = 2
    ORDER BY ISNULL(ultimo.UltimoMovimiento, '19000101') DESC, ruta.Nombre;
END;
GO

-- ----------------------------------------------------------------------------
-- Linea de tiempo unificada de una ruta: pedidos + cuadres (preliminares y
-- definitivos), ordenados por fecha real (no por la fecha de entrega elegida
-- a mano, que puede ser futura). El frontend decide si los muestra juntos o
-- separados por Tipo.
-- ----------------------------------------------------------------------------
IF OBJECT_ID(N'dbo.spj_LoginGeneral_Sistemas_ListarMovimientosRuta', N'P') IS NULL
    EXEC(N'CREATE PROCEDURE dbo.spj_LoginGeneral_Sistemas_ListarMovimientosRuta AS BEGIN SET NOCOUNT ON; END');
GO

ALTER PROCEDURE dbo.spj_LoginGeneral_Sistemas_ListarMovimientosRuta
    @IdRuta INT,
    @FechaDesde DATE,
    @FechaHasta DATE
AS
BEGIN
    SET NOCOUNT ON;
    SET ARITHABORT ON;

    ;WITH Movimientos AS
    (
        SELECT
            'CUADRE' AS Tipo,
            c.Id_Cuadre AS IdReferencia,
            c.Fecha AS Fecha,
            c.Total AS Total,
            'DEFINITIVO' AS Estado,
            c.Observacion AS Observacion
        FROM dbo.tbl_Cuadre c
        WHERE c.Id_Ruta = @IdRuta AND c.E_Eliminado = 2
          AND c.Fecha >= @FechaDesde AND c.Fecha < DATEADD(DAY, 1, @FechaHasta)

        UNION ALL

        SELECT
            'CUADRE_PRELIMINAR',
            cr.Id_Cuadre_EnRuta,
            cr.Fecha,
            cr.Total,
            CASE ISNULL(cr.E_Aprobado, 1) WHEN 1 THEN 'PENDIENTE' ELSE 'APROBADO' END,
            cr.Observacion
        FROM dbo.tbl_Cuadre_EnRuta cr
        WHERE cr.Id_Ruta = @IdRuta AND cr.E_Eliminado = 2
          AND cr.Fecha >= @FechaDesde AND cr.Fecha < DATEADD(DAY, 1, @FechaHasta)

        UNION ALL

        SELECT
            'PEDIDO',
            per.Id_PedidoVendedor_EnRuta,
            ISNULL(pv.Fecha_Registro, per.Fecha_Registro),
            per.Total,
            CASE per.E_Aprobado WHEN 1 THEN 'PENDIENTE' ELSE 'APROBADO' END,
            per.Observacion
        FROM dbo.tbl_PedidoVendedor_EnRuta per
        LEFT JOIN dbo.tbl_PedidoVendedor pv
            ON pv.Id_PedidoVendedor = per.Id_PedidoVendedorNormal
           AND per.Id_PedidoVendedorNormal > 0
           AND pv.E_Eliminado = 2
        WHERE per.Id_Ruta = @IdRuta AND per.E_Eliminado = 2
          AND ISNULL(pv.Fecha_Registro, per.Fecha_Registro) >= @FechaDesde
          AND ISNULL(pv.Fecha_Registro, per.Fecha_Registro) < DATEADD(DAY, 1, @FechaHasta)
    )
    SELECT Tipo, IdReferencia, Fecha, Total, Estado, Observacion
    FROM Movimientos
    ORDER BY Fecha DESC, IdReferencia DESC;
END;
GO

-- ----------------------------------------------------------------------------
-- Construye (sin escribir nada) la cola de movimientos que la cascada
-- tocaria: la ruta completa desde @DesdeFecha (inclusive) hasta ahora,
-- ordenada del mas reciente al mas antiguo. Usada tanto por el preview
-- como por la ejecucion real, para garantizar que ambas vean exactamente
-- lo mismo.
-- ----------------------------------------------------------------------------
IF OBJECT_ID(N'dbo.spj_LoginGeneral_Sistemas_PreviewCascadaRuta', N'P') IS NULL
    EXEC(N'CREATE PROCEDURE dbo.spj_LoginGeneral_Sistemas_PreviewCascadaRuta AS BEGIN SET NOCOUNT ON; END');
GO

ALTER PROCEDURE dbo.spj_LoginGeneral_Sistemas_PreviewCascadaRuta
    @IdRuta INT,
    @DesdeFecha DATETIME
AS
BEGIN
    SET NOCOUNT ON;
    SET ARITHABORT ON;

    ;WITH Movimientos AS
    (
        SELECT 'CUADRE' AS Tipo, c.Id_Cuadre AS IdReferencia, c.Fecha AS Fecha, c.Total AS Total
        FROM dbo.tbl_Cuadre c
        WHERE c.Id_Ruta = @IdRuta AND c.E_Eliminado = 2 AND c.Fecha >= @DesdeFecha

        UNION ALL

        SELECT 'PEDIDO', per.Id_PedidoVendedor_EnRuta, ISNULL(pv.Fecha_Registro, per.Fecha_Registro), per.Total
        FROM dbo.tbl_PedidoVendedor_EnRuta per
        INNER JOIN dbo.tbl_PedidoVendedor pv
            ON pv.Id_PedidoVendedor = per.Id_PedidoVendedorNormal
           AND per.Id_PedidoVendedorNormal > 0 AND pv.E_Eliminado = 2
        WHERE per.Id_Ruta = @IdRuta AND per.E_Eliminado = 2 AND per.E_Aprobado = 2
          AND pv.Fecha_Registro >= @DesdeFecha
    )
    SELECT Tipo, IdReferencia, Fecha, Total
    FROM Movimientos
    ORDER BY Fecha DESC, IdReferencia DESC;
END;
GO

-- Vista previa operativa: muestra el valor actual, el valor registrado antes
-- y despues de cada movimiento, y el saldo final que quedaria al completar
-- toda la cascada. No escribe datos.
IF OBJECT_ID(N'dbo.spj_LoginGeneral_Sistemas_PreviewDetalleCascadaRuta', N'P') IS NULL
    EXEC(N'CREATE PROCEDURE dbo.spj_LoginGeneral_Sistemas_PreviewDetalleCascadaRuta AS BEGIN SET NOCOUNT ON; END');
GO

ALTER PROCEDURE dbo.spj_LoginGeneral_Sistemas_PreviewDetalleCascadaRuta
    @IdRuta INT,
    @DesdeFecha DATETIME
AS
BEGIN
    SET NOCOUNT ON;
    SET ARITHABORT ON;

    ;WITH Detalle AS
    (
        SELECT
            'CUADRE' AS Tipo,
            c.Id_Cuadre AS IdReferencia,
            c.Fecha,
            CONVERT(DECIMAL(18,2), c.Total) AS Total,
            'DEFINITIVO' AS EstadoActual,
            'ANULADO; PRELIMINAR PENDIENTE' AS EstadoProyectado,
            c.Observacion,
            cc.Id_Producto AS IdProducto,
            producto.Nombre AS Producto,
            cc.ItemsVendidos AS CantidadMovimiento,
            ISNULL(saldo.Cantidad, 0) AS SaldoActual,
            cc.ItemsSobrantes + cc.ItemsVendidos AS SaldoAntesMovimiento,
            cc.ItemsSobrantes AS SaldoDespuesMovimiento,
            (SELECT COUNT(*) FROM dbo.tbl_Productos fisico
             WHERE fisico.Id_Cuadre = c.Id_Cuadre AND fisico.Id_Producto = cc.Id_Producto) AS FisicosAfectados,
            (SELECT COUNT(*) FROM dbo.tbl_Productos fisico
             WHERE fisico.Id_Cuadre = c.Id_Cuadre AND fisico.Id_Producto = cc.Id_Producto AND fisico.Vendido = 2) AS FisicosVendidos,
            STUFF((
                SELECT '; ' + ISNULL(CONVERT(NVARCHAR(100), tira.Cod_Inicio), '0')
                    + ' - ' + ISNULL(CONVERT(NVARCHAR(100), tira.Cod_Final), '0')
                    + ' (' + CONVERT(NVARCHAR(20), tira.Cantidad) + ')'
                FROM dbo.tbl_SaldoCuadre tira
                WHERE tira.Id_Cuadre = c.Id_Cuadre
                  AND tira.Id_Producto = cc.Id_Producto
                  AND ISNULL(tira.E_Eliminado, 0) = 0
                ORDER BY tira.Id_SaldoCuadre
                FOR XML PATH(''), TYPE
            ).value('.', 'NVARCHAR(MAX)'), 1, 2, '') AS Codigos,
            'tbl_Cuadre' AS TablaPrincipal,
            'tbl_Cuadre, tbl_CodigoCuadre, tbl_SaldoCuadre, tbl_Productos, tbl_SaldoTarjetas, tbl_GiroTigo, tbl_Cuadre_EnRuta, tbl_CodigoCuadre_EnRuta, tbl_TransaccionCuadre, tbl_Caja, tbl_Deuda, tbl_Sistemas_ReversionRuta' AS TablasAfectadas,
            0 AS Bloqueado,
            CAST(NULL AS VARCHAR(500)) AS MotivoBloqueo
        FROM dbo.tbl_Cuadre c
        INNER JOIN dbo.tbl_CodigoCuadre cc
            ON cc.Id_Cuadre = c.Id_Cuadre AND cc.E_Eliminado = 2
        INNER JOIN dbo.tbl_Producto producto ON producto.Id_Producto = cc.Id_Producto
        LEFT JOIN dbo.tbl_SaldoTarjetas saldo
            ON saldo.Id_Ruta = c.Id_Ruta AND saldo.Id_Producto = cc.Id_Producto AND saldo.E_Eliminado = 2
        WHERE c.Id_Ruta = @IdRuta AND c.E_Eliminado = 2 AND c.Fecha >= @DesdeFecha

        UNION ALL

        SELECT
            'PEDIDO',
            per.Id_PedidoVendedor_EnRuta,
            ISNULL(pv.Fecha_Registro, per.Fecha_Registro),
            CONVERT(DECIMAL(18,2), per.Total),
            'APROBADO',
            'PENDIENTE',
            per.Observacion,
            codigo.Id_Producto,
            producto.Nombre,
            codigo.NvoPedido,
            ISNULL(saldo.Cantidad, 0),
            codigo.Saldo,
            codigo.ItemsHoy,
            (SELECT COUNT(*) FROM dbo.PedidoVendedor_EnRuta_ProductoFisico fisico
             WHERE fisico.Id_PedidoVendedor_EnRuta = per.Id_PedidoVendedor_EnRuta
               AND fisico.Id_Producto = codigo.Id_Producto AND fisico.E_Eliminado = 2),
            0,
            STUFF((
                SELECT '; Tira ' + CONVERT(NVARCHAR(20), tiras.Numero_Tira)
                    + ': ' + CONVERT(NVARCHAR(30), tiras.Inicio)
                    + CASE WHEN tiras.Inicio = tiras.Final THEN '' ELSE ' - ' + CONVERT(NVARCHAR(30), tiras.Final) END
                    + ' (' + CONVERT(NVARCHAR(20), tiras.Cantidad) + ')'
                FROM
                (
                    SELECT fisico.Numero_Tira, MIN(fisico.Imei) AS Inicio,
                           MAX(fisico.Imei) AS Final, COUNT(*) AS Cantidad
                    FROM dbo.PedidoVendedor_EnRuta_ProductoFisico fisico
                    WHERE fisico.Id_PedidoVendedor_EnRuta = per.Id_PedidoVendedor_EnRuta
                      AND fisico.Id_Producto = codigo.Id_Producto AND fisico.E_Eliminado = 2
                    GROUP BY fisico.Numero_Tira
                ) tiras
                ORDER BY tiras.Numero_Tira
                FOR XML PATH(''), TYPE
            ).value('.', 'NVARCHAR(MAX)'), 1, 2, ''),
            'tbl_PedidoVendedor_EnRuta',
            'tbl_PedidoVendedor_EnRuta, tbl_PedidoVendedor, tbl_CodigoPedidoVendedor, tbl_AlmacenVendedor, tbl_CodigoAlmacenVendedor, PedidoVendedor_EnRuta_ProductoFisico, tbl_Productos, tbl_SaldoTarjetas',
            0,
            NULL
        FROM dbo.tbl_PedidoVendedor_EnRuta per
        INNER JOIN dbo.tbl_PedidoVendedor pv
            ON pv.Id_PedidoVendedor = per.Id_PedidoVendedorNormal
           AND per.Id_PedidoVendedorNormal > 0 AND pv.E_Eliminado = 2
        INNER JOIN dbo.tbl_CodigoPedidoVendedor codigo
            ON codigo.Id_PedidoVendedor = pv.Id_PedidoVendedor AND codigo.E_Eliminado = 2
        INNER JOIN dbo.tbl_Producto producto ON producto.Id_Producto = codigo.Id_Producto
        LEFT JOIN dbo.tbl_SaldoTarjetas saldo
            ON saldo.Id_Ruta = per.Id_Ruta AND saldo.Id_Producto = codigo.Id_Producto AND saldo.E_Eliminado = 2
        WHERE per.Id_Ruta = @IdRuta AND per.E_Eliminado = 2 AND per.E_Aprobado = 2
          AND pv.Fecha_Registro >= @DesdeFecha
    ), Proyeccion AS
    (
        SELECT detalle.*,
            (SELECT TOP (1) anterior.SaldoAntesMovimiento
             FROM Detalle anterior
             WHERE anterior.IdProducto = detalle.IdProducto
             ORDER BY anterior.Fecha ASC, anterior.IdReferencia ASC) AS SaldoProyectadoFinal
        FROM Detalle detalle
    )
    SELECT
        Tipo, IdReferencia, Fecha, Total, EstadoActual, EstadoProyectado,
        Observacion, IdProducto, Producto, CantidadMovimiento, SaldoActual,
        SaldoAntesMovimiento, SaldoDespuesMovimiento, SaldoProyectadoFinal,
        FisicosAfectados, FisicosVendidos, Codigos, TablaPrincipal, TablasAfectadas,
        Bloqueado, MotivoBloqueo
    FROM Proyeccion
    ORDER BY Fecha DESC, IdReferencia DESC, IdProducto;
END;
GO

-- ----------------------------------------------------------------------------
-- Revierte UN cuadre definitivo. Se asume que todo lo posterior a este
-- cuadre, para esta ruta, ya fue revertido antes en la misma cascada (o no
-- existe). No abre transaccion propia: se llama dentro de la transaccion
-- del proceso que orquesta la cascada.
-- ----------------------------------------------------------------------------
IF OBJECT_ID(N'dbo.spj_LoginGeneral_Sistemas_RevertirCuadreInterno', N'P') IS NULL
    EXEC(N'CREATE PROCEDURE dbo.spj_LoginGeneral_Sistemas_RevertirCuadreInterno AS BEGIN SET NOCOUNT ON; END');
GO

ALTER PROCEDURE dbo.spj_LoginGeneral_Sistemas_RevertirCuadreInterno
    @IdCuadre INT,
    @IdRuta INT,
    @DesdeFecha DATETIME
AS
BEGIN
    SET NOCOUNT ON;
    SET ARITHABORT ON;

    IF NOT EXISTS
    (
        SELECT 1 FROM dbo.tbl_Cuadre WITH (UPDLOCK, HOLDLOCK)
        WHERE Id_Cuadre = @IdCuadre AND Id_Ruta = @IdRuta AND E_Eliminado = 2
    )
    BEGIN
        RAISERROR('El cuadre %d no existe, ya fue restaurado o no pertenece a la ruta.', 16, 1, @IdCuadre);
        RETURN;
    END;

    DECLARE @Cajas TABLE (Id_Caja INT PRIMARY KEY);

    INSERT INTO @Cajas (Id_Caja)
    SELECT DISTINCT Id_Caja
    FROM dbo.tbl_TransaccionCuadre
    WHERE Id_Cuadre = @IdCuadre AND E_Eliminado = 2 AND Id_Caja IS NOT NULL;

    INSERT INTO @Cajas (Id_Caja)
    SELECT Id_Caja
    FROM
    (
        SELECT Id_CajaDeuda AS Id_Caja FROM dbo.tbl_Deuda
        WHERE Id_Cuadre = @IdCuadre AND E_Eliminado = 2
        UNION
        SELECT Id_CajaPago FROM dbo.tbl_Deuda
        WHERE Id_Cuadre = @IdCuadre AND E_Eliminado = 2
    ) cajasDeuda
    WHERE Id_Caja IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM @Cajas existente WHERE existente.Id_Caja = cajasDeuda.Id_Caja);

    -- Una caja exclusiva del cuadre se puede revertir completa. Si una caja
    -- agrupa otro cuadre que no forma parte de esta misma cascada, se aborta:
    -- no es posible repartir sus montos con seguridad entre movimientos.
    IF EXISTS
    (
        SELECT 1
        FROM @Cajas objetivo
        INNER JOIN dbo.tbl_TransaccionCuadre otraTransaccion
            ON otraTransaccion.Id_Caja = objetivo.Id_Caja
           AND otraTransaccion.E_Eliminado = 2
           AND otraTransaccion.Id_Cuadre <> @IdCuadre
        INNER JOIN dbo.tbl_Cuadre otroCuadre ON otroCuadre.Id_Cuadre = otraTransaccion.Id_Cuadre
        WHERE NOT (otroCuadre.Id_Ruta = @IdRuta AND otroCuadre.Fecha >= @DesdeFecha)
    )
    OR EXISTS
    (
        SELECT 1
        FROM @Cajas objetivo
        INNER JOIN dbo.tbl_Deuda otraDeuda
            ON (otraDeuda.Id_CajaDeuda = objetivo.Id_Caja OR otraDeuda.Id_CajaPago = objetivo.Id_Caja)
           AND otraDeuda.E_Eliminado = 2
           AND otraDeuda.Id_Cuadre <> @IdCuadre
        INNER JOIN dbo.tbl_Cuadre otroCuadre ON otroCuadre.Id_Cuadre = otraDeuda.Id_Cuadre
        WHERE NOT (otroCuadre.Id_Ruta = @IdRuta AND otroCuadre.Fecha >= @DesdeFecha)
    )
    BEGIN
        RAISERROR('No se puede restaurar el cuadre %d porque una de sus cajas tambien contiene movimientos fuera de esta cascada.', 16, 1, @IdCuadre);
        RETURN;
    END;

    UPDATE dbo.tbl_TransaccionCuadre
    SET E_Eliminado = 1
    WHERE Id_Cuadre = @IdCuadre AND E_Eliminado = 2;

    UPDATE dbo.tbl_Deuda
    SET E_Eliminado = 1
    WHERE Id_Cuadre = @IdCuadre AND E_Eliminado = 2;

    UPDATE caja
    SET caja.E_Eliminado = 1
    FROM dbo.tbl_Caja caja
    INNER JOIN @Cajas objetivo ON objetivo.Id_Caja = caja.Id_Caja
    WHERE NOT EXISTS
          (
              SELECT 1 FROM dbo.tbl_TransaccionCuadre t
              WHERE t.Id_Caja = caja.Id_Caja AND t.E_Eliminado = 2
          )
      AND NOT EXISTS
          (
              SELECT 1 FROM dbo.tbl_Deuda d
              WHERE (d.Id_CajaDeuda = caja.Id_Caja OR d.Id_CajaPago = caja.Id_Caja)
                AND d.E_Eliminado = 2
          );

    -- Productos fisicos: lo consumido por este cuadre vuelve a estar en
    -- poder del tecnico (Vendido=1), no vuelve al almacen (Vendido=0),
    -- porque nunca dejo de estar entregado a la ruta.
    UPDATE dbo.tbl_Productos
    SET Vendido = 1, Id_Cuadre = NULL
    WHERE Id_Cuadre = @IdCuadre AND Id_Ruta = @IdRuta AND Vendido = 2;

    UPDATE dbo.tbl_Productos
    SET Id_Cuadre = NULL
    WHERE Id_Cuadre = @IdCuadre AND Id_Ruta = @IdRuta AND Vendido = 1;

    -- El saldo de CADA producto vuelve al valor exacto que tenia antes del
    -- cuadre. Esta es la fuente historica correcta: sobrantes + vendidos.
    UPDATE saldo
    SET saldo.Cantidad = codigo.ItemsSobrantes + codigo.ItemsVendidos
    FROM dbo.tbl_SaldoTarjetas saldo
    INNER JOIN dbo.tbl_CodigoCuadre codigo
        ON codigo.Id_Cuadre = @IdCuadre AND codigo.E_Eliminado = 2
    WHERE saldo.Id_Ruta = @IdRuta
      AND saldo.Id_Producto = codigo.Id_Producto
      AND saldo.E_Eliminado = 2;

    INSERT INTO dbo.tbl_SaldoTarjetas (Id_Producto, Id_Ruta, Cantidad, E_Eliminado)
    SELECT codigo.Id_Producto, @IdRuta,
           codigo.ItemsSobrantes + codigo.ItemsVendidos, 2
    FROM dbo.tbl_CodigoCuadre codigo
    WHERE codigo.Id_Cuadre = @IdCuadre AND codigo.E_Eliminado = 2
      AND NOT EXISTS
      (
          SELECT 1 FROM dbo.tbl_SaldoTarjetas saldo
          WHERE saldo.Id_Ruta = @IdRuta
            AND saldo.Id_Producto = codigo.Id_Producto
            AND saldo.E_Eliminado = 2
      );

    -- Si este cuadre nacio de un preliminar del tecnico, ese preliminar
    -- vuelve a quedar pendiente para que se pueda corregir y reenviar.
    UPDATE dbo.tbl_Cuadre_EnRuta
    SET E_Aprobado = 1, Id_Cuadre = 0, AprobadoPor = NULL, FechaAprobacion = NULL
    WHERE Id_Cuadre = @IdCuadre AND E_Eliminado = 2;

    UPDATE dbo.tbl_Cuadre SET E_Eliminado = 1 WHERE Id_Cuadre = @IdCuadre;
    UPDATE dbo.tbl_CodigoCuadre SET E_Eliminado = 1 WHERE Id_Cuadre = @IdCuadre;
    UPDATE dbo.tbl_SaldoCuadre SET E_Eliminado = 1 WHERE Id_Cuadre = @IdCuadre;
    UPDATE dbo.tbl_GiroTigo SET E_Eliminado = 1 WHERE Id_Cuadre = @IdCuadre;
END;
GO

-- ----------------------------------------------------------------------------
-- Revierte UN pedido en ruta ya aprobado (entregado). Misma precondicion:
-- todo lo posterior de esta ruta ya fue revertido antes en la cascada.
-- ----------------------------------------------------------------------------
IF OBJECT_ID(N'dbo.spj_LoginGeneral_Sistemas_RevertirPedidoInterno', N'P') IS NULL
    EXEC(N'CREATE PROCEDURE dbo.spj_LoginGeneral_Sistemas_RevertirPedidoInterno AS BEGIN SET NOCOUNT ON; END');
GO

ALTER PROCEDURE dbo.spj_LoginGeneral_Sistemas_RevertirPedidoInterno
    @IdPedidoEnRuta INT,
    @IdRuta INT,
    @DesdeFecha DATETIME
AS
BEGIN
    SET NOCOUNT ON;
    SET ARITHABORT ON;

    DECLARE @IdPedidoNormal INT;
    SELECT @IdPedidoNormal = NULLIF(Id_PedidoVendedorNormal, 0)
    FROM dbo.tbl_PedidoVendedor_EnRuta WITH (UPDLOCK, HOLDLOCK)
    WHERE Id_PedidoVendedor_EnRuta = @IdPedidoEnRuta
      AND Id_Ruta = @IdRuta AND E_Aprobado = 2 AND E_Eliminado = 2;

    IF @IdPedidoNormal IS NULL
    BEGIN
        RAISERROR('El pedido %d no existe, ya fue restaurado o no pertenece a la ruta.', 16, 1, @IdPedidoEnRuta);
        RETURN;
    END;

    -- Materializar una sola vez las unidades del pedido. tbl_Productos supera
    -- varios millones de filas y el antiguo OR correlacionado obligaba a SQL
    -- Server a recorrerla repetidamente hasta agotar el socketTimeout.
    CREATE TABLE #ProductosPedido
    (
        Imei VARCHAR(25) NOT NULL PRIMARY KEY
    );

    INSERT INTO #ProductosPedido (Imei)
    SELECT DISTINCT CONVERT(VARCHAR(25), p.Imei)
    FROM dbo.tbl_Productos p
    WHERE p.Id_PedidoVendedor = @IdPedidoNormal
      AND p.Imei IS NOT NULL;

    INSERT INTO #ProductosPedido (Imei)
    SELECT DISTINCT CONVERT(VARCHAR(25), fisico.Imei)
    FROM dbo.PedidoVendedor_EnRuta_ProductoFisico fisico
    WHERE fisico.Id_PedidoVendedor_EnRuta = @IdPedidoEnRuta
      AND fisico.E_Eliminado = 2
      AND fisico.Imei IS NOT NULL
      AND NOT EXISTS
      (
          SELECT 1 FROM #ProductosPedido incluido
          WHERE incluido.Imei = CONVERT(VARCHAR(25), fisico.Imei)
      );

    -- Seguridad: solo se bloquea si la unidad pertenece realmente a un
    -- cuadre ACTIVO fuera de la cascada. Hay datos historicos donde
    -- Vendido=2 quedo con Id_Cuadre=0 despues de anular el cuadre; esos
    -- registros huerfanos deben poder volver al almacen con su pedido.
    IF EXISTS
    (
        SELECT 1
        FROM #ProductosPedido incluido
        INNER JOIN dbo.tbl_Productos p ON p.Imei = incluido.Imei
        INNER JOIN dbo.tbl_Cuadre cuadreActivo
            ON cuadreActivo.Id_Cuadre = p.Id_Cuadre
           AND cuadreActivo.E_Eliminado = 2
        WHERE p.Vendido = 2
          AND NOT (cuadreActivo.Id_Ruta = @IdRuta AND cuadreActivo.Fecha >= @DesdeFecha)
    )
    BEGIN
        RAISERROR('No se puede revertir el pedido %d: hay unidades entregadas por el que ya fueron cuadradas y no forman parte de esta cascada.', 16, 1, @IdPedidoEnRuta);
        RETURN;
    END;

    -- Los productos fisicos entregados vuelven al almacen (libres, nunca cuadrados).
    UPDATE p
    SET p.Vendido = 0, p.Id_Ruta = 0, p.Id_PedidoVendedor = 0, p.Id_Cuadre = NULL
    FROM dbo.tbl_Productos p
    INNER JOIN #ProductosPedido incluido ON incluido.Imei = p.Imei;

    -- Cada detalle normal conserva el saldo exacto que existia antes de la
    -- aprobacion. Restaurarlo evita errores acumulativos y respeta la hilera.
    UPDATE saldo
    SET saldo.Cantidad = codigo.Saldo
    FROM dbo.tbl_SaldoTarjetas saldo
    INNER JOIN dbo.tbl_CodigoPedidoVendedor codigo
        ON codigo.Id_PedidoVendedor = @IdPedidoNormal AND codigo.E_Eliminado = 2
    WHERE saldo.Id_Ruta = @IdRuta
      AND saldo.Id_Producto = codigo.Id_Producto
      AND saldo.E_Eliminado = 2;

    INSERT INTO dbo.tbl_SaldoTarjetas (Id_Producto, Id_Ruta, Cantidad, E_Eliminado)
    SELECT codigo.Id_Producto, @IdRuta, codigo.Saldo, 2
    FROM dbo.tbl_CodigoPedidoVendedor codigo
    WHERE codigo.Id_PedidoVendedor = @IdPedidoNormal AND codigo.E_Eliminado = 2
      AND NOT EXISTS
      (
          SELECT 1 FROM dbo.tbl_SaldoTarjetas saldo
          WHERE saldo.Id_Ruta = @IdRuta
            AND saldo.Id_Producto = codigo.Id_Producto
            AND saldo.E_Eliminado = 2
      );

    UPDATE dbo.PedidoVendedor_EnRuta_ProductoFisico
    SET E_Eliminado = 1
    WHERE Id_PedidoVendedor_EnRuta = @IdPedidoEnRuta;

    UPDATE dbo.tbl_CodigoAlmacenVendedor
    SET E_Eliminado = 1
    WHERE Id_AlmacenVendedor IN
    (
        SELECT Id_AlmacenVendedor FROM dbo.tbl_AlmacenVendedor WHERE Id_PedidoVendedor = @IdPedidoNormal
    );

    UPDATE dbo.tbl_AlmacenVendedor SET E_Eliminado = 1 WHERE Id_PedidoVendedor = @IdPedidoNormal;
    UPDATE dbo.tbl_CodigoPedidoVendedor SET E_Eliminado = 1 WHERE Id_PedidoVendedor = @IdPedidoNormal;
    UPDATE dbo.tbl_PedidoVendedor SET E_Eliminado = 1 WHERE Id_PedidoVendedor = @IdPedidoNormal;

    -- El pedido en ruta vuelve a quedar pendiente (no eliminado del todo),
    -- para que almacen decida si lo vuelve a aprobar con datos correctos.
    UPDATE dbo.tbl_PedidoVendedor_EnRuta
    SET E_Aprobado = 1, AprobadoPor = NULL, Id_PedidoVendedorNormal = 0
    WHERE Id_PedidoVendedor_EnRuta = @IdPedidoEnRuta;
END;
GO

-- ----------------------------------------------------------------------------
-- Orquesta la cascada completa para una ruta: desde @DesdeFecha hasta ahora,
-- revirtiendo del movimiento mas reciente al mas antiguo, en una sola
-- transaccion. Si algo falla, se revierte todo (no queda a medias).
-- ----------------------------------------------------------------------------
IF OBJECT_ID(N'dbo.spj_LoginGeneral_Sistemas_EjecutarCascadaRuta', N'P') IS NULL
    EXEC(N'CREATE PROCEDURE dbo.spj_LoginGeneral_Sistemas_EjecutarCascadaRuta AS BEGIN SET NOCOUNT ON; END');
GO

ALTER PROCEDURE dbo.spj_LoginGeneral_Sistemas_EjecutarCascadaRuta
    @IdRuta INT,
    @DesdeFecha DATETIME,
    @IdUsuarioSistemas INT,
    @NombreUsuarioSistemas VARCHAR(150),
    @Justificacion VARCHAR(500),
    @JobId VARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET ARITHABORT ON;

    IF NULLIF(LTRIM(RTRIM(@Justificacion)), '') IS NULL
    BEGIN
        RAISERROR('Debes indicar una justificacion para revertir movimientos de la ruta.', 16, 1);
        RETURN;
    END;

    IF NULLIF(LTRIM(RTRIM(@JobId)), '') IS NULL
    BEGIN
        RAISERROR('No se recibio el identificador seguro de la restauracion.', 16, 1);
        RETURN;
    END;

    DECLARE @Movimientos TABLE
    (
        Orden INT IDENTITY(1,1) NOT NULL,
        Tipo VARCHAR(30) NOT NULL,
        IdReferencia INT NOT NULL,
        Fecha DATETIME NOT NULL
    );

    INSERT INTO @Movimientos (Tipo, IdReferencia, Fecha)
    SELECT 'CUADRE', c.Id_Cuadre, c.Fecha
    FROM dbo.tbl_Cuadre c
    WHERE c.Id_Ruta = @IdRuta AND c.E_Eliminado = 2 AND c.Fecha >= @DesdeFecha

    UNION ALL

    SELECT 'PEDIDO', per.Id_PedidoVendedor_EnRuta, ISNULL(pv.Fecha_Registro, per.Fecha_Registro)
    FROM dbo.tbl_PedidoVendedor_EnRuta per
    INNER JOIN dbo.tbl_PedidoVendedor pv
        ON pv.Id_PedidoVendedor = per.Id_PedidoVendedorNormal
       AND per.Id_PedidoVendedorNormal > 0 AND pv.E_Eliminado = 2
    WHERE per.Id_Ruta = @IdRuta AND per.E_Eliminado = 2 AND per.E_Aprobado = 2
      AND pv.Fecha_Registro >= @DesdeFecha;

    IF NOT EXISTS (SELECT 1 FROM @Movimientos)
    BEGIN
        RAISERROR('No hay movimientos de esta ruta desde la fecha indicada.', 16, 1);
        RETURN;
    END;

    DECLARE @ResultadoBloqueo INT;
    DECLARE @Recurso NVARCHAR(255) = N'LoginGeneral:Sistemas:CascadaRuta:' + CONVERT(NVARCHAR(20), @IdRuta);

    BEGIN TRY
        BEGIN TRANSACTION;

        EXEC @ResultadoBloqueo = sys.sp_getapplock
            @Resource = @Recurso, @LockMode = 'Exclusive', @LockOwner = 'Transaction', @LockTimeout = 15000;
        IF @ResultadoBloqueo < 0
            RAISERROR('No se pudo bloquear la ruta para revertir sus movimientos. Intenta nuevamente.', 16, 1);

        IF NULLIF(LTRIM(RTRIM(@JobId)), '') IS NOT NULL
           AND EXISTS (SELECT 1 FROM dbo.tbl_Sistemas_ReversionRuta WITH (UPDLOCK, HOLDLOCK) WHERE JobId = @JobId)
        BEGIN
            SELECT TOP 1
                Id_ReversionRuta AS IdReversion, Id_Ruta AS IdRuta,
                CantidadMovimientos, Fecha_Registro AS FechaEjecucion
            FROM dbo.tbl_Sistemas_ReversionRuta WHERE JobId = @JobId;
            COMMIT TRANSACTION;
            RETURN;
        END;

        DECLARE @Tipo VARCHAR(30), @IdReferencia INT;
        DECLARE movimientos_cursor CURSOR LOCAL FAST_FORWARD FOR
            SELECT Tipo, IdReferencia FROM @Movimientos ORDER BY Fecha DESC, Orden DESC;
        OPEN movimientos_cursor;
        FETCH NEXT FROM movimientos_cursor INTO @Tipo, @IdReferencia;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            IF @Tipo = 'CUADRE'
                EXEC dbo.spj_LoginGeneral_Sistemas_RevertirCuadreInterno @IdReferencia, @IdRuta, @DesdeFecha;
            ELSE IF @Tipo = 'PEDIDO'
                EXEC dbo.spj_LoginGeneral_Sistemas_RevertirPedidoInterno @IdReferencia, @IdRuta, @DesdeFecha;
            FETCH NEXT FROM movimientos_cursor INTO @Tipo, @IdReferencia;
        END;
        CLOSE movimientos_cursor;
        DEALLOCATE movimientos_cursor;

        DECLARE @DetalleJson NVARCHAR(MAX);
        SELECT @DetalleJson = STUFF((
            SELECT '; ' + Tipo + '#' + CONVERT(VARCHAR(20), IdReferencia)
                + ' (' + CONVERT(VARCHAR(19), Fecha, 120) + ')'
            FROM @Movimientos
            ORDER BY Fecha DESC, Orden DESC
            FOR XML PATH(''), TYPE
        ).value('.', 'NVARCHAR(MAX)'), 1, 2, '');

        INSERT INTO dbo.tbl_Sistemas_ReversionRuta
        (Id_Ruta, DesdeFecha, Id_UsuarioSistemas, NombreUsuarioSistemas, Justificacion, CantidadMovimientos, DetalleJson, JobId)
        VALUES
        (@IdRuta, @DesdeFecha, @IdUsuarioSistemas, @NombreUsuarioSistemas, @Justificacion, (SELECT COUNT(*) FROM @Movimientos), @DetalleJson, NULLIF(LTRIM(RTRIM(@JobId)), ''));

        COMMIT TRANSACTION;

        SELECT
            SCOPE_IDENTITY() AS IdReversion,
            @IdRuta AS IdRuta,
            (SELECT COUNT(*) FROM @Movimientos) AS CantidadMovimientos,
            GETDATE() AS FechaEjecucion;
    END TRY
    BEGIN CATCH
        IF CURSOR_STATUS('local', 'movimientos_cursor') > -1 CLOSE movimientos_cursor;
        IF CURSOR_STATUS('local', 'movimientos_cursor') >= -1 DEALLOCATE movimientos_cursor;
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        DECLARE @Mensaje NVARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR(@Mensaje, 16, 1);
    END CATCH;
END;
GO
