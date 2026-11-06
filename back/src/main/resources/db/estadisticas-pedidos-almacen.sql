USE BDAlmacenTarija_Prueba;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF COL_LENGTH(N'dbo.tbl_PedidoVendedor_EnRuta', N'FechaModificacionAlmacen') IS NULL
BEGIN
    ALTER TABLE dbo.tbl_PedidoVendedor_EnRuta
    ADD FechaModificacionAlmacen DATETIME NULL;
END;
GO

IF OBJECT_ID(N'dbo.spj_LoginGeneral_Almacen_EstadisticasDemorasCaja', N'P') IS NULL
BEGIN
    EXEC(N'CREATE PROCEDURE dbo.spj_LoginGeneral_Almacen_EstadisticasDemorasCaja AS BEGIN SET NOCOUNT ON; END');
END;
GO

ALTER PROCEDURE dbo.spj_LoginGeneral_Almacen_EstadisticasDemorasCaja
    @FechaDesde DATE,
    @FechaHasta DATE
AS
BEGIN
    SET NOCOUNT ON;

    IF @FechaDesde IS NULL OR @FechaHasta IS NULL OR @FechaDesde > @FechaHasta
    BEGIN
        RAISERROR('El rango de fechas no es valido.', 16, 1);
        RETURN;
    END;

    ;WITH PasoCaja AS
    (
        SELECT
            cuadre.Id_Cuadre,
            cuadre.Id_Ruta,
            cuadre.Id_Vendedor,
            cuadre.Fecha AS FechaCuadre,
            caja.Id_Caja,
            caja.Fecha AS FechaCaja,
            ROW_NUMBER() OVER
            (
                PARTITION BY cuadre.Id_Cuadre
                ORDER BY caja.Fecha, transaccion.Id_TransaccionCuadre
            ) AS OrdenPaso
        FROM dbo.tbl_Cuadre cuadre
        INNER JOIN dbo.tbl_TransaccionCuadre transaccion
            ON transaccion.Id_Cuadre = cuadre.Id_Cuadre
           AND transaccion.E_Eliminado = 2
        INNER JOIN dbo.tbl_Caja caja
            ON caja.Id_Caja = transaccion.Id_Caja
           AND caja.E_Eliminado = 2
           AND caja.Fecha >= cuadre.Fecha
        WHERE cuadre.E_Eliminado = 2
          AND cuadre.Fecha >= @FechaDesde
          AND cuadre.Fecha < DATEADD(DAY, 1, @FechaHasta)
    )
    SELECT
        CONVERT(DATE, paso.FechaCuadre) AS Fecha,
        paso.Id_Cuadre AS IdCuadre,
        paso.Id_Ruta AS IdRuta,
        ISNULL(ruta.Nombre, 'RUTA ' + CONVERT(VARCHAR(12), paso.Id_Ruta)) AS Ruta,
        paso.Id_Vendedor AS IdVendedor,
        ISNULL(vendedor.Nombre, 'VENDEDOR ' + CONVERT(VARCHAR(12), paso.Id_Vendedor)) AS Vendedor,
        paso.FechaCuadre,
        paso.Id_Caja AS IdCaja,
        paso.FechaCaja,
        DATEDIFF(MINUTE, paso.FechaCuadre, paso.FechaCaja) AS MinutosDemora
    FROM PasoCaja paso
    LEFT JOIN dbo.tbl_Ruta ruta ON ruta.Id_Ruta = paso.Id_Ruta
    LEFT JOIN dbo.tbl_Vendedor vendedor ON vendedor.Id_Vendedor = paso.Id_Vendedor
    WHERE paso.OrdenPaso = 1
    ORDER BY paso.FechaCuadre DESC, MinutosDemora DESC;
END;
GO

IF OBJECT_ID(N'dbo.spj_LoginGeneral_Almacen_EstadisticasVendedores', N'P') IS NULL
BEGIN
    EXEC(N'CREATE PROCEDURE dbo.spj_LoginGeneral_Almacen_EstadisticasVendedores AS BEGIN SET NOCOUNT ON; END');
END;
GO

ALTER PROCEDURE dbo.spj_LoginGeneral_Almacen_EstadisticasVendedores
    @FechaDesde DATE,
    @FechaHasta DATE
