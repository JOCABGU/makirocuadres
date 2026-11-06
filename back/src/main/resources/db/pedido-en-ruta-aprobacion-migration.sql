USE BDAlmacenTarija_Prueba;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF COL_LENGTH(N'dbo.tbl_PedidoVendedor_EnRuta', N'AprobadoPor') IS NULL
BEGIN
    ALTER TABLE dbo.tbl_PedidoVendedor_EnRuta
        ADD AprobadoPor VARCHAR(150) NULL;
END;
GO
