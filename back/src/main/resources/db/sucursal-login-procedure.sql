SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID(N'dbo.tbl_PedidoVendedor_EnRuta', N'U') IS NOT NULL
   AND COL_LENGTH(N'dbo.tbl_PedidoVendedor_EnRuta', N'Id_PedidoVendedorNormal') IS NULL
BEGIN
    ALTER TABLE dbo.tbl_PedidoVendedor_EnRuta
        ADD Id_PedidoVendedorNormal INT NOT NULL
            CONSTRAINT DF_PedidoVendedor_EnRuta_IdPedidoNormal DEFAULT (0) WITH VALUES;
END;
GO

IF OBJECT_ID(N'dbo.spj_LoginGeneral_ValidarUsuario', N'P') IS NULL
BEGIN
    EXEC(N'CREATE PROCEDURE dbo.spj_LoginGeneral_ValidarUsuario AS BEGIN SET NOCOUNT ON; END');
END;
GO

IF OBJECT_ID(N'dbo.spj_LoginGeneral_ObtenerSaldoRuta', N'P') IS NULL
BEGIN
    EXEC(N'CREATE PROCEDURE dbo.spj_LoginGeneral_ObtenerSaldoRuta AS BEGIN SET NOCOUNT ON; END');
END;
GO

IF OBJECT_ID(N'dbo.spj_LoginGeneral_ListarTiposProducto', N'P') IS NULL
BEGIN
    EXEC(N'CREATE PROCEDURE dbo.spj_LoginGeneral_ListarTiposProducto AS BEGIN SET NOCOUNT ON; END');
END;
GO

ALTER PROCEDURE dbo.spj_LoginGeneral_ListarTiposProducto
AS
BEGIN
    SET NOCOUNT ON;

    SELECT DISTINCT
        tp.Id_TipoProducto,
        tp.Nombre
    FROM dbo.tbl_TipoProducto tp
    INNER JOIN dbo.tbl_Producto p
        ON p.Id_TipoProducto = tp.Id_TipoProducto
    WHERE ISNULL(p.E_ELIMINADO, 0) = 0
    ORDER BY tp.Nombre;
END;
GO

IF OBJECT_ID(N'dbo.spj_LoginGeneral_ListarProductosPorTipo', N'P') IS NULL
BEGIN
    EXEC(N'CREATE PROCEDURE dbo.spj_LoginGeneral_ListarProductosPorTipo AS BEGIN SET NOCOUNT ON; END');
END;
GO

ALTER PROCEDURE dbo.spj_LoginGeneral_ListarProductosPorTipo
    @IdTipoProducto INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        p.Id_Producto,
        p.Nombre,
        p.PrecioVenta
    FROM dbo.tbl_Producto p
    WHERE p.Id_TipoProducto = @IdTipoProducto
      AND ISNULL(p.E_ELIMINADO, 0) = 0
      AND p.Id_Producto <> 32
    ORDER BY p.Nombre;
END;
GO

ALTER PROCEDURE dbo.spj_LoginGeneral_ObtenerSaldoRuta
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
    FROM dbo.tbl_SaldoTarjetas s
    INNER JOIN dbo.tbl_Producto p
        ON p.Id_Producto = s.Id_Producto
    LEFT JOIN dbo.tbl_TipoProducto tp
        ON tp.Id_TipoProducto = p.Id_TipoProducto
    WHERE s.Id_Ruta = @IdRuta
      AND s.Cantidad > 0
    ORDER BY s.Id_Producto;
END;
GO

IF OBJECT_ID(N'dbo.spj_LoginGeneral_ObtenerTecnicoPorUsuario', N'P') IS NULL
BEGIN
    EXEC(N'CREATE PROCEDURE dbo.spj_LoginGeneral_ObtenerTecnicoPorUsuario AS BEGIN SET NOCOUNT ON; END');
END;
GO