AS
BEGIN
    SET NOCOUNT ON;

    IF @FechaDesde IS NULL OR @FechaHasta IS NULL OR @FechaDesde > @FechaHasta
    BEGIN
        RAISERROR('El rango de fechas no es valido.', 16, 1);
        RETURN;
    END;

    SELECT
        pedido.Id_Vendedor AS IdVendedor,
        ISNULL(vendedor.Nombre, 'VENDEDOR #' + CONVERT(VARCHAR(12), pedido.Id_Vendedor)) AS Vendedor,
        COUNT(*) AS Pedidos,
        SUM(CASE WHEN pedido.E_Aprobado = 2 THEN 1 ELSE 0 END) AS Aprobados,
        SUM(CASE WHEN pedido.E_Aprobado = 1 THEN 1 ELSE 0 END) AS Pendientes,
        SUM(CASE WHEN ISNULL(pedido.ModificadoPorAlmacen, 2) = 1 THEN 1 ELSE 0 END) AS Modificados,
        SUM(ISNULL(detalle.Unidades, 0)) AS UnidadesSolicitadas,
        CONVERT(DECIMAL(18,2), SUM(CONVERT(DECIMAL(18,2), ISNULL(pedido.Total, 0)))) AS MontoSolicitado
    FROM dbo.tbl_PedidoVendedor_EnRuta pedido
    LEFT JOIN dbo.tbl_Vendedor vendedor
        ON vendedor.Id_Vendedor = pedido.Id_Vendedor
    OUTER APPLY
    (
        SELECT SUM(ISNULL(codigo.NvoPedido, 0)) AS Unidades
        FROM dbo.tbl_CodigoPedidoVendedor_EnRuta codigo
        WHERE codigo.Id_PedidoVendedor_EnRuta = pedido.Id_PedidoVendedor_EnRuta
          AND codigo.E_Eliminado = 2
    ) detalle
    WHERE pedido.E_Eliminado = 2
      AND pedido.Fecha_Registro >= @FechaDesde
      AND pedido.Fecha_Registro < DATEADD(DAY, 1, @FechaHasta)
    GROUP BY pedido.Id_Vendedor, vendedor.Nombre
    ORDER BY Pedidos DESC, UnidadesSolicitadas DESC, Vendedor;
END;
GO

IF OBJECT_ID(N'dbo.spj_LoginGeneral_Almacen_EstadisticasConsumoProductosDiario', N'P') IS NULL
BEGIN
    EXEC(N'CREATE PROCEDURE dbo.spj_LoginGeneral_Almacen_EstadisticasConsumoProductosDiario AS BEGIN SET NOCOUNT ON; END');
END;
GO

ALTER PROCEDURE dbo.spj_LoginGeneral_Almacen_EstadisticasConsumoProductosDiario
    @FechaDesde DATE,
    @FechaHasta DATE
AS
BEGIN
    SET NOCOUNT ON;

    IF @FechaDesde IS NULL OR @FechaHasta IS NULL OR @FechaDesde > @FechaHasta
    BEGIN
        RAISERROR('El rango de fechas no es valido.', 16, 1);
        RETURN;
    END;

    SELECT
        CONVERT(DATE, cuadre.Fecha) AS Fecha,
        codigo.Id_Producto AS IdProducto,
        producto.Nombre AS Producto,
        ISNULL(tipo.Nombre, 'Sin tipo') AS TipoProducto,
        SUM(ISNULL(codigo.ItemsVendidos, 0)) AS UnidadesVendidas,
        SUM(ISNULL(codigo.ItemsSobrantes, 0)) AS UnidadesSobrantes,
        CONVERT(DECIMAL(18,2), SUM(CONVERT(DECIMAL(18,2), ISNULL(codigo.TotalVendidos, 0)))) AS TotalVendido,
        COUNT(DISTINCT cuadre.Id_Ruta) AS RutasConMovimiento,
        COUNT(DISTINCT cuadre.Id_Cuadre) AS Cuadres
    FROM dbo.tbl_Cuadre cuadre
    INNER JOIN dbo.tbl_CodigoCuadre codigo
        ON codigo.Id_Cuadre = cuadre.Id_Cuadre
       AND codigo.E_Eliminado = 2
    INNER JOIN dbo.tbl_Producto producto
        ON producto.Id_Producto = codigo.Id_Producto
    LEFT JOIN dbo.tbl_TipoProducto tipo
        ON tipo.Id_TipoProducto = producto.Id_TipoProducto
    WHERE cuadre.E_Eliminado = 2
      AND cuadre.Fecha >= @FechaDesde
      AND cuadre.Fecha < DATEADD(DAY, 1, @FechaHasta)
    GROUP BY CONVERT(DATE, cuadre.Fecha), codigo.Id_Producto, producto.Nombre, tipo.Nombre
    ORDER BY Fecha, UnidadesVendidas DESC, Producto;
END;
GO

