SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET ARITHABORT ON;
GO

IF OBJECT_ID(N'dbo.spj_LoginGeneral_Contabilidad_ListarDepositosPendientes', N'P') IS NULL
    EXEC(N'CREATE PROCEDURE dbo.spj_LoginGeneral_Contabilidad_ListarDepositosPendientes AS BEGIN SET NOCOUNT ON; END');
GO

ALTER PROCEDURE dbo.spj_LoginGeneral_Contabilidad_ListarDepositosPendientes
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        deposito.Id_Deposito_EnRuta AS IdDeposito,
        deposito.Id_Ruta AS IdRuta,
        ISNULL(ruta.Nombre, 'RUTA ' + CONVERT(VARCHAR(12), deposito.Id_Ruta)) AS Ruta,
        deposito.Id_Vendedor AS IdVendedor,
        ISNULL(vendedor.Nombre, 'VENDEDOR ' + CONVERT(VARCHAR(12), deposito.Id_Vendedor)) AS Vendedor,
        deposito.Id_Usuario AS IdUsuario,
        deposito.Id_Entidad AS IdEntidad,
        COALESCE(NULLIF(LTRIM(RTRIM(entidad.Nombre)), ''), 'Entidad ' + CONVERT(VARCHAR(20), deposito.Id_Entidad)) AS NombreBanco,
        deposito.Cuenta,
        deposito.Monto,
        deposito.OP,
        COALESCE(deposito.Fecha_Registro, deposito.FechaTransaccion) AS FechaRegistro,
        deposito.E_Aprobado AS EstadoAprobacion,
        CASE deposito.E_Aprobado
            WHEN 1 THEN 'Rechazado'
            WHEN 2 THEN 'Pendiente'
            WHEN 3 THEN 'Aprobado'
            ELSE 'Desconocido'
        END AS EstadoTexto,
        deposito.AprobadoPor,
        deposito.Fecha_Aprobacion AS FechaAprobacion,
        CASE WHEN deposito.E_Aprobado = 2 AND NULLIF(LTRIM(RTRIM(deposito.OP)), '') IS NULL THEN 1 ELSE 0 END AS PuedeEditar,
        CASE WHEN deposito.E_Aprobado = 2 THEN 1 ELSE 0 END AS PuedeAprobar
    FROM dbo.tbl_Deposito_EnRuta deposito
    LEFT JOIN dbo.tbl_Ruta ruta ON ruta.Id_Ruta = deposito.Id_Ruta
    LEFT JOIN dbo.tbl_Vendedor vendedor ON vendedor.Id_Vendedor = deposito.Id_Vendedor
    LEFT JOIN dbo.tbl_Entidad entidad ON entidad.Id_Entidad = deposito.Id_Entidad
    WHERE deposito.E_Eliminado = 2
      AND deposito.E_Aprobado IN (2, 3)
    ORDER BY CASE deposito.E_Aprobado WHEN 2 THEN 0 ELSE 1 END,
             CASE WHEN NULLIF(LTRIM(RTRIM(deposito.OP)), '') IS NULL THEN 0 ELSE 1 END,
             deposito.Id_Deposito_EnRuta DESC;
END;
GO

IF OBJECT_ID(N'dbo.spj_LoginGeneral_Contabilidad_EditarDepositoSinOP', N'P') IS NULL
    EXEC(N'CREATE PROCEDURE dbo.spj_LoginGeneral_Contabilidad_EditarDepositoSinOP AS BEGIN SET NOCOUNT ON; END');
GO

