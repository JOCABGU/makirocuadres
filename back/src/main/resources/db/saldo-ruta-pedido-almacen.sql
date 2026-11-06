USE BDAlmacenTarija_Prueba;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID(N'dbo.spj_LoginGeneral_Almacen_ObtenerSaldoRutaPedido', N'P') IS NULL
BEGIN
    EXEC(N'CREATE PROCEDURE dbo.spj_LoginGeneral_Almacen_ObtenerSaldoRutaPedido AS BEGIN SET NOCOUNT ON; END');
END;
GO

ALTER PROCEDURE dbo.spj_LoginGeneral_Almacen_ObtenerSaldoRutaPedido
    @IdPedido INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @IdRuta INT;
    SELECT @IdRuta = Id_Ruta
    FROM dbo.tbl_PedidoVendedor_EnRuta
    WHERE Id_PedidoVendedor_EnRuta = @IdPedido
      AND E_Eliminado = 2;

    IF @IdRuta IS NULL
    BEGIN
        RAISERROR('El pedido no existe o esta eliminado.', 16, 1);
        RETURN;
    END;

    SELECT
        r.Id_Ruta AS IdRuta,
        r.Nombre AS Ruta,
        p.Id_Producto,
        p.Nombre AS Producto,
        s.Cantidad,
        tp.Nombre AS TipoProducto,
        p.PrecioVenta
    FROM dbo.tbl_Ruta r
    LEFT JOIN dbo.tbl_SaldoTarjetas s
        ON s.Id_Ruta = r.Id_Ruta
       AND s.Cantidad > 0
    LEFT JOIN dbo.tbl_Producto p
        ON p.Id_Producto = s.Id_Producto
    LEFT JOIN dbo.tbl_TipoProducto tp
        ON tp.Id_TipoProducto = p.Id_TipoProducto
    WHERE r.Id_Ruta = @IdRuta
    ORDER BY p.Id_Producto;
END;
GO
