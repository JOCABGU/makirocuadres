SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF NOT EXISTS
(
    SELECT 1
    FROM sys.indexes
    WHERE object_id = OBJECT_ID(N'dbo.tbl_Productos')
      AND name = N'IX_tbl_Productos_Imei_Disponibilidad'
)
BEGIN
    CREATE NONCLUSTERED INDEX IX_tbl_Productos_Imei_Disponibilidad
        ON dbo.tbl_Productos (Imei)
        INCLUDE (Id_Ruta, Vendido);
END;
GO

IF OBJECT_ID(N'dbo.spj_LoginGeneral_Scanner_ValidarImeis', N'P') IS NULL
BEGIN
    EXEC(N'CREATE PROCEDURE dbo.spj_LoginGeneral_Scanner_ValidarImeis AS BEGIN SET NOCOUNT ON; END');
END;
GO

ALTER PROCEDURE dbo.spj_LoginGeneral_Scanner_ValidarImeis
    @ImeisXml XML
AS
BEGIN
    SET NOCOUNT ON;
    SET ARITHABORT ON;

    DECLARE @Solicitados TABLE
    (
        Orden INT IDENTITY(1,1) NOT NULL,
        Imei BIGINT NOT NULL PRIMARY KEY
    );

    INSERT INTO @Solicitados (Imei)
    SELECT nodo.valor.value('@v', 'BIGINT')
    FROM @ImeisXml.nodes('/imeis/i') nodo(valor);

    SELECT
        CONVERT(VARCHAR(30), solicitado.Imei) AS Imei,
        CASE WHEN producto.Imei IS NULL THEN 0 ELSE 1 END AS Existe,
        producto.Id_Ruta AS IdRuta,
        producto.Vendido,
        CASE
            WHEN producto.Imei IS NOT NULL
             AND producto.Id_Ruta = 0
             AND producto.Vendido = 0 THEN 1
            ELSE 0
        END AS Valido,
        CASE
            WHEN producto.Imei IS NULL THEN 'El IMEI no existe en tbl_Productos.'
            WHEN producto.Id_Ruta IS NULL OR producto.Id_Ruta <> 0 THEN 'El producto no tiene Id_Ruta = 0.'
            WHEN producto.Vendido IS NULL OR producto.Vendido <> 0 THEN 'El producto no tiene Vendido = 0.'
            ELSE NULL
        END AS Motivo
    FROM @Solicitados solicitado
    OUTER APPLY
    (
        SELECT TOP (1)
            p.Imei,
            p.Id_Ruta,
            p.Vendido
        FROM dbo.tbl_Productos p WITH (INDEX(IX_tbl_Productos_Imei_Disponibilidad))
        WHERE p.Imei = solicitado.Imei
        ORDER BY
            CASE WHEN p.Id_Ruta = 0 AND p.Vendido = 0 THEN 0 ELSE 1 END
    ) producto
    ORDER BY solicitado.Orden;
END;
GO
