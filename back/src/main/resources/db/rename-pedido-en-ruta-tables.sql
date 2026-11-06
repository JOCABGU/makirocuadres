SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET XACT_ABORT ON;
GO

BEGIN TRY
    BEGIN TRANSACTION;

    IF OBJECT_ID(N'dbo.PedidoVendedor_EnRuta', N'U') IS NOT NULL
       AND OBJECT_ID(N'dbo.tbl_PedidoVendedor_EnRuta', N'U') IS NULL
    BEGIN
        EXEC sys.sp_rename
            @objname = N'dbo.PedidoVendedor_EnRuta',
            @newname = N'tbl_PedidoVendedor_EnRuta',
            @objtype = N'OBJECT';
    END;

    IF OBJECT_ID(N'dbo.CodigoPedidoVendedor_EnRuta', N'U') IS NOT NULL
       AND OBJECT_ID(N'dbo.tbl_CodigoPedidoVendedor_EnRuta', N'U') IS NULL
    BEGIN
        EXEC sys.sp_rename
            @objname = N'dbo.CodigoPedidoVendedor_EnRuta',
            @newname = N'tbl_CodigoPedidoVendedor_EnRuta',
            @objtype = N'OBJECT';
    END;

    IF OBJECT_ID(N'dbo.tbl_PedidoVendedor_EnRuta', N'U') IS NULL
        RAISERROR('No existe dbo.tbl_PedidoVendedor_EnRuta despues de la migracion.', 16, 1);

    IF OBJECT_ID(N'dbo.tbl_CodigoPedidoVendedor_EnRuta', N'U') IS NULL
        RAISERROR('No existe dbo.tbl_CodigoPedidoVendedor_EnRuta despues de la migracion.', 16, 1);

    DECLARE @Nombre SYSNAME;
    DECLARE @Definicion NVARCHAR(MAX);
    DECLARE @PosicionCreate INT;

    DECLARE procedimientos CURSOR LOCAL STATIC READ_ONLY FORWARD_ONLY FOR
        SELECT QUOTENAME(OBJECT_SCHEMA_NAME(modulo.object_id)) + N'.' + QUOTENAME(OBJECT_NAME(modulo.object_id)),
               modulo.definition
        FROM sys.sql_modules modulo
        INNER JOIN sys.objects objeto ON objeto.object_id = modulo.object_id
        WHERE objeto.type = 'P'
          AND
          (
              CHARINDEX(N'dbo.PedidoVendedor_EnRuta', modulo.definition) > 0
              OR CHARINDEX(N'dbo.CodigoPedidoVendedor_EnRuta', modulo.definition) > 0
              OR CHARINDEX(N'[dbo].[PedidoVendedor_EnRuta]', modulo.definition) > 0
              OR CHARINDEX(N'[dbo].[CodigoPedidoVendedor_EnRuta]', modulo.definition) > 0
          );

    OPEN procedimientos;
    FETCH NEXT FROM procedimientos INTO @Nombre, @Definicion;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        -- El nombre de la tabla de productos fisicos contiene el nombre anterior
        -- como prefijo y debe conservarse sin cambios.
        SET @Definicion = REPLACE(
            @Definicion,
            N'dbo.PedidoVendedor_EnRuta_ProductoFisico',
            N'dbo.__PedidoRutaProductoFisico__');
        SET @Definicion = REPLACE(
            @Definicion,
            N'[dbo].[PedidoVendedor_EnRuta_ProductoFisico]',
            N'[dbo].[__PedidoRutaProductoFisico__]');

        SET @Definicion = REPLACE(
            @Definicion,
            N'dbo.PedidoVendedor_EnRuta',
            N'dbo.tbl_PedidoVendedor_EnRuta');
        SET @Definicion = REPLACE(
            @Definicion,
            N'dbo.CodigoPedidoVendedor_EnRuta',
            N'dbo.tbl_CodigoPedidoVendedor_EnRuta');
        SET @Definicion = REPLACE(
            @Definicion,
            N'[dbo].[PedidoVendedor_EnRuta]',
            N'[dbo].[tbl_PedidoVendedor_EnRuta]');
        SET @Definicion = REPLACE(
            @Definicion,
            N'[dbo].[CodigoPedidoVendedor_EnRuta]',
            N'[dbo].[tbl_CodigoPedidoVendedor_EnRuta]');

        SET @Definicion = REPLACE(
            @Definicion,
            N'dbo.__PedidoRutaProductoFisico__',
            N'dbo.PedidoVendedor_EnRuta_ProductoFisico');
        SET @Definicion = REPLACE(
            @Definicion,
            N'[dbo].[__PedidoRutaProductoFisico__]',
            N'[dbo].[PedidoVendedor_EnRuta_ProductoFisico]');

        IF UPPER(@Definicion) NOT LIKE '%CREATE OR ALTER PROCEDURE%'
        BEGIN
            SET @PosicionCreate = CHARINDEX(N'CREATE PROCEDURE', UPPER(@Definicion));
            IF @PosicionCreate > 0
                SET @Definicion = STUFF(@Definicion, @PosicionCreate, 6, N'ALTER');
            ELSE IF CHARINDEX(N'ALTER PROCEDURE', UPPER(@Definicion)) = 0
                RAISERROR('No se pudo convertir el procedimiento dependiente %s a ALTER.', 16, 1, @Nombre);
        END;

        EXEC sys.sp_executesql @Definicion;
        FETCH NEXT FROM procedimientos INTO @Nombre, @Definicion;
    END;

    CLOSE procedimientos;
    DEALLOCATE procedimientos;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF CURSOR_STATUS('local', 'procedimientos') >= 0 CLOSE procedimientos;
    IF CURSOR_STATUS('local', 'procedimientos') > -3 DEALLOCATE procedimientos;
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    DECLARE @MensajeError NVARCHAR(4000);
    SET @MensajeError = ERROR_MESSAGE();
    RAISERROR(@MensajeError, 16, 1);
END CATCH;
GO
