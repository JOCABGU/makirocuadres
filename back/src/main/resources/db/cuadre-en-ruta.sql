SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF COL_LENGTH('dbo.tbl_Cuadre_EnRuta', 'Modificado') IS NULL
    ALTER TABLE dbo.tbl_Cuadre_EnRuta ADD Modificado BIT NOT NULL
        CONSTRAINT DF_tbl_Cuadre_EnRuta_Modificado DEFAULT (0);
GO

IF COL_LENGTH('dbo.tbl_Cuadre_EnRuta', 'TirasXml') IS NULL
    ALTER TABLE dbo.tbl_Cuadre_EnRuta ADD TirasXml XML NULL;
GO

IF COL_LENGTH('dbo.tbl_Cuadre_EnRuta', 'FechaAprobacion') IS NULL
    ALTER TABLE dbo.tbl_Cuadre_EnRuta ADD FechaAprobacion DATETIME NULL;
GO

IF OBJECT_ID(N'dbo.spj_LoginGeneral_CuadreEnRuta_ObtenerHoy', N'P') IS NULL
    EXEC(N'CREATE PROCEDURE dbo.spj_LoginGeneral_CuadreEnRuta_ObtenerHoy AS BEGIN SET NOCOUNT ON; END');
GO

ALTER PROCEDURE dbo.spj_LoginGeneral_CuadreEnRuta_ObtenerHoy
    @IdRuta INT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Hoy DATE=CONVERT(DATE,GETDATE());
    SELECT TOP (1)
        CAST(1 AS BIT) Existe,
        c.Id_Cuadre_EnRuta IdCuadre,
        c.Id_Ruta IdRuta,
        c.Fecha,
        CAST(1 AS BIT) EsPreliminar,
        ISNULL(c.E_Aprobado,1) EstadoAprobado,
        CAST(ISNULL(c.Modificado,0) AS BIT) Modificado
    FROM dbo.tbl_Cuadre_EnRuta c
    WHERE c.Id_Ruta=@IdRuta AND c.E_Eliminado=2
      AND c.Fecha>=@Hoy AND c.Fecha<DATEADD(DAY,1,@Hoy)
    ORDER BY c.Id_Cuadre_EnRuta DESC;

    IF @@ROWCOUNT=0
        SELECT CAST(0 AS BIT) Existe,NULL IdCuadre,@IdRuta IdRuta,NULL Fecha,
               CAST(1 AS BIT) EsPreliminar,NULL EstadoAprobado,CAST(0 AS BIT) Modificado;
END;
GO

IF OBJECT_ID(N'dbo.spj_LoginGeneral_CuadreEnRuta_Crear', N'P') IS NULL
    EXEC(N'CREATE PROCEDURE dbo.spj_LoginGeneral_CuadreEnRuta_Crear AS BEGIN SET NOCOUNT ON; END');
GO