ALTER PROCEDURE dbo.spj_LoginGeneral_ObtenerTecnicoPorUsuario
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

    DECLARE @SQL NVARCHAR(MAX);
    SET @SQL = N'
        IF EXISTS (SELECT 1 FROM dbo.tbl_UsuarioTecnico ut
                   WHERE ut.id_Usuario=@IdUsuario AND ISNULL(ut.e_eliminado,0)=0)
        BEGIN
            SELECT TOP 1 CAST(1 AS BIT) AS EsTecnico,
                   ut.id AS IdUsuarioTecnico, ut.id_Vendedor AS IdVendedor,
                   ruta.Id_Ruta AS IdRuta, ruta.Nombre AS NombreRuta,
                   v.Nombre AS NombreTecnico, v.CI, v.Telefono, v.Direccion, v.Observacion
            FROM dbo.tbl_UsuarioTecnico ut
            LEFT JOIN dbo.tbl_Vendedor v ON v.Id_Vendedor=ut.id_Vendedor
            OUTER APPLY (
                SELECT TOP 1 r.Id_Ruta, r.Nombre
                FROM dbo.tbl_Ruta r
                WHERE r.Id_Vendedor=ut.id_Vendedor
                  AND r.E_Eliminado=2
                ORDER BY r.Id_Ruta DESC
            ) ruta
            WHERE ut.id_Usuario=@IdUsuario AND ISNULL(ut.e_eliminado,0)=0
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
    EXEC sp_executesql @SQL, N'@IdUsuario INT', @IdUsuario=@IdUsuario;
END;
GO

ALTER PROCEDURE dbo.spj_LoginGeneral_ValidarUsuario
    @Login VARCHAR(50),
    @PasswordHash VARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    IF OBJECT_ID(N'dbo.Rol', N'U') IS NOT NULL
       AND COL_LENGTH(N'dbo.tbl_Usuario', N'rol_id') IS NOT NULL
    BEGIN
        DECLARE @SQL NVARCHAR(MAX);
        SET @SQL = N'
            SELECT TOP 1
                u.Id,
                u.Nombre,
                u.Loggin,
                u.rol_id AS IdRol,
                r.nombre AS Rol
            FROM dbo.tbl_Usuario u
            LEFT JOIN dbo.Rol r ON r.rol_id = u.rol_id
            WHERE u.E_Eliminado = 2
              AND u.Loggin = @Login
              AND u.Password = @PasswordHash;';
        EXEC sp_executesql
            @SQL,
            N'@Login VARCHAR(50), @PasswordHash VARCHAR(50)',
            @Login = @Login,
            @PasswordHash = @PasswordHash;
    END
    ELSE
    BEGIN
        SELECT TOP 1
            u.Id,
            u.Nombre,
            u.Loggin,
            CAST(NULL AS INT) AS IdRol,
            CAST('Tecnico' AS VARCHAR(50)) AS Rol
        FROM dbo.tbl_Usuario u
        WHERE u.E_Eliminado = 2
          AND u.Loggin = @Login
          AND u.Password = @PasswordHash;
    END;
END;
GO

IF OBJECT_ID(N'dbo.spj_LoginGeneral_CrearPedidoEnRuta', N'P') IS NULL
BEGIN
    EXEC(N'CREATE PROCEDURE dbo.spj_LoginGeneral_CrearPedidoEnRuta AS BEGIN SET NOCOUNT ON; END');
END;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

