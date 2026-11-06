SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET ARITHABORT ON;
GO

IF OBJECT_ID('dbo.tbl_PedidoDirectoAlmacen', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.tbl_PedidoDirectoAlmacen
    (
        Id_PedidoDirectoAlmacen INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        Id_PedidoVendedor INT NOT NULL,
        Id_AlmacenVendedor INT NOT NULL,
        Id_Ruta INT NOT NULL,
        Id_UsuarioAlmacenero INT NOT NULL,
        CreadoPor VARCHAR(150) NOT NULL,
        Fecha_Registro DATETIME NOT NULL CONSTRAINT DF_PedidoDirectoAlmacen_Fecha DEFAULT(GETDATE()),
        E_Eliminado INT NOT NULL CONSTRAINT DF_PedidoDirectoAlmacen_Eliminado DEFAULT(2)
    );
    CREATE UNIQUE INDEX UX_PedidoDirectoAlmacen_Pedido
        ON dbo.tbl_PedidoDirectoAlmacen(Id_PedidoVendedor);
END;
GO

IF OBJECT_ID('dbo.spj_LoginGeneral_Scanner_ValidarImeisPedidoDirecto', 'P') IS NULL
    EXEC('CREATE PROCEDURE dbo.spj_LoginGeneral_Scanner_ValidarImeisPedidoDirecto AS BEGIN SET NOCOUNT ON; END');
GO
ALTER PROCEDURE dbo.spj_LoginGeneral_Scanner_ValidarImeisPedidoDirecto
    @IdProducto INT,
    @CantidadSolicitada INT,
    @ImeisXml XML
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Imeis TABLE(Imei BIGINT NOT NULL PRIMARY KEY);
    INSERT @Imeis SELECT n.v.value('@v','BIGINT') FROM @ImeisXml.nodes('/imeis/i') n(v);
    SELECT CONVERT(VARCHAR(25),i.Imei) Imei,
           CONVERT(BIT,CASE WHEN p.Imei IS NULL THEN 0 ELSE 1 END) Existe,
           p.Id_Ruta IdRuta,p.Vendido,
           p.Id_Producto IdProductoEncontrado,pe.Nombre ProductoEncontrado,
           @IdProducto IdProductoEsperado,esperado.Nombre ProductoEsperado,
           @CantidadSolicitada CantidadSolicitada,
           CONVERT(BIT,CASE WHEN p.Imei IS NOT NULL AND p.Id_Producto=@IdProducto
             AND ISNULL(p.Id_Ruta,0)=0 AND ISNULL(p.Id_PedidoVendedor,0)=0
             AND ISNULL(p.Vendido,0)=0 AND ISNULL(p.e_Eliminado,0)=0 THEN 1 ELSE 0 END) Valido,
           CASE WHEN p.Imei IS NULL THEN 'El IMEI no existe en tbl_Productos.'
                WHEN p.Id_Producto<>@IdProducto THEN 'El IMEI pertenece a otro producto.'
                WHEN ISNULL(p.Id_Ruta,0)<>0 OR ISNULL(p.Id_PedidoVendedor,0)<>0 OR ISNULL(p.Vendido,0)<>0 THEN 'El IMEI ya fue asignado o utilizado.'
                WHEN ISNULL(p.e_Eliminado,0)<>0 THEN 'El IMEI esta eliminado.' ELSE '' END Motivo
    FROM @Imeis i LEFT JOIN dbo.tbl_Productos p WITH (INDEX(IX_tbl_Productos_Imei_Disponibilidad)) ON p.Imei=i.Imei
    LEFT JOIN dbo.tbl_Producto pe ON pe.Id_Producto=p.Id_Producto
    LEFT JOIN dbo.tbl_Producto esperado ON esperado.Id_Producto=@IdProducto;
END;
GO

IF OBJECT_ID('dbo.spj_LoginGeneral_Almacen_ValidarTigoMoneyDirecto', 'P') IS NULL
    EXEC('CREATE PROCEDURE dbo.spj_LoginGeneral_Almacen_ValidarTigoMoneyDirecto AS BEGIN SET NOCOUNT ON; END');
GO
ALTER PROCEDURE dbo.spj_LoginGeneral_Almacen_ValidarTigoMoneyDirecto @Cantidad DECIMAL(18,2)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Saldo TABLE(IdProducto INT,Producto NVARCHAR(200),Cantidad DECIMAL(18,2));
    DECLARE @SaldoAmpliado TABLE(
        IdProducto INT, IdTipoProducto INT, Producto NVARCHAR(200),
        PrecioVenta DECIMAL(38,10), PrecioPromocionTigo DECIMAL(38,10),
        PrecioNominal DECIMAL(38,10), PrecioPromocion DECIMAL(38,10),
        IdTipoProductoRepetido INT, Cantidad DECIMAL(18,2));
    DECLARE @Disponible DECIMAL(18,2);
    DECLARE @Fecha DATETIME; SET @Fecha=GETDATE();
    IF OBJECT_DEFINITION(OBJECT_ID('dbo.sp_Traer_Saldos_Productos_Almacen_X_Fecha')) LIKE '%Pr.Id_TipoProducto%'
    BEGIN
        INSERT @SaldoAmpliado EXEC dbo.sp_Traer_Saldos_Productos_Almacen_X_Fecha @Fecha;
        SELECT @Disponible=ISNULL(Cantidad,0) FROM @SaldoAmpliado WHERE IdProducto=31;
    END
    ELSE
    BEGIN
        INSERT @Saldo EXEC dbo.sp_Traer_Saldos_Productos_Almacen_X_Fecha @Fecha;
        SELECT @Disponible=ISNULL(Cantidad,0) FROM @Saldo WHERE IdProducto=31;
    END;
    SET @Disponible=ISNULL(@Disponible,0);
    SELECT @Disponible SaldoDisponible,@Cantidad MontoPedido,@Disponible-@Cantidad SaldoRestante,
           CONVERT(BIT,CASE WHEN @Cantidad>0 AND @Disponible>=@Cantidad THEN 1 ELSE 0 END) Valido;
END;
GO

IF OBJECT_ID('dbo.tbl_PedidoDirectoAlmacen_ProductoFisico', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.tbl_PedidoDirectoAlmacen_ProductoFisico
    (
        Id_AsignacionDirecta INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        Id_PedidoVendedor INT NOT NULL,
        Id_Producto INT NOT NULL,
        Imei BIGINT NOT NULL,
        Id_Ruta INT NOT NULL,
        Numero_Tira INT NOT NULL,
        Modo_Tira VARCHAR(20) NOT NULL,
        Fecha_Registro DATETIME NOT NULL CONSTRAINT DF_PedidoDirectoFisico_Fecha DEFAULT(GETDATE()),
        E_Eliminado INT NOT NULL CONSTRAINT DF_PedidoDirectoFisico_Eliminado DEFAULT(2)
    );
    CREATE UNIQUE INDEX UX_PedidoDirectoFisico_ImeiActivo
        ON dbo.tbl_PedidoDirectoAlmacen_ProductoFisico(Imei, E_Eliminado);
END;
GO
IF EXISTS(SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID('dbo.tbl_PedidoDirectoAlmacen_ProductoFisico') AND name='UX_PedidoDirectoFisico_ImeiActivo')
    DROP INDEX UX_PedidoDirectoFisico_ImeiActivo ON dbo.tbl_PedidoDirectoAlmacen_ProductoFisico;
CREATE UNIQUE INDEX UX_PedidoDirectoFisico_ImeiActivo
    ON dbo.tbl_PedidoDirectoAlmacen_ProductoFisico(Imei)
    WHERE E_Eliminado=2;
GO

IF OBJECT_ID('dbo.spj_LoginGeneral_Almacen_CrearPedidoDirecto', 'P') IS NULL
    EXEC('CREATE PROCEDURE dbo.spj_LoginGeneral_Almacen_CrearPedidoDirecto AS BEGIN SET NOCOUNT ON; END');
GO

ALTER PROCEDURE dbo.spj_LoginGeneral_Almacen_CrearPedidoDirecto
    @IdRuta INT,
    @IdUsuarioAlmacenero INT,
    @CreadoPor VARCHAR(150),
    @Observacion VARCHAR(50),
    @DetalleXml XML,
    @ProductosXml XML
AS
BEGIN
    SET NOCOUNT ON;
    SET ARITHABORT ON;
    SET XACT_ABORT ON;

    DECLARE @Detalle TABLE
    (
        IdProducto INT NOT NULL PRIMARY KEY,
        Cantidad INT NOT NULL,
        Saldo INT NULL,
        ItemsHoy INT NULL,
        Precio DECIMAL(18,2) NULL,
        TotalParcial FLOAT NULL
    );
    DECLARE @Asignados TABLE
    (
        IdProducto INT NOT NULL,
        Imei BIGINT NOT NULL PRIMARY KEY,
        NumeroTira INT NOT NULL,
        ModoTira VARCHAR(20) NOT NULL
    );
    DECLARE @SaldosAlmacen TABLE(IdProducto INT, Producto NVARCHAR(200), Cantidad DECIMAL(18,2));
    DECLARE @SaldosAlmacenAmpliado TABLE(
        IdProducto INT, IdTipoProducto INT, Producto NVARCHAR(200),
        PrecioVenta DECIMAL(38,10), PrecioPromocionTigo DECIMAL(38,10),
        PrecioNominal DECIMAL(38,10), PrecioPromocion DECIMAL(38,10),
        IdTipoProductoRepetido INT, Cantidad DECIMAL(18,2));
    DECLARE @IdVendedor INT, @IdPedido INT, @IdAlmacen INT, @ResultadoBloqueo INT;
    DECLARE @Fecha DATETIME, @TotalPedido DECIMAL(18,2), @TotalAlmacen DECIMAL(18,2);
    DECLARE @TigoMoney DECIMAL(18,2), @SaldoTigoMoney DECIMAL(18,2), @Mensaje VARCHAR(350);
    DECLARE @Recurso VARCHAR(255);

    INSERT INTO @Detalle(IdProducto, Cantidad)
    SELECT n.v.value('@producto','INT'), n.v.value('@cantidad','INT')
    FROM @DetalleXml.nodes('/pedido/i') n(v);

    INSERT INTO @Asignados(IdProducto, Imei, NumeroTira, ModoTira)
    SELECT n.v.value('@producto','INT'), n.v.value('@imei','BIGINT'),
           n.v.value('@tira','INT'), LOWER(n.v.value('@modo','VARCHAR(20)'))
    FROM @ProductosXml.nodes('/productos/i') n(v);

    IF NOT EXISTS(SELECT 1 FROM @Detalle)
        RAISERROR('El pedido directo debe contener al menos un producto.',16,1);
    IF EXISTS(SELECT 1 FROM @Detalle WHERE Cantidad < 1 OR IdProducto = 32)
        RAISERROR('El pedido contiene una cantidad o producto no permitido.',16,1);
    IF EXISTS(SELECT 1 FROM @Asignados WHERE NumeroTira < 1 OR ModoTira NOT IN ('individual','rango','cantidad'))
        RAISERROR('Una de las tiras tiene datos invalidos.',16,1);

    BEGIN TRY
        BEGIN TRANSACTION;

        SELECT @IdVendedor = Id_Vendedor
        FROM dbo.tbl_Ruta WITH(UPDLOCK,HOLDLOCK)
        WHERE Id_Ruta=@IdRuta AND ISNULL(E_Eliminado,2)=2 AND ISNULL(Id_Vendedor,0)>0;
        IF @IdVendedor IS NULL RAISERROR('La ruta no existe o no tiene vendedor asignado.',16,1);

        SET @Recurso='LoginGeneral:Sistemas:CascadaRuta:'+CONVERT(VARCHAR(20),@IdRuta);
        EXEC @ResultadoBloqueo=sys.sp_getapplock @Resource=@Recurso,@LockMode='Shared',@LockOwner='Transaction',@LockTimeout=15000;
        IF @ResultadoBloqueo<0 RAISERROR('La ruta esta siendo restaurada por Sistemas. Intente nuevamente.',16,1);
        SET @Recurso='LoginGeneral:PedidoDirectoRuta:'+CONVERT(VARCHAR(20),@IdRuta);
        EXEC @ResultadoBloqueo=sys.sp_getapplock @Resource=@Recurso,@LockMode='Exclusive',@LockOwner='Transaction',@LockTimeout=15000;
        IF @ResultadoBloqueo<0 RAISERROR('La ruta esta siendo actualizada por otro almacenero. Intente nuevamente.',16,1);

        IF EXISTS(SELECT 1 FROM @Detalle d LEFT JOIN dbo.tbl_Producto p ON p.Id_Producto=d.IdProducto WHERE p.Id_Producto IS NULL)
            RAISERROR('Uno de los productos no existe en el catalogo.',16,1);
        IF EXISTS(SELECT 1 FROM @Asignados a LEFT JOIN @Detalle d ON d.IdProducto=a.IdProducto WHERE d.IdProducto IS NULL OR a.IdProducto=31)
            RAISERROR('Un IMEI fue asociado a un producto incorrecto.',16,1);
        IF EXISTS
        (
            SELECT 1 FROM @Detalle d
            LEFT JOIN (SELECT IdProducto,COUNT(*) Cantidad FROM @Asignados GROUP BY IdProducto) a ON a.IdProducto=d.IdProducto
            WHERE d.IdProducto<>31 AND ISNULL(a.Cantidad,0)<>d.Cantidad
        ) RAISERROR('Las cantidades fisicas no completan exactamente el pedido.',16,1);

        IF EXISTS
        (
            SELECT 1 FROM @Asignados a
            LEFT JOIN dbo.tbl_Productos p WITH(UPDLOCK,HOLDLOCK,INDEX(IX_tbl_Productos_Imei_Disponibilidad))
              ON p.Imei=a.Imei AND p.Id_Producto=a.IdProducto
             AND ISNULL(p.Id_Ruta,0)=0 AND ISNULL(p.Id_PedidoVendedor,0)=0
             AND ISNULL(p.Vendido,0)=0 AND ISNULL(p.e_Eliminado,0)=0
            WHERE p.Imei IS NULL
        ) RAISERROR('Uno o mas IMEI no existen, son de otro producto o dejaron de estar libres.',16,1);

        SET @Fecha=GETDATE();
        UPDATE d SET Saldo=ISNULL(s.Cantidad,0), ItemsHoy=ISNULL(s.Cantidad,0)+d.Cantidad,
            Precio=CONVERT(DECIMAL(18,2),p.PrecioVenta),
            TotalParcial=CONVERT(FLOAT,(ISNULL(s.Cantidad,0)+d.Cantidad)*p.PrecioVenta)
        FROM @Detalle d JOIN dbo.tbl_Producto p ON p.Id_Producto=d.IdProducto
        LEFT JOIN dbo.tbl_SaldoTarjetas s WITH(UPDLOCK,HOLDLOCK)
          ON s.Id_Ruta=@IdRuta AND s.Id_Producto=d.IdProducto AND s.E_Eliminado=2;

        SELECT @TotalPedido=CONVERT(DECIMAL(18,2),SUM(TotalParcial)),
               @TotalAlmacen=CONVERT(DECIMAL(18,2),SUM(Cantidad*Precio)) FROM @Detalle;
        SELECT @TigoMoney=ISNULL(SUM(Cantidad),0) FROM @Detalle WHERE IdProducto=31;
        IF @TigoMoney>0
        BEGIN
            SET @Recurso='LoginGeneral:TigoMoney:'+CONVERT(VARCHAR(8),@Fecha,112);
            EXEC @ResultadoBloqueo=sys.sp_getapplock @Resource=@Recurso,@LockMode='Exclusive',@LockOwner='Transaction',@LockTimeout=15000;
            IF @ResultadoBloqueo<0 RAISERROR('No se pudo bloquear el saldo de Tigo Money.',16,1);
            IF OBJECT_DEFINITION(OBJECT_ID('dbo.sp_Traer_Saldos_Productos_Almacen_X_Fecha')) LIKE '%Pr.Id_TipoProducto%'
            BEGIN
                INSERT INTO @SaldosAlmacenAmpliado EXEC dbo.sp_Traer_Saldos_Productos_Almacen_X_Fecha @Fecha;
                SELECT @SaldoTigoMoney=ISNULL(Cantidad,0) FROM @SaldosAlmacenAmpliado WHERE IdProducto=31;
            END
            ELSE
            BEGIN
                INSERT INTO @SaldosAlmacen EXEC dbo.sp_Traer_Saldos_Productos_Almacen_X_Fecha @Fecha;
                SELECT @SaldoTigoMoney=ISNULL(Cantidad,0) FROM @SaldosAlmacen WHERE IdProducto=31;
            END;
            SET @SaldoTigoMoney=ISNULL(@SaldoTigoMoney,0);
            IF @SaldoTigoMoney<@TigoMoney
            BEGIN
                SET @Mensaje='Saldo insuficiente de Tigo Money. Disponible: '+CONVERT(VARCHAR(30),@SaldoTigoMoney)+', solicitado: '+CONVERT(VARCHAR(30),@TigoMoney)+'.';
                RAISERROR(@Mensaje,16,1);
            END;
        END;

        INSERT dbo.tbl_PedidoVendedor(Id_Ruta,Id_Vendedor,Id_Usuario,Fecha,Fecha_Registro,Observacion,Total,E_Entregado,E_Pagado,E_Eliminado)
        VALUES(@IdRuta,@IdVendedor,@IdUsuarioAlmacenero,@Fecha,@Fecha,ISNULL(@Observacion,''),@TotalPedido,1,2,2);
        SET @IdPedido=CONVERT(INT,SCOPE_IDENTITY());
        INSERT dbo.tbl_CodigoPedidoVendedor(Id_Producto,Id_PedidoVendedor,Saldo,NvoPedido,ItemsHoy,Precio,TotalParcial,E_Eliminado)
        SELECT IdProducto,@IdPedido,Saldo,Cantidad,ItemsHoy,Precio,TotalParcial,2 FROM @Detalle;

        INSERT dbo.tbl_AlmacenVendedor(Id_Ruta,Id_Vendedor,Id_PedidoVendedor,Id_Usuario,Fecha,Fecha_Registro,Observacion,Total,E_Eliminado)
        VALUES(@IdRuta,@IdVendedor,@IdPedido,@IdUsuarioAlmacenero,@Fecha,@Fecha,ISNULL(@Observacion,''),@TotalAlmacen,2);
        SET @IdAlmacen=CONVERT(INT,SCOPE_IDENTITY());
        INSERT dbo.tbl_CodigoAlmacenVendedor(Id_Producto,Id_AlmacenVendedor,Cod_Inicio,Cod_Final,Cantidad,Precio,TotalParcial,E_Eliminado)
        SELECT a.IdProducto,@IdAlmacen,CONVERT(VARCHAR(50),MIN(a.Imei)),CONVERT(VARCHAR(50),MAX(a.Imei)),COUNT(*),d.Precio,CONVERT(FLOAT,COUNT(*)*d.Precio),2
        FROM @Asignados a JOIN @Detalle d ON d.IdProducto=a.IdProducto
        GROUP BY a.IdProducto,a.NumeroTira,d.Precio;
        INSERT dbo.tbl_CodigoAlmacenVendedor(Id_Producto,Id_AlmacenVendedor,Cod_Inicio,Cod_Final,Cantidad,Precio,TotalParcial,E_Eliminado)
        SELECT IdProducto,@IdAlmacen,'0','0',Cantidad,Precio,CONVERT(FLOAT,Cantidad*Precio),2 FROM @Detalle WHERE IdProducto=31;

        UPDATE p SET Id_Ruta=@IdRuta,Id_PedidoVendedor=@IdPedido,Vendido=1
        FROM dbo.tbl_Productos p JOIN @Asignados a ON a.Imei=p.Imei AND a.IdProducto=p.Id_Producto
        WHERE ISNULL(p.Id_Ruta,0)=0 AND ISNULL(p.Id_PedidoVendedor,0)=0 AND ISNULL(p.Vendido,0)=0 AND ISNULL(p.e_Eliminado,0)=0;
        IF @@ROWCOUNT<>(SELECT COUNT(*) FROM @Asignados)
            RAISERROR('No se pudo actualizar exactamente un registro por cada IMEI.',16,1);

        UPDATE s SET Cantidad=s.Cantidad+d.Cantidad FROM dbo.tbl_SaldoTarjetas s JOIN @Detalle d ON d.IdProducto=s.Id_Producto
        WHERE s.Id_Ruta=@IdRuta AND s.E_Eliminado=2;
        INSERT dbo.tbl_SaldoTarjetas(Id_Producto,Id_Ruta,Cantidad,E_Eliminado)
        SELECT d.IdProducto,@IdRuta,d.Cantidad,2 FROM @Detalle d
        WHERE NOT EXISTS(SELECT 1 FROM dbo.tbl_SaldoTarjetas s WHERE s.Id_Ruta=@IdRuta AND s.Id_Producto=d.IdProducto AND s.E_Eliminado=2);

        INSERT dbo.tbl_PedidoDirectoAlmacen(Id_PedidoVendedor,Id_AlmacenVendedor,Id_Ruta,Id_UsuarioAlmacenero,CreadoPor)
        VALUES(@IdPedido,@IdAlmacen,@IdRuta,@IdUsuarioAlmacenero,@CreadoPor);
        INSERT dbo.tbl_PedidoDirectoAlmacen_ProductoFisico(Id_PedidoVendedor,Id_Producto,Imei,Id_Ruta,Numero_Tira,Modo_Tira)
        SELECT @IdPedido,IdProducto,Imei,@IdRuta,NumeroTira,ModoTira FROM @Asignados;

        COMMIT TRANSACTION;
        SELECT @IdPedido IdPedidoVendedor,@IdAlmacen IdAlmacenVendedor,@IdRuta IdRuta,
               (SELECT COUNT(*) FROM @Detalle) CantidadProductos,(SELECT SUM(Cantidad) FROM @Detalle) CantidadUnidades,
               @TotalAlmacen Total,@Fecha FechaRegistro;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT>0 ROLLBACK TRANSACTION;
        DECLARE @Error NVARCHAR(4000); SET @Error=ERROR_MESSAGE(); RAISERROR(@Error,16,1);
    END CATCH;
END;
GO
