# Backend — Login General

Backend Spring Boot para autenticación por sucursal.

## Flujo

1. Consulta las sucursales mediante `BDFacturasPreV.dbo.spx_LoginGeneral_ListarSucursales`.
2. Obtiene `IP`, `BD` y `Puerto` mediante `dbo.spx_LoginGeneral_ObtenerConexionSucursal`.
3. Abre una conexión a la base seleccionada usando las credenciales configuradas.
4. Convierte la contraseña a MD5 + Base64 y ejecuta `dbo.spx_LoginGeneral_ValidarUsuario` en la sucursal.
5. Si las credenciales son válidas, emite un JWT `HS256` con vigencia de ocho horas.

La configuración visible está en `src/main/resources/application.properties`.

## Procedimientos

- Central: `src/main/resources/db/login-general-procedures.sql`
- Cada sucursal: `src/main/resources/db/sucursal-login-procedure.sql`

## Desarrollo

```powershell
mvn spring-boot:run
```

API disponible en `http://localhost:8085`:

- `GET /api/status`
- `GET /api/auth/sucursales`
- `POST /api/auth/login`
- `GET /api/auth/me`
- `POST /api/auth/logout`