ALTER PROCEDURE dbo.spj_LoginGeneral_CuadreEnRuta_Crear
    @IdRuta INT,
    @IdVendedor INT,
    @IdUsuario INT,
    @Observacion VARCHAR(100),
    @TirasXml XML
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON; SET ARITHABORT ON;
    DECLARE @Hoy DATE=CONVERT(DATE,GETDATE()),@IdCuadreEnRuta INT,@Lock INT,@Recurso NVARCHAR(255);
    SET @Recurso=N'LoginGeneral:CuadreEnRuta:Ruta:'+CONVERT(NVARCHAR(20),@IdRuta)+N':'+CONVERT(CHAR(8),@Hoy,112);
    DECLARE @Tiras TABLE(IdProducto INT,NumeroTira INT,Modo VARCHAR(20),CantidadManual INT,Efectivizacion INT,PRIMARY KEY(IdProducto,NumeroTira));
    INSERT @Tiras SELECT n.value('@producto','INT'),n.value('@numero','INT'),n.value('@modo','VARCHAR(20)'),n.value('@cantidad','INT'),n.value('@efectivizacion','INT')
    FROM @TirasXml.nodes('/tiras/tira')x(n);
    DECLARE @Imeis TABLE(IdProducto INT,NumeroTira INT,Modo VARCHAR(20),Imei BIGINT PRIMARY KEY);
    INSERT @Imeis SELECT t.value('@producto','INT'),t.value('@numero','INT'),t.value('@modo','VARCHAR(20)'),i.value('@v','BIGINT')
    FROM @TirasXml.nodes('/tiras/tira')x(t) CROSS APPLY t.nodes('i')y(i);

    IF NOT EXISTS(SELECT 1 FROM @Tiras) RAISERROR('Debes registrar al menos un producto sobrante.',16,1);
    IF EXISTS(SELECT 1 FROM @Tiras WHERE NumeroTira<1 OR Modo NOT IN('individual','rango','cantidad','tigo_money','chip_cantidad'))
        RAISERROR('La Lista Master contiene una tira no valida.',16,1);
    IF EXISTS(SELECT 1 FROM @Tiras t WHERE Modo NOT IN('tigo_money','chip_cantidad') AND NOT EXISTS(SELECT 1 FROM @Imeis i WHERE i.IdProducto=t.IdProducto AND i.NumeroTira=t.NumeroTira))
        RAISERROR('Una tira fisica no contiene IMEI.',16,1);
    IF EXISTS(SELECT 1 FROM @Imeis WHERE Modo='tigo_money') RAISERROR('Tigo Money no debe contener IMEI.',16,1);
    IF (SELECT COUNT(*) FROM @Tiras WHERE Modo='tigo_money')>1 RAISERROR('Tigo Money solo puede registrarse una vez.',16,1);
    IF EXISTS(SELECT 1 FROM @Imeis WHERE Modo='chip_cantidad') RAISERROR('El sobrante de chips se registra por cantidad y no debe contener IMEI.',16,1);
    IF EXISTS(SELECT 1 FROM @Tiras WHERE Modo='chip_cantidad' GROUP BY IdProducto HAVING COUNT(*)>1)
        RAISERROR('Cada chip solo puede registrarse una vez por cantidad.',16,1);

    BEGIN TRY
      BEGIN TRANSACTION;
      EXEC @Lock=sys.sp_getapplock @Resource=@Recurso,@LockMode='Exclusive',@LockOwner='Transaction',@LockTimeout=15000;
      IF @Lock<0 RAISERROR('No se pudo bloquear la ruta para registrar el cuadre.',16,1);
      IF EXISTS(SELECT 1 FROM dbo.tbl_Cuadre_EnRuta WITH(UPDLOCK,HOLDLOCK) WHERE Id_Ruta=@IdRuta AND E_Eliminado=2 AND Fecha>=@Hoy AND Fecha<DATEADD(DAY,1,@Hoy))
        RAISERROR('La ruta ya envio un cuadre hoy.',16,1);
      IF EXISTS(SELECT 1 FROM dbo.tbl_Cuadre WITH(UPDLOCK,HOLDLOCK) WHERE Id_Ruta=@IdRuta AND E_Eliminado=2 AND Fecha>=@Hoy AND Fecha<DATEADD(DAY,1,@Hoy))
        RAISERROR('La ruta ya tiene un cuadre definitivo hoy.',16,1);
      IF NOT EXISTS(SELECT 1 FROM dbo.tbl_Ruta WITH(UPDLOCK,HOLDLOCK) WHERE Id_Ruta=@IdRuta AND Id_Vendedor=@IdVendedor AND E_Eliminado=2)
        RAISERROR('La ruta ya no pertenece al vendedor autenticado.',16,1);
      IF EXISTS(
          SELECT 1
          FROM dbo.tbl_SaldoTarjetas saldo WITH(UPDLOCK,HOLDLOCK)
          JOIN dbo.tbl_Producto producto ON producto.Id_Producto=saldo.Id_Producto
          WHERE saldo.Id_Ruta=@IdRuta
            AND saldo.E_Eliminado=2
            AND ISNULL(saldo.Cantidad,0)>0
            AND producto.Id_TipoProducto=5
            AND UPPER(LTRIM(RTRIM(producto.Nombre)))='TM_VENTA'
            AND NOT EXISTS(SELECT 1 FROM @Tiras WHERE Modo='tigo_money')
      )
        RAISERROR('Debes registrar el sobrante y la efectivizacion de Tigo Money.',16,1);
      IF EXISTS(SELECT 1 FROM @Imeis i LEFT JOIN dbo.tbl_Productos p WITH(UPDLOCK,HOLDLOCK) ON p.Imei=i.Imei AND p.Id_Producto=i.IdProducto AND p.Id_Ruta=@IdRuta AND ISNULL(p.Vendido,0)=1 AND ISNULL(p.e_Eliminado,0)=0 WHERE p.Imei IS NULL)
        RAISERROR('Uno o mas IMEI no pertenecen a la ruta, producto o estado requerido.',16,1);
      IF EXISTS(SELECT 1 FROM @Tiras t LEFT JOIN dbo.tbl_Producto p ON p.Id_Producto=t.IdProducto
                WHERE t.Modo='chip_cantidad'
                  AND (p.Id_Producto IS NULL OR ISNULL(p.Id_TipoProducto,0)<>2 OR ISNULL(t.CantidadManual,-1)<0
                       OR EXISTS(SELECT 1 FROM @Imeis i WHERE i.IdProducto=t.IdProducto)))
        RAISERROR('El sobrante por cantidad solo aplica a chips, debe ser mayor o igual a cero y no puede mezclarse con IMEI del mismo chip.',16,1);

      DECLARE @Productos TABLE(IdProducto INT PRIMARY KEY,SaldoInicial INT,Sobrantes INT,Vendidos INT,Precio DECIMAL(18,2));
      INSERT @Productos
      SELECT e.IdProducto,e.Cantidad,ISNULL(s.Cantidad,0)+ISNULL(m.Cantidad,0),e.Cantidad-ISNULL(s.Cantidad,0)-ISNULL(m.Cantidad,0),ISNULL(p.PrecioVenta,0)
      FROM(SELECT Id_Producto IdProducto,CONVERT(INT,COUNT_BIG(*)) Cantidad FROM dbo.tbl_Productos WITH(UPDLOCK,HOLDLOCK) WHERE Id_Ruta=@IdRuta AND ISNULL(Vendido,0)=1 AND ISNULL(e_Eliminado,0)=0 GROUP BY Id_Producto)e
      JOIN dbo.tbl_Producto p ON p.Id_Producto=e.IdProducto
      OUTER APPLY(SELECT COUNT(*) Cantidad FROM @Imeis i WHERE i.IdProducto=e.IdProducto)s
      OUTER APPLY(SELECT SUM(t.CantidadManual) Cantidad FROM @Tiras t WHERE t.Modo='chip_cantidad' AND t.IdProducto=e.IdProducto)m
      WHERE ISNULL(p.Id_TipoProducto,0)<>5;
      IF EXISTS(SELECT 1 FROM @Tiras t WHERE t.Modo='chip_cantidad' AND t.CantidadManual>0 AND NOT EXISTS(SELECT 1 FROM @Productos p WHERE p.IdProducto=t.IdProducto))
        RAISERROR('Un chip registrado por cantidad no tiene saldo en la ruta.',16,1);

      DECLARE @IdV INT,@IdE INT,@Saldo INT,@Sob INT,@Ef INT,@VendTotal INT,@ESob INT,@EVend INT,@VSob INT,@VVend INT;
      SELECT TOP 1 @IdV=IdProducto,@IdE=IdProducto+1,@Sob=CantidadManual,@Ef=Efectivizacion FROM @Tiras WHERE Modo='tigo_money';
      IF @IdV IS NOT NULL
      BEGIN
        IF NOT EXISTS(SELECT 1 FROM dbo.tbl_Producto WHERE Id_Producto=@IdV AND Id_TipoProducto=5 AND UPPER(LTRIM(RTRIM(Nombre)))='TM_VENTA')
          RAISERROR('El registro manual solo corresponde a TM_Venta.',16,1);
        SELECT @Saldo=CONVERT(INT,SUM(ISNULL(Cantidad,0))) FROM dbo.tbl_SaldoTarjetas WITH(UPDLOCK,HOLDLOCK) WHERE Id_Ruta=@IdRuta AND Id_Producto=@IdV AND E_Eliminado=2;
        SET @Saldo=ISNULL(@Saldo,0); SET @VendTotal=@Saldo+@Ef-@Sob;
        IF @Sob<0 OR @Ef<0 OR @VendTotal<0 RAISERROR('El sobrante no puede superar el saldo mas la efectivizacion.',16,1);
        SET @ESob=CASE WHEN @VendTotal>@Ef THEN 0 ELSE @Ef-@VendTotal END;
        SET @EVend=CASE WHEN @VendTotal>@Ef THEN @Ef ELSE @VendTotal END;
        SET @VSob=@Sob-@ESob; SET @VVend=@Saldo-@VSob;
        INSERT @Productos SELECT @IdV,@Saldo,@VSob,@VVend,ISNULL(PrecioVenta,0) FROM dbo.tbl_Producto WHERE Id_Producto=@IdV;
        IF @ESob+@EVend>0
        BEGIN
          IF NOT EXISTS(SELECT 1 FROM dbo.tbl_Producto WHERE Id_Producto=@IdE AND Id_TipoProducto=5 AND UPPER(LTRIM(RTRIM(Nombre)))='TM_COMPRA')
            RAISERROR('No se encontro TM_Compra asociado.',16,1);
          INSERT @Productos SELECT @IdE,@Ef,@ESob,@EVend,ISNULL(PrecioVenta,0) FROM dbo.tbl_Producto WHERE Id_Producto=@IdE;
        END;
      END;
      IF EXISTS(SELECT 1 FROM @Productos WHERE Vendidos<0 OR Sobrantes<0) RAISERROR('Las cantidades del cuadre no son validas.',16,1);
      IF NOT EXISTS(SELECT 1 FROM @Productos) RAISERROR('La ruta no tiene saldo para cuadrar.',16,1);

      INSERT dbo.tbl_Cuadre_EnRuta(Id_Ruta,Id_Vendedor,Id_Usuario,Fecha,Observacion,Total,E_Aprobado,AprobadoPor,Id_Cuadre,E_Eliminado,Modificado,TirasXml,FechaAprobacion)
      SELECT @IdRuta,@IdVendedor,@IdUsuario,GETDATE(),NULLIF(LTRIM(RTRIM(@Observacion)),''),SUM(CONVERT(FLOAT,Vendidos*Precio)),1,NULL,0,2,0,@TirasXml,NULL FROM @Productos;
      SET @IdCuadreEnRuta=CONVERT(INT,SCOPE_IDENTITY());
      INSERT dbo.tbl_CodigoCuadre_EnRuta(Id_Cuadre_EnRuta,Id_Producto,ItemsSobrantes,ItemsVendidos,Precio,TotalVendidos,E_Eliminado)
      SELECT @IdCuadreEnRuta,IdProducto,Sobrantes,Vendidos,Precio,CONVERT(FLOAT,Vendidos*Precio),2 FROM @Productos;
      COMMIT;
      SELECT @IdCuadreEnRuta IdCuadre,@IdRuta IdRuta,GETDATE() Fecha,
             ISNULL((SELECT SUM(Sobrantes) FROM @Productos),0) TotalSobrantes,
             ISNULL((SELECT SUM(Vendidos) FROM @Productos),0) TotalVendidos,
             ISNULL((SELECT SUM(CONVERT(DECIMAL(18,2),Vendidos*Precio)) FROM @Productos),0) Total;
    END TRY
    BEGIN CATCH
      IF @@TRANCOUNT>0 ROLLBACK;
      DECLARE @Msg NVARCHAR(4000)=ERROR_MESSAGE(); RAISERROR(@Msg,16,1);
    END CATCH;
