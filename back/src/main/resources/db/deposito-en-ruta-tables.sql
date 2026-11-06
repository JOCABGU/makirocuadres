USE BDAlmacenTarija_Prueba;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

-- Tabla de depósitos registrados por el vendedor en ruta
IF OBJECT_ID(N'dbo.tbl_Deposito_EnRuta', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.tbl_Deposito_EnRuta
    (
        Id_Deposito_EnRuta  INT IDENTITY(1,1) NOT NULL,
        Id_Ruta             INT NOT NULL,
        Id_Vendedor         INT NOT NULL,
        Id_Usuario          INT NOT NULL,
        Id_Entidad          INT NOT NULL,
        Cuenta              VARCHAR(50) NOT NULL,
        Monto               DECIMAL(18,2) NOT NULL,
        OP                  VARCHAR(50) NULL,
        Fecha_Registro      DATETIME NOT NULL
            CONSTRAINT DF_Deposito_EnRuta_FechaRegistro DEFAULT (GETDATE()),
        E_Aprobado          INT NOT NULL
            CONSTRAINT DF_Deposito_EnRuta_Aprobado DEFAULT (2),
        E_Eliminado         INT NOT NULL
            CONSTRAINT DF_Deposito_EnRuta_Eliminado DEFAULT (2),

        CONSTRAINT PK_Deposito_EnRuta
            PRIMARY KEY CLUSTERED (Id_Deposito_EnRuta),
        CONSTRAINT FK_Deposito_EnRuta_Ruta
            FOREIGN KEY (Id_Ruta) REFERENCES dbo.tbl_Ruta (Id_Ruta),
        CONSTRAINT FK_Deposito_EnRuta_Vendedor
            FOREIGN KEY (Id_Vendedor) REFERENCES dbo.tbl_Vendedor (Id_Vendedor),
        CONSTRAINT FK_Deposito_EnRuta_Usuario
            FOREIGN KEY (Id_Usuario) REFERENCES dbo.tbl_Usuario (Id),
        CONSTRAINT FK_Deposito_EnRuta_Entidad
            FOREIGN KEY (Id_Entidad) REFERENCES dbo.tbl_Entidad (Id_Entidad)
    );
END;
GO

-- Procedimiento para registrar depósito del vendedor
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

        -- Validar ruta
        IF NOT EXISTS (SELECT 1 FROM dbo.tbl_Ruta WHERE Id_Ruta = @IdRuta)
        BEGIN
            RAISERROR('La ruta especificada no existe.', 16, 1);
            RETURN;
        END;

        -- Validar vendedor
        IF NOT EXISTS (SELECT 1 FROM dbo.tbl_Vendedor WHERE Id_Vendedor = @IdVendedor)
        BEGIN
            RAISERROR('El vendedor especificado no existe.', 16, 1);
            RETURN;
        END;

        -- Validar usuario
        IF NOT EXISTS (SELECT 1 FROM dbo.tbl_Usuario WHERE Id = @IdUsuario AND E_Eliminado = 2)
        BEGIN
            RAISERROR('El usuario especificado no existe o está eliminado.', 16, 1);
            RETURN;
        END;

        -- Validar banco/entidad
        IF NOT EXISTS (SELECT 1 FROM dbo.tbl_Entidad WHERE Id_Entidad = @IdEntidad)
        BEGIN
            RAISERROR('El banco especificado no existe.', 16, 1);
            RETURN;
        END;

        -- Validar monto positivo
        IF @Monto <= 0
        BEGIN
            RAISERROR('El monto debe ser mayor a cero.', 16, 1);
            RETURN;
        END;

        -- Registrar depósito
        DECLARE @IdDepositoCreado INT;

        INSERT INTO dbo.tbl_Deposito_EnRuta
            (Id_Ruta, Id_Vendedor, Id_Usuario, Id_Entidad, Cuenta, Monto, OP, E_Aprobado, E_Eliminado)
        VALUES
            (@IdRuta, @IdVendedor, @IdUsuario, @IdEntidad, @Cuenta, @Monto, @OP, 2, 2);

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

-- Procedimiento para listar bancos/entidades
IF OBJECT_ID(N'dbo.spj_LoginGeneral_ListarEntidades', N'P') IS NOT NULL
    DROP PROCEDURE dbo.spj_LoginGeneral_ListarEntidades;
GO

CREATE PROCEDURE dbo.spj_LoginGeneral_ListarEntidades
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        Id_Entidad AS IdEntidad,
        Entidad AS Nombre
    FROM
        dbo.tbl_Entidad
    ORDER BY
        Entidad;
END;
GO

-- Procedimiento para listar depósitos del vendedor
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
        d.Id_Ruta AS IdRuta,
        d.Id_Vendedor AS IdVendedor,
        d.Id_Usuario AS IdUsuario,
        d.Id_Entidad AS IdEntidad,
        e.Entidad AS NombreBanco,
        d.Cuenta,
        d.Monto,
        d.OP,
        d.Fecha_Registro AS FechaRegistro,
        d.E_Aprobado AS EstadoAprobacion,
        CASE
            WHEN d.E_Aprobado = 1 THEN 'Rechazado'
            WHEN d.E_Aprobado = 2 THEN 'Pendiente'
            WHEN d.E_Aprobado = 3 THEN 'Aprobado'
            ELSE 'Desconocido'
        END AS EstadoTexto
    FROM
        dbo.tbl_Deposito_EnRuta d
        INNER JOIN dbo.tbl_Entidad e ON d.Id_Entidad = e.Id_Entidad
    WHERE
        d.Id_Ruta = @IdRuta
        AND d.E_Eliminado = 2
    ORDER BY
        d.Fecha_Registro DESC;
END;
GO