ALTER PROCEDURE dbo.spj_LoginGeneral_CrearPedidoEnRuta
    @IdRuta INT,
    @IdVendedor INT,
    @IdUsuario INT,
    @Detalle XML,
    @Observacion VARCHAR(50) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET ARITHABORT ON;

    DECLARE @Detalles TABLE
    (
        IdProducto INT NOT NULL,
        Cantidad INT NOT NULL,
        Precio DECIMAL(18,2) NULL,
        TotalParcial DECIMAL(18,2) NULL
    );

    INSERT INTO @Detalles (IdProducto, Cantidad)
    SELECT
        T.Item.value('@idProducto', 'INT'),
        T.Item.value('@cantidad', 'INT')
    FROM @Detalle.nodes('/pedido/item') AS T(Item);

    IF NOT EXISTS (SELECT 1 FROM @Detalles)
    BEGIN
        RAISERROR('El pedido debe contener al menos un producto.', 16, 1);
        RETURN;
    END;

    IF EXISTS (SELECT 1 FROM @Detalles WHERE Cantidad <= 0)
    BEGIN
        RAISERROR('Todas las cantidades deben ser mayores a cero.', 16, 1);
        RETURN;
    END;

    IF EXISTS (SELECT IdProducto FROM @Detalles GROUP BY IdProducto HAVING COUNT(*) > 1)
    BEGIN
        RAISERROR('El pedido contiene productos repetidos.', 16, 1);
        RETURN;
    END;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.tbl_Ruta
        WHERE Id_Ruta = @IdRuta
          AND Id_Vendedor = @IdVendedor
          AND E_Eliminado = 2
    )
    BEGIN
        RAISERROR('La ruta no pertenece al vendedor autenticado.', 16, 1);
        RETURN;
    END;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.tbl_Usuario
        WHERE Id = @IdUsuario
          AND E_Eliminado = 2
    )
    BEGIN
        RAISERROR('El usuario autenticado no se encuentra activo.', 16, 1);
        RETURN;
    END;

    IF EXISTS (
        SELECT 1
        FROM @Detalles d
        LEFT JOIN dbo.tbl_Producto p ON p.Id_Producto = d.IdProducto
        WHERE p.Id_Producto IS NULL OR ISNULL(p.E_ELIMINADO, 0) <> 0
    )
    BEGIN
        RAISERROR('Uno de los productos seleccionados no está activo.', 16, 1);
        RETURN;
    END;

    DECLARE @Total DECIMAL(18,2);
    DECLARE @IdPedido INT;
    DECLARE @FechaRegistro DATETIME = GETDATE();
    SET @Observacion = NULLIF(LTRIM(RTRIM(@Observacion)), '');

    UPDATE d
       SET Precio = p.PrecioVenta,
           TotalParcial = ROUND(p.PrecioVenta * d.Cantidad, 2)
    FROM @Detalles d
    INNER JOIN dbo.tbl_Producto p ON p.Id_Producto = d.IdProducto;

    IF EXISTS (SELECT 1 FROM @Detalles WHERE Precio IS NULL)
    BEGIN
        RAISERROR('Uno de los productos no tiene precio de venta.', 16, 1);
        RETURN;
    END;

    SELECT @Total = SUM(TotalParcial) FROM @Detalles;

    BEGIN TRY
        BEGIN TRANSACTION;

        INSERT INTO dbo.tbl_PedidoVendedor_EnRuta
        (
            Id_Ruta,
            Id_Vendedor,
            Id_Usuario,
            Fecha,
            Fecha_Registro,
            Observacion,
            Total,
            Id_PedidoVendedorNormal,
            E_Aprobado,
            E_Eliminado
        )
        VALUES
        (
            @IdRuta,
            @IdVendedor,
            @IdUsuario,
            @FechaRegistro,
            @FechaRegistro,
            ISNULL(@Observacion, 'Pedido desde portal técnico'),
            @Total,
            0,
            1,
            2
        );

        SET @IdPedido = CONVERT(INT, SCOPE_IDENTITY());

        INSERT INTO dbo.tbl_CodigoPedidoVendedor_EnRuta
        (
            Id_Producto,
            Id_PedidoVendedor_EnRuta,
            NvoPedido,
            Precio,
            TotalParcial,
            E_Eliminado
        )
        SELECT
            d.IdProducto,
            @IdPedido,
            d.Cantidad,
            d.Precio,
            d.TotalParcial,
            2
        FROM @Detalles d;

        COMMIT TRANSACTION;

        SELECT
            @IdPedido AS IdPedido,
            COUNT(*) AS CantidadProductos,
            SUM(d.Cantidad) AS CantidadUnidades,
            @Total AS Total,
            @FechaRegistro AS FechaRegistro,
            CAST(1 AS INT) AS EstadoAprobado
        FROM @Detalles d;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        DECLARE @ErrorMessage NVARCHAR(4000);
        SET @ErrorMessage = ERROR_MESSAGE();
        RAISERROR(@ErrorMessage, 16, 1);
    END CATCH;
END;
GO

IF OBJECT_ID(N'dbo.spj_LoginGeneral_ListarPedidosEnRuta', N'P') IS NULL
BEGIN
    EXEC(N'CREATE PROCEDURE dbo.spj_LoginGeneral_ListarPedidosEnRuta AS BEGIN SET NOCOUNT ON; END');
END;
GO