END;
GO

IF OBJECT_ID(N'dbo.spj_LoginGeneral_Almacen_CuadreEnRuta_Listar', N'P') IS NULL
    EXEC(N'CREATE PROCEDURE dbo.spj_LoginGeneral_Almacen_CuadreEnRuta_Listar AS BEGIN SET NOCOUNT ON; END');
GO
ALTER PROCEDURE dbo.spj_LoginGeneral_Almacen_CuadreEnRuta_Listar @Fecha DATE
AS
BEGIN
 SET NOCOUNT ON;
 SELECT c.Id_Cuadre_EnRuta IdCuadreEnRuta,c.Id_Ruta IdRuta,r.Nombre Ruta,
        c.Id_Vendedor IdVendedor,v.Nombre Tecnico,c.Id_Usuario IdUsuario,
        c.Fecha,c.Observacion,c.Total,ISNULL(c.E_Aprobado,1) EstadoAprobado,c.AprobadoPor,c.Id_Cuadre IdCuadre,
        CAST(ISNULL(c.Modificado,0) AS BIT) Modificado,c.FechaAprobacion
 FROM dbo.tbl_Cuadre_EnRuta c JOIN dbo.tbl_Ruta r ON r.Id_Ruta=c.Id_Ruta LEFT JOIN dbo.tbl_Vendedor v ON v.Id_Vendedor=c.Id_Vendedor
 WHERE c.E_Eliminado=2 AND c.Fecha>=@Fecha AND c.Fecha<DATEADD(DAY,1,@Fecha)
 ORDER BY CASE WHEN ISNULL(c.E_Aprobado,1)=1 THEN 0 ELSE 1 END,c.Fecha DESC;
