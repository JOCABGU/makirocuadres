SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID(N'dbo.spj_LoginGeneral_Almacen_Cuadre_ListarRutas', N'P') IS NULL
    EXEC(N'CREATE PROCEDURE dbo.spj_LoginGeneral_Almacen_Cuadre_ListarRutas AS BEGIN SET NOCOUNT ON; END');
GO

ALTER PROCEDURE dbo.spj_LoginGeneral_Almacen_Cuadre_ListarRutas
    @Fecha DATE
AS
BEGIN
    SET NOCOUNT ON;
    SET ARITHABORT ON;

    SELECT
        ruta.Id_Ruta AS IdRuta,
        ruta.Nombre AS Ruta,
        ruta.Id_Vendedor AS IdVendedor,
        ISNULL(vendedor.Nombre, 'Sin tecnico asignado') AS Tecnico,
        CONVERT(BIT, CASE WHEN cuadre.Id_Cuadre IS NULL THEN 0 ELSE 1 END) AS RealizoCuadre,
        cuadre.Id_Cuadre AS IdCuadre,
        cuadre.Fecha AS FechaCuadre,
        CONVERT(DECIMAL(18,2), ISNULL(cuadre.Total, 0)) AS Total
    FROM dbo.tbl_Ruta ruta
    LEFT JOIN dbo.tbl_Vendedor vendedor ON vendedor.Id_Vendedor = ruta.Id_Vendedor
    OUTER APPLY
    (
        SELECT TOP (1) c.Id_Cuadre, c.Fecha, c.Total
        FROM dbo.tbl_Cuadre c
        WHERE c.Id_Ruta = ruta.Id_Ruta
          AND c.E_Eliminado = 2
          AND c.Fecha >= @Fecha
          AND c.Fecha < DATEADD(DAY, 1, @Fecha)
        ORDER BY c.Fecha DESC, c.Id_Cuadre DESC
    ) cuadre
    WHERE ruta.E_Eliminado = 2
    ORDER BY CASE WHEN cuadre.Id_Cuadre IS NULL THEN 1 ELSE 0 END,
             ruta.Id_Ruta;
END;
GO

IF OBJECT_ID(N'dbo.spj_LoginGeneral_Almacen_Cuadre_ObtenerDetalle', N'P') IS NULL
    EXEC(N'CREATE PROCEDURE dbo.spj_LoginGeneral_Almacen_Cuadre_ObtenerDetalle AS BEGIN SET NOCOUNT ON; END');
GO

ALTER PROCEDURE dbo.spj_LoginGeneral_Almacen_Cuadre_ObtenerDetalle
    @IdCuadre INT
AS
BEGIN
    SET NOCOUNT ON;
    SET ARITHABORT ON;

    SELECT
        cuadre.Id_Cuadre AS IdCuadre,
        cuadre.Id_Ruta AS IdRuta,
        ruta.Nombre AS Ruta,
        cuadre.Id_Vendedor AS IdVendedor,
        ISNULL(vendedor.Nombre, 'Sin tecnico asignado') AS Tecnico,
        cuadre.Fecha,
        cuadre.Observacion,
        CONVERT(DECIMAL(18,2), ISNULL(cuadre.Total, 0)) AS Total,
        codigo.Id_Producto AS IdProducto,
        producto.Nombre AS Producto,
        tipo.Nombre AS TipoProducto,
        ISNULL(codigo.ItemsSobrantes, 0) + ISNULL(codigo.ItemsVendidos, 0) AS SaldoAnterior,
        ISNULL(codigo.ItemsSobrantes, 0) AS SobranteIngresado,
        ISNULL(codigo.ItemsVendidos, 0) AS Vendido,
        ISNULL(saldoActual.Cantidad, 0) AS SaldoActual,
        CONVERT(DECIMAL(18,2), ISNULL(codigo.Precio, 0)) AS Precio,
        CONVERT(DECIMAL(18,2), ISNULL(codigo.TotalVendidos, 0)) AS TotalVendido,
        tira.Id_SaldoCuadre AS IdSaldoCuadre,
        tira.Cantidad AS CantidadTira,
        tira.Cod_Inicio AS CodigoInicio,
        tira.Cod_Final AS CodigoFinal
    FROM dbo.tbl_Cuadre cuadre
    INNER JOIN dbo.tbl_Ruta ruta ON ruta.Id_Ruta = cuadre.Id_Ruta
    LEFT JOIN dbo.tbl_Vendedor vendedor ON vendedor.Id_Vendedor = cuadre.Id_Vendedor
    INNER JOIN dbo.tbl_CodigoCuadre codigo
        ON codigo.Id_Cuadre = cuadre.Id_Cuadre
       AND codigo.E_Eliminado = 2
    INNER JOIN dbo.tbl_Producto producto ON producto.Id_Producto = codigo.Id_Producto
    LEFT JOIN dbo.tbl_TipoProducto tipo ON tipo.Id_TipoProducto = producto.Id_TipoProducto
    LEFT JOIN dbo.tbl_SaldoCuadre tira
        ON tira.Id_Cuadre = codigo.Id_Cuadre
       AND tira.Id_Producto = codigo.Id_Producto
       AND tira.E_Eliminado = 0
    OUTER APPLY
    (
        SELECT SUM(ISNULL(saldo.Cantidad, 0)) AS Cantidad
        FROM dbo.tbl_SaldoTarjetas saldo
        WHERE saldo.Id_Ruta = cuadre.Id_Ruta
          AND saldo.Id_Producto = codigo.Id_Producto
          AND saldo.E_Eliminado = 2
    ) saldoActual
    WHERE cuadre.Id_Cuadre = @IdCuadre
      AND cuadre.E_Eliminado = 2
    ORDER BY producto.Observacion, producto.Nombre, tira.Id_SaldoCuadre;
END;
GO
