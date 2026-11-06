USE BDAlmacenTarija_Prueba;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID(N'dbo.tbl_PedidoVendedor_EnRuta', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.tbl_PedidoVendedor_EnRuta
    (
        Id_PedidoVendedor_EnRuta INT IDENTITY(1,1) NOT NULL,
        Id_Ruta                  INT NOT NULL,
        Id_Vendedor              INT NOT NULL,
        Id_Usuario               INT NOT NULL,
        Fecha                    DATETIME NOT NULL,
        Fecha_Registro           DATETIME NOT NULL,
        Observacion              VARCHAR(50) NOT NULL,
        ModificadoPorAlmacen     INT NOT NULL
            CONSTRAINT DF_PedidoVendedor_EnRuta_ModificadoPorAlmacen DEFAULT (2),
        ComentarioAlmacen        VARCHAR(250) NOT NULL
            CONSTRAINT DF_PedidoVendedor_EnRuta_ComentarioAlmacen DEFAULT (''),
        FechaModificacionAlmacen DATETIME NULL,
        Total                    DECIMAL(18,2) NOT NULL,
        Id_PedidoVendedorNormal  INT NOT NULL
            CONSTRAINT DF_PedidoVendedor_EnRuta_IdPedidoNormal DEFAULT (0),
        E_Aprobado               INT NOT NULL,
        E_Eliminado              INT NOT NULL,

        CONSTRAINT PK_PedidoVendedor_EnRuta
            PRIMARY KEY CLUSTERED (Id_PedidoVendedor_EnRuta),
        CONSTRAINT FK_PedidoVendedor_EnRuta_Ruta
            FOREIGN KEY (Id_Ruta) REFERENCES dbo.tbl_Ruta (Id_Ruta),
        CONSTRAINT FK_PedidoVendedor_EnRuta_Vendedor
            FOREIGN KEY (Id_Vendedor) REFERENCES dbo.tbl_Vendedor (Id_Vendedor),
        CONSTRAINT FK_PedidoVendedor_EnRuta_Usuario
            FOREIGN KEY (Id_Usuario) REFERENCES dbo.tbl_Usuario (Id)
    );
END;
GO

IF COL_LENGTH(N'dbo.tbl_PedidoVendedor_EnRuta', N'Id_PedidoVendedorNormal') IS NULL
BEGIN
    ALTER TABLE dbo.tbl_PedidoVendedor_EnRuta
        ADD Id_PedidoVendedorNormal INT NOT NULL
            CONSTRAINT DF_PedidoVendedor_EnRuta_IdPedidoNormal DEFAULT (0) WITH VALUES;
END;
GO

IF OBJECT_ID(N'dbo.tbl_CodigoPedidoVendedor_EnRuta', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.tbl_CodigoPedidoVendedor_EnRuta
    (
        Id_CodigoPedidoVendedor_EnRuta INT IDENTITY(1,1) NOT NULL,
        Id_Producto                    INT NOT NULL,
        Id_PedidoVendedor_EnRuta       INT NOT NULL,
        NvoPedido                      INT NOT NULL,
        Precio                         DECIMAL(18,2) NULL,
        TotalParcial                   FLOAT NOT NULL,
        E_Eliminado                    INT NOT NULL,

        CONSTRAINT PK_CodigoPedidoVendedor_EnRuta
            PRIMARY KEY CLUSTERED (Id_CodigoPedidoVendedor_EnRuta),
        CONSTRAINT FK_CodigoPedidoVendedor_EnRuta_Producto
            FOREIGN KEY (Id_Producto) REFERENCES dbo.tbl_Producto (Id_Producto),
        CONSTRAINT FK_CodigoPedidoVendedor_EnRuta_Pedido
            FOREIGN KEY (Id_PedidoVendedor_EnRuta)
                REFERENCES dbo.tbl_PedidoVendedor_EnRuta (Id_PedidoVendedor_EnRuta)
    );
END;
GO