ALTER PROCEDURE dbo.spj_LoginGeneral_ListarPedidosEnRuta
    @IdUsuario INT,
    @IdRuta INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        p.Id_PedidoVendedor_EnRuta AS IdPedido,
        p.Fecha_Registro AS FechaRegistro,
        p.Observacion,
        p.ModificadoPorAlmacen,
        p.ComentarioAlmacen,
        p.Total,
        p.E_Aprobado AS EstadoAprobado,
        COUNT(d.Id_CodigoPedidoVendedor_EnRuta) AS CantidadProductos,
        ISNULL(SUM(d.NvoPedido), 0) AS CantidadUnidades
    FROM dbo.tbl_PedidoVendedor_EnRuta p
    LEFT JOIN dbo.tbl_CodigoPedidoVendedor_EnRuta d
        ON d.Id_PedidoVendedor_EnRuta = p.Id_PedidoVendedor_EnRuta
       AND d.E_Eliminado = 2
    WHERE p.Id_Usuario = @IdUsuario
      AND p.Id_Ruta = @IdRuta
      AND p.E_Eliminado = 2
    GROUP BY
        p.Id_PedidoVendedor_EnRuta,
        p.Fecha_Registro,
        p.Observacion,
        p.ModificadoPorAlmacen,
        p.ComentarioAlmacen,
        p.Total,
        p.E_Aprobado
    ORDER BY p.Id_PedidoVendedor_EnRuta DESC;
END;
GO

IF OBJECT_ID(N'dbo.spj_LoginGeneral_ObtenerDetallePedidoEnRuta', N'P') IS NULL
BEGIN
    EXEC(N'CREATE PROCEDURE dbo.spj_LoginGeneral_ObtenerDetallePedidoEnRuta AS BEGIN SET NOCOUNT ON; END');
END;
GO

ALTER PROCEDURE dbo.spj_LoginGeneral_ObtenerDetallePedidoEnRuta
    @IdPedido INT,
    @IdUsuario INT,
    @IdRuta INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        d.Id_CodigoPedidoVendedor_EnRuta AS IdDetalle,
        d.Id_Producto AS IdProducto,
        producto.Nombre AS Producto,
        tipo.Nombre AS TipoProducto,
        d.NvoPedido AS Cantidad,
        d.Precio,
        CONVERT(DECIMAL(18,2), d.TotalParcial) AS TotalParcial
    FROM dbo.tbl_CodigoPedidoVendedor_EnRuta d
    INNER JOIN dbo.tbl_PedidoVendedor_EnRuta p
        ON p.Id_PedidoVendedor_EnRuta = d.Id_PedidoVendedor_EnRuta
    INNER JOIN dbo.tbl_Producto producto
        ON producto.Id_Producto = d.Id_Producto
    LEFT JOIN dbo.tbl_TipoProducto tipo
        ON tipo.Id_TipoProducto = producto.Id_TipoProducto
    WHERE p.Id_PedidoVendedor_EnRuta = @IdPedido
      AND p.Id_Usuario = @IdUsuario
      AND p.Id_Ruta = @IdRuta
      AND p.E_Eliminado = 2
      AND d.E_Eliminado = 2
    ORDER BY d.Id_CodigoPedidoVendedor_EnRuta;
END;
GO

IF OBJECT_ID(N'dbo.spj_LoginGeneral_Almacen_ListarTecnicos', N'P') IS NULL
BEGIN
    EXEC(N'CREATE PROCEDURE dbo.spj_LoginGeneral_Almacen_ListarTecnicos AS BEGIN SET NOCOUNT ON; END');
END;
GO

ALTER PROCEDURE dbo.spj_LoginGeneral_Almacen_ListarTecnicos
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        u.Id AS IdUsuario,
        u.Nombre,
        ut.id_Vendedor AS IdVendedor,
        ruta.Id_Ruta AS IdRuta,
        ruta.Nombre AS Ruta,
        COUNT(DISTINCT p.Id_PedidoVendedor_EnRuta) AS PedidosPendientes
    FROM dbo.tbl_UsuarioTecnico ut
    INNER JOIN dbo.tbl_Usuario u
        ON u.Id = ut.id_Usuario
       AND u.E_Eliminado = 2
    LEFT JOIN dbo.tbl_Ruta ruta
        ON ruta.Id_Vendedor = ut.id_Vendedor
       AND ruta.E_Eliminado = 2
    LEFT JOIN dbo.tbl_PedidoVendedor_EnRuta p
        ON p.Id_Usuario = u.Id
       AND p.Id_Ruta = ruta.Id_Ruta
       AND p.E_Aprobado = 1
       AND p.E_Eliminado = 2
    WHERE ISNULL(ut.e_eliminado, 0) = 0
    GROUP BY
        u.Id,
        u.Nombre,
        ut.id_Vendedor,
        ruta.Id_Ruta,
        ruta.Nombre
    ORDER BY u.Nombre, ruta.Nombre;
