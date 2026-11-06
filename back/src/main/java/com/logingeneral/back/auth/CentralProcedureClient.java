package com.logingeneral.back.auth;

import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.concurrent.ConcurrentHashMap;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;

import com.logingeneral.back.auth.AuthDtos.SucursalResponse;

@Component
public class CentralProcedureClient {

    // IP/BD/Puerto de una sucursal casi nunca cambian: se consultan como mucho cada 5 minutos.
    private static final Duration VIGENCIA_CONEXION = Duration.ofMinutes(5);

    private final JdbcTemplate jdbcTemplate;
    private final Map<Integer, ConexionCacheada> conexiones = new ConcurrentHashMap<>();

    public CentralProcedureClient(JdbcTemplate jdbcTemplate) {
        this.jdbcTemplate = jdbcTemplate;
    }

    public List<SucursalResponse> listarSucursalesActivas() {
        return jdbcTemplate.query(
                "EXEC dbo.spj_LoginGeneral_ListarSucursales",
                (rs, rowNum) -> new SucursalResponse(
                        rs.getInt("Id_Sucursal"),
                        rs.getString("Sucursal")));
    }

    public Optional<SucursalConnection> obtenerConexion(Integer idSucursal) {
        if (idSucursal == null) {
            return consultarConexion(null);
        }
        ConexionCacheada cacheada = conexiones.get(idSucursal);
        if (cacheada != null && cacheada.expira().isAfter(Instant.now())) {
            return Optional.of(cacheada.conexion());
        }
        Optional<SucursalConnection> conexion = consultarConexion(idSucursal);
        conexion.ifPresentOrElse(
                valor -> conexiones.put(
                        idSucursal, new ConexionCacheada(valor, Instant.now().plus(VIGENCIA_CONEXION))),
                () -> conexiones.remove(idSucursal));
        return conexion;
    }

    private Optional<SucursalConnection> consultarConexion(Integer idSucursal) {
        List<SucursalConnection> conexiones = jdbcTemplate.query(
                "EXEC dbo.spj_LoginGeneral_ObtenerConexionSucursal ?",
                (rs, rowNum) -> new SucursalConnection(
                        rs.getInt("Id_Sucursal"),
                        rs.getString("Sucursal"),
                        rs.getString("Agente"),
                        rs.getString("IP"),
                        rs.getString("BD"),
                        rs.getInt("Puerto")),
                idSucursal);
        return conexiones.stream().findFirst();
    }

    private record ConexionCacheada(SucursalConnection conexion, Instant expira) {
    }
}
