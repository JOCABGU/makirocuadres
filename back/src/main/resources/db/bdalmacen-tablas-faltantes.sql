USE [BDAlmacen];
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

SET XACT_ABORT ON;
GO

BEGIN TRANSACTION;

IF OBJECT_ID(N'dbo.tbl_PedidoVendedor_EnRuta', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.tbl_PedidoVendedor_EnRuta
    (
        Id_PedidoVendedor_EnRuta INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_tbl_PedidoVendedor_EnRuta PRIMARY KEY,
        Id_Ruta INT NOT NULL,
        Id_Vendedor INT NOT NULL,
        Id_Usuario INT NOT NULL,
        Fecha DATETIME NOT NULL,
        Fecha_Registro DATETIME NOT NULL,
        Observacion VARCHAR(50) NOT NULL,
        Total DECIMAL(18,2) NOT NULL,
        E_Aprobado INT NOT NULL,
        E_Eliminado INT NOT NULL,
        AprobadoPor VARCHAR(150) NULL,
        Id_PedidoVendedorNormal INT NOT NULL CONSTRAINT DF_PedidoRuta_PedidoNormal DEFAULT (0),
        ModificadoPorAlmacen INT NOT NULL CONSTRAINT DF_PedidoRuta_Modificado DEFAULT (2),
        ComentarioAlmacen VARCHAR(250) NOT NULL CONSTRAINT DF_PedidoRuta_Comentario DEFAULT (''),
        FechaModificacionAlmacen DATETIME NULL
    );
END;

IF OBJECT_ID(N'dbo.tbl_CodigoPedidoVendedor_EnRuta', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.tbl_CodigoPedidoVendedor_EnRuta
    (
        Id_CodigoPedidoVendedor_EnRuta INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_CodigoPedidoVendedor_EnRuta PRIMARY KEY,
        Id_Producto INT NOT NULL,
        Id_PedidoVendedor_EnRuta INT NOT NULL,
        NvoPedido INT NOT NULL,
        Precio DECIMAL(18,2) NULL,
        TotalParcial FLOAT NOT NULL,
        E_Eliminado INT NOT NULL
    );
END;

IF OBJECT_ID(N'dbo.PedidoVendedor_EnRuta_ProductoFisico', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.PedidoVendedor_EnRuta_ProductoFisico
    (
        Id_PedidoProductoFisico INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_PedidoVendedor_EnRuta_ProductoFisico PRIMARY KEY,
        Id_PedidoVendedor_EnRuta INT NOT NULL,
        Id_CodigoPedidoVendedor_EnRuta INT NOT NULL,
        Id_Producto INT NOT NULL,
        Imei BIGINT NOT NULL,
        Id_Ruta INT NOT NULL,
        Id_UsuarioAlmacenero INT NOT NULL,
        Fecha_Registro DATETIME NOT NULL CONSTRAINT DF_PedidoRutaFisico_Fecha DEFAULT (GETDATE()),
        E_Eliminado INT NOT NULL CONSTRAINT DF_PedidoRutaFisico_Eliminado DEFAULT (2),
        Numero_Tira INT NOT NULL CONSTRAINT DF_PedidoRutaFisico_Tira DEFAULT (1),
        Modo_Tira VARCHAR(20) NOT NULL CONSTRAINT DF_PedidoRutaFisico_Modo DEFAULT ('individual')
    );
END;

IF OBJECT_ID(N'dbo.tbl_Cuadre_EnRuta', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.tbl_Cuadre_EnRuta
    (
        Id_Cuadre_EnRuta INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_tbl_Cuadre_EnRuta PRIMARY KEY,
        Id_Ruta INT NOT NULL,
        Id_Vendedor INT NOT NULL,
        Id_Usuario INT NOT NULL,
        Fecha DATETIME NOT NULL,
        Observacion VARCHAR(100) NULL,
        Total FLOAT NOT NULL,
        E_Aprobado INT NULL,
        AprobadoPor VARCHAR(150) NULL,
        Id_Cuadre INT NOT NULL,
        E_Eliminado INT NOT NULL,
        Modificado BIT NOT NULL CONSTRAINT DF_CuadreRuta_Modificado DEFAULT (0),
        TirasXml XML NULL,
        FechaAprobacion DATETIME NULL
    );
END;

IF OBJECT_ID(N'dbo.tbl_CodigoCuadre_EnRuta', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.tbl_CodigoCuadre_EnRuta
    (
        Id_CodigoCuadre_EnRuta INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_tbl_CodigoCuadre_EnRuta PRIMARY KEY,
        Id_Cuadre_EnRuta INT NOT NULL,
        Id_Producto INT NOT NULL,
        ItemsSobrantes INT NOT NULL,
        ItemsVendidos INT NOT NULL,
        Precio DECIMAL(18,2) NOT NULL,
        TotalVendidos FLOAT NOT NULL,
        E_Eliminado INT NOT NULL
    );
END;

IF OBJECT_ID(N'dbo.tbl_Deposito_EnRuta', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.tbl_Deposito_EnRuta
    (
        Id_Deposito_EnRuta INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_tbl_Deposito_EnRuta PRIMARY KEY,
        Id_Caja INT NULL,
        Id_Entidad INT NOT NULL,
        Monto DECIMAL(18,2) NOT NULL,
        Cuenta NVARCHAR(100) NULL,
        Observacion VARCHAR(200) NOT NULL,
        E_Eliminado INT NOT NULL,
        OP VARCHAR(25) NULL,
        FechaTransaccion DATETIME NULL,
        HoraTransaccion TIME NULL,
        E_Aprobado INT NOT NULL,
        AprobadoPor VARCHAR(150) NULL,
        Id_Ruta INT NULL,
        Id_Vendedor INT NULL,
        Id_Usuario INT NULL,
        Fecha_Registro DATETIME NULL CONSTRAINT DF_DepositoRuta_Fecha DEFAULT (GETDATE()),
        Fecha_Aprobacion DATETIME NULL,
        Id_Deposito INT NULL
    );
END;

IF OBJECT_ID(N'dbo.tbl_PedidoDirectoAlmacen', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.tbl_PedidoDirectoAlmacen
    (
        Id_PedidoDirectoAlmacen INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_tbl_PedidoDirectoAlmacen PRIMARY KEY,
        Id_PedidoVendedor INT NOT NULL,
        Id_AlmacenVendedor INT NOT NULL,
        Id_Ruta INT NOT NULL,
        Id_UsuarioAlmacenero INT NOT NULL,
        CreadoPor VARCHAR(150) NOT NULL,
        Fecha_Registro DATETIME NOT NULL CONSTRAINT DF_PedidoDirecto_Fecha DEFAULT (GETDATE()),
        E_Eliminado INT NOT NULL CONSTRAINT DF_PedidoDirecto_Eliminado DEFAULT (2)
    );
END;

IF OBJECT_ID(N'dbo.tbl_PedidoDirectoAlmacen_ProductoFisico', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.tbl_PedidoDirectoAlmacen_ProductoFisico
    (
        Id_AsignacionDirecta INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_tbl_PedidoDirectoAlmacen_ProductoFisico PRIMARY KEY,
        Id_PedidoVendedor INT NOT NULL,
        Id_Producto INT NOT NULL,
        Imei BIGINT NOT NULL,
        Id_Ruta INT NOT NULL,
        Numero_Tira INT NOT NULL,
        Modo_Tira VARCHAR(20) NOT NULL,
        Fecha_Registro DATETIME NOT NULL CONSTRAINT DF_PedidoDirectoFisico_Fecha DEFAULT (GETDATE()),
        E_Eliminado INT NOT NULL CONSTRAINT DF_PedidoDirectoFisico_Eliminado DEFAULT (2)
    );
END;

IF OBJECT_ID(N'dbo.tbl_Sistemas_ReversionRuta', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.tbl_Sistemas_ReversionRuta
    (
        Id_ReversionRuta INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_tbl_Sistemas_ReversionRuta PRIMARY KEY,
        Id_Ruta INT NOT NULL,
        DesdeFecha DATETIME NOT NULL,
        Id_UsuarioSistemas INT NOT NULL,
        NombreUsuarioSistemas VARCHAR(150) NOT NULL,
        Justificacion VARCHAR(500) NOT NULL,
        CantidadMovimientos INT NOT NULL,
        DetalleJson NVARCHAR(MAX) NULL,
        Fecha_Registro DATETIME NOT NULL CONSTRAINT DF_ReversionRuta_Fecha DEFAULT (GETDATE()),
        JobId VARCHAR(100) NOT NULL
    );
END;

IF OBJECT_ID(N'dbo.ScannerImeiReserva', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.ScannerImeiReserva
    (
        Imei BIGINT NOT NULL CONSTRAINT PK_ScannerImeiReserva PRIMARY KEY,
        Token_Vinculacion VARCHAR(64) NOT NULL,
        Id_PedidoVendedor_EnRuta INT NOT NULL,
        Id_CodigoPedidoVendedor_EnRuta INT NOT NULL,
        Id_Usuario INT NOT NULL,
        Fecha_Reserva DATETIME NOT NULL CONSTRAINT DF_ScannerReserva_Fecha DEFAULT (GETDATE()),
        Fecha_Expiracion DATETIME NOT NULL
    );
END;

COMMIT TRANSACTION;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'UX_PedidoDirectoAlmacen_Pedido' AND object_id = OBJECT_ID(N'dbo.tbl_PedidoDirectoAlmacen'))
    CREATE UNIQUE INDEX UX_PedidoDirectoAlmacen_Pedido ON dbo.tbl_PedidoDirectoAlmacen (Id_PedidoVendedor);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'UX_PedidoDirectoFisico_ImeiActivo' AND object_id = OBJECT_ID(N'dbo.tbl_PedidoDirectoAlmacen_ProductoFisico'))
    CREATE UNIQUE INDEX UX_PedidoDirectoFisico_ImeiActivo ON dbo.tbl_PedidoDirectoAlmacen_ProductoFisico (Imei) WHERE E_Eliminado = 2;
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_PedidoRutaProductoFisico_Imei_Estado' AND object_id = OBJECT_ID(N'dbo.PedidoVendedor_EnRuta_ProductoFisico'))
    CREATE INDEX IX_PedidoRutaProductoFisico_Imei_Estado ON dbo.PedidoVendedor_EnRuta_ProductoFisico (Imei, E_Eliminado);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_PedidoRutaProductoFisico_PedidoDetalle' AND object_id = OBJECT_ID(N'dbo.PedidoVendedor_EnRuta_ProductoFisico'))
    CREATE INDEX IX_PedidoRutaProductoFisico_PedidoDetalle ON dbo.PedidoVendedor_EnRuta_ProductoFisico (Id_PedidoVendedor_EnRuta, Id_CodigoPedidoVendedor_EnRuta, Id_Producto, Id_Ruta, E_Eliminado);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_ScannerImeiReserva_TokenPedido' AND object_id = OBJECT_ID(N'dbo.ScannerImeiReserva'))
    CREATE INDEX IX_ScannerImeiReserva_TokenPedido ON dbo.ScannerImeiReserva (Token_Vinculacion, Id_PedidoVendedor_EnRuta, Id_CodigoPedidoVendedor_EnRuta, Id_Usuario, Fecha_Expiracion);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_ScannerImeiReserva_Expiracion' AND object_id = OBJECT_ID(N'dbo.ScannerImeiReserva'))
    CREATE INDEX IX_ScannerImeiReserva_Expiracion ON dbo.ScannerImeiReserva (Fecha_Expiracion);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'UX_Sistemas_ReversionRuta_JobId' AND object_id = OBJECT_ID(N'dbo.tbl_Sistemas_ReversionRuta'))
    CREATE UNIQUE INDEX UX_Sistemas_ReversionRuta_JobId ON dbo.tbl_Sistemas_ReversionRuta (JobId);

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_PedidoVendedor_EnRuta_Ruta')
    ALTER TABLE dbo.tbl_PedidoVendedor_EnRuta ADD CONSTRAINT FK_PedidoVendedor_EnRuta_Ruta FOREIGN KEY (Id_Ruta) REFERENCES dbo.tbl_Ruta (Id_Ruta);
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_PedidoVendedor_EnRuta_Vendedor')
    ALTER TABLE dbo.tbl_PedidoVendedor_EnRuta ADD CONSTRAINT FK_PedidoVendedor_EnRuta_Vendedor FOREIGN KEY (Id_Vendedor) REFERENCES dbo.tbl_Vendedor (Id_Vendedor);
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_PedidoVendedor_EnRuta_Usuario')
    ALTER TABLE dbo.tbl_PedidoVendedor_EnRuta ADD CONSTRAINT FK_PedidoVendedor_EnRuta_Usuario FOREIGN KEY (Id_Usuario) REFERENCES dbo.tbl_Usuario (Id);
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_CodigoPedidoVendedor_EnRuta_Producto')
    ALTER TABLE dbo.tbl_CodigoPedidoVendedor_EnRuta ADD CONSTRAINT FK_CodigoPedidoVendedor_EnRuta_Producto FOREIGN KEY (Id_Producto) REFERENCES dbo.tbl_Producto (Id_Producto);
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_CodigoPedidoVendedor_EnRuta_Pedido')
    ALTER TABLE dbo.tbl_CodigoPedidoVendedor_EnRuta ADD CONSTRAINT FK_CodigoPedidoVendedor_EnRuta_Pedido FOREIGN KEY (Id_PedidoVendedor_EnRuta) REFERENCES dbo.tbl_PedidoVendedor_EnRuta (Id_PedidoVendedor_EnRuta);
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_PedidoRutaProductoFisico_Pedido')
    ALTER TABLE dbo.PedidoVendedor_EnRuta_ProductoFisico ADD CONSTRAINT FK_PedidoRutaProductoFisico_Pedido FOREIGN KEY (Id_PedidoVendedor_EnRuta) REFERENCES dbo.tbl_PedidoVendedor_EnRuta (Id_PedidoVendedor_EnRuta);
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_PedidoRutaProductoFisico_Detalle')
    ALTER TABLE dbo.PedidoVendedor_EnRuta_ProductoFisico ADD CONSTRAINT FK_PedidoRutaProductoFisico_Detalle FOREIGN KEY (Id_CodigoPedidoVendedor_EnRuta) REFERENCES dbo.tbl_CodigoPedidoVendedor_EnRuta (Id_CodigoPedidoVendedor_EnRuta);
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_PedidoRutaProductoFisico_Producto')
    ALTER TABLE dbo.PedidoVendedor_EnRuta_ProductoFisico ADD CONSTRAINT FK_PedidoRutaProductoFisico_Producto FOREIGN KEY (Id_Producto) REFERENCES dbo.tbl_Producto (Id_Producto);
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_Codigocuadre_EnRuta_Cuadre_EnRuta')
    ALTER TABLE dbo.tbl_CodigoCuadre_EnRuta ADD CONSTRAINT FK_Codigocuadre_EnRuta_Cuadre_EnRuta FOREIGN KEY (Id_Cuadre_EnRuta) REFERENCES dbo.tbl_Cuadre_EnRuta (Id_Cuadre_EnRuta);
IF OBJECT_ID(N'dbo.tbl_Deposito', N'U') IS NOT NULL
   AND NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_DepositoEnRuta_Deposito')
    ALTER TABLE dbo.tbl_Deposito_EnRuta ADD CONSTRAINT FK_DepositoEnRuta_Deposito FOREIGN KEY (Id_Deposito) REFERENCES dbo.tbl_Deposito (Id_Deposito);
GO