END;
GO

IF OBJECT_ID(N'dbo.spj_LoginGeneral_Almacen_ListarPedidosTecnico', N'P') IS NULL
BEGIN
    EXEC(N'CREATE PROCEDURE dbo.spj_LoginGeneral_Almacen_ListarPedidosTecnico AS BEGIN SET NOCOUNT ON; END');
END;
GO

ALTER PROCEDURE dbo.spj_LoginGeneral_Almacen_ListarPedidosTecnico
    @IdUsuarioTecnico INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        p.Id_PedidoVendedor_EnRuta AS IdPedido,
        p.Id_Ruta AS IdRuta,
        ruta.Nombre AS Ruta,
        p.Fecha_Registro AS FechaRegistro,
        p.Observacion,
        p.ModificadoPorAlmacen,
        p.ComentarioAlmacen,
        p.Total,
        p.E_Aprobado AS EstadoAprobado,
        COUNT(d.Id_CodigoPedidoVendedor_EnRuta) AS CantidadProductos,
        ISNULL(SUM(d.NvoPedido), 0) AS CantidadUnidades
    FROM dbo.tbl_PedidoVendedor_EnRuta p
    INNER JOIN dbo.tbl_UsuarioTecnico ut
        ON ut.id_Usuario = p.Id_Usuario
       AND ISNULL(ut.e_eliminado, 0) = 0
    LEFT JOIN dbo.tbl_Ruta ruta
        ON ruta.Id_Ruta = p.Id_Ruta
    LEFT JOIN dbo.tbl_CodigoPedidoVendedor_EnRuta d
        ON d.Id_PedidoVendedor_EnRuta = p.Id_PedidoVendedor_EnRuta
       AND d.E_Eliminado = 2
    WHERE p.Id_Usuario = @IdUsuarioTecnico
      AND p.E_Eliminado = 2
    GROUP BY
        p.Id_PedidoVendedor_EnRuta,
        p.Id_Ruta,
        ruta.Nombre,
        p.Fecha_Registro,
        p.Observacion,
        p.ModificadoPorAlmacen,
        p.ComentarioAlmacen,
        p.Total,
        p.E_Aprobado
    ORDER BY p.Id_PedidoVendedor_EnRuta DESC;
END;
GO

IF OBJECT_ID(N'dbo.spj_LoginGeneral_Almacen_ObtenerDetallePedido', N'P') IS NULL
BEGIN
    EXEC(N'CREATE PROCEDURE dbo.spj_LoginGeneral_Almacen_ObtenerDetallePedido AS BEGIN SET NOCOUNT ON; END');
END;
GO

ALTER PROCEDURE dbo.spj_LoginGeneral_Almacen_ObtenerDetallePedido
    @IdPedido INT,
    @IdUsuarioTecnico INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        d.Id_CodigoPedidoVendedor_EnRuta AS IdDetalle,
        d.Id_Producto AS IdProducto,
        producto.Nombre AS Producto,
        tipo.Nombre AS TipoProducto,
        d.NvoPedido AS Cantidad,
        d.Precio,
        CONVERT(DECIMAL(18,2), d.TotalParcial) AS TotalParcial
    FROM dbo.tbl_CodigoPedidoVendedor_EnRuta d
    INNER JOIN dbo.tbl_PedidoVendedor_EnRuta p
        ON p.Id_PedidoVendedor_EnRuta = d.Id_PedidoVendedor_EnRuta
    INNER JOIN dbo.tbl_UsuarioTecnico ut
        ON ut.id_Usuario = p.Id_Usuario
       AND ISNULL(ut.e_eliminado, 0) = 0
    INNER JOIN dbo.tbl_Producto producto
        ON producto.Id_Producto = d.Id_Producto
    LEFT JOIN dbo.tbl_TipoProducto tipo
        ON tipo.Id_TipoProducto = producto.Id_TipoProducto
    WHERE p.Id_PedidoVendedor_EnRuta = @IdPedido
      AND p.Id_Usuario = @IdUsuarioTecnico
      AND p.E_Aprobado = 1
      AND p.E_Eliminado = 2
      AND d.E_Eliminado = 2
    ORDER BY d.Id_CodigoPedidoVendedor_EnRuta;
END;
GO