ALTER PROCEDURE dbo.spj_LoginGeneral_Contabilidad_EditarDepositoSinOP
    @IdDeposito INT,
    @IdEntidad INT,
    @Cuenta VARCHAR(50),
    @Monto DECIMAL(18,2),
    @OP VARCHAR(50) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        IF NOT EXISTS
        (
            SELECT 1
            FROM dbo.tbl_Deposito_EnRuta WITH (UPDLOCK, HOLDLOCK)
            WHERE Id_Deposito_EnRuta = @IdDeposito
              AND E_Eliminado = 2
              AND E_Aprobado = 2
        )
            RAISERROR('El depósito no existe o ya no está pendiente.', 16, 1);

        IF EXISTS
        (
            SELECT 1
            FROM dbo.tbl_Deposito_EnRuta
            WHERE Id_Deposito_EnRuta = @IdDeposito
              AND NULLIF(LTRIM(RTRIM(OP)), '') IS NOT NULL
        )
            RAISERROR('El depósito ya tiene OP y no puede ser editado.', 16, 1);

        IF NOT EXISTS (SELECT 1 FROM dbo.tbl_Entidad WHERE Id_Entidad = @IdEntidad AND E_Eliminado = 2)
            RAISERROR('La entidad bancaria no existe o no está activa.', 16, 1);

        IF NULLIF(LTRIM(RTRIM(@Cuenta)), '') IS NULL
            RAISERROR('La cuenta es obligatoria.', 16, 1);

        IF @Monto IS NULL OR @Monto <= 0
            RAISERROR('El monto debe ser mayor a cero.', 16, 1);

        UPDATE dbo.tbl_Deposito_EnRuta
        SET Id_Entidad = @IdEntidad,
            Cuenta = LTRIM(RTRIM(@Cuenta)),
            Monto = @Monto,
            OP = NULLIF(LTRIM(RTRIM(@OP)), '')
        WHERE Id_Deposito_EnRuta = @IdDeposito;

        COMMIT TRANSACTION;
        SELECT @IdDeposito AS IdDeposito, 'Depósito actualizado correctamente.' AS Mensaje;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        DECLARE @MensajeError NVARCHAR(4000) = ERROR_MESSAGE();
        DECLARE @SeveridadError INT = ERROR_SEVERITY();
        DECLARE @EstadoError INT = ERROR_STATE();
        RAISERROR(@MensajeError, @SeveridadError, @EstadoError);
    END CATCH;
END;
GO

IF COL_LENGTH('dbo.tbl_Deposito_EnRuta', 'Fecha_Aprobacion') IS NULL
    ALTER TABLE dbo.tbl_Deposito_EnRuta ADD Fecha_Aprobacion DATETIME NULL;
GO

IF COL_LENGTH('dbo.tbl_Deposito_EnRuta', 'Id_Deposito') IS NULL
    ALTER TABLE dbo.tbl_Deposito_EnRuta ADD Id_Deposito INT NULL;
GO

IF NOT EXISTS
(
    SELECT 1 FROM sys.foreign_keys
    WHERE parent_object_id = OBJECT_ID(N'dbo.tbl_Deposito_EnRuta')
      AND name = N'FK_DepositoEnRuta_Deposito'
)
    ALTER TABLE dbo.tbl_Deposito_EnRuta WITH CHECK
        ADD CONSTRAINT FK_DepositoEnRuta_Deposito
        FOREIGN KEY (Id_Deposito) REFERENCES dbo.tbl_Deposito (Id_Deposito);
GO

IF EXISTS
(
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID(N'dbo.tbl_Deposito_EnRuta')
      AND name = N'UX_DepositoEnRuta_IdDeposito'
)
    DROP INDEX UX_DepositoEnRuta_IdDeposito ON dbo.tbl_Deposito_EnRuta;
GO

IF OBJECT_ID(N'dbo.spj_LoginGeneral_Contabilidad_AprobarDeposito', N'P') IS NULL
    EXEC(N'CREATE PROCEDURE dbo.spj_LoginGeneral_Contabilidad_AprobarDeposito AS BEGIN SET NOCOUNT ON; END');
GO