UPDATE dbo.tbl_PedidoVendedor_EnRuta
SET FechaModificacionAlmacen = Fecha_Registro
WHERE ModificadoPorAlmacen = 1
  AND FechaModificacionAlmacen IS NULL;
GO

IF OBJECT_ID(N'dbo.spj_LoginGeneral_Almacen_EstadisticasPedidos', N'P') IS NULL
BEGIN
    EXEC(N'CREATE PROCEDURE dbo.spj_LoginGeneral_Almacen_EstadisticasPedidos AS BEGIN SET NOCOUNT ON; END');
END;
GO

ALTER PROCEDURE dbo.spj_LoginGeneral_Almacen_EstadisticasPedidos
    @FechaDesde DATE,
    @FechaHasta DATE
AS
BEGIN
    SET NOCOUNT ON;

    IF @FechaDesde IS NULL OR @FechaHasta IS NULL OR @FechaDesde > @FechaHasta
    BEGIN
        RAISERROR('El rango de fechas no es valido.', 16, 1);
        RETURN;
    END;

    SELECT
        eventos.Fecha,
        eventos.IdRuta,
        ISNULL(ruta.Nombre, 'RUTA ' + CONVERT(VARCHAR(12), eventos.IdRuta)) AS Ruta,
        SUM(eventos.Realizados) AS Realizados,
        SUM(eventos.Aprobados) AS Aprobados,
        SUM(eventos.Pendientes) AS Pendientes,
        SUM(eventos.Modificados) AS Modificados,
        SUM(eventos.UnidadesSolicitadas) AS UnidadesSolicitadas,
        SUM(eventos.UnidadesAprobadas) AS UnidadesAprobadas,
        CONVERT(DECIMAL(18,2), SUM(eventos.MontoSolicitado)) AS MontoSolicitado,
        CONVERT(DECIMAL(18,2), SUM(eventos.MontoAprobado)) AS MontoAprobado,
        SUM(eventos.CuadresEnviados) AS CuadresEnviados,
        SUM(eventos.CuadresRealizados) AS CuadresRealizados,
        SUM(eventos.CuadresPendientes) AS CuadresPendientes,
        SUM(eventos.CuadresModificados) AS CuadresModificados,
        SUM(eventos.UnidadesSobrantes) AS UnidadesSobrantes,
        SUM(eventos.UnidadesVendidas) AS UnidadesVendidas,
        CONVERT(DECIMAL(18,2), SUM(eventos.MontoVendido)) AS MontoVendido
    FROM
    (
        SELECT
            CONVERT(DATE, pedido.Fecha_Registro) AS Fecha,
            pedido.Id_Ruta AS IdRuta,
            COUNT(*) AS Realizados,
            0 AS Aprobados,
            SUM(CASE WHEN pedido.E_Aprobado = 1 THEN 1 ELSE 0 END) AS Pendientes,
            0 AS Modificados,
            SUM(ISNULL(detalle.Unidades, 0)) AS UnidadesSolicitadas,
            0 AS UnidadesAprobadas,
            SUM(CONVERT(DECIMAL(18,2), ISNULL(pedido.Total, 0))) AS MontoSolicitado,
            CONVERT(DECIMAL(18,2), 0) AS MontoAprobado,
            0 AS CuadresEnviados,
            0 AS CuadresRealizados,
            0 AS CuadresPendientes,
            0 AS CuadresModificados,
            0 AS UnidadesSobrantes,
            0 AS UnidadesVendidas,
            CONVERT(DECIMAL(18,2), 0) AS MontoVendido
        FROM dbo.tbl_PedidoVendedor_EnRuta pedido
        OUTER APPLY
        (
            SELECT SUM(codigo.NvoPedido) AS Unidades
            FROM dbo.tbl_CodigoPedidoVendedor_EnRuta codigo
            WHERE codigo.Id_PedidoVendedor_EnRuta = pedido.Id_PedidoVendedor_EnRuta
              AND codigo.E_Eliminado = 2
        ) detalle
        WHERE pedido.E_Eliminado = 2
          AND pedido.Fecha_Registro >= @FechaDesde
          AND pedido.Fecha_Registro < DATEADD(DAY, 1, @FechaHasta)
        GROUP BY CONVERT(DATE, pedido.Fecha_Registro), pedido.Id_Ruta

        UNION ALL

        SELECT
            CONVERT(DATE, normal.Fecha_Registro) AS Fecha,
            pedido.Id_Ruta AS IdRuta,
            0 AS Realizados,
            COUNT(*) AS Aprobados,
            0 AS Pendientes,
            0 AS Modificados,
            0 AS UnidadesSolicitadas,
            SUM(ISNULL(detalle.Unidades, 0)) AS UnidadesAprobadas,
            CONVERT(DECIMAL(18,2), 0) AS MontoSolicitado,
            SUM(CONVERT(DECIMAL(18,2), ISNULL(normal.Total, 0))) AS MontoAprobado,
            0 AS CuadresEnviados,
            0 AS CuadresRealizados,
            0 AS CuadresPendientes,
            0 AS CuadresModificados,
            0 AS UnidadesSobrantes,
            0 AS UnidadesVendidas,
            CONVERT(DECIMAL(18,2), 0) AS MontoVendido
        FROM dbo.tbl_PedidoVendedor_EnRuta pedido
        INNER JOIN dbo.tbl_PedidoVendedor normal
            ON normal.Id_PedidoVendedor = pedido.Id_PedidoVendedorNormal
           AND normal.E_Eliminado = 2
        OUTER APPLY
        (
            SELECT SUM(codigo.NvoPedido) AS Unidades
            FROM dbo.tbl_CodigoPedidoVendedor codigo
            WHERE codigo.Id_PedidoVendedor = normal.Id_PedidoVendedor
              AND codigo.E_Eliminado = 2
        ) detalle
        WHERE pedido.E_Eliminado = 2
          AND pedido.E_Aprobado = 2
          AND normal.Fecha_Registro >= @FechaDesde
          AND normal.Fecha_Registro < DATEADD(DAY, 1, @FechaHasta)
        GROUP BY CONVERT(DATE, normal.Fecha_Registro), pedido.Id_Ruta

        UNION ALL

        SELECT
            CONVERT(DATE, pedido.FechaModificacionAlmacen) AS Fecha,
            pedido.Id_Ruta AS IdRuta,
            0 AS Realizados,
            0 AS Aprobados,
            0 AS Pendientes,
            COUNT(*) AS Modificados,
            0 AS UnidadesSolicitadas,
            0 AS UnidadesAprobadas,
            CONVERT(DECIMAL(18,2), 0) AS MontoSolicitado,
            CONVERT(DECIMAL(18,2), 0) AS MontoAprobado,
            0 AS CuadresEnviados,
            0 AS CuadresRealizados,
            0 AS CuadresPendientes,
            0 AS CuadresModificados,
            0 AS UnidadesSobrantes,
            0 AS UnidadesVendidas,
            CONVERT(DECIMAL(18,2), 0) AS MontoVendido
        FROM dbo.tbl_PedidoVendedor_EnRuta pedido
        WHERE pedido.E_Eliminado = 2
          AND pedido.ModificadoPorAlmacen = 1
          AND pedido.FechaModificacionAlmacen >= @FechaDesde
          AND pedido.FechaModificacionAlmacen < DATEADD(DAY, 1, @FechaHasta)
        GROUP BY CONVERT(DATE, pedido.FechaModificacionAlmacen), pedido.Id_Ruta

        UNION ALL

        SELECT
            CONVERT(DATE, preliminar.Fecha), preliminar.Id_Ruta,
            0, 0, 0, 0, 0, 0,
            CONVERT(DECIMAL(18,2), 0), CONVERT(DECIMAL(18,2), 0),
            COUNT(*), 0,
            SUM(CASE WHEN ISNULL(preliminar.E_Aprobado, 1) = 1 THEN 1 ELSE 0 END),
            0, 0, 0, CONVERT(DECIMAL(18,2), 0)
        FROM dbo.tbl_Cuadre_EnRuta preliminar
        WHERE preliminar.E_Eliminado = 2
          AND preliminar.Fecha >= @FechaDesde
          AND preliminar.Fecha < DATEADD(DAY, 1, @FechaHasta)
        GROUP BY CONVERT(DATE, preliminar.Fecha), preliminar.Id_Ruta

        UNION ALL

        SELECT
            CONVERT(DATE, cuadre.Fecha), cuadre.Id_Ruta,
            0, 0, 0, 0, 0, 0,
            CONVERT(DECIMAL(18,2), 0), CONVERT(DECIMAL(18,2), 0),
            0, COUNT(*), 0, 0,
            SUM(ISNULL(detalle.Sobrantes, 0)),
            SUM(ISNULL(detalle.Vendidos, 0)),
            SUM(CONVERT(DECIMAL(18,2), ISNULL(detalle.TotalVendido, 0)))
        FROM dbo.tbl_Cuadre cuadre
        OUTER APPLY
        (
            SELECT
                SUM(codigo.ItemsSobrantes) AS Sobrantes,
                SUM(codigo.ItemsVendidos) AS Vendidos,
                SUM(CONVERT(DECIMAL(18,2), codigo.TotalVendidos)) AS TotalVendido
            FROM dbo.tbl_CodigoCuadre codigo
            WHERE codigo.Id_Cuadre = cuadre.Id_Cuadre
              AND codigo.E_Eliminado = 2
        ) detalle
        WHERE cuadre.E_Eliminado = 2
          AND cuadre.Fecha >= @FechaDesde
          AND cuadre.Fecha < DATEADD(DAY, 1, @FechaHasta)
        GROUP BY CONVERT(DATE, cuadre.Fecha), cuadre.Id_Ruta

        UNION ALL

        SELECT
            CONVERT(DATE, preliminar.FechaAprobacion), preliminar.Id_Ruta,
            0, 0, 0, 0, 0, 0,
            CONVERT(DECIMAL(18,2), 0), CONVERT(DECIMAL(18,2), 0),
            0, 0, 0, COUNT(*), 0, 0, CONVERT(DECIMAL(18,2), 0)
        FROM dbo.tbl_Cuadre_EnRuta preliminar
        WHERE preliminar.E_Eliminado = 2
          AND preliminar.E_Aprobado = 2
          AND preliminar.Modificado = 1
          AND preliminar.FechaAprobacion >= @FechaDesde
          AND preliminar.FechaAprobacion < DATEADD(DAY, 1, @FechaHasta)
        GROUP BY CONVERT(DATE, preliminar.FechaAprobacion), preliminar.Id_Ruta
    ) eventos
    LEFT JOIN dbo.tbl_Ruta ruta
        ON ruta.Id_Ruta = eventos.IdRuta
    GROUP BY eventos.Fecha, eventos.IdRuta, ruta.Nombre
    ORDER BY eventos.Fecha, eventos.IdRuta;