IF OBJECT_ID(N'dbo.spj_LoginGeneral_Almacen_ListarRutas', N'P') IS NULL
BEGIN
    EXEC(N'CREATE PROCEDURE dbo.spj_LoginGeneral_Almacen_ListarRutas AS BEGIN SET NOCOUNT ON; END');
END;
GO

ALTER PROCEDURE dbo.spj_LoginGeneral_Almacen_ListarRutas
    @FechaDesde DATE,
    @FechaHasta DATE
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        r.Id_Ruta AS IdRuta,
        r.Nombre AS Ruta,
        NULLIF(r.Id_Vendedor, 0) AS IdVendedor,
        COALESCE(v.Nombre, N'Sin t' + NCHAR(233) + N'cnico asignado') AS Tecnico,
        COUNT(DISTINCT p.Id_PedidoVendedor_EnRuta) AS PedidosPendientes
    FROM dbo.tbl_Ruta r
    LEFT JOIN dbo.tbl_Vendedor v
        ON v.Id_Vendedor = NULLIF(r.Id_Vendedor, 0)
       AND v.E_Eliminado = 2
    LEFT JOIN dbo.tbl_PedidoVendedor_EnRuta p
        ON p.Id_Ruta = r.Id_Ruta
       AND p.E_Aprobado = 1
       AND p.E_Eliminado = 2
       AND p.Fecha_Registro >= @FechaDesde
       AND p.Fecha_Registro < DATEADD(DAY, 1, @FechaHasta)
    WHERE r.E_Eliminado = 2
    GROUP BY
        r.Id_Ruta,
        r.Nombre,
        r.Id_Vendedor,
        v.Nombre
    ORDER BY
        CASE WHEN COUNT(DISTINCT p.Id_PedidoVendedor_EnRuta) > 0 THEN 0 ELSE 1 END,
        COUNT(DISTINCT p.Id_PedidoVendedor_EnRuta) DESC,
        r.Nombre;
END;
GO

IF OBJECT_ID(N'dbo.spj_LoginGeneral_Almacen_ListarPedidosPendientes', N'P') IS NULL
BEGIN
    EXEC(N'CREATE PROCEDURE dbo.spj_LoginGeneral_Almacen_ListarPedidosPendientes AS BEGIN SET NOCOUNT ON; END');
END;
GO

ALTER PROCEDURE dbo.spj_LoginGeneral_Almacen_ListarPedidosPendientes
    @FechaDesde DATE,
    @FechaHasta DATE,
    @IdRuta INT = NULL,
    @EstadoAprobado INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        p.Id_PedidoVendedor_EnRuta AS IdPedido,
        p.Id_Usuario AS IdUsuarioTecnico,
        p.Id_Vendedor AS IdVendedor,
        vendedor.Nombre AS Tecnico,
        p.Id_Ruta AS IdRuta,
        ruta.Nombre AS Ruta,
        p.Fecha_Registro AS FechaRegistro,
        p.Observacion,
        p.ModificadoPorAlmacen,
        p.ComentarioAlmacen,
        p.Total,
        p.E_Aprobado AS EstadoAprobado,
        p.AprobadoPor,
        COUNT(d.Id_CodigoPedidoVendedor_EnRuta) AS CantidadProductos,
        ISNULL(SUM(d.NvoPedido), 0) AS CantidadUnidades
    FROM dbo.tbl_PedidoVendedor_EnRuta p
    INNER JOIN dbo.tbl_Vendedor vendedor
        ON vendedor.Id_Vendedor = p.Id_Vendedor
    LEFT JOIN dbo.tbl_Ruta ruta
        ON ruta.Id_Ruta = p.Id_Ruta
    LEFT JOIN dbo.tbl_CodigoPedidoVendedor_EnRuta d
        ON d.Id_PedidoVendedor_EnRuta = p.Id_PedidoVendedor_EnRuta
       AND d.E_Eliminado = 2
    WHERE p.E_Eliminado = 2
      AND (@EstadoAprobado IS NULL OR p.E_Aprobado = @EstadoAprobado)
      AND p.Fecha_Registro >= @FechaDesde
      AND p.Fecha_Registro < DATEADD(DAY, 1, @FechaHasta)
      AND (@IdRuta IS NULL OR p.Id_Ruta = @IdRuta)
    GROUP BY
        p.Id_PedidoVendedor_EnRuta,
        p.Id_Usuario,
        p.Id_Vendedor,
        vendedor.Nombre,
        p.Id_Ruta,
        ruta.Nombre,
        p.Fecha_Registro,
        p.Observacion,
        p.ModificadoPorAlmacen,
        p.ComentarioAlmacen,
        p.Total,
        p.E_Aprobado,
        p.AprobadoPor
    ORDER BY p.Fecha_Registro DESC, p.Id_PedidoVendedor_EnRuta DESC;