ALTER PROCEDURE dbo.spj_LoginGeneral_Contabilidad_AprobarDeposito
    @IdDeposito INT,
    @AprobadoPor VARCHAR(150),
    @IdUsuarioAprobador INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE
            @IdCaja INT,
            @IdDepositoDefinitivo INT,
            @IdEntidad INT,
            @Monto DECIMAL(18,2),
            @Cuenta NVARCHAR(50),
            @Observacion VARCHAR(200),
            @OP VARCHAR(25),
            @FechaTransaccion DATETIME,
            @HoraTransaccion TIME(7),
            @IdRuta INT,
            @Vendedor VARCHAR(150);

        SELECT
            @IdCaja = deposito.Id_Caja,
            @IdDepositoDefinitivo = deposito.Id_Deposito,
            @IdEntidad = deposito.Id_Entidad,
            @Monto = deposito.Monto,
            @Cuenta = deposito.Cuenta,
            @Observacion = deposito.Observacion,
            @OP = deposito.OP,
            @FechaTransaccion = deposito.FechaTransaccion,
            @HoraTransaccion = deposito.HoraTransaccion,
            @IdRuta = deposito.Id_Ruta,
            @Vendedor = vendedor.Nombre
        FROM dbo.tbl_Deposito_EnRuta deposito WITH (UPDLOCK, HOLDLOCK)
        LEFT JOIN dbo.tbl_Vendedor vendedor ON vendedor.Id_Vendedor = deposito.Id_Vendedor
        WHERE deposito.Id_Deposito_EnRuta = @IdDeposito
          AND deposito.E_Eliminado = 2;

        IF @IdEntidad IS NULL
            RAISERROR('El depósito no existe o está eliminado.', 16, 1);

        IF @IdDepositoDefinitivo IS NOT NULL
            RAISERROR('El depósito ya fue trasladado a la tabla definitiva.', 16, 1);

        IF NOT EXISTS
        (
            SELECT 1 FROM dbo.tbl_Deposito_EnRuta
            WHERE Id_Deposito_EnRuta = @IdDeposito AND E_Aprobado = 2
        )
            RAISERROR('El depósito ya no está pendiente de aprobación.', 16, 1);

        IF NULLIF(LTRIM(RTRIM(@OP)), '') IS NULL
            RAISERROR('No se puede aprobar el depósito sin completar la OP.', 16, 1);

        IF NOT EXISTS
        (
            SELECT 1 FROM dbo.tbl_Usuario WITH (HOLDLOCK)
            WHERE Id = @IdUsuarioAprobador AND E_Eliminado = 2
        )
            RAISERROR('El usuario aprobador no existe o no está activo.', 16, 1);

        IF @IdCaja IS NULL
        BEGIN
            INSERT INTO dbo.tbl_Caja
            (
                Id_TipoMovimiento, Id_Usuario, Entregado, Fecha, Observacion,
                Total, MontoDeposito, MontoEfectivo, MontoDPago, MontoCambio,
                MontoDeuda, E_Eliminado, TotalDs, TipoCambio
            )
            VALUES
            (
                22, @IdUsuarioAprobador,
                LEFT(COALESCE(NULLIF(LTRIM(RTRIM(@Vendedor)), ''), 'RUTA ' + CONVERT(VARCHAR(12), @IdRuta)) + ' - DEPÓSITO EN RUTA', 100),
                GETDATE(), LEFT('Depósito aprobado desde portal - RUTA ' + CONVERT(VARCHAR(12), @IdRuta), 500),
                @Monto, @Monto, 0, 0, 0, 0, 2, 0, NULL
            );
            SET @IdCaja = CONVERT(INT, SCOPE_IDENTITY());
        END;

        INSERT INTO dbo.tbl_Deposito
        (
            Id_Caja, Id_Entidad, Monto, Cuenta, Observacion, E_Eliminado,
            Id_PedidoCliente, OP, FechaTransaccion, HoraTransaccion
        )
        VALUES
        (
            @IdCaja, @IdEntidad, @Monto, @Cuenta, COALESCE(@Observacion, ''),
            0, 0, @OP, COALESCE(@FechaTransaccion, GETDATE()),
            COALESCE(@HoraTransaccion, CONVERT(TIME(7), GETDATE()))
        );

        SET @IdDepositoDefinitivo = CONVERT(INT, SCOPE_IDENTITY());

        UPDATE dbo.tbl_Deposito_EnRuta
        SET E_Aprobado = 3,
            AprobadoPor = NULLIF(LTRIM(RTRIM(@AprobadoPor)), ''),
            Fecha_Aprobacion = GETDATE(),
            Id_Caja = @IdCaja,
            Id_Deposito = @IdDepositoDefinitivo
        WHERE Id_Deposito_EnRuta = @IdDeposito;

        COMMIT TRANSACTION;
        SELECT @IdDeposito AS IdDeposito,
               @IdDepositoDefinitivo AS IdDepositoDefinitivo,
               'Depósito aprobado y registrado en la tabla definitiva.' AS Mensaje;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        DECLARE @MensajeError NVARCHAR(4000) = ERROR_MESSAGE();
        DECLARE @SeveridadError INT = ERROR_SEVERITY();
        DECLARE @EstadoError INT = ERROR_STATE();
        RAISERROR(@MensajeError, @SeveridadError, @EstadoError);
    END CATCH;
END;
GO
