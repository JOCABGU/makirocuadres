SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

ALTER PROCEDURE dbo.spj_LoginGeneral_ListarProductosPorTipo
    @IdTipoProducto INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT p.Id_Producto, p.Nombre, p.PrecioVenta
    FROM dbo.tbl_Producto p
    WHERE p.Id_TipoProducto = @IdTipoProducto
      AND ISNULL(p.E_ELIMINADO, 0) = 0
      AND p.Id_Producto <> 32
    ORDER BY p.Nombre;
END;
GO

IF OBJECT_ID(N'dbo.spj_LoginGeneral_Almacen_ValidarTigoMoneyPedido', N'P') IS NULL
BEGIN
    EXEC(N'CREATE PROCEDURE dbo.spj_LoginGeneral_Almacen_ValidarTigoMoneyPedido
           AS BEGIN SET NOCOUNT ON; END');
END;
GO

ALTER PROCEDURE dbo.spj_LoginGeneral_Almacen_ValidarTigoMoneyPedido
    @IdPedido INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @MontoPedido DECIMAL(18,2);
    DECLARE @SaldoDisponible DECIMAL(18,2);
    DECLARE @ResultadoBloqueo INT;
    DECLARE @RecursoBloqueo VARCHAR(255);
    DECLARE @Ahora DATETIME;

    DECLARE @SaldosAlmacen TABLE
    (
        IdProducto INT,
        Producto NVARCHAR(200),
        Cantidad DECIMAL(18,2)
    );

    SELECT @MontoPedido = CONVERT(DECIMAL(18,2), ISNULL(SUM(detalle.NvoPedido), 0))
    FROM dbo.tbl_PedidoVendedor_EnRuta pedido
    INNER JOIN dbo.tbl_CodigoPedidoVendedor_EnRuta detalle
        ON detalle.Id_PedidoVendedor_EnRuta = pedido.Id_PedidoVendedor_EnRuta
       AND detalle.Id_Producto = 31
       AND detalle.E_Eliminado = 2
    WHERE pedido.Id_PedidoVendedor_EnRuta = @IdPedido
      AND pedido.E_Aprobado = 1
      AND pedido.E_Eliminado = 2;

    IF ISNULL(@MontoPedido, 0) <= 0
    BEGIN
        RAISERROR('El pedido pendiente no contiene Tigo Money Venta.', 16, 1);
        RETURN;
    END;

    SET @Ahora = GETDATE();
    SET @RecursoBloqueo = 'LoginGeneral:TigoMoney:' + CONVERT(VARCHAR(8), @Ahora, 112);

    BEGIN TRY
        BEGIN TRANSACTION;

        EXEC @ResultadoBloqueo = sys.sp_getapplock
            @Resource = @RecursoBloqueo,
            @LockMode = 'Exclusive',
            @LockOwner = 'Transaction',
            @LockTimeout = 15000;

        IF @ResultadoBloqueo < 0
            RAISERROR('No se pudo bloquear el saldo de Tigo Money. Intente nuevamente.', 16, 1);

        INSERT INTO @SaldosAlmacen (IdProducto, Producto, Cantidad)
        EXEC dbo.sp_Traer_Saldos_Productos_Almacen_X_Fecha @Ahora;

        SELECT @SaldoDisponible = ISNULL(Cantidad, 0)
        FROM @SaldosAlmacen
        WHERE IdProducto = 31;

        SET @SaldoDisponible = ISNULL(@SaldoDisponible, 0);

        IF @SaldoDisponible - @MontoPedido < 0
        BEGIN
            DECLARE @Mensaje VARCHAR(300);
            SET @Mensaje = 'Saldo insuficiente de Tigo Money. Disponible: '
                + CONVERT(VARCHAR(30), @SaldoDisponible)
                + ', solicitado: ' + CONVERT(VARCHAR(30), @MontoPedido) + '.';
            RAISERROR(@Mensaje, 16, 1);
        END;

        SELECT
            @SaldoDisponible AS SaldoDisponible,
            @MontoPedido AS MontoPedido,
            @SaldoDisponible - @MontoPedido AS SaldoRestante,
            CAST(1 AS BIT) AS Valido;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        DECLARE @ErrorMessage NVARCHAR(4000);
        SET @ErrorMessage = ERROR_MESSAGE();
        RAISERROR(@ErrorMessage, 16, 1);
    END CATCH;
END;
GO

