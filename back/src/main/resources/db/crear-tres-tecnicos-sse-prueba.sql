SET NOCOUNT ON;
SET XACT_ABORT ON;

BEGIN TRY
    BEGIN TRANSACTION;

    DECLARE @PasswordTecnico159 VARCHAR(50);
    DECLARE @RolTecnico INT;

    SELECT TOP (1) @PasswordTecnico159 = u.Password
    FROM dbo.tbl_Usuario u
    INNER JOIN dbo.tbl_UsuarioTecnico ut
        ON ut.id_Usuario = u.Id
       AND ISNULL(ut.e_eliminado, 0) = 0
    WHERE ut.id_Vendedor = 159
      AND u.E_Eliminado = 2
    ORDER BY ut.id DESC;

    SELECT @RolTecnico = rol_id
    FROM dbo.Rol
    WHERE nombre = 'Tecnico';

    IF @PasswordTecnico159 IS NULL
        RAISERROR('No se encontro la clave del tecnico 159.', 16, 1);

    IF @RolTecnico IS NULL
        RAISERROR('No se encontro el rol Tecnico.', 16, 1);

    DECLARE @Tecnicos TABLE
    (
        IdVendedor INT NOT NULL,
        Login VARCHAR(50) NOT NULL
    );

    INSERT INTO @Tecnicos (IdVendedor, Login)
    VALUES
        (170, 't170_avila'),
        (131, 't131_mendez'),
        (167, 't167_rodriguez');

    DECLARE @IdVendedor INT;
    DECLARE @Login VARCHAR(50);
    DECLARE @IdUsuario INT;
    DECLARE @Nombre VARCHAR(150);

    DECLARE tecnico_cursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT IdVendedor, Login FROM @Tecnicos;

    OPEN tecnico_cursor;
    FETCH NEXT FROM tecnico_cursor INTO @IdVendedor, @Login;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        SELECT @Nombre = Nombre
        FROM dbo.tbl_Vendedor
        WHERE Id_Vendedor = @IdVendedor
          AND E_Eliminado = 2;

        IF @Nombre IS NULL
            RAISERROR('Uno de los vendedores no existe o esta eliminado.', 16, 1);

        SELECT @IdUsuario = Id
        FROM dbo.tbl_Usuario
        WHERE Loggin = @Login;

        IF @IdUsuario IS NULL
        BEGIN
            INSERT INTO dbo.tbl_Usuario
                (Nombre, Loggin, Password, E_Eliminado, rol_id)
            VALUES
                (@Nombre, @Login, @PasswordTecnico159, 2, @RolTecnico);

            SET @IdUsuario = CONVERT(INT, SCOPE_IDENTITY());
        END
        ELSE
        BEGIN
            UPDATE dbo.tbl_Usuario
            SET Nombre = @Nombre,
                Password = @PasswordTecnico159,
                E_Eliminado = 2,
                rol_id = @RolTecnico
            WHERE Id = @IdUsuario;
        END;

        IF NOT EXISTS
        (
            SELECT 1
            FROM dbo.tbl_UsuarioTecnico
            WHERE id_Usuario = @IdUsuario
              AND id_Vendedor = @IdVendedor
              AND ISNULL(e_eliminado, 0) = 0
        )
        BEGIN
            INSERT INTO dbo.tbl_UsuarioTecnico
                (id_Usuario, id_Vendedor, e_eliminado, fecharegistro, id_UsuarioRegistra)
            VALUES
                (@IdUsuario, @IdVendedor, 0, GETDATE(), 1);
        END;

        SET @IdUsuario = NULL;
        SET @Nombre = NULL;
        FETCH NEXT FROM tecnico_cursor INTO @IdVendedor, @Login;
    END;

    CLOSE tecnico_cursor;
    DEALLOCATE tecnico_cursor;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    DECLARE @ErrorMessage NVARCHAR(4000);
    DECLARE @ErrorSeverity INT;
    DECLARE @ErrorState INT;
    SELECT
        @ErrorMessage = ERROR_MESSAGE(),
        @ErrorSeverity = ERROR_SEVERITY(),
        @ErrorState = ERROR_STATE();
    IF CURSOR_STATUS('local', 'tecnico_cursor') >= 0
        CLOSE tecnico_cursor;
    IF CURSOR_STATUS('local', 'tecnico_cursor') > -3
        DEALLOCATE tecnico_cursor;
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;
    RAISERROR(@ErrorMessage, @ErrorSeverity, @ErrorState);
END CATCH;

SELECT
    u.Id AS IdUsuario,
    u.Loggin,
    u.Nombre,
    ut.id_Vendedor AS IdVendedor,
    r.Id_Ruta AS IdRuta,
    r.Nombre AS Ruta,
    rol.nombre AS Rol,
    CASE WHEN u.Password = origen.Password THEN 1 ELSE 0 END AS MismaClaveTecnico159
FROM dbo.tbl_Usuario u
INNER JOIN dbo.tbl_UsuarioTecnico ut
    ON ut.id_Usuario = u.Id
   AND ISNULL(ut.e_eliminado, 0) = 0
INNER JOIN dbo.tbl_Ruta r
    ON r.Id_Vendedor = ut.id_Vendedor
   AND r.E_Eliminado = 2
INNER JOIN dbo.Rol rol
    ON rol.rol_id = u.rol_id
CROSS APPLY
(
    SELECT TOP (1) u159.Password
    FROM dbo.tbl_Usuario u159
    INNER JOIN dbo.tbl_UsuarioTecnico ut159
        ON ut159.id_Usuario = u159.Id
       AND ISNULL(ut159.e_eliminado, 0) = 0
    WHERE ut159.id_Vendedor = 159
      AND u159.E_Eliminado = 2
    ORDER BY ut159.id DESC
) origen
WHERE u.Loggin IN ('t170_avila', 't131_mendez', 't167_rodriguez')
ORDER BY r.Id_Ruta;