END;
GO

IF OBJECT_ID(N'dbo.spj_LoginGeneral_Almacen_CuadreEnRuta_Detalle', N'P') IS NULL
    EXEC(N'CREATE PROCEDURE dbo.spj_LoginGeneral_Almacen_CuadreEnRuta_Detalle AS BEGIN SET NOCOUNT ON; END');
GO
ALTER PROCEDURE dbo.spj_LoginGeneral_Almacen_CuadreEnRuta_Detalle @IdCuadreEnRuta INT
AS
BEGIN
 SET NOCOUNT ON;
 SELECT c.Id_Cuadre_EnRuta IdCuadreEnRuta,c.Id_Ruta IdRuta,r.Nombre Ruta,
        c.Id_Vendedor IdVendedor,v.Nombre Tecnico,c.Id_Usuario IdUsuario,c.Fecha,c.Observacion,c.Total,
        ISNULL(c.E_Aprobado,1) EstadoAprobado,c.AprobadoPor,c.Id_Cuadre IdCuadre,
        CAST(ISNULL(c.Modificado,0) AS BIT) Modificado,c.FechaAprobacion,
        cc.Id_Producto,p.Nombre Producto,tp.Nombre TipoProducto,cc.ItemsSobrantes,cc.ItemsVendidos,cc.Precio,cc.TotalVendidos,
        CONVERT(NVARCHAR(MAX),c.TirasXml) TirasXml
 FROM dbo.tbl_Cuadre_EnRuta c JOIN dbo.tbl_Ruta r ON r.Id_Ruta=c.Id_Ruta LEFT JOIN dbo.tbl_Vendedor v ON v.Id_Vendedor=c.Id_Vendedor
 JOIN dbo.tbl_CodigoCuadre_EnRuta cc ON cc.Id_Cuadre_EnRuta=c.Id_Cuadre_EnRuta AND cc.E_Eliminado=2
 JOIN dbo.tbl_Producto p ON p.Id_Producto=cc.Id_Producto LEFT JOIN dbo.tbl_TipoProducto tp ON tp.Id_TipoProducto=p.Id_TipoProducto
 WHERE c.Id_Cuadre_EnRuta=@IdCuadreEnRuta AND c.E_Eliminado=2 ORDER BY cc.Id_Producto;
