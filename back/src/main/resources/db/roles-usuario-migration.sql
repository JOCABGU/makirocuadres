USE BDAlmacenTarija_Prueba;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID(N'dbo.Rol', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Rol
    (
        rol_id      INT IDENTITY(1,1) NOT NULL,
        nombre      VARCHAR(50) NOT NULL,
        e_eliminado INT NOT NULL CONSTRAINT DF_Rol_E_Eliminado DEFAULT (2),
        CONSTRAINT PK_Rol PRIMARY KEY CLUSTERED (rol_id),
        CONSTRAINT UQ_Rol_Nombre UNIQUE (nombre)
    );
END;
GO

IF NOT EXISTS (SELECT 1 FROM dbo.Rol WHERE nombre = 'Tecnico')
    INSERT INTO dbo.Rol (nombre, e_eliminado) VALUES ('Tecnico', 2);

IF NOT EXISTS (SELECT 1 FROM dbo.Rol WHERE nombre = 'Almacenero')
    INSERT INTO dbo.Rol (nombre, e_eliminado) VALUES ('Almacenero', 2);
GO

IF COL_LENGTH(N'dbo.tbl_Usuario', N'rol_id') IS NULL
    ALTER TABLE dbo.tbl_Usuario ADD rol_id INT NULL;
GO

UPDATE dbo.tbl_Usuario
SET rol_id = (SELECT rol_id FROM dbo.Rol WHERE nombre = 'Tecnico')
WHERE rol_id IS NULL;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE parent_object_id = OBJECT_ID(N'dbo.tbl_Usuario')
      AND name = N'FK_tbl_Usuario_Rol'
)
BEGIN
    ALTER TABLE dbo.tbl_Usuario WITH CHECK
        ADD CONSTRAINT FK_tbl_Usuario_Rol
        FOREIGN KEY (rol_id) REFERENCES dbo.Rol (rol_id);
END;
GO

IF NOT EXISTS (SELECT 1 FROM dbo.tbl_Usuario WHERE Loggin = 'p_almacenero')
BEGIN
    INSERT INTO dbo.tbl_Usuario
    (
        Nombre,
        Loggin,
        Password,
        E_Eliminado,
        rol_id
    )
    SELECT
        'p_almacenero',
        'p_almacenero',
        u.Password,
        2,
        (SELECT rol_id FROM dbo.Rol WHERE nombre = 'Almacenero')
    FROM dbo.tbl_Usuario u
    INNER JOIN dbo.tbl_UsuarioTecnico ut
        ON ut.id_Usuario = u.Id
    WHERE ut.id_Vendedor = 159
      AND u.E_Eliminado = 2;
END;
ELSE
BEGIN
    UPDATE dbo.tbl_Usuario
    SET rol_id = (SELECT rol_id FROM dbo.Rol WHERE nombre = 'Almacenero'),
        E_Eliminado = 2
    WHERE Loggin = 'p_almacenero';
END;
GO
