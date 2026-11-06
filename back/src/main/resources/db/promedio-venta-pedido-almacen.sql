USE BDAlmacenTarija_Prueba;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID(N'dbo.spj_LoginGeneral_Almacen_ObtenerPromedioPedido', N'P') IS NULL
BEGIN
    EXEC(N'CREATE PROCEDURE dbo.spj_LoginGeneral_Almacen_ObtenerPromedioPedido AS BEGIN SET NOCOUNT ON; END');
END;
GO

ALTER PROCEDURE dbo.spj_LoginGeneral_Almacen_ObtenerPromedioPedido
    @IdPedido INT,
    @Fecha DATE
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

    EXEC dbo.spy_PromedioVenta_X_Dia @Fecha, @IdRuta;
END;
GO