END;
GO

IF OBJECT_ID(N'dbo.spj_LoginGeneral_Almacen_AprobarPedido', N'P') IS NULL
BEGIN
    EXEC(N'CREATE PROCEDURE dbo.spj_LoginGeneral_Almacen_AprobarPedido AS BEGIN SET NOCOUNT ON; END');
END;
GO

ALTER PROCEDURE dbo.spj_LoginGeneral_Almacen_AprobarPedido
    @IdPedido INT,
    @FechaEntrega DATE,
    @AprobadoPor VARCHAR(150)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @FechaEntrega IS NULL
    BEGIN
        RAISERROR('La fecha de entrega es requerida.', 16, 1);
        RETURN;
    END;

    IF @FechaEntrega < CONVERT(DATE, GETDATE())
    BEGIN
        RAISERROR('La fecha de entrega no puede ser anterior a la fecha actual.', 16, 1);
        RETURN;
    END;

    IF NULLIF(LTRIM(RTRIM(@AprobadoPor)), '') IS NULL
    BEGIN
        RAISERROR('No se identificó al almacenero que aprueba.', 16, 1);
        RETURN;
    END;

    BEGIN TRY
        BEGIN TRANSACTION;

        UPDATE dbo.tbl_PedidoVendedor_EnRuta
        SET Fecha = @FechaEntrega,
            E_Aprobado = 2,
            AprobadoPor = @AprobadoPor
        WHERE Id_PedidoVendedor_EnRuta = @IdPedido
          AND E_Aprobado = 1
          AND E_Eliminado = 2;

        IF @@ROWCOUNT = 0
        BEGIN
            RAISERROR('El pedido no existe, fue eliminado o ya está aprobado.', 16, 1);
        END;

        COMMIT TRANSACTION;

        SELECT
            Id_PedidoVendedor_EnRuta AS IdPedido,
            Fecha AS FechaEntrega,
            E_Aprobado AS EstadoAprobado,
            AprobadoPor
        FROM dbo.tbl_PedidoVendedor_EnRuta
        WHERE Id_PedidoVendedor_EnRuta = @IdPedido;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        DECLARE @ErrorMessage NVARCHAR(4000);
        SET @ErrorMessage = ERROR_MESSAGE();
        RAISERROR(@ErrorMessage, 16, 1);
    END CATCH;
END;
GO

IF OBJECT_ID(N'dbo.spj_LoginGeneral_Almacen_ObtenerDetallePendiente', N'P') IS NULL
BEGIN
    EXEC(N'CREATE PROCEDURE dbo.spj_LoginGeneral_Almacen_ObtenerDetallePendiente AS BEGIN SET NOCOUNT ON; END');
END;
GO

ALTER PROCEDURE dbo.spj_LoginGeneral_Almacen_ObtenerDetallePendiente
    @IdPedido INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        d.Id_CodigoPedidoVendedor_EnRuta AS IdDetalle,
        d.Id_Producto AS IdProducto,
        producto.Nombre AS Producto,
        tipo.Nombre AS TipoProducto,
        d.NvoPedido AS Cantidad,
        d.Precio,
        CONVERT(DECIMAL(18,2), d.TotalParcial) AS TotalParcial
    FROM dbo.tbl_CodigoPedidoVendedor_EnRuta d
    INNER JOIN dbo.tbl_PedidoVendedor_EnRuta p
        ON p.Id_PedidoVendedor_EnRuta = d.Id_PedidoVendedor_EnRuta
    INNER JOIN dbo.tbl_Producto producto
        ON producto.Id_Producto = d.Id_Producto
    LEFT JOIN dbo.tbl_TipoProducto tipo
        ON tipo.Id_TipoProducto = producto.Id_TipoProducto
    WHERE p.Id_PedidoVendedor_EnRuta = @IdPedido
      AND p.E_Eliminado = 2
      AND d.E_Eliminado = 2
    ORDER BY d.Id_CodigoPedidoVendedor_EnRuta;
END;
GO
