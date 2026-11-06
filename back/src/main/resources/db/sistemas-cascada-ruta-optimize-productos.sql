USE [BDAlmacenTarija_Prueba];
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

    UPDATE p
    SET p.Vendido = 0, p.Id_Ruta = 0, p.Id_PedidoVendedor = 0, p.Id_Cuadre = NULL
    FROM dbo.tbl_Productos p
    INNER JOIN #ProductosPedido incluido ON incluido.Imei = p.Imei;

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

    UPDATE dbo.tbl_PedidoVendedor_EnRuta
    SET E_Aprobado = 1, AprobadoPor = NULL, Id_PedidoVendedorNormal = 0
    WHERE Id_PedidoVendedor_EnRuta = @IdPedidoEnRuta;
END;
GO
