-- Chat entre almacén y el técnico de cada ruta (Login General).
-- Compatible con SQL Server 2008 R2: sin CREATE OR ALTER, OFFSET/FETCH ni IIF.
-- Solo agrega objetos nuevos; no modifica tablas ni procedimientos existentes.
-- Aplicado a BDAlmacen el 2026-10-27.
--
-- Seguridad:
--   * El backend decide la ruta: el técnico solo puede usar la ruta de su token; el almacenero, cualquier ruta de su sucursal.
--   * El emisor (usuario, nombre y origen) lo pone el backend desde el token, nunca el cliente.
--   * Todo se llama con parámetros; aquí no se arma SQL dinámico.
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID(N'dbo.tbl_ChatRuta_Mensaje', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.tbl_ChatRuta_Mensaje
    (
        Id_Mensaje                  BIGINT IDENTITY(1,1) NOT NULL,
        Id_Ruta                     INT NOT NULL,
        Id_Usuario                  INT NOT NULL,
        Origen                      CHAR(1) NOT NULL,          -- 'A' almacén, 'T' técnico
        NombreEmisor                NVARCHAR(120) NOT NULL,
        Texto                       NVARCHAR(1000) NOT NULL,
        Id_PedidoVendedor_EnRuta    INT NULL,                  -- pedido al que se refiere el mensaje (opcional)
        Fecha_Registro              DATETIME NOT NULL
            CONSTRAINT DF_ChatRuta_Mensaje_Fecha DEFAULT (GETDATE()),

        CONSTRAINT PK_ChatRuta_Mensaje PRIMARY KEY CLUSTERED (Id_Mensaje),
        CONSTRAINT FK_ChatRuta_Mensaje_Ruta FOREIGN KEY (Id_Ruta) REFERENCES dbo.tbl_Ruta (Id_Ruta),
        CONSTRAINT FK_ChatRuta_Mensaje_Usuario FOREIGN KEY (Id_Usuario) REFERENCES dbo.tbl_Usuario (Id),
        CONSTRAINT FK_ChatRuta_Mensaje_Pedido FOREIGN KEY (Id_PedidoVendedor_EnRuta)
            REFERENCES dbo.tbl_PedidoVendedor_EnRuta (Id_PedidoVendedor_EnRuta),
        CONSTRAINT CK_ChatRuta_Mensaje_Origen CHECK (Origen IN ('A', 'T')),
        CONSTRAINT CK_ChatRuta_Mensaje_Texto CHECK (LEN(LTRIM(RTRIM(Texto))) BETWEEN 1 AND 1000)
    );
    CREATE NONCLUSTERED INDEX IX_ChatRuta_Mensaje_Ruta ON dbo.tbl_ChatRuta_Mensaje (Id_Ruta, Id_Mensaje)
        INCLUDE (Origen);
END;
GO

-- Hasta qué mensaje leyó cada lado de la conversación ('A' = almacén en conjunto, 'T' = técnico de la ruta)
IF OBJECT_ID(N'dbo.tbl_ChatRuta_Lectura', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.tbl_ChatRuta_Lectura
    (
        Id_Ruta             INT NOT NULL,
        Origen              CHAR(1) NOT NULL,
        Id_UltimoLeido      BIGINT NOT NULL,
        Fecha_Lectura       DATETIME NOT NULL
            CONSTRAINT DF_ChatRuta_Lectura_Fecha DEFAULT (GETDATE()),

        CONSTRAINT PK_ChatRuta_Lectura PRIMARY KEY CLUSTERED (Id_Ruta, Origen),
        CONSTRAINT FK_ChatRuta_Lectura_Ruta FOREIGN KEY (Id_Ruta) REFERENCES dbo.tbl_Ruta (Id_Ruta),
        CONSTRAINT CK_ChatRuta_Lectura_Origen CHECK (Origen IN ('A', 'T'))
    );
END;
GO

IF OBJECT_ID(N'dbo.spj_LoginGeneral_Chat_Listar', N'P') IS NOT NULL
    DROP PROCEDURE dbo.spj_LoginGeneral_Chat_Listar;
GO
-- Mensajes de una ruta. Con @DesdeId > 0 devuelve solo los nuevos; con 0, los últimos @Limite.
CREATE PROCEDURE dbo.spj_LoginGeneral_Chat_Listar
    @IdRuta INT,
    @DesdeId BIGINT,
    @Limite INT
AS
BEGIN
    SET NOCOUNT ON;
    IF @Limite IS NULL OR @Limite < 1 OR @Limite > 200 SET @Limite = 100;

    IF ISNULL(@DesdeId, 0) > 0
        SELECT TOP (@Limite)
            m.Id_Mensaje AS IdMensaje, m.Id_Ruta AS IdRuta, m.Id_Usuario AS IdUsuario, m.Origen,
            m.NombreEmisor, m.Texto, m.Id_PedidoVendedor_EnRuta AS IdPedido, m.Fecha_Registro AS Fecha
        FROM dbo.tbl_ChatRuta_Mensaje m
        WHERE m.Id_Ruta = @IdRuta AND m.Id_Mensaje > @DesdeId
        ORDER BY m.Id_Mensaje ASC;
    ELSE
        SELECT ultimos.*
        FROM
        (
            SELECT TOP (@Limite)
                m.Id_Mensaje AS IdMensaje, m.Id_Ruta AS IdRuta, m.Id_Usuario AS IdUsuario, m.Origen,
                m.NombreEmisor, m.Texto, m.Id_PedidoVendedor_EnRuta AS IdPedido, m.Fecha_Registro AS Fecha
            FROM dbo.tbl_ChatRuta_Mensaje m
            WHERE m.Id_Ruta = @IdRuta
            ORDER BY m.Id_Mensaje DESC
        ) ultimos
        ORDER BY ultimos.IdMensaje ASC;
END;
GO

IF OBJECT_ID(N'dbo.spj_LoginGeneral_Chat_Enviar', N'P') IS NOT NULL
    DROP PROCEDURE dbo.spj_LoginGeneral_Chat_Enviar;
GO
-- Registra un mensaje. Si la ruta no existe o el pedido no pertenece a la ruta, no inserta y no devuelve filas.
CREATE PROCEDURE dbo.spj_LoginGeneral_Chat_Enviar
    @IdRuta INT,
    @IdUsuario INT,
    @Origen CHAR(1),
    @NombreEmisor NVARCHAR(120),
    @Texto NVARCHAR(1000),
    @IdPedido INT
AS
BEGIN
    SET NOCOUNT ON;
    SET @Texto = LTRIM(RTRIM(@Texto));

    IF @Origen NOT IN ('A', 'T') OR LEN(ISNULL(@Texto, '')) = 0 RETURN;
    IF NOT EXISTS (SELECT 1 FROM dbo.tbl_Ruta WHERE Id_Ruta = @IdRuta) RETURN;
    IF @IdPedido IS NOT NULL AND NOT EXISTS
        (SELECT 1 FROM dbo.tbl_PedidoVendedor_EnRuta WHERE Id_PedidoVendedor_EnRuta = @IdPedido AND Id_Ruta = @IdRuta)
        RETURN;

    INSERT INTO dbo.tbl_ChatRuta_Mensaje (Id_Ruta, Id_Usuario, Origen, NombreEmisor, Texto, Id_PedidoVendedor_EnRuta)
    OUTPUT inserted.Id_Mensaje AS IdMensaje, inserted.Id_Ruta AS IdRuta, inserted.Id_Usuario AS IdUsuario,
           inserted.Origen, inserted.NombreEmisor, inserted.Texto, inserted.Id_PedidoVendedor_EnRuta AS IdPedido,
           inserted.Fecha_Registro AS Fecha
    VALUES (@IdRuta, @IdUsuario, @Origen, LEFT(@NombreEmisor, 120), @Texto, @IdPedido);
END;
GO

IF OBJECT_ID(N'dbo.spj_LoginGeneral_Chat_MarcarLeido', N'P') IS NOT NULL
    DROP PROCEDURE dbo.spj_LoginGeneral_Chat_MarcarLeido;
GO
-- Marca como leídos los mensajes de la ruta hasta @HastaId (nunca retrocede ni pasa del último mensaje real).
CREATE PROCEDURE dbo.spj_LoginGeneral_Chat_MarcarLeido
    @IdRuta INT,
    @Origen CHAR(1),
    @HastaId BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    IF @Origen NOT IN ('A', 'T') RETURN;
    DECLARE @Maximo BIGINT = (SELECT MAX(Id_Mensaje) FROM dbo.tbl_ChatRuta_Mensaje WHERE Id_Ruta = @IdRuta);
    IF @Maximo IS NULL RETURN;
    IF @HastaId > @Maximo SET @HastaId = @Maximo;

    MERGE dbo.tbl_ChatRuta_Lectura WITH (HOLDLOCK) AS destino
    USING (SELECT @IdRuta AS Id_Ruta, @Origen AS Origen) AS origen
        ON destino.Id_Ruta = origen.Id_Ruta AND destino.Origen = origen.Origen
    WHEN MATCHED AND destino.Id_UltimoLeido < @HastaId THEN
        UPDATE SET Id_UltimoLeido = @HastaId, Fecha_Lectura = GETDATE()
    WHEN NOT MATCHED THEN
        INSERT (Id_Ruta, Origen, Id_UltimoLeido) VALUES (@IdRuta, @Origen, @HastaId);
END;
GO

IF OBJECT_ID(N'dbo.spj_LoginGeneral_Chat_Resumen', N'P') IS NOT NULL
    DROP PROCEDURE dbo.spj_LoginGeneral_Chat_Resumen;
GO
-- Por ruta: mensajes del otro lado sin leer y último mensaje. @IdRuta NULL = todas las rutas con conversación.
CREATE PROCEDURE dbo.spj_LoginGeneral_Chat_Resumen
    @Lector CHAR(1),
    @IdRuta INT
AS
BEGIN
    SET NOCOUNT ON;
    IF @Lector NOT IN ('A', 'T') RETURN;
    DECLARE @Otro CHAR(1) = CASE WHEN @Lector = 'A' THEN 'T' ELSE 'A' END;

    SELECT
        r.Id_Ruta AS IdRuta,
        (SELECT COUNT(*) FROM dbo.tbl_ChatRuta_Mensaje m
          WHERE m.Id_Ruta = r.Id_Ruta AND m.Origen = @Otro AND m.Id_Mensaje > ISNULL(l.Id_UltimoLeido, 0)) AS NoLeidos,
        ultimo.Fecha AS UltimaFecha,
        ultimo.Texto AS UltimoTexto,
        ultimo.Origen AS UltimoOrigen
    FROM (SELECT DISTINCT Id_Ruta FROM dbo.tbl_ChatRuta_Mensaje WHERE @IdRuta IS NULL OR Id_Ruta = @IdRuta) r
    LEFT JOIN dbo.tbl_ChatRuta_Lectura l ON l.Id_Ruta = r.Id_Ruta AND l.Origen = @Lector
    OUTER APPLY
    (
        SELECT TOP 1 m.Fecha_Registro AS Fecha, LEFT(m.Texto, 140) AS Texto, m.Origen
        FROM dbo.tbl_ChatRuta_Mensaje m WHERE m.Id_Ruta = r.Id_Ruta ORDER BY m.Id_Mensaje DESC
    ) ultimo;
END;
GO
