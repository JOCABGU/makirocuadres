SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET ARITHABORT ON;
SET NUMERIC_ROUNDABORT OFF;
SET XACT_ABORT ON;
BEGIN TRANSACTION;

IF NOT EXISTS (SELECT 1 FROM dbo.Rol WHERE nombre = 'Sistemas' AND e_eliminado = 2)
    INSERT INTO dbo.Rol (nombre, e_eliminado) VALUES ('Sistemas', 2);

IF OBJECT_ID('dbo.ReinicioPassword', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.ReinicioPassword (
        Id_ReinicioPassword INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        Id_Usuario INT NOT NULL,
        Estado TINYINT NOT NULL CONSTRAINT DF_ReinicioPassword_Estado DEFAULT (1),
        Id_UsuarioSolicita INT NOT NULL,
        FechaSolicitud DATETIME NOT NULL CONSTRAINT DF_ReinicioPassword_FechaSolicitud DEFAULT (GETDATE()),
        FechaCompletado DATETIME NULL,
        CONSTRAINT CK_ReinicioPassword_Estado CHECK (Estado IN (1, 2)),
        CONSTRAINT FK_ReinicioPassword_Usuario FOREIGN KEY (Id_Usuario) REFERENCES dbo.tbl_Usuario(Id),
        CONSTRAINT FK_ReinicioPassword_Solicita FOREIGN KEY (Id_UsuarioSolicita) REFERENCES dbo.tbl_Usuario(Id)
    );
END;

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.ReinicioPassword') AND name = 'UX_ReinicioPassword_Pendiente')
    CREATE UNIQUE INDEX UX_ReinicioPassword_Pendiente
        ON dbo.ReinicioPassword (Id_Usuario) WHERE Estado = 1;

IF NOT EXISTS (SELECT 1 FROM dbo.tbl_Usuario WHERE Loggin = 'sistemas')
    INSERT INTO dbo.tbl_Usuario (Nombre, Loggin, Password, E_Eliminado)
    VALUES ('SISTEMAS', 'sistemas', 's0z5x9Die/SwEM6tSX18DA==', 2);

INSERT INTO dbo.Rol_Usuario (rol_id, usuario_id, e_eliminado, fecha_registro)
SELECT r.rol_id, u.Id, 2, GETDATE()
FROM dbo.Rol r CROSS JOIN dbo.tbl_Usuario u
WHERE r.nombre = 'Sistemas' AND r.e_eliminado = 2 AND u.Loggin = 'sistemas' AND u.E_Eliminado = 2
  AND NOT EXISTS (
      SELECT 1 FROM dbo.Rol_Usuario ru
      WHERE ru.rol_id = r.rol_id AND ru.usuario_id = u.Id AND ru.e_eliminado = 2
  );

COMMIT TRANSACTION;
