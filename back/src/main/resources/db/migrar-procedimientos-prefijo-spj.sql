SET NOCOUNT ON;
SET ARITHABORT ON;
GO

DECLARE @NombreAnterior SYSNAME;
DECLARE @NombreNuevo SYSNAME;
DECLARE @Definicion NVARCHAR(MAX);
DECLARE @ExisteNuevo BIT;

DECLARE procedimientos CURSOR LOCAL FAST_FORWARD FOR
SELECT name
FROM sys.procedures
WHERE name LIKE 'spx[_]LoginGeneral[_]%'
ORDER BY name;

OPEN procedimientos;
FETCH NEXT FROM procedimientos INTO @NombreAnterior;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @NombreNuevo = REPLACE(@NombreAnterior, 'spx_LoginGeneral_', 'spj_LoginGeneral_');
    SET @Definicion = OBJECT_DEFINITION(OBJECT_ID(N'dbo.' + @NombreAnterior));
    SET @ExisteNuevo = CASE WHEN OBJECT_ID(N'dbo.' + @NombreNuevo, N'P') IS NULL THEN 0 ELSE 1 END;

    IF @Definicion IS NULL
    BEGIN
        CLOSE procedimientos;
        DEALLOCATE procedimientos;
        RAISERROR('No se pudo leer la definicion del procedimiento %s.', 16, 1, @NombreAnterior);
        RETURN;
    END;

    -- Cambia tanto el nombre del procedimiento como cualquier llamada interna entre SP propios.
    SET @Definicion = REPLACE(@Definicion, 'spx_LoginGeneral_', 'spj_LoginGeneral_');

    IF @ExisteNuevo = 0
    BEGIN
        SET @Definicion = REPLACE(@Definicion, 'ALTER PROCEDURE', 'CREATE PROCEDURE');
        SET @Definicion = REPLACE(@Definicion, 'ALTER PROC', 'CREATE PROC');
    END
    ELSE
    BEGIN
        SET @Definicion = REPLACE(@Definicion, 'CREATE PROCEDURE', 'ALTER PROCEDURE');
        SET @Definicion = REPLACE(@Definicion, 'CREATE PROC', 'ALTER PROC');
    END;

    EXEC sp_executesql @Definicion;
    PRINT 'Procedimiento disponible: dbo.' + @NombreNuevo;

    FETCH NEXT FROM procedimientos INTO @NombreAnterior;
END;

CLOSE procedimientos;
DEALLOCATE procedimientos;
GO

SELECT name
FROM sys.procedures
WHERE name LIKE 'spj[_]LoginGeneral[_]%'
ORDER BY name;
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
