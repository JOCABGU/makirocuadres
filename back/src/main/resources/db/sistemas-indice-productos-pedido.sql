USE [BDAlmacenTarija_Prueba];
GO

-- Acelera la localizacion de las unidades fisicas de un pedido durante una
-- reversion. No cambia datos ni reglas de negocio; solo agrega una ruta de
-- acceso cubierta para Id_PedidoVendedor + Imei.
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
