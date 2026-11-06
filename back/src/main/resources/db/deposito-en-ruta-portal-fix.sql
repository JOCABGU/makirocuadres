SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/*
 * Corrige la tabla preliminar de depósitos para que siga el mismo patrón
 * de Pedido/Cuadre EnRuta: el registro pertenece directamente a la ruta,
 * vendedor y usuario. La caja se asignará recién durante la aprobación.
 */
IF COL_LENGTH('dbo.tbl_Deposito_EnRuta', 'Id_Ruta') IS NULL
    ALTER TABLE dbo.tbl_Deposito_EnRuta ADD Id_Ruta INT NULL;
GO
IF COL_LENGTH('dbo.tbl_Deposito_EnRuta', 'Id_Vendedor') IS NULL
    ALTER TABLE dbo.tbl_Deposito_EnRuta ADD Id_Vendedor INT NULL;
GO
IF COL_LENGTH('dbo.tbl_Deposito_EnRuta', 'Id_Usuario') IS NULL
    ALTER TABLE dbo.tbl_Deposito_EnRuta ADD Id_Usuario INT NULL;
GO
IF COL_LENGTH('dbo.tbl_Deposito_EnRuta', 'Fecha_Registro') IS NULL
    ALTER TABLE dbo.tbl_Deposito_EnRuta ADD Fecha_Registro DATETIME NULL
        CONSTRAINT DF_DepositoEnRuta_Portal_FechaRegistro DEFAULT (GETDATE());
GO

/* Un depósito pendiente todavía no tiene una caja definitiva. */
ALTER TABLE dbo.tbl_Deposito_EnRuta ALTER COLUMN Id_Caja INT NULL;
GO

IF OBJECT_ID(N'dbo.spj_LoginGeneral_RegistrarDepositoEnRuta', N'P') IS NULL
    EXEC(N'CREATE PROCEDURE dbo.spj_LoginGeneral_RegistrarDepositoEnRuta AS BEGIN SET NOCOUNT ON; END');
GO

ALTER PROCEDURE dbo.spj_LoginGeneral_RegistrarDepositoEnRuta
    @IdRuta         INT,
    @IdVendedor     INT,
    @IdUsuario      INT,
    @IdEntidad      INT,
    @Cuenta         VARCHAR(50),
    @Monto          DECIMAL(18,2),
    @OP             VARCHAR(50) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        IF NOT EXISTS
        (
            SELECT 1
            FROM dbo.tbl_Ruta ruta
            WHERE ruta.Id_Ruta = @IdRuta
              AND ruta.Id_Vendedor = @IdVendedor
              AND ruta.E_Eliminado = 2
        )
            RAISERROR('La ruta indicada no pertenece al vendedor o no está activa.', 16, 1);

        IF NOT EXISTS
        (
            SELECT 1
            FROM dbo.tbl_Usuario usuario
            INNER JOIN dbo.tbl_UsuarioTecnico tecnico
                ON tecnico.id_usuario = usuario.Id
               AND tecnico.id_vendedor = @IdVendedor
               AND ISNULL(tecnico.e_eliminado, 0) = 0
            WHERE usuario.Id = @IdUsuario
              AND usuario.E_Eliminado = 2
        )
            RAISERROR('El usuario no está vinculado al vendedor de la ruta.', 16, 1);

        IF NOT EXISTS
        (
            SELECT 1 FROM dbo.tbl_Entidad entidad
            WHERE entidad.Id_Entidad = @IdEntidad
              AND entidad.E_Eliminado = 2
        )
            RAISERROR('La entidad bancaria indicada no existe o no está activa.', 16, 1);

        IF NULLIF(LTRIM(RTRIM(@Cuenta)), '') IS NULL
            RAISERROR('La cuenta es obligatoria.', 16, 1);

        IF @Monto IS NULL OR @Monto <= 0
            RAISERROR('El monto debe ser mayor a cero.', 16, 1);

        INSERT INTO dbo.tbl_Deposito_EnRuta
        (
            Id_Caja, Id_Entidad, Monto, Cuenta, Observacion,
            E_Eliminado, OP, FechaTransaccion, HoraTransaccion,
            E_Aprobado, AprobadoPor,
            Id_Ruta, Id_Vendedor, Id_Usuario, Fecha_Registro
        )
        VALUES
        (
            NULL, @IdEntidad, @Monto, LTRIM(RTRIM(@Cuenta)), '',
            2, NULLIF(LTRIM(RTRIM(@OP)), ''), GETDATE(), CONVERT(TIME(0), GETDATE()),
            2, NULL,
            @IdRuta, @IdVendedor, @IdUsuario, GETDATE()
        );

        DECLARE @IdDepositoCreado INT = SCOPE_IDENTITY();
        COMMIT TRANSACTION;

        SELECT @IdDepositoCreado AS IdDeposito,
               'Depósito registrado correctamente. Pendiente de aprobación.' AS Mensaje;
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

IF OBJECT_ID(N'dbo.spj_LoginGeneral_ListarDepositosEnRuta', N'P') IS NULL
    EXEC(N'CREATE PROCEDURE dbo.spj_LoginGeneral_ListarDepositosEnRuta AS BEGIN SET NOCOUNT ON; END');
GO

ALTER PROCEDURE dbo.spj_LoginGeneral_ListarDepositosEnRuta
    @IdRuta INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        deposito.Id_Deposito_EnRuta AS IdDeposito,
        deposito.Id_Ruta AS IdRuta,
        deposito.Id_Vendedor AS IdVendedor,
        deposito.Id_Usuario AS IdUsuario,
        deposito.Id_Entidad AS IdEntidad,
        COALESCE(NULLIF(LTRIM(RTRIM(entidad.Nombre)), ''),
                 NULLIF(LTRIM(RTRIM(CONVERT(NVARCHAR(100), entidad.EntidadBancaria))), ''),
                 'Entidad ' + CONVERT(VARCHAR(20), entidad.Id_Entidad)) AS NombreBanco,
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
        END AS EstadoTexto
    FROM dbo.tbl_Deposito_EnRuta deposito
    LEFT JOIN dbo.tbl_Entidad entidad
        ON entidad.Id_Entidad = deposito.Id_Entidad
    WHERE deposito.Id_Ruta = @IdRuta
      AND deposito.E_Eliminado = 2
    ORDER BY deposito.Id_Deposito_EnRuta DESC;
END;
GO
