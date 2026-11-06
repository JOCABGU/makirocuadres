package com.logingeneral.back.auth;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.time.Duration;
import java.time.Instant;
import java.util.Base64;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

import javax.sql.DataSource;

import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DataSourceTransactionManager;
import org.springframework.stereotype.Service;
import org.springframework.transaction.support.TransactionTemplate;
import org.springframework.web.server.ResponseStatusException;

@Service
public class PasswordResetService {
    public record UsuarioClave(int id, String nombre, String loggin, Integer rolId, String rol,
            boolean pendiente) {}
    public record RolClave(int id, String nombre) {}
    public record SolicitudResultado(int creadas, int yaPendientes) {}
    public record CambioRequest(String nuevaPassword, String confirmarPassword) {}
    public record SolicitudRequest(List<Integer> idsUsuario) {}

    // Se consulta en cada petición autenticada; se guarda unos segundos para no ir a la BD cada vez.
    // Las solicitudes y cambios hechos desde este backend invalidan la caché al instante.
    private static final Duration VIGENCIA_PENDIENTE = Duration.ofSeconds(60);

    private final CentralProcedureClient central;
    private final JwtService jwt;
    private final SucursalDataSourceProvider dataSources;
    private final Map<String, PendienteCacheado> pendientes = new ConcurrentHashMap<>();

    public PasswordResetService(CentralProcedureClient central, JwtService jwt,
            SucursalDataSourceProvider dataSources) {
        this.central = central;
        this.jwt = jwt;
        this.dataSources = dataSources;
    }

    public boolean pendiente(AuthDtos.UsuarioResponse usuario) {
        String clave = clavePendiente(usuario.sucursal().id(), usuario.id());
        PendienteCacheado cacheado = pendientes.get(clave);
        if (cacheado != null && cacheado.expira().isAfter(Instant.now())) {
            return cacheado.pendiente();
        }
        boolean pendiente = jdbc(usuario).queryForObject(
                "IF OBJECT_ID('dbo.ReinicioPassword', 'U') IS NULL SELECT 0 ELSE SELECT COUNT(1) FROM dbo.ReinicioPassword WHERE Id_Usuario = ? AND Estado = 1",
                Integer.class, usuario.id()) > 0;
        pendientes.put(clave, new PendienteCacheado(pendiente, Instant.now().plus(VIGENCIA_PENDIENTE)));
        return pendiente;
    }

    private static String clavePendiente(Integer idSucursal, Integer idUsuario) {
        return idSucursal + ":" + idUsuario;
    }

    private record PendienteCacheado(boolean pendiente, Instant expira) {}

    public AuthDtos.UsuarioResponse usuarioSinBloqueo(String authorization) {
        if (authorization == null || !authorization.startsWith("Bearer "))
            throw new ResponseStatusException(HttpStatus.UNAUTHORIZED, "Se requiere una sesión válida.");
        return jwt.parse(authorization.substring(7).trim());
    }

    private AuthDtos.UsuarioResponse exigirSistemas(String authorization) {
        var usuario = usuarioSinBloqueo(authorization);
        if (!"Sistemas".equalsIgnoreCase(usuario.rol()))
            throw new ResponseStatusException(HttpStatus.FORBIDDEN, "Se requiere el rol Sistemas.");
        if (pendiente(usuario))
            throw new ResponseStatusException(HttpStatus.LOCKED, "Primero debes cambiar tu contraseña.");
        return usuario;
    }

    public List<RolClave> roles(String authorization) {
        var usuario = exigirSistemas(authorization);
        return jdbc(usuario).query(
                "SELECT rol_id, nombre FROM dbo.Rol WHERE e_eliminado = 2 ORDER BY nombre",
                (rs, row) -> new RolClave(rs.getInt(1), rs.getString(2)));
    }

