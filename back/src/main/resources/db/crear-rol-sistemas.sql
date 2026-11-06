SET XACT_ABORT ON;
GO

BEGIN TRY
    BEGIN TRANSACTION;

    DECLARE @IdRolSistemas INT;
    SELECT @IdRolSistemas = rol_id
    FROM dbo.Rol WITH (UPDLOCK, HOLDLOCK)
    WHERE LOWER(LTRIM(RTRIM(nombre))) = 'sistemas';

    IF @IdRolSistemas IS NULL
    BEGIN
        INSERT INTO dbo.Rol (nombre, e_eliminado)
        VALUES ('Sistemas', 2);
        SET @IdRolSistemas = SCOPE_IDENTITY();
    END
    ELSE
        UPDATE dbo.Rol SET nombre = 'Sistemas', e_eliminado = 2
        WHERE rol_id = @IdRolSistemas;

    DECLARE @PasswordReferencia VARCHAR(50);
    SELECT @PasswordReferencia = Password
    FROM dbo.tbl_Usuario
    WHERE Loggin = 'p_almacenero' AND E_Eliminado = 2;

    IF @PasswordReferencia IS NULL
        RAISERROR('No se encontró la contraseña de referencia de p_almacenero.', 16, 1);

    IF EXISTS (SELECT 1 FROM dbo.tbl_Usuario WITH (UPDLOCK, HOLDLOCK) WHERE Loggin = 'sistemas')
    BEGIN
        UPDATE dbo.tbl_Usuario
        SET Nombre = 'SISTEMAS',
            rol_id = @IdRolSistemas,
            E_Eliminado = 2
        WHERE Loggin = 'sistemas';
    END
    ELSE
    BEGIN
        INSERT INTO dbo.tbl_Usuario (Nombre, Loggin, Password, E_Eliminado, rol_id)
        VALUES ('SISTEMAS', 'sistemas', @PasswordReferencia, 2, @IdRolSistemas);
    END;

    COMMIT TRANSACTION;

    SELECT usuario.Id AS IdUsuario, usuario.Nombre, usuario.Loggin,
           rol.rol_id AS IdRol, rol.nombre AS Rol, usuario.E_Eliminado
    FROM dbo.tbl_Usuario usuario
    INNER JOIN dbo.Rol rol ON rol.rol_id = usuario.rol_id
    WHERE usuario.Loggin = 'sistemas';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    DECLARE @MensajeError NVARCHAR(4000) = ERROR_MESSAGE();
    DECLARE @SeveridadError INT = ERROR_SEVERITY();
    DECLARE @EstadoError INT = ERROR_STATE();
    RAISERROR(@MensajeError, @SeveridadError, @EstadoError);
END CATCH;
GO
