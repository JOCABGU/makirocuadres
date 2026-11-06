SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID(N'dbo.spj_LoginGeneral_Almacen_ObtenerEstadoCierre', N'P') IS NULL
    EXEC(N'CREATE PROCEDURE dbo.spj_LoginGeneral_Almacen_ObtenerEstadoCierre AS BEGIN SET NOCOUNT ON; END');
GO

ALTER PROCEDURE dbo.spj_LoginGeneral_Almacen_ObtenerEstadoCierre
    @Fecha date
AS
BEGIN
    SET NOCOUNT ON;

    SELECT TOP (1)
        ci.Id_CantidadItems AS IdCierreAlmacen,
        ci.Fecha,
        ci.Observacion,
        CAST(1 AS bit) AS Existe,
        (SELECT COUNT(*)
         FROM dbo.tbl_CodigoCantidadItems cci
         WHERE cci.Id_CantidadItems = ci.Id_CantidadItems
           AND cci.E_Eliminado = 2) AS CantidadProductos
    FROM dbo.tbl_CantidadItems ci
    WHERE CONVERT(date, ci.Fecha) = @Fecha
      AND ci.E_Cierre = 1
      AND ci.E_Eliminado = 2
    ORDER BY ci.Id_CantidadItems DESC;
END;
GO

IF OBJECT_ID(N'dbo.spj_LoginGeneral_Almacen_GuardarCierre', N'P') IS NULL
    EXEC(N'CREATE PROCEDURE dbo.spj_LoginGeneral_Almacen_GuardarCierre AS BEGIN SET NOCOUNT ON; END');
GO

ALTER PROCEDURE dbo.spj_LoginGeneral_Almacen_GuardarCierre
    @IdUsuario int,
    @Fecha date,
    @Observacion varchar(28) = ''
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @Fecha IS NULL
    BEGIN
        RAISERROR('La fecha del cierre es requerida.', 16, 1);
        RETURN;
    END;

    IF @Fecha > CONVERT(date, GETDATE())
    BEGIN
        RAISERROR('No se puede registrar un cierre con fecha futura.', 16, 1);
        RETURN;
    END;

    BEGIN TRANSACTION;
    BEGIN TRY
        DECLARE @ResultadoBloqueo int;
        DECLARE @Recurso nvarchar(255) = N'LoginGeneral:CierreAlmacen:' + CONVERT(nvarchar(10), @Fecha, 120);

        EXEC @ResultadoBloqueo = sys.sp_getapplock
            @Resource = @Recurso,
            @LockMode = 'Exclusive',
            @LockOwner = 'Transaction',
            @LockTimeout = 15000;

        IF @ResultadoBloqueo < 0
            RAISERROR('No se pudo bloquear el cierre. Intenta nuevamente.', 16, 1);

        IF EXISTS (
            SELECT 1
            FROM dbo.tbl_CantidadItems WITH (UPDLOCK, HOLDLOCK)
            WHERE CONVERT(date, Fecha) = @Fecha
              AND E_Cierre = 1
              AND E_Eliminado = 2
        )
            RAISERROR('Ya existe un cierre de almacen para la fecha seleccionada.', 16, 1);

        DECLARE @Detalle table (
            Id_Producto int,
            Nombre nvarchar(255),
            PrecioVenta decimal(18,2),
            SaldoDiaAnterior decimal(18,2),
            TotalSaldoDiaAnterior decimal(18,2),
            SaldoDiaAnteriorTIGO decimal(18,2),
            TotalSaldoDiaAnteriorTIGO decimal(18,2),
            CompraDia decimal(18,2),
            TotalCompraDia decimal(18,2),
            CompraDiaTIGO decimal(18,2),
            TotalCompraDiaTIGO decimal(18,2),
            DevolucionIngreso decimal(18,2),
            TotalDevolucionIngreso decimal(18,2),
            VentaDia decimal(18,2),
            TotalVentaDia decimal(18,2),
            SaldoDiaHoy decimal(18,2),
            TotalSaldoDiaHoy decimal(18,2),
            SaldoDiaHoyTIGO decimal(18,2),
            TotalSaldoDiaHoyTIGO decimal(18,2)
        );

        INSERT INTO @Detalle
        EXEC dbo.sp_ObtenerCierreAlmacen_ @Fecha;

        DELETE FROM @Detalle
        WHERE ISNULL(SaldoDiaHoy, 0) <= 0
          AND ISNULL(SaldoDiaHoyTIGO, 0) <= 0;

        IF NOT EXISTS (SELECT 1 FROM @Detalle)
            RAISERROR('El detalle del cierre no contiene productos con saldo mayor a cero.', 16, 1);

        INSERT INTO dbo.tbl_CantidadItems
            (Id_Usuario, Fecha, Observacion, E_Eliminado, E_Cierre)
        VALUES
            (@IdUsuario, @Fecha, LEFT(LTRIM(RTRIM(ISNULL(@Observacion, ''))), 28), 2, 1);

        DECLARE @IdCierreAlmacen int = CONVERT(int, SCOPE_IDENTITY());

        INSERT INTO dbo.tbl_CodigoCantidadItems (
            Id_CantidadItems, Id_Producto, Precio,
            SaldoDiaAnterior, TotalSaldoDiaAnterior,
            CompraDia, TotalCompraDia,
            DevolucionIngreso, TotalDevolucionIngreso,
            VentaDia, TotalVentaDia,
            SaldoDiaHoy, TotalSaldoDiaHoy, E_Eliminado,
            SaldoDiaAnteriorTIGO, TotalSaldoDiaAnteriorTIGO,
            CompraDiaTIGO, TotalCompraDiaTIGO,
            SaldoDiaHoyTIGO, TotalSaldoDiaHoyTIGO
        )
        SELECT
            @IdCierreAlmacen, Id_Producto, ISNULL(PrecioVenta, 0),
            CONVERT(int, ISNULL(SaldoDiaAnterior, 0)), ISNULL(TotalSaldoDiaAnterior, 0),
            CONVERT(int, ISNULL(CompraDia, 0)), ISNULL(TotalCompraDia, 0),
            CONVERT(int, ISNULL(DevolucionIngreso, 0)), ISNULL(TotalDevolucionIngreso, 0),
            CONVERT(int, ISNULL(VentaDia, 0)), ISNULL(TotalVentaDia, 0),
            CONVERT(int, ISNULL(SaldoDiaHoy, 0)), ISNULL(TotalSaldoDiaHoy, 0), 2,
            CONVERT(int, ISNULL(SaldoDiaAnteriorTIGO, 0)), ISNULL(TotalSaldoDiaAnteriorTIGO, 0),
            CONVERT(int, ISNULL(CompraDiaTIGO, 0)), ISNULL(TotalCompraDiaTIGO, 0),
            CONVERT(int, ISNULL(SaldoDiaHoyTIGO, 0)), ISNULL(TotalSaldoDiaHoyTIGO, 0)
        FROM @Detalle;

        COMMIT TRANSACTION;

        SELECT
            @IdCierreAlmacen AS IdCierreAlmacen,
            CONVERT(datetime, @Fecha) AS Fecha,
            COUNT(*) AS CantidadProductos
        FROM @Detalle;
    END TRY
    BEGIN CATCH
        DECLARE @MensajeError nvarchar(2048) = ERROR_MESSAGE();
        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;
        RAISERROR('%s', 16, 1, @MensajeError);
    END CATCH;
END;
GO