    public List<UsuarioClave> usuarios(String authorization, String buscar, Integer rolId) {
        var usuario = exigirSistemas(authorization);
        String filtro = buscar == null ? "" : buscar.trim();
        if (filtro.length() > 100)
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "La búsqueda es demasiado larga.");
        return jdbc(usuario).query("""
                SELECT u.Id, u.Nombre, u.Loggin, r.rol_id, r.nombre AS rol,
                       CASE WHEN p.Id_ReinicioPassword IS NULL THEN 0 ELSE 1 END AS pendiente
                FROM dbo.tbl_Usuario u
                LEFT JOIN dbo.Rol_Usuario ru ON ru.usuario_id = u.Id AND ru.e_eliminado = 2
                LEFT JOIN dbo.Rol r ON r.rol_id = ru.rol_id AND r.e_eliminado = 2
                LEFT JOIN dbo.ReinicioPassword p ON p.Id_Usuario = u.Id AND p.Estado = 1
                WHERE u.E_Eliminado = 2
                  AND (? IS NULL OR r.rol_id = ?)
                  AND (u.Nombre LIKE ? OR u.Loggin LIKE ?)
                ORDER BY u.Nombre, u.Id, r.nombre
                """, (rs, row) -> new UsuarioClave(rs.getInt("Id"), rs.getString("Nombre"),
                        rs.getString("Loggin"), (Integer) rs.getObject("rol_id"),
                        rs.getString("rol"), rs.getInt("pendiente") == 1),
                rolId, rolId, "%" + filtro + "%", "%" + filtro + "%");
    }

    public SolicitudResultado solicitar(String authorization, SolicitudRequest request) {
        var admin = exigirSistemas(authorization);
        if (request == null || request.idsUsuario() == null || request.idsUsuario().isEmpty()
                || request.idsUsuario().size() > 500)
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Selecciona entre 1 y 500 usuarios.");
        var ids = new LinkedHashSet<>(request.idsUsuario());
        if (ids.contains(null) || ids.stream().anyMatch(id -> id <= 0))
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "La selección contiene usuarios inválidos.");
        DataSource ds = dataSource(admin);
        SolicitudResultado resultado = new TransactionTemplate(new DataSourceTransactionManager(ds)).execute(status -> {
            int creadas = 0;
            int existentes = 0;
            Connection con = org.springframework.jdbc.datasource.DataSourceUtils.getConnection(ds);
            try {
                for (int id : ids) {
                    try (PreparedStatement user = con.prepareStatement(
                            "SELECT Id FROM dbo.tbl_Usuario WITH (UPDLOCK, HOLDLOCK) WHERE Id = ? AND E_Eliminado = 2")) {
                        user.setInt(1, id);
                        try (ResultSet rs = user.executeQuery()) {
                            if (!rs.next()) throw new ResponseStatusException(HttpStatus.CONFLICT,
                                    "Uno de los usuarios seleccionados ya no está activo.");
                        }
                    }
                    try (PreparedStatement pending = con.prepareStatement(
                            "SELECT Id_ReinicioPassword FROM dbo.ReinicioPassword WITH (UPDLOCK, HOLDLOCK) WHERE Id_Usuario = ? AND Estado = 1")) {
                        pending.setInt(1, id);
                        try (ResultSet rs = pending.executeQuery()) {
                            if (rs.next()) { existentes++; continue; }
                        }
                    }
                    try (PreparedStatement insert = con.prepareStatement(
                            "INSERT INTO dbo.ReinicioPassword (Id_Usuario, Id_UsuarioSolicita) VALUES (?, ?)")) {
                        insert.setInt(1, id);
                        insert.setInt(2, admin.id());
                        insert.executeUpdate();
                        creadas++;
                    }
                }
            } catch (SQLException ex) {
                throw new ResponseStatusException(HttpStatus.CONFLICT, "No se pudieron registrar todas las solicitudes.", ex);
            }
            return new SolicitudResultado(creadas, existentes);
        });
        ids.forEach(id -> pendientes.remove(clavePendiente(admin.sucursal().id(), id)));
        return resultado;
    }

    public Map<String, Boolean> estado(String authorization) {
        return Map.of("pendiente", pendiente(usuarioSinBloqueo(authorization)));
    }

    public void cambiar(String authorization, CambioRequest request) {
        var usuario = usuarioSinBloqueo(authorization);
        if (request == null || request.nuevaPassword() == null || request.confirmarPassword() == null
                || !request.nuevaPassword().equals(request.confirmarPassword())
                || request.nuevaPassword().length() < 8 || request.nuevaPassword().length() > 72)
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "La contraseña debe tener de 8 a 72 caracteres y coincidir con la confirmación.");
        String hash = hashMd5Base64(request.nuevaPassword());
        DataSource ds = dataSource(usuario);
        new TransactionTemplate(new DataSourceTransactionManager(ds)).executeWithoutResult(status -> {
            Connection con = org.springframework.jdbc.datasource.DataSourceUtils.getConnection(ds);
            try {
                int actualizadas;
                try (PreparedStatement update = con.prepareStatement("""
                        UPDATE dbo.tbl_Usuario SET Password = ?
                        WHERE Id = ? AND E_Eliminado = 2 AND Password <> ?
                          AND EXISTS (SELECT 1 FROM dbo.ReinicioPassword WITH (UPDLOCK, HOLDLOCK)
                                      WHERE Id_Usuario = ? AND Estado = 1)
                        """)) {
                    update.setString(1, hash);
                    update.setInt(2, usuario.id());
                    update.setString(3, hash);
                    update.setInt(4, usuario.id());
                    actualizadas = update.executeUpdate();
                }
                if (actualizadas != 1)
                    throw new ResponseStatusException(HttpStatus.CONFLICT,
                            "No hay un cambio pendiente o la nueva contraseña coincide con la actual.");
                try (PreparedStatement update = con.prepareStatement("""
                        UPDATE dbo.ReinicioPassword SET Estado = 2, FechaCompletado = GETDATE()
                        WHERE Id_Usuario = ? AND Estado = 1
                        """)) {
                    update.setInt(1, usuario.id());
                    if (update.executeUpdate() != 1)
                        throw new ResponseStatusException(HttpStatus.CONFLICT, "No se pudo completar la solicitud.");
                }
            } catch (SQLException ex) {
                throw new ResponseStatusException(HttpStatus.CONFLICT, "No se pudo cambiar la contraseña.", ex);
            }
        });
        pendientes.remove(clavePendiente(usuario.sucursal().id(), usuario.id()));
    }

    private JdbcTemplate jdbc(AuthDtos.UsuarioResponse usuario) { return new JdbcTemplate(dataSource(usuario)); }

    private DataSource dataSource(AuthDtos.UsuarioResponse usuario) {
        SucursalConnection sucursal = central.obtenerConexion(usuario.sucursal().id()).orElseThrow(() ->
                new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE, "Sucursal no disponible."));
        return dataSources.obtener(sucursal);
    }

    private static String hashMd5Base64(String value) {
        try {
            return Base64.getEncoder().encodeToString(
                    MessageDigest.getInstance("MD5").digest(value.getBytes(StandardCharsets.UTF_8)));
        } catch (NoSuchAlgorithmException ex) { throw new IllegalStateException(ex); }
    }
}
