USE BDAlmacenTarija_Prueba;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID(N'dbo.spj_LoginGeneral_ObtenerTigoMoneyAprobadoHoy', N'P') IS NULL
BEGIN
    EXEC(N'CREATE PROCEDURE dbo.spj_LoginGeneral_ObtenerTigoMoneyAprobadoHoy
           AS BEGIN SET NOCOUNT ON; END');
END;
GO

ALTER PROCEDURE dbo.spj_LoginGeneral_ObtenerTigoMoneyAprobadoHoy
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @InicioHoy DATETIME;
    DECLARE @InicioManana DATETIME;

    SET @InicioHoy = DATEADD(DAY, DATEDIFF(DAY, 0, GETDATE()), 0);
    SET @InicioManana = DATEADD(DAY, 1, @InicioHoy);

    SELECT
        CONVERT(DATE, @InicioHoy) AS Fecha,
        CAST(31 AS INT) AS IdProducto,
        CAST(N'TM_Venta' AS NVARCHAR(100)) AS Producto,
        CONVERT(DECIMAL(18,2), ISNULL(SUM(detalle.NvoPedido), 0)) AS TotalTigoMoneyAprobado,
        COUNT(DISTINCT pedidoNormal.Id_PedidoVendedor) AS CantidadPedidos
    FROM dbo.tbl_PedidoVendedor_EnRuta pedidoRuta
    INNER JOIN dbo.tbl_PedidoVendedor pedidoNormal
        ON pedidoNormal.Id_PedidoVendedor = pedidoRuta.Id_PedidoVendedorNormal
    INNER JOIN dbo.tbl_CodigoPedidoVendedor detalle
        ON detalle.Id_PedidoVendedor = pedidoNormal.Id_PedidoVendedor
       AND detalle.Id_Producto = 31
       AND detalle.E_Eliminado = 2
    WHERE pedidoRuta.E_Aprobado = 2
      AND pedidoRuta.E_Eliminado = 2
      AND pedidoRuta.Id_PedidoVendedorNormal <> 0
      AND pedidoNormal.E_Eliminado = 2
      AND pedidoNormal.Fecha_Registro >= @InicioHoy
      AND pedidoNormal.Fecha_Registro < @InicioManana;
END;
GO

