USE [BDAlmacen];
GO

IF OBJECT_ID(N'dbo.tbl_UsuarioTecnico', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.tbl_UsuarioTecnico
    (
        id INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_tbl_UsuarioTecnico PRIMARY KEY,
        id_Usuario INT NULL,
        id_Vendedor INT NULL,
        e_eliminado BIT NULL,
        fecharegistro DATETIME NULL,
        id_UsuarioRegistra INT NULL
    );
END;
GO

SET XACT_ABORT ON;
GO

BEGIN TRY
    BEGIN TRANSACTION;

    DECLARE @IdUsuario INT, @IdVendedor INT, @IdRuta INT, @IdUsuarioTecnico INT;

    SELECT @IdUsuario = u.Id
    FROM dbo.tbl_Usuario AS u WITH (UPDLOCK, HOLDLOCK)
    WHERE u.Loggin = 'p_vendedor';

    IF @IdUsuario IS NULL
    BEGIN
        INSERT INTO dbo.tbl_Usuario (Nombre, Loggin, Password, E_Eliminado)
        VALUES ('P VENDEDOR', 'p_vendedor', 'ICy5YqxZB1uWSwcVLSNLcA==', 2);

        SET @IdUsuario = CONVERT(INT, SCOPE_IDENTITY());
    END
    ELSE
    BEGIN
        UPDATE dbo.tbl_Usuario
        SET Nombre = 'P VENDEDOR',
            Password = 'ICy5YqxZB1uWSwcVLSNLcA==',
            E_Eliminado = 2
        WHERE Id = @IdUsuario;
    END;

    UPDATE dbo.Rol_Usuario
    SET e_eliminado = 2
    WHERE usuario_id = @IdUsuario
      AND rol_id = 1;

    IF @@ROWCOUNT = 0
    BEGIN
        INSERT INTO dbo.Rol_Usuario (rol_id, usuario_id, e_eliminado)
        VALUES (1, @IdUsuario, 2);
    END;

    SELECT @IdVendedor = Id_Vendedor
    FROM dbo.tbl_Vendedor WITH (UPDLOCK, HOLDLOCK)
    WHERE Nombre = 'P VENDEDOR (PRUEBA)';

    IF @IdVendedor IS NULL
    BEGIN
        INSERT INTO dbo.tbl_Vendedor
            (Nombre, Direccion, Observacion, E_Eliminado, E_EsPDA, CI, Telefono)
        VALUES
            ('P VENDEDOR (PRUEBA)', 'SIN DIRECCION', 'Cuenta de prueba del portal', 2, 2, 'P-VENDEDOR', '000000000');
        SET @IdVendedor = CONVERT(INT, SCOPE_IDENTITY());
    END;

    SELECT @IdRuta = Id_Ruta
    FROM dbo.tbl_Ruta WITH (UPDLOCK, HOLDLOCK)
    WHERE Nombre = 'RUTA PRUEBA P_VENDEDOR'
      AND Id_Vendedor = @IdVendedor;

    IF @IdRuta IS NULL
    BEGIN
        INSERT INTO dbo.tbl_Ruta (Nombre, Id_Vendedor, E_Eliminado, E_EsPDA, Sucursal)
        VALUES ('RUTA PRUEBA P_VENDEDOR', @IdVendedor, 2, 0, 'SANTA CRUZ');
        SET @IdRuta = CONVERT(INT, SCOPE_IDENTITY());
    END;

    SELECT @IdUsuarioTecnico = id
    FROM dbo.tbl_UsuarioTecnico WITH (UPDLOCK, HOLDLOCK)
    WHERE id_Usuario = @IdUsuario;

    IF @IdUsuarioTecnico IS NULL
    BEGIN
        INSERT INTO dbo.tbl_UsuarioTecnico
            (id_Usuario, id_Vendedor, e_eliminado, fecharegistro, id_UsuarioRegistra)
        VALUES (@IdUsuario, @IdVendedor, 0, GETDATE(), @IdUsuario);
    END
    ELSE
    BEGIN
        UPDATE dbo.tbl_UsuarioTecnico
        SET id_Vendedor = @IdVendedor,
            e_eliminado = 0,
            fecharegistro = ISNULL(fecharegistro, GETDATE())
        WHERE id = @IdUsuarioTecnico;
    END;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    DECLARE @ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
    RAISERROR(@ErrorMessage, 16, 1);
END CATCH;
GO

IF OBJECT_ID(N'dbo.spj_LoginGeneral_ValidarUsuario', N'P') IS NOT NULL
    DROP PROCEDURE dbo.spj_LoginGeneral_ValidarUsuario;
GO

CREATE PROCEDURE dbo.spj_LoginGeneral_ValidarUsuario
    @Login VARCHAR(50),
    @PasswordHash VARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT TOP (1)
        u.Id,
        u.Nombre,
        u.Loggin,
        ru.rol_id AS IdRol,
        r.nombre AS Rol
    FROM dbo.tbl_Usuario AS u
    INNER JOIN dbo.Rol_Usuario AS ru
        ON ru.usuario_id = u.Id
       AND ru.e_eliminado = 2
    INNER JOIN dbo.Rol AS r
        ON r.rol_id = ru.rol_id
       AND r.e_eliminado = 2
    WHERE u.E_Eliminado = 2
      AND u.Loggin = @Login
      AND u.Password = @PasswordHash
    ORDER BY ru.rol_id;
END;
GO

IF OBJECT_ID(N'dbo.spj_LoginGeneral_ObtenerTecnicoPorUsuario', N'P') IS NOT NULL
    DROP PROCEDURE dbo.spj_LoginGeneral_ObtenerTecnicoPorUsuario;
GO

CREATE PROCEDURE dbo.spj_LoginGeneral_ObtenerTecnicoPorUsuario
    @IdUsuario INT
AS
BEGIN
    SET NOCOUNT ON;

    IF OBJECT_ID(N'dbo.tbl_UsuarioTecnico', N'U') IS NULL
    BEGIN
        SELECT CAST(0 AS BIT) AS EsTecnico,
               CAST(NULL AS INT) AS IdUsuarioTecnico,
               CAST(NULL AS INT) AS IdVendedor,
               CAST(NULL AS INT) AS IdRuta,
               CAST(NULL AS NVARCHAR(150)) AS NombreRuta,
               CAST(NULL AS VARCHAR(150)) AS NombreTecnico,
               CAST(NULL AS VARCHAR(15)) AS CI,
               CAST(NULL AS VARCHAR(25)) AS Telefono,
               CAST(NULL AS VARCHAR(100)) AS Direccion,
               CAST(NULL AS VARCHAR(100)) AS Observacion;
        RETURN;
    END;

    DECLARE @SQL NVARCHAR(MAX) = N'
        IF EXISTS (
            SELECT 1
            FROM dbo.tbl_UsuarioTecnico
            WHERE id_Usuario = @IdUsuario
              AND ISNULL(e_eliminado, 0) = 0
        )
        BEGIN
            SELECT TOP (1)
                   CAST(1 AS BIT) AS EsTecnico,
                   ut.id AS IdUsuarioTecnico,
                   ut.id_Vendedor AS IdVendedor,
                   ruta.Id_Ruta AS IdRuta,
                   ruta.Nombre AS NombreRuta,
                   v.Nombre AS NombreTecnico,
                   v.CI,
                   v.Telefono,
                   v.Direccion,
                   v.Observacion
            FROM dbo.tbl_UsuarioTecnico AS ut
            LEFT JOIN dbo.tbl_Vendedor AS v ON v.Id_Vendedor = ut.id_Vendedor
            OUTER APPLY (
                SELECT TOP (1) r.Id_Ruta, r.Nombre
                FROM dbo.tbl_Ruta AS r
                WHERE r.Id_Vendedor = ut.id_Vendedor
                  AND r.E_Eliminado = 2
                ORDER BY r.Id_Ruta DESC
            ) AS ruta
            WHERE ut.id_Usuario = @IdUsuario
              AND ISNULL(ut.e_eliminado, 0) = 0
            ORDER BY ut.id DESC;
        END
        ELSE
        BEGIN
            SELECT CAST(0 AS BIT) AS EsTecnico,
                   CAST(NULL AS INT) AS IdUsuarioTecnico,
                   CAST(NULL AS INT) AS IdVendedor,
                   CAST(NULL AS INT) AS IdRuta,
                   CAST(NULL AS NVARCHAR(150)) AS NombreRuta,
                   CAST(NULL AS VARCHAR(150)) AS NombreTecnico,
                   CAST(NULL AS VARCHAR(15)) AS CI,
                   CAST(NULL AS VARCHAR(25)) AS Telefono,
                   CAST(NULL AS VARCHAR(100)) AS Direccion,
                   CAST(NULL AS VARCHAR(100)) AS Observacion;
        END;';

    EXEC sys.sp_executesql @SQL, N'@IdUsuario INT', @IdUsuario = @IdUsuario;
END;
GO

IF OBJECT_ID(N'dbo.spj_LoginGeneral_ObtenerSaldoRuta', N'P') IS NOT NULL
    DROP PROCEDURE dbo.spj_LoginGeneral_ObtenerSaldoRuta;
GO

CREATE PROCEDURE dbo.spj_LoginGeneral_ObtenerSaldoRuta
    @IdRuta INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        p.Id_Producto,
        p.Nombre AS Producto,
        s.Cantidad,
        tp.Nombre AS TipoProducto,
        p.PrecioVenta
    FROM dbo.tbl_SaldoTarjetas AS s
    INNER JOIN dbo.tbl_Producto AS p ON p.Id_Producto = s.Id_Producto
    LEFT JOIN dbo.tbl_TipoProducto AS tp ON tp.Id_TipoProducto = p.Id_TipoProducto
    WHERE s.Id_Ruta = @IdRuta
      AND s.Cantidad > 0
      AND ISNULL(s.E_Eliminado, 2) = 2
      AND ISNULL(p.E_Eliminado, 0) = 0
    ORDER BY s.Id_Producto;
END;
GO
