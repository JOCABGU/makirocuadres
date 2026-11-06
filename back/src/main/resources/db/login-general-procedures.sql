USE BDFacturasPreV;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID(N'dbo.spj_LoginGeneral_ListarSucursales', N'P') IS NULL
BEGIN
    EXEC(N'CREATE PROCEDURE dbo.spj_LoginGeneral_ListarSucursales AS BEGIN SET NOCOUNT ON; END');
END;
GO

ALTER PROCEDURE dbo.spj_LoginGeneral_ListarSucursales
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        Id_Sucursal,
        LTRIM(RTRIM(Sucursal)) AS Sucursal
    FROM dbo.tbl_Sucursal
    WHERE e_eliminado = 2
    ORDER BY Sucursal;
END;
GO

IF OBJECT_ID(N'dbo.spj_LoginGeneral_ObtenerConexionSucursal', N'P') IS NULL
BEGIN
    EXEC(N'CREATE PROCEDURE dbo.spj_LoginGeneral_ObtenerConexionSucursal AS BEGIN SET NOCOUNT ON; END');
END;
GO

ALTER PROCEDURE dbo.spj_LoginGeneral_ObtenerConexionSucursal
    @Id_Sucursal INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        s.Id_Sucursal,
        LTRIM(RTRIM(s.Sucursal)) AS Sucursal,
        LTRIM(RTRIM(s.Agente)) AS Agente,
        LTRIM(RTRIM(s.IP)) AS IP,
        LTRIM(RTRIM(s.BD)) AS BD,
        ISNULL(s.Puerto, 1433) AS Puerto
    FROM dbo.tbl_Sucursal s
    WHERE s.Id_Sucursal = @Id_Sucursal
      AND s.e_eliminado = 2
      AND NULLIF(LTRIM(RTRIM(s.IP)), '') IS NOT NULL
      AND NULLIF(LTRIM(RTRIM(s.BD)), '') IS NOT NULL;
END;
GO
