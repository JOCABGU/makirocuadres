SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID(N'dbo.spj_LoginGeneral_RegistrarDepositoEnRuta', N'P') IS NOT NULL
    DROP PROCEDURE dbo.spj_LoginGeneral_RegistrarDepositoEnRuta;
GO

CREATE PROCEDURE dbo.spj_LoginGeneral_RegistrarDepositoEnRuta
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

        IF NOT EXISTS (
            SELECT 1
            FROM dbo.tbl_Ruta r
            WHERE r.Id_Ruta = @IdRuta
              AND r.Id_Vendedor = @IdVendedor
              AND ISNULL(r.E_Eliminado, 2) = 2
        )
        BEGIN
            RAISERROR('La ruta indicada no pertenece al vendedor o no está activa.', 16, 1);
            RETURN;
        END;

        IF NOT EXISTS (
            SELECT 1
            FROM dbo.tbl_UsuarioTecnico ut
            WHERE ut.id_usuario = @IdUsuario
              AND ut.id_vendedor = @IdVendedor
              AND ISNULL(ut.e_eliminado, 2) = 2
        )
        BEGIN
            RAISERROR('El usuario no está vinculado al vendedor de la ruta.', 16, 1);
            RETURN;
        END;

        IF NOT EXISTS (
            SELECT 1
            FROM dbo.tbl_Entidad e
            WHERE e.Id_Entidad = @IdEntidad
              AND ISNULL(e.E_Eliminado, 2) = 2
        )
        BEGIN
            RAISERROR('La entidad bancaria indicada no existe.', 16, 1);
            RETURN;
        END;

        IF @Monto IS NULL OR @Monto <= 0
        BEGIN
            RAISERROR('El monto debe ser mayor a cero.', 16, 1);
            RETURN;
        END;

        DECLARE @IdCaja INT;

        SELECT TOP (1)
            @IdCaja = c.Id_Caja
        FROM dbo.tbl_Caja c
        WHERE c.Id_Usuario = @IdUsuario
          AND ISNULL(c.E_Eliminado, 2) = 2
        ORDER BY c.Id_Caja DESC;

        IF @IdCaja IS NULL
        BEGIN
            RAISERROR('No existe una caja registrada para el usuario técnico.', 16, 1);
            RETURN;
        END;

        DECLARE @IdDepositoCreado INT;

        INSERT INTO dbo.tbl_Deposito_EnRuta
            (Id_Caja, Id_Entidad, Monto, Cuenta, Observacion, E_Eliminado, OP, FechaTransaccion, HoraTransaccion, E_Aprobado, AprobadoPor)
        VALUES
            (@IdCaja, @IdEntidad, @Monto, @Cuenta, NULL, 2, NULLIF(LTRIM(RTRIM(@OP)), ''), CONVERT(date, GETDATE()), CONVERT(time(0), GETDATE()), 2, NULL);

        SET @IdDepositoCreado = SCOPE_IDENTITY();

        SELECT
            @IdDepositoCreado AS IdDeposito,
            'Depósito registrado correctamente. Pendiente de aprobación.' AS Mensaje;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        DECLARE @ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
        DECLARE @ErrorSeverity INT = ERROR_SEVERITY();
        DECLARE @ErrorState INT = ERROR_STATE();

        RAISERROR(@ErrorMessage, @ErrorSeverity, @ErrorState);
    END CATCH;
END;
GO

IF OBJECT_ID(N'dbo.spj_LoginGeneral_ListarEntidades', N'P') IS NOT NULL
    DROP PROCEDURE dbo.spj_LoginGeneral_ListarEntidades;
GO

CREATE PROCEDURE dbo.spj_LoginGeneral_ListarEntidades
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        e.Id_Entidad AS IdEntidad,
        COALESCE(NULLIF(LTRIM(RTRIM(e.Nombre)), ''), NULLIF(LTRIM(RTRIM(e.EntidadBancaria)), ''), 'Entidad ' + CAST(e.Id_Entidad AS VARCHAR(20))) AS Nombre
    FROM dbo.tbl_Entidad e
    WHERE ISNULL(e.E_Eliminado, 2) = 2
    ORDER BY Nombre;
END;
GO

IF OBJECT_ID(N'dbo.spj_LoginGeneral_ListarDepositosEnRuta', N'P') IS NOT NULL
    DROP PROCEDURE dbo.spj_LoginGeneral_ListarDepositosEnRuta;
GO

CREATE PROCEDURE dbo.spj_LoginGeneral_ListarDepositosEnRuta
    @IdRuta INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        d.Id_Deposito_EnRuta AS IdDeposito,
        r.Id_Ruta AS IdRuta,
        ut.id_vendedor AS IdVendedor,
        c.Id_Usuario AS IdUsuario,
        d.Id_Entidad AS IdEntidad,
        COALESCE(NULLIF(LTRIM(RTRIM(e.Nombre)), ''), NULLIF(LTRIM(RTRIM(e.EntidadBancaria)), ''), 'Entidad ' + CAST(e.Id_Entidad AS VARCHAR(20))) AS NombreBanco,
        d.Cuenta,
        d.Monto,
        d.OP,
        CASE
            WHEN d.FechaTransaccion IS NOT NULL THEN DATEADD(SECOND, DATEDIFF(SECOND, CONVERT(time(0), '00:00:00'), ISNULL(d.HoraTransaccion, CONVERT(time(0), '00:00:00'))), CONVERT(datetime2(0), d.FechaTransaccion))
            ELSE NULL
        END AS FechaRegistro,
        d.E_Aprobado AS EstadoAprobacion,
        CASE
            WHEN d.E_Aprobado = 1 THEN 'Rechazado'
            WHEN d.E_Aprobado = 2 THEN 'Pendiente'
            WHEN d.E_Aprobado = 3 THEN 'Aprobado'
            ELSE 'Desconocido'
        END AS EstadoTexto
    FROM dbo.tbl_Deposito_EnRuta d
    INNER JOIN dbo.tbl_Caja c
        ON c.Id_Caja = d.Id_Caja
       AND ISNULL(c.E_Eliminado, 2) = 2
    INNER JOIN dbo.tbl_UsuarioTecnico ut
        ON ut.id_usuario = c.Id_Usuario
       AND ISNULL(ut.e_eliminado, 2) = 2
    INNER JOIN dbo.tbl_Ruta r
        ON r.Id_Vendedor = ut.id_vendedor
       AND ISNULL(r.E_Eliminado, 2) = 2
    LEFT JOIN dbo.tbl_Entidad e
        ON e.Id_Entidad = d.Id_Entidad
    WHERE r.Id_Ruta = @IdRuta
      AND ISNULL(d.E_Eliminado, 2) = 2
    ORDER BY d.Id_Deposito_EnRuta DESC;
END;
GO
