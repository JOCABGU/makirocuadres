package com.logingeneral.back.auth;

import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

import javax.sql.DataSource;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import org.springframework.stereotype.Component;

import com.zaxxer.hikari.HikariConfig;
import com.zaxxer.hikari.HikariDataSource;

import jakarta.annotation.PreDestroy;

/**
 * Mantiene un pool de conexiones por cada base de sucursal, para no abrir una conexión
 * TCP + login de SQL Server en cada consulta.
 */
@Component
public class SucursalDataSourceProvider {

    private static final String DRIVER = "net.sourceforge.jtds.jdbc.Driver";

    private final String username;
    private final String password;
    private final String connectionParams;
    private final String connectionParamsCuadre;
    private final Map<String, HikariDataSource> pools = new ConcurrentHashMap<>();

    public SucursalDataSourceProvider(
            @Value("${app.sucursal.datasource.username}") String username,
            @Value("${app.sucursal.datasource.password}") String password,
            @Value("${app.sucursal.datasource.params}") String connectionParams,
            @Value("${app.sucursal.datasource.cuadre-socket-timeout-seconds:300}") int cuadreSocketTimeoutSegundos) {
        this.username = username;
        this.password = password;
        this.connectionParams = connectionParams;
        // El cierre del cuadre recorre miles de productos: usa un socketTimeout propio y mas amplio.
        String sinTimeout = connectionParams.replaceAll("(?i);?socketTimeout=\\d+", "");
        this.connectionParamsCuadre = sinTimeout + ";socketTimeout=" + cuadreSocketTimeoutSegundos;
    }

    public DataSource obtener(SucursalConnection sucursal) {
        return pool(sucursal, connectionParams, "general", 10);
    }

    public DataSource obtenerCuadre(SucursalConnection sucursal) {
        return pool(sucursal, connectionParamsCuadre, "cuadre", 5);
    }

    /**
     * Conexión sin pool, para operaciones que cambian opciones de sesión (SET XACT_ABORT, etc.).
     * jTDS no reinicia la sesión al reutilizar una conexión, así que esas opciones se heredarían.
     */
    public DataSource obtenerSinPool(SucursalConnection sucursal) {
        DriverManagerDataSource dataSource = new DriverManagerDataSource();
        dataSource.setDriverClassName(DRIVER);
        dataSource.setUrl(url(sucursal, connectionParams));
        dataSource.setUsername(username);
        dataSource.setPassword(password);
        return dataSource;
    }

    private DataSource pool(SucursalConnection sucursal, String parametros, String tipo, int maximo) {
        String url = url(sucursal, parametros);
        return pools.computeIfAbsent(url, ignored -> {
            HikariConfig config = new HikariConfig();
            config.setPoolName("sucursal-" + sucursal.id() + "-" + tipo);
            config.setDriverClassName(DRIVER);
            config.setJdbcUrl(url);
            config.setUsername(username);
            config.setPassword(password);
            config.setMaximumPoolSize(maximo);
            config.setMinimumIdle(0);
            config.setIdleTimeout(300_000);
            config.setMaxLifetime(1_800_000);
            config.setConnectionTimeout(20_000);
            config.setValidationTimeout(5_000);
            // jTDS no implementa Connection.isValid(): Hikari debe validar con una consulta.
            config.setConnectionTestQuery("SELECT 1");
            // No conectar al crear el pool: si la sucursal no responde, el error sale en la consulta.
            config.setInitializationFailTimeout(-1);
            return new HikariDataSource(config);
        });
    }

    private String url(SucursalConnection sucursal, String parametros) {
        return "jdbc:jtds:sqlserver://"
                + sucursal.host() + ":" + sucursal.port()
                + "/" + sucursal.database()
                + ";" + parametros;
    }

    @PreDestroy
    void cerrar() {
        pools.values().forEach(HikariDataSource::close);
    }
}
