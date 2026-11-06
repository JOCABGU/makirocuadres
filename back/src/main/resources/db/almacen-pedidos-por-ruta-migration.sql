SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID(N'dbo.spj_LoginGeneral_Almacen_ListarRutas', N'P') IS NULL
BEGIN
    EXEC(N'CREATE PROCEDURE dbo.spj_LoginGeneral_Almacen_ListarRutas AS BEGIN SET NOCOUNT ON; END');
END;
GO

ALTER PROCEDURE dbo.spj_LoginGeneral_Almacen_ListarRutas
    @FechaDesde DATE,
    @FechaHasta DATE
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        r.Id_Ruta AS IdRuta,
        r.Nombre AS Ruta,
        NULLIF(r.Id_Vendedor, 0) AS IdVendedor,
        COALESCE(v.Nombre, N'Sin t' + NCHAR(233) + N'cnico asignado') AS Tecnico,
        COUNT(DISTINCT p.Id_PedidoVendedor_EnRuta) AS PedidosPendientes
    FROM dbo.tbl_Ruta r
    LEFT JOIN dbo.tbl_Vendedor v
        ON v.Id_Vendedor = NULLIF(r.Id_Vendedor, 0)
       AND v.E_Eliminado = 2
    LEFT JOIN dbo.tbl_PedidoVendedor_EnRuta p
        ON p.Id_Ruta = r.Id_Ruta
       AND p.E_Aprobado = 1
       AND p.E_Eliminado = 2
       AND p.Fecha_Registro >= @FechaDesde
       AND p.Fecha_Registro < DATEADD(DAY, 1, @FechaHasta)
    WHERE r.E_Eliminado = 2
    GROUP BY r.Id_Ruta, r.Nombre, r.Id_Vendedor, v.Nombre
    ORDER BY
        CASE WHEN COUNT(DISTINCT p.Id_PedidoVendedor_EnRuta) > 0 THEN 0 ELSE 1 END,
        COUNT(DISTINCT p.Id_PedidoVendedor_EnRuta) DESC,
        r.Nombre;
END;
GO

ALTER PROCEDURE dbo.spj_LoginGeneral_Almacen_ListarPedidosPendientes
    @FechaDesde DATE,
    @FechaHasta DATE,
    @IdRuta INT = NULL,
    @EstadoAprobado INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        p.Id_PedidoVendedor_EnRuta AS IdPedido,
        p.Id_Usuario AS IdUsuarioTecnico,
        p.Id_Vendedor AS IdVendedor,
        vendedor.Nombre AS Tecnico,
        p.Id_Ruta AS IdRuta,
        ruta.Nombre AS Ruta,
        p.Fecha_Registro AS FechaRegistro,
        p.Observacion,
        p.ModificadoPorAlmacen,
        p.ComentarioAlmacen,
        p.Total,
        p.E_Aprobado AS EstadoAprobado,
        p.AprobadoPor,
        COUNT(d.Id_CodigoPedidoVendedor_EnRuta) AS CantidadProductos,
        ISNULL(SUM(d.NvoPedido), 0) AS CantidadUnidades
    FROM dbo.tbl_PedidoVendedor_EnRuta p
    INNER JOIN dbo.tbl_Vendedor vendedor
        ON vendedor.Id_Vendedor = p.Id_Vendedor
    LEFT JOIN dbo.tbl_Ruta ruta
        ON ruta.Id_Ruta = p.Id_Ruta
    LEFT JOIN dbo.tbl_CodigoPedidoVendedor_EnRuta d
        ON d.Id_PedidoVendedor_EnRuta = p.Id_PedidoVendedor_EnRuta
       AND d.E_Eliminado = 2
    WHERE p.E_Eliminado = 2
      AND (@EstadoAprobado IS NULL OR p.E_Aprobado = @EstadoAprobado)
      AND p.Fecha_Registro >= @FechaDesde
      AND p.Fecha_Registro < DATEADD(DAY, 1, @FechaHasta)
      AND (@IdRuta IS NULL OR p.Id_Ruta = @IdRuta)
    GROUP BY
        p.Id_PedidoVendedor_EnRuta,
        p.Id_Usuario,
        p.Id_Vendedor,
        vendedor.Nombre,
        p.Id_Ruta,
        ruta.Nombre,
        p.Fecha_Registro,
        p.Observacion,
        p.ModificadoPorAlmacen,
        p.ComentarioAlmacen,
        p.Total,
        p.E_Aprobado,
        p.AprobadoPor
    ORDER BY p.Fecha_Registro DESC, p.Id_PedidoVendedor_EnRuta DESC;
END;
GO
