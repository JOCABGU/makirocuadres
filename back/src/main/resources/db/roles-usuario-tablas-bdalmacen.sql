SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET XACT_ABORT ON;
GO

BEGIN TRANSACTION;
BEGIN TRY
    IF OBJECT_ID(N'dbo.Rol', N'U') IS NULL
    BEGIN
        CREATE TABLE dbo.Rol (
            rol_id int IDENTITY(1,1) NOT NULL,
            nombre varchar(50) NOT NULL,
            e_eliminado int NOT NULL CONSTRAINT DF_Rol_EEliminado DEFAULT (2),
            CONSTRAINT PK_Rol PRIMARY KEY CLUSTERED (rol_id),
            CONSTRAINT UQ_Rol_Nombre UNIQUE (nombre)
        );
    END;

    SET IDENTITY_INSERT dbo.Rol ON;

    IF NOT EXISTS (SELECT 1 FROM dbo.Rol WHERE rol_id = 1)
        INSERT INTO dbo.Rol (rol_id, nombre, e_eliminado) VALUES (1, 'Tecnico', 2);
    IF NOT EXISTS (SELECT 1 FROM dbo.Rol WHERE rol_id = 2)
        INSERT INTO dbo.Rol (rol_id, nombre, e_eliminado) VALUES (2, 'Almacenero', 2);
    IF NOT EXISTS (SELECT 1 FROM dbo.Rol WHERE rol_id = 3)
        INSERT INTO dbo.Rol (rol_id, nombre, e_eliminado) VALUES (3, 'Contabilidad', 2);
    IF NOT EXISTS (SELECT 1 FROM dbo.Rol WHERE rol_id = 4)
        INSERT INTO dbo.Rol (rol_id, nombre, e_eliminado) VALUES (4, 'Sistemas', 2);

    SET IDENTITY_INSERT dbo.Rol OFF;

    IF OBJECT_ID(N'dbo.Rol_Usuario', N'U') IS NULL
    BEGIN
        CREATE TABLE dbo.Rol_Usuario (
            rol_usuario_id int IDENTITY(1,1) NOT NULL,
            rol_id int NOT NULL,
            usuario_id int NOT NULL,
            e_eliminado int NOT NULL CONSTRAINT DF_RolUsuario_EEliminado DEFAULT (2),
            fecha_registro datetime NOT NULL CONSTRAINT DF_RolUsuario_FechaRegistro DEFAULT (GETDATE()),
            CONSTRAINT PK_Rol_Usuario PRIMARY KEY CLUSTERED (rol_usuario_id),
            CONSTRAINT UQ_Rol_Usuario_UsuarioRol UNIQUE (usuario_id, rol_id),
            CONSTRAINT FK_Rol_Usuario_Rol FOREIGN KEY (rol_id) REFERENCES dbo.Rol (rol_id),
            CONSTRAINT FK_Rol_Usuario_Usuario FOREIGN KEY (usuario_id) REFERENCES dbo.tbl_Usuario (Id)
        );
    END;

    INSERT INTO dbo.Rol_Usuario (rol_id, usuario_id, e_eliminado)
    SELECT 1, u.Id, 2
    FROM dbo.tbl_Usuario u
    WHERE NOT EXISTS (
        SELECT 1
        FROM dbo.Rol_Usuario ru
        WHERE ru.usuario_id = u.Id
          AND ru.rol_id = 1
    );

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    DECLARE @MensajeError nvarchar(2048) = ERROR_MESSAGE();
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;
    RAISERROR('%s', 16, 1, @MensajeError);
END CATCH;
GO