END;
GO

IF OBJECT_ID(N'dbo.spj_LoginGeneral_Almacen_EstadisticasCuadresDetalle', N'P') IS NULL
BEGIN
    EXEC(N'CREATE PROCEDURE dbo.spj_LoginGeneral_Almacen_EstadisticasCuadresDetalle AS BEGIN SET NOCOUNT ON; END');
END;
GO

ALTER PROCEDURE dbo.spj_LoginGeneral_Almacen_EstadisticasCuadresDetalle
    @FechaDesde DATE,
    @FechaHasta DATE
AS
BEGIN
    SET NOCOUNT ON;

    IF @FechaDesde IS NULL OR @FechaHasta IS NULL OR @FechaDesde > @FechaHasta
    BEGIN
        RAISERROR('El rango de fechas no es valido.', 16, 1);
        RETURN;
    END;

    SELECT
        CONVERT(DATE, cuadre.Fecha) AS Fecha,
        cuadre.Id_Ruta AS IdRuta,
        ISNULL(ruta.Nombre, 'RUTA ' + CONVERT(VARCHAR(12), cuadre.Id_Ruta)) AS Ruta,
        cuadre.Id_Cuadre AS IdCuadre,
        detalle.Id_Producto AS IdProducto,
        producto.Nombre AS Producto,
        ISNULL(tipo.Nombre, 'Sin tipo') AS TipoProducto,
        detalle.ItemsSobrantes AS Sobrantes,
        detalle.ItemsVendidos AS Vendidos,
        CONVERT(DECIMAL(18,2), ISNULL(detalle.Precio, 0)) AS Precio,
        CONVERT(DECIMAL(18,2), ISNULL(detalle.TotalVendidos, 0)) AS TotalVendido
    FROM dbo.tbl_Cuadre cuadre
    INNER JOIN dbo.tbl_CodigoCuadre detalle
        ON detalle.Id_Cuadre = cuadre.Id_Cuadre
       AND detalle.E_Eliminado = 2
    INNER JOIN dbo.tbl_Producto producto
        ON producto.Id_Producto = detalle.Id_Producto
    LEFT JOIN dbo.tbl_TipoProducto tipo
        ON tipo.Id_TipoProducto = producto.Id_TipoProducto
    LEFT JOIN dbo.tbl_Ruta ruta
        ON ruta.Id_Ruta = cuadre.Id_Ruta
    WHERE cuadre.E_Eliminado = 2
      AND cuadre.Fecha >= @FechaDesde
      AND cuadre.Fecha < DATEADD(DAY, 1, @FechaHasta)
    ORDER BY cuadre.Fecha DESC, cuadre.Id_Ruta, detalle.Id_Producto;
END;
GO
