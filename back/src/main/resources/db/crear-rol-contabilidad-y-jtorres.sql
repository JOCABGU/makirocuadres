SET XACT_ABORT ON;
GO

BEGIN TRY
    BEGIN TRANSACTION;

    DECLARE @IdRolContabilidad INT;
    SELECT @IdRolContabilidad = rol_id
    FROM dbo.Rol WITH (UPDLOCK, HOLDLOCK)
    WHERE LOWER(LTRIM(RTRIM(nombre))) = 'contabilidad';

    IF @IdRolContabilidad IS NULL
    BEGIN
        INSERT INTO dbo.Rol (nombre, e_eliminado)
        VALUES ('Contabilidad', 2);
        SET @IdRolContabilidad = SCOPE_IDENTITY();
    END
    ELSE
        UPDATE dbo.Rol SET nombre = 'Contabilidad', e_eliminado = 2
        WHERE rol_id = @IdRolContabilidad;

    DECLARE @PasswordReferencia VARCHAR(50);
    SELECT @PasswordReferencia = Password
    FROM dbo.tbl_Usuario
    WHERE Loggin = 'ecalizaya' AND E_Eliminado = 2;

    IF @PasswordReferencia IS NULL
        RAISERROR('No se encontró la contraseña de referencia del técnico 159.', 16, 1);

    IF EXISTS (SELECT 1 FROM dbo.tbl_Usuario WITH (UPDLOCK, HOLDLOCK) WHERE Loggin = 'jtorres')
    BEGIN
        UPDATE dbo.tbl_Usuario
        SET Nombre = 'JTORRES',
            rol_id = @IdRolContabilidad,
            E_Eliminado = 2
        WHERE Loggin = 'jtorres';
    END
    ELSE
    BEGIN
        INSERT INTO dbo.tbl_Usuario (Nombre, Loggin, Password, E_Eliminado, rol_id)
        VALUES ('JTORRES', 'jtorres', @PasswordReferencia, 2, @IdRolContabilidad);
    END;

    COMMIT TRANSACTION;

    SELECT usuario.Id AS IdUsuario, usuario.Nombre, usuario.Loggin,
           rol.rol_id AS IdRol, rol.nombre AS Rol, usuario.E_Eliminado
    FROM dbo.tbl_Usuario usuario
    INNER JOIN dbo.Rol rol ON rol.rol_id = usuario.rol_id
    WHERE usuario.Loggin = 'jtorres';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    DECLARE @MensajeError NVARCHAR(4000) = ERROR_MESSAGE();
    DECLARE @SeveridadError INT = ERROR_SEVERITY();
    DECLARE @EstadoError INT = ERROR_STATE();
    RAISERROR(@MensajeError, @SeveridadError, @EstadoError);
END CATCH;
GO
