USE BDAlmacenTarija_Prueba;
GO

SET XACT_ABORT ON;
GO

IF COL_LENGTH(N'dbo.tbl_PedidoVendedor_EnRuta', N'Id_PedidoVendedorNormal') IS NULL
BEGIN
    ALTER TABLE dbo.tbl_PedidoVendedor_EnRuta
        ADD Id_PedidoVendedorNormal INT NOT NULL
            CONSTRAINT DF_PedidoVendedor_EnRuta_IdPedidoNormal DEFAULT (0) WITH VALUES;
END;
GO

-- La aprobación transaccional asigna a esta columna el ID generado
-- en dbo.tbl_PedidoVendedor. Los pedidos pendientes conservan el valor 0.
;WITH VinculosRecuperables AS
(
    SELECT
        pedido.Id_PedidoVendedor_EnRuta,
        MIN(NULLIF(producto.Id_PedidoVendedor, 0)) AS IdPedidoVendedorNormal
    FROM dbo.tbl_PedidoVendedor_EnRuta pedido
    INNER JOIN dbo.PedidoVendedor_EnRuta_ProductoFisico fisico
        ON fisico.Id_PedidoVendedor_EnRuta = pedido.Id_PedidoVendedor_EnRuta
       AND fisico.E_Eliminado = 2
    INNER JOIN dbo.tbl_Productos producto
        ON producto.Imei = fisico.Imei
       AND producto.Id_Producto = fisico.Id_Producto
    WHERE pedido.E_Aprobado = 2
      AND pedido.Id_PedidoVendedorNormal = 0
      AND ISNULL(producto.Id_PedidoVendedor, 0) <> 0
    GROUP BY pedido.Id_PedidoVendedor_EnRuta
    HAVING COUNT(DISTINCT producto.Id_PedidoVendedor) = 1
)
UPDATE pedido
SET pedido.Id_PedidoVendedorNormal = vinculo.IdPedidoVendedorNormal
FROM dbo.tbl_PedidoVendedor_EnRuta pedido
INNER JOIN VinculosRecuperables vinculo
    ON vinculo.Id_PedidoVendedor_EnRuta = pedido.Id_PedidoVendedor_EnRuta;
GO
