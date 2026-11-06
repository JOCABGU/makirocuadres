SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

DECLARE @Nombre SYSNAME;
DECLARE @Definicion NVARCHAR(MAX);

DECLARE ProcedimientosSpj CURSOR LOCAL STATIC FOR
SELECT procedimiento.name, modulo.definition
FROM sys.procedures procedimiento
INNER JOIN sys.sql_modules modulo
    ON modulo.object_id = procedimiento.object_id
WHERE procedimiento.name LIKE N'spj[_]LoginGeneral[_]%';

OPEN ProcedimientosSpj;
FETCH NEXT FROM ProcedimientosSpj INTO @Nombre, @Definicion;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @Definicion = REPLACE(@Definicion, N'CREATE PROCEDURE', N'ALTER PROCEDURE');
    SET @Definicion = REPLACE(@Definicion, N'CREATE PROC ', N'ALTER PROC ');
    EXEC sp_executesql @Definicion;

    FETCH NEXT FROM ProcedimientosSpj INTO @Nombre, @Definicion;
END;

CLOSE ProcedimientosSpj;
DEALLOCATE ProcedimientosSpj;
GO

