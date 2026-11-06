USE BDAlmacenTarija_Prueba;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

BEGIN TRY
    BEGIN TRANSACTION;

    DECLARE @IdVendedor INT = 169;
    DECLARE @Login VARCHAR(50) = 'jrodriguez';
    DECLARE @IdUsuario INT;
    DECLARE @PasswordTecnico159 VARCHAR(50);
    DECLARE @IdRolTecnico INT;

    SELECT @PasswordTecnico159 = u.Password
    FROM dbo.tbl_Usuario u
    INNER JOIN dbo.tbl_UsuarioTecnico ut ON ut.id_Usuario = u.Id
    WHERE ut.id_Vendedor = 159
      AND u.E_Eliminado = 2;

    SELECT @IdRolTecnico = rol_id
    FROM dbo.Rol
    WHERE nombre = 'Tecnico'
      AND e_eliminado = 2;

    IF @PasswordTecnico159 IS NULL
        RAISERROR('No se encontró la contraseña del técnico 159.', 16, 1);

    IF @IdRolTecnico IS NULL
        RAISERROR('No se encontró el rol Técnico.', 16, 1);

    SELECT @IdUsuario = Id
    FROM dbo.tbl_Usuario
    WHERE Loggin = @Login;

    IF @IdUsuario IS NULL
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
            v.Nombre,
            @Login,
            @PasswordTecnico159,
            2,
            @IdRolTecnico
        FROM dbo.tbl_Vendedor v
        WHERE v.Id_Vendedor = @IdVendedor
          AND v.E_Eliminado = 2;

        SET @IdUsuario = CONVERT(INT, SCOPE_IDENTITY());
    END
    ELSE
    BEGIN
        UPDATE dbo.tbl_Usuario
        SET Password = @PasswordTecnico159,
            E_Eliminado = 2,
            rol_id = @IdRolTecnico
        WHERE Id = @IdUsuario;
    END;

    IF @IdUsuario IS NULL
        RAISERROR('No se encontró el vendedor 169 activo.', 16, 1);

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.tbl_UsuarioTecnico
        WHERE id_Usuario = @IdUsuario
          AND id_Vendedor = @IdVendedor
    )
    BEGIN
        INSERT INTO dbo.tbl_UsuarioTecnico
        (
            id_Usuario,
            id_Vendedor,
            e_eliminado,
            fecharegistro,
            id_UsuarioRegistra
        )
        VALUES
        (
            @IdUsuario,
            @IdVendedor,
            0,
            GETDATE(),
            24
        );
    END
    ELSE
    BEGIN
        UPDATE dbo.tbl_UsuarioTecnico
        SET e_eliminado = 0
        WHERE id_Usuario = @IdUsuario
          AND id_Vendedor = @IdVendedor;
    END;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;
    DECLARE @ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
    RAISERROR(@ErrorMessage, 16, 1);
END CATCH;
GO
