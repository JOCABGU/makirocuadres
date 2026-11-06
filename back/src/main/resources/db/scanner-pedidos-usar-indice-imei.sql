-- Ejecutar en BDAlmacen y BDAlmacenTarija_Prueba. Conserva la definicion actual
-- de cada SP y solo agrega el hint a tres lecturas de IMEI en pedidos.
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID(N'dbo.tbl_Productos')
      AND name = N'IX_tbl_Productos_Imei_Disponibilidad'
      AND is_disabled = 0
)
BEGIN
    RAISERROR('Falta el indice activo IX_tbl_Productos_Imei_Disponibilidad.', 16, 1);
    RETURN;
END;

DECLARE @Paso INT = 1;
DECLARE @Procedimiento SYSNAME;
DECLARE @Anterior NVARCHAR(300);
DECLARE @Nuevo NVARCHAR(350);
DECLARE @Definicion NVARCHAR(MAX);
DECLARE @Posicion INT;
DECLARE @Actualizar BIT;
DECLARE @Error NVARCHAR(4000);

BEGIN TRY
    BEGIN TRANSACTION;
    WHILE @Paso <= 3
    BEGIN
        SET @Actualizar = 0;
        IF @Paso = 1
        BEGIN
            SET @Procedimiento = N'dbo.spj_LoginGeneral_Scanner_ValidarImeisPedidoDirecto';
            SET @Anterior = N'FROM @Imeis i LEFT JOIN dbo.tbl_Productos p ON p.Imei=i.Imei';
            SET @Nuevo = N'FROM @Imeis i LEFT JOIN dbo.tbl_Productos p WITH (INDEX(IX_tbl_Productos_Imei_Disponibilidad)) ON p.Imei=i.Imei';
        END;
        IF @Paso = 2
        BEGIN
            SET @Procedimiento = N'dbo.spj_LoginGeneral_Almacen_AprobarPedidoConProductos';
            SET @Anterior = N'LEFT JOIN dbo.tbl_Productos fisico WITH (UPDLOCK, HOLDLOCK)';
            SET @Nuevo = N'LEFT JOIN dbo.tbl_Productos fisico WITH (UPDLOCK, HOLDLOCK, INDEX(IX_tbl_Productos_Imei_Disponibilidad))';
        END;
        IF @Paso = 3
        BEGIN
            SET @Procedimiento = N'dbo.spj_LoginGeneral_Almacen_CrearPedidoDirecto';
            SET @Anterior = N'LEFT JOIN dbo.tbl_Productos p WITH(UPDLOCK,HOLDLOCK)';
            SET @Nuevo = N'LEFT JOIN dbo.tbl_Productos p WITH(UPDLOCK,HOLDLOCK,INDEX(IX_tbl_Productos_Imei_Disponibilidad))';
        END;

        SELECT @Definicion = definition
        FROM sys.sql_modules
        WHERE object_id = OBJECT_ID(@Procedimiento);

        IF @Definicion IS NULL
        BEGIN
            SET @Error = N'No existe o no se puede leer ' + @Procedimiento;
            RAISERROR(@Error, 16, 1);
        END;
        IF CHARINDEX(@Nuevo, @Definicion) = 0
        BEGIN
            IF CHARINDEX(@Anterior, @Definicion) = 0
            BEGIN
                SET @Error = N'La consulta esperada no coincide en ' + @Procedimiento;
                RAISERROR(@Error, 16, 1);
            END;
            SET @Definicion = REPLACE(@Definicion, @Anterior, @Nuevo);
            SET @Actualizar = 1;
        END;
        IF OBJECTPROPERTY(OBJECT_ID(@Procedimiento), 'ExecIsQuotedIdentOn') = 0
            SET @Actualizar = 1;
        IF @Actualizar = 1
        BEGIN
            SET @Posicion = CHARINDEX(N'CREATE PROCEDURE', @Definicion);
            IF @Posicion > 0
                SET @Definicion = STUFF(@Definicion, @Posicion, LEN(N'CREATE PROCEDURE'), N'ALTER PROCEDURE');
            ELSE IF CHARINDEX(N'ALTER PROCEDURE', @Definicion) = 0
            BEGIN
                SET @Error = N'No se pudo preparar ALTER PROCEDURE para ' + @Procedimiento;
                RAISERROR(@Error, 16, 1);
            END;
            EXEC sp_executesql @Definicion;
        END;
        SET @Paso = @Paso + 1;
    END;
    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    SET @Error = ERROR_MESSAGE();
    RAISERROR(@Error, 16, 1);
END CATCH;

SELECT OBJECT_NAME(object_id) AS procedimiento
FROM sys.sql_modules
WHERE object_id IN (
    OBJECT_ID(N'dbo.spj_LoginGeneral_Scanner_ValidarImeisPedidoDirecto'),
    OBJECT_ID(N'dbo.spj_LoginGeneral_Almacen_AprobarPedidoConProductos'),
    OBJECT_ID(N'dbo.spj_LoginGeneral_Almacen_CrearPedidoDirecto')
)
AND definition LIKE N'%INDEX(IX_tbl_Productos_Imei_Disponibilidad)%';