END;
GO

IF OBJECT_ID(N'dbo.spj_LoginGeneral_Almacen_CuadreEnRuta_Aprobar', N'P') IS NULL
    EXEC(N'CREATE PROCEDURE dbo.spj_LoginGeneral_Almacen_CuadreEnRuta_Aprobar AS BEGIN SET NOCOUNT ON; END');
GO
ALTER PROCEDURE dbo.spj_LoginGeneral_Almacen_CuadreEnRuta_Aprobar
 @IdCuadreEnRuta INT,@AprobadoPor VARCHAR(150),@Modificado BIT,@TirasModificadasXml XML=NULL
AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON; SET ARITHABORT ON;
 DECLARE @IdRuta INT,@IdVendedor INT,@IdUsuario INT,@Observacion VARCHAR(100),@Xml XML,@Lock INT,@Recurso NVARCHAR(255);
 SET @Recurso=N'LoginGeneral:CuadreEnRuta:Aprobar:'+CONVERT(NVARCHAR(20),@IdCuadreEnRuta);
 DECLARE @Resultado TABLE(IdCuadre INT,IdRuta INT,Fecha DATETIME,TotalSobrantes INT,TotalVendidos INT,Total DECIMAL(18,2));
 BEGIN TRY
  BEGIN TRANSACTION;
  EXEC @Lock=sys.sp_getapplock @Resource=@Recurso,@LockMode='Exclusive',@LockOwner='Transaction',@LockTimeout=15000;
  IF @Lock<0 RAISERROR('No se pudo bloquear el cuadre para aprobarlo.',16,1);
  SELECT @IdRuta=Id_Ruta,@IdVendedor=Id_Vendedor,@IdUsuario=Id_Usuario,@Observacion=Observacion,@Xml=TirasXml
  FROM dbo.tbl_Cuadre_EnRuta WITH(UPDLOCK,HOLDLOCK) WHERE Id_Cuadre_EnRuta=@IdCuadreEnRuta AND E_Eliminado=2 AND ISNULL(E_Aprobado,1)=1;
  IF @IdRuta IS NULL RAISERROR('El cuadre preliminar no existe o ya fue procesado.',16,1);
  IF @Modificado=1 BEGIN IF @TirasModificadasXml IS NULL RAISERROR('La version modificada no contiene Lista Master.',16,1); SET @Xml=@TirasModificadasXml; END;
  INSERT @Resultado EXEC dbo.spj_LoginGeneral_Cuadre_Finalizar @IdRuta,@IdVendedor,@IdUsuario,@Observacion,@Xml;
  DECLARE @IdCuadre INT=(SELECT TOP 1 IdCuadre FROM @Resultado);
  UPDATE dbo.tbl_Cuadre_EnRuta SET E_Aprobado=2,AprobadoPor=@AprobadoPor,Id_Cuadre=@IdCuadre,Modificado=@Modificado,FechaAprobacion=GETDATE()
  WHERE Id_Cuadre_EnRuta=@IdCuadreEnRuta;
  COMMIT;
  SELECT * FROM @Resultado;
 END TRY
 BEGIN CATCH
  IF @@TRANCOUNT>0 ROLLBACK;
  DECLARE @Msg NVARCHAR(4000)=ERROR_MESSAGE(); RAISERROR(@Msg,16,1);
 END CATCH;
END;
GO
