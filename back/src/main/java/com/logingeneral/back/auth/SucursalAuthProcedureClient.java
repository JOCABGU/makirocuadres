package com.logingeneral.back.auth;

import java.util.List;
import java.util.Optional;
import java.math.BigDecimal;
import java.util.Map;
import java.util.LinkedHashMap;

import javax.sql.DataSource;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;

import com.logingeneral.back.auth.AuthDtos.TecnicoResponse;
import com.logingeneral.back.auth.AlmacenDtos.PedidoTecnicoResponse;
import com.logingeneral.back.auth.AlmacenDtos.TecnicoPendientesResponse;
import com.logingeneral.back.auth.AlmacenDtos.PedidoPendienteAlmacenResponse;
import com.logingeneral.back.auth.AlmacenDtos.RutaPendientesResponse;
import com.logingeneral.back.auth.AlmacenDtos.AprobarPedidoResponse;
import com.logingeneral.back.auth.AlmacenDtos.ProductoFisicoPedidoResponse;
import com.logingeneral.back.auth.AlmacenDtos.ModificarDetallePedidoRequest;
import com.logingeneral.back.auth.AlmacenDtos.ModificarPedidoAlmacenResponse;
import com.logingeneral.back.auth.AlmacenDtos.CrearPedidoDirectoResponse;
import com.logingeneral.back.auth.AlmacenDtos.DetallePedidoDirectoRequest;
import com.logingeneral.back.auth.AlmacenDtos.ProductoFisicoDirectoRequest;
import com.logingeneral.back.auth.CierreAlmacenDtos.CierreAlmacenProductoResponse;
import com.logingeneral.back.auth.PedidoEnRutaDtos.CrearPedidoResponse;
import com.logingeneral.back.auth.PedidoEnRutaDtos.DetallePedidoRequest;
import com.logingeneral.back.auth.PedidoEnRutaDtos.DetallePedidoResponse;
import com.logingeneral.back.auth.PedidoEnRutaDtos.PedidoResumenResponse;
import com.logingeneral.back.auth.PedidoEnRutaDtos.ProductoPedidoResponse;
import com.logingeneral.back.auth.PedidoEnRutaDtos.PromedioVentaResponse;
import com.logingeneral.back.auth.PedidoEnRutaDtos.TipoProductoResponse;
import com.logingeneral.back.auth.SaldoRutaDtos.SaldoProducto;
import com.logingeneral.back.auth.SaldoRutaDtos.SaldoRutaResponse;
import com.logingeneral.back.auth.EstadisticasAlmacenDtos.EstadisticaPedidosDiaRutaResponse;
import com.logingeneral.back.auth.EstadisticasAlmacenDtos.EstadisticaCuadreProductoResponse;
import com.logingeneral.back.auth.EstadisticasAlmacenDtos.EstadisticaVendedorResponse;
import com.logingeneral.back.auth.EstadisticasAlmacenDtos.EstadisticaConsumoProductoDiaResponse;
import com.logingeneral.back.auth.EstadisticasAlmacenDtos.EstadisticaDemoraCajaResponse;
import com.logingeneral.back.auth.CuadreDtos.ProductoCuadreResponse;
import com.logingeneral.back.auth.CuadreDtos.EstadoCuadreHoyResponse;
import com.logingeneral.back.auth.CuadreDtos.ImeiCuadreValidacion;
import com.logingeneral.back.auth.CuadreDtos.ValidacionCuadreResponse;
import com.logingeneral.back.auth.CuadreDtos.TiraCuadreRequest;
import com.logingeneral.back.auth.CuadreDtos.FinalizarCuadreResponse;
import com.logingeneral.back.auth.CuadreAlmacenDtos.RutaCuadreResponse;
import com.logingeneral.back.auth.CuadreAlmacenDtos.DetalleCuadreAlmacenResponse;
import com.logingeneral.back.auth.CuadreAlmacenDtos.ProductoCuadreAlmacenResponse;
import com.logingeneral.back.auth.CuadreAlmacenDtos.TiraCuadreAlmacenResponse;
import com.logingeneral.back.auth.CuadreEnRutaDtos.ResumenCuadreEnRutaResponse;
import com.logingeneral.back.auth.CuadreEnRutaDtos.DetalleCuadreEnRutaResponse;
import com.logingeneral.back.auth.CuadreEnRutaDtos.ProductoCuadreEnRutaResponse;
import com.logingeneral.back.scanner.ProductoScanDtos.ProductoValidacion;
import com.logingeneral.back.scanner.ProductoScanDtos.ProductoPedidoValidacion;
import com.logingeneral.back.auth.AlmacenDtos.ProductoFisicoAsignadoRequest;
import com.logingeneral.back.auth.DepositoEnRutaDtos.EntidadResponse;
import com.logingeneral.back.auth.DepositoEnRutaDtos.RegistrarDepositoResponse;
import com.logingeneral.back.auth.DepositoEnRutaDtos.DepositoResponse;
import com.logingeneral.back.auth.DepositoEnRutaDtos.DepositoContabilidadResponse;

@Component
public class SucursalAuthProcedureClient {

    private final SucursalDataSourceProvider dataSources;

    public SucursalAuthProcedureClient(SucursalDataSourceProvider dataSources) {
        this.dataSources = dataSources;
    }

    public Optional<SucursalUser> autenticar(
            SucursalConnection sucursal,
            String login,
            String passwordHash) {
        JdbcTemplate jdbcTemplate = new JdbcTemplate(crearDataSource(sucursal));
        List<SucursalUser> usuarios = jdbcTemplate.query(
                "EXEC dbo.spj_LoginGeneral_ValidarUsuario ?, ?",
                (rs, rowNum) -> new SucursalUser(
                        rs.getInt("Id"),
                        rs.getString("Nombre"),
                        rs.getString("Loggin"),
                        nullableInt(rs, "IdRol"),
                        optionalString(rs, "Rol", "Tecnico")),
                login,
                passwordHash);
        return usuarios.stream().findFirst();
    }

    public TecnicoResponse obtenerTecnico(SucursalConnection sucursal, Integer idUsuario) {
        JdbcTemplate jdbcTemplate = new JdbcTemplate(crearDataSource(sucursal));
        List<TecnicoResponse> resultados = jdbcTemplate.query(
                "EXEC dbo.spj_LoginGeneral_ObtenerTecnicoPorUsuario ?",
                (rs, rowNum) -> new TecnicoResponse(
                        rs.getBoolean("EsTecnico"),
                        nullableInt(rs, "IdUsuarioTecnico"),
                        nullableInt(rs, "IdVendedor"),
                        nullableInt(rs, "IdRuta"),
                        rs.getString("NombreRuta"),
                        rs.getString("NombreTecnico"),
                        rs.getString("CI"),
                        rs.getString("Telefono"),
                        rs.getString("Direccion"),
                        rs.getString("Observacion")),
                idUsuario);
        return resultados.stream().findFirst()
                .orElseGet(() -> new TecnicoResponse(
                        false, null, null, null, null, null, null, null, null, null));
    }

    public List<SaldoProducto> obtenerSaldoRuta(SucursalConnection sucursal, Integer idRuta) {
        JdbcTemplate jdbcTemplate = new JdbcTemplate(crearDataSource(sucursal));
        return jdbcTemplate.query(
                "EXEC dbo.spj_LoginGeneral_ObtenerSaldoRuta ?",
                (rs, rowNum) -> {
                    int cantidad = rs.getInt("Cantidad");
                    BigDecimal precio = rs.getBigDecimal("PrecioVenta");
                    if (precio == null) {
                        precio = BigDecimal.ZERO;
                    }
                    return new SaldoProducto(
                            rs.getInt("Id_Producto"),
                            rs.getString("Producto"),
                            cantidad,
                            rs.getString("TipoProducto"),
                            precio,
                            precio.multiply(BigDecimal.valueOf(cantidad)));
                },
                idRuta);
    }

    public List<ProductoCuadreResponse> listarProductosCuadre(
            SucursalConnection sucursal,
            Integer idRuta) {
        return new JdbcTemplate(crearDataSource(sucursal)).query(
                "EXEC dbo.spj_LoginGeneral_Cuadre_ListarProductos ?",
                (rs, rowNum) -> new ProductoCuadreResponse(
                        rs.getInt("IdProducto"),
                        rs.getString("Producto"),
                        rs.getString("TipoProducto"),
                        rs.getInt("CantidadAsignada")),
                idRuta);
    }

    public EstadoCuadreHoyResponse obtenerEstadoCuadreHoy(
            SucursalConnection sucursal,
            Integer idRuta) {
        return new JdbcTemplate(crearDataSource(sucursal)).query(
                "EXEC dbo.spj_LoginGeneral_Cuadre_ObtenerHoy ?",
                (rs, rowNum) -> {
                    var fecha = rs.getTimestamp("Fecha");
                    return new EstadoCuadreHoyResponse(
                            rs.getBoolean("Existe"),
                            nullableInt(rs, "IdCuadre"),
                            nullableInt(rs, "IdRuta"),
                            fecha == null ? null : fecha.toLocalDateTime(),
                            false, null, false);
                },
                idRuta).stream().findFirst()
                .orElse(new EstadoCuadreHoyResponse(false, null, idRuta, null, false, null, false));
    }

    public EstadoCuadreHoyResponse obtenerEstadoCuadreEnRutaHoy(
            SucursalConnection sucursal, Integer idRuta) {
        return new JdbcTemplate(crearDataSource(sucursal)).query(
                "EXEC dbo.spj_LoginGeneral_CuadreEnRuta_ObtenerHoy ?",
                (rs, rowNum) -> {
                    var fecha = rs.getTimestamp("Fecha");
                    return new EstadoCuadreHoyResponse(
                            rs.getBoolean("Existe"), nullableInt(rs, "IdCuadre"),
                            nullableInt(rs, "IdRuta"), fecha == null ? null : fecha.toLocalDateTime(),
                            rs.getBoolean("EsPreliminar"), nullableInt(rs, "EstadoAprobado"),
                            rs.getBoolean("Modificado"));
                }, idRuta).stream().findFirst()
                .orElse(new EstadoCuadreHoyResponse(false, null, idRuta, null, true, null, false));
    }

    public ValidacionCuadreResponse validarImeisCuadre(
            SucursalConnection sucursal,
            Integer idRuta,
            Integer idProducto,
            List<String> imeis) {
        StringBuilder xml = new StringBuilder("<imeis>");
        imeis.forEach(imei -> xml.append("<i v=\"").append(imei).append("\"/>"));
        xml.append("</imeis>");
        List<ImeiCuadreValidacion> resultados = new JdbcTemplate(crearDataSourceCuadre(sucursal)).query(
                "EXEC dbo.spj_LoginGeneral_Cuadre_ValidarImeis ?, ?, ?",
                (rs, rowNum) -> new ImeiCuadreValidacion(
                        rs.getString("Imei"),
                        rs.getBoolean("Existe"),
                        nullableInt(rs, "IdRuta"),
                        nullableInt(rs, "Vendido"),
                        nullableInt(rs, "IdProductoEncontrado"),
                        rs.getString("ProductoEncontrado"),
                        rs.getInt("IdProductoEsperado"),
                        rs.getString("ProductoEsperado"),
                        rs.getBoolean("Valido"),
                        rs.getString("Motivo")),
                idRuta, idProducto, xml.toString());
        int validos = (int) resultados.stream().filter(ImeiCuadreValidacion::valido).count();
        return new ValidacionCuadreResponse(
                resultados.size(), validos, validos == resultados.size(), resultados);
    }

    public FinalizarCuadreResponse finalizarCuadre(
            SucursalConnection sucursal,
            Integer idRuta,
            Integer idVendedor,
            Integer idUsuario,
            String observacion,
            List<TiraCuadreRequest> tiras) {
        String xml = crearTirasXml(tiras);
        return new JdbcTemplate(crearDataSourceCuadre(sucursal)).query(
                "EXEC dbo.spj_LoginGeneral_Cuadre_Finalizar ?, ?, ?, ?, ?",
                (rs, rowNum) -> new FinalizarCuadreResponse(
                        rs.getInt("IdCuadre"),
                        rs.getInt("IdRuta"),
                        rs.getTimestamp("Fecha").toLocalDateTime(),
                        rs.getInt("TotalSobrantes"),
                        rs.getInt("TotalVendidos"),
                        rs.getBigDecimal("Total")),
                idRuta, idVendedor, idUsuario, observacion, xml).stream().findFirst()
                .orElseThrow(() -> new IllegalStateException("El procedimiento no devolvio el cuadre creado."));
    }

    public FinalizarCuadreResponse crearCuadreEnRuta(
            SucursalConnection sucursal, Integer idRuta, Integer idVendedor,
            Integer idUsuario, String observacion, List<TiraCuadreRequest> tiras) {
        return new JdbcTemplate(crearDataSourceCuadre(sucursal)).query(
                "EXEC dbo.spj_LoginGeneral_CuadreEnRuta_Crear ?, ?, ?, ?, ?",
                (rs, rowNum) -> new FinalizarCuadreResponse(
                        rs.getInt("IdCuadre"), rs.getInt("IdRuta"),
                        rs.getTimestamp("Fecha").toLocalDateTime(),
                        rs.getInt("TotalSobrantes"), rs.getInt("TotalVendidos"),
                        rs.getBigDecimal("Total")),
                idRuta, idVendedor, idUsuario, observacion, crearTirasXml(tiras))
                .stream().findFirst()
                .orElseThrow(() -> new IllegalStateException("El procedimiento no devolvio el cuadre preliminar."));
    }

    private String crearTirasXml(List<TiraCuadreRequest> tiras) {
        StringBuilder xml = new StringBuilder("<tiras>");
        for (TiraCuadreRequest tira : tiras) {
            xml.append("<tira producto=\"").append(tira.idProducto())
                    .append("\" numero=\"").append(tira.numeroTira())
                    .append("\" modo=\"").append(tira.modo())
                    .append("\" cantidad=\"").append(tira.cantidadManual() == null ? 0 : tira.cantidadManual())
                    .append("\" efectivizacion=\"").append(tira.cantidadEfectivizada() == null ? 0 : tira.cantidadEfectivizada())
                    .append("\">");
            tira.imeis().forEach(imei -> xml.append("<i v=\"").append(imei).append("\"/>"));
            xml.append("</tira>");
        }
        return xml.append("</tiras>").toString();
    }

    public List<RutaCuadreResponse> listarRutasCuadreAlmacen(
            SucursalConnection sucursal,
            java.time.LocalDate fecha) {
        return new JdbcTemplate(crearDataSource(sucursal)).query(
                "EXEC dbo.spj_LoginGeneral_Almacen_Cuadre_ListarRutas ?",
                (rs, rowNum) -> {
                    var fechaCuadre = rs.getTimestamp("FechaCuadre");
                    return new RutaCuadreResponse(
                            rs.getInt("IdRuta"),
                            rs.getString("Ruta"),
                            nullableInt(rs, "IdVendedor"),
                            rs.getString("Tecnico"),
                            rs.getBoolean("RealizoCuadre"),
                            nullableInt(rs, "IdCuadre"),
                            fechaCuadre == null ? null : fechaCuadre.toLocalDateTime(),
                            rs.getBigDecimal("Total"));
                },
                java.sql.Date.valueOf(fecha));
    }

    public DetalleCuadreAlmacenResponse obtenerDetalleCuadreAlmacen(
            SucursalConnection sucursal,
            Integer idCuadre) {
        List<FilaDetalleCuadreAlmacen> filas = new JdbcTemplate(crearDataSource(sucursal)).query(
                "EXEC dbo.spj_LoginGeneral_Almacen_Cuadre_ObtenerDetalle ?",
                (rs, rowNum) -> new FilaDetalleCuadreAlmacen(
                        rs.getInt("IdCuadre"), rs.getInt("IdRuta"), rs.getString("Ruta"),
                        nullableInt(rs, "IdVendedor"), rs.getString("Tecnico"),
                        rs.getTimestamp("Fecha").toLocalDateTime(), rs.getString("Observacion"),
                        rs.getBigDecimal("Total"), rs.getInt("IdProducto"), rs.getString("Producto"),
                        rs.getString("TipoProducto"), rs.getInt("SaldoAnterior"),
                        rs.getInt("SobranteIngresado"), rs.getInt("Vendido"),
                        rs.getInt("SaldoActual"), rs.getBigDecimal("Precio"),
                        rs.getBigDecimal("TotalVendido"), nullableInt(rs, "IdSaldoCuadre"),
                        nullableInt(rs, "CantidadTira"), rs.getString("CodigoInicio"),
                        rs.getString("CodigoFinal")),
                idCuadre);
        if (filas.isEmpty()) {
            throw new org.springframework.web.server.ResponseStatusException(
                    org.springframework.http.HttpStatus.NOT_FOUND, "El cuadre no existe o esta eliminado.");
        }
        FilaDetalleCuadreAlmacen cabecera = filas.get(0);
        Map<Integer, List<FilaDetalleCuadreAlmacen>> porProducto = new LinkedHashMap<>();
        filas.forEach(fila -> porProducto.computeIfAbsent(fila.idProducto(), key -> new java.util.ArrayList<>()).add(fila));
        List<ProductoCuadreAlmacenResponse> productos = porProducto.values().stream().map(grupo -> {
            FilaDetalleCuadreAlmacen producto = grupo.get(0);
            List<TiraCuadreAlmacenResponse> tiras = grupo.stream()
                    .filter(fila -> fila.idSaldoCuadre() != null)
                    .map(fila -> new TiraCuadreAlmacenResponse(
                            fila.idSaldoCuadre(), fila.cantidadTira(),
                            fila.codigoInicio(), fila.codigoFinal()))
                    .toList();
            return new ProductoCuadreAlmacenResponse(
                    producto.idProducto(), producto.producto(), producto.tipoProducto(),
                    producto.saldoAnterior(), producto.sobranteIngresado(), producto.vendido(),
                    producto.saldoActual(), producto.precio(), producto.totalVendido(), tiras);
        }).toList();
        return new DetalleCuadreAlmacenResponse(
                cabecera.idCuadre(), cabecera.idRuta(), cabecera.ruta(), cabecera.idVendedor(),
                cabecera.tecnico(), cabecera.fecha(), cabecera.observacion(), cabecera.total(), productos);
    }

    private record FilaDetalleCuadreAlmacen(
            Integer idCuadre, Integer idRuta, String ruta, Integer idVendedor, String tecnico,
            java.time.LocalDateTime fecha, String observacion, BigDecimal total,
            Integer idProducto, String producto, String tipoProducto, Integer saldoAnterior,
            Integer sobranteIngresado, Integer vendido, Integer saldoActual, BigDecimal precio,
            BigDecimal totalVendido, Integer idSaldoCuadre, Integer cantidadTira,
            String codigoInicio, String codigoFinal) {
    }

    public List<ResumenCuadreEnRutaResponse> listarCuadresEnRutaAlmacen(
            SucursalConnection sucursal, java.time.LocalDate fecha) {
        return new JdbcTemplate(crearDataSource(sucursal)).query(
                "EXEC dbo.spj_LoginGeneral_Almacen_CuadreEnRuta_Listar ?",
                (rs, rowNum) -> {
                    var aprobacion = rs.getTimestamp("FechaAprobacion");
                    return new ResumenCuadreEnRutaResponse(
                            rs.getInt("IdCuadreEnRuta"), rs.getInt("IdRuta"), rs.getString("Ruta"),
                            nullableInt(rs, "IdVendedor"), rs.getString("Tecnico"), nullableInt(rs, "IdUsuario"),
                            rs.getTimestamp("Fecha").toLocalDateTime(), rs.getString("Observacion"),
                            rs.getBigDecimal("Total"), nullableInt(rs, "EstadoAprobado"),
                            rs.getString("AprobadoPor"), nullableInt(rs, "IdCuadre"), rs.getBoolean("Modificado"),
                            aprobacion == null ? null : aprobacion.toLocalDateTime());
                }, java.sql.Date.valueOf(fecha));
    }

    public DetalleCuadreEnRutaResponse obtenerDetalleCuadreEnRutaAlmacen(
            SucursalConnection sucursal, Integer idCuadreEnRuta) {
        List<FilaCuadreEnRuta> filas = new JdbcTemplate(crearDataSource(sucursal)).query(
                "EXEC dbo.spj_LoginGeneral_Almacen_CuadreEnRuta_Detalle ?",
                (rs, rowNum) -> {
                    var aprobacion = rs.getTimestamp("FechaAprobacion");
                    return new FilaCuadreEnRuta(
                            rs.getInt("IdCuadreEnRuta"), rs.getInt("IdRuta"), rs.getString("Ruta"),
                            nullableInt(rs, "IdVendedor"), rs.getString("Tecnico"), nullableInt(rs, "IdUsuario"),
                            rs.getTimestamp("Fecha").toLocalDateTime(), rs.getString("Observacion"),
                            rs.getBigDecimal("Total"), nullableInt(rs, "EstadoAprobado"),
                            rs.getString("AprobadoPor"), nullableInt(rs, "IdCuadre"), rs.getBoolean("Modificado"),
                            aprobacion == null ? null : aprobacion.toLocalDateTime(), rs.getString("TirasXml"),
                            rs.getInt("Id_Producto"), rs.getString("Producto"), rs.getString("TipoProducto"),
                            rs.getInt("ItemsSobrantes"), rs.getInt("ItemsVendidos"),
                            rs.getBigDecimal("Precio"), rs.getBigDecimal("TotalVendidos"));
                }, idCuadreEnRuta);
        if (filas.isEmpty()) {
            throw new org.springframework.web.server.ResponseStatusException(
                    org.springframework.http.HttpStatus.NOT_FOUND, "El cuadre preliminar no existe.");
        }
        FilaCuadreEnRuta h = filas.get(0);
        List<ProductoCuadreEnRutaResponse> productos = filas.stream().map(f -> new ProductoCuadreEnRutaResponse(
                f.idProducto(), f.producto(), f.tipoProducto(), f.itemsSobrantes(), f.itemsVendidos(),
                f.precio(), f.totalVendidos())).toList();
        DetalleCuadreAlmacenResponse definitiva = h.idCuadre() == null || h.idCuadre() == 0
                ? null : obtenerDetalleCuadreAlmacen(sucursal, h.idCuadre());
        return new DetalleCuadreEnRutaResponse(
                h.idCuadreEnRuta(), h.idRuta(), h.ruta(), h.idVendedor(), h.tecnico(), h.idUsuario(),
                h.fecha(), h.observacion(), h.total(), h.estadoAprobado(), h.aprobadoPor(), h.idCuadre(),
                h.modificado(), h.fechaAprobacion(), h.tirasXml(), productos, definitiva);
    }

    public FinalizarCuadreResponse aprobarCuadreEnRuta(
            SucursalConnection sucursal, Integer idCuadreEnRuta, String aprobadoPor,
            boolean modificado, List<TiraCuadreRequest> tirasModificadas) {
        String xml = modificado ? crearTirasXml(tirasModificadas) : null;
        return new JdbcTemplate(crearDataSourceCuadre(sucursal)).query(
                "EXEC dbo.spj_LoginGeneral_Almacen_CuadreEnRuta_Aprobar ?, ?, ?, ?",
                (rs, rowNum) -> new FinalizarCuadreResponse(
                        rs.getInt("IdCuadre"), rs.getInt("IdRuta"), rs.getTimestamp("Fecha").toLocalDateTime(),
                        rs.getInt("TotalSobrantes"), rs.getInt("TotalVendidos"), rs.getBigDecimal("Total")),
                idCuadreEnRuta, aprobadoPor, modificado, xml).stream().findFirst()
                .orElseThrow(() -> new IllegalStateException("El procedimiento no devolvio el cuadre aprobado."));
    }

    private record FilaCuadreEnRuta(
            Integer idCuadreEnRuta, Integer idRuta, String ruta, Integer idVendedor, String tecnico,
            Integer idUsuario, java.time.LocalDateTime fecha, String observacion, BigDecimal total,
            Integer estadoAprobado, String aprobadoPor, Integer idCuadre, boolean modificado,
            java.time.LocalDateTime fechaAprobacion, String tirasXml, Integer idProducto,
            String producto, String tipoProducto, Integer itemsSobrantes, Integer itemsVendidos,
            BigDecimal precio, BigDecimal totalVendidos) {
    }

    public Map<String, ProductoValidacion> validarProductosParaTira(
            SucursalConnection sucursal,
            List<Long> imeis) {
        JdbcTemplate jdbcTemplate = new JdbcTemplate(crearDataSource(sucursal));
        StringBuilder xml = new StringBuilder("<imeis>");
        for (Long imei : imeis) {
            xml.append("<i v=\"").append(imei).append("\"/>");
        }
        xml.append("</imeis>");
        Map<String, ProductoValidacion> encontrados = new LinkedHashMap<>();
        jdbcTemplate.query(
                "EXEC dbo.spj_LoginGeneral_Scanner_ValidarImeis ?",
                rs -> {
                    String imei = rs.getString("Imei");
                    Integer idRuta = nullableInt(rs, "IdRuta");
                    Integer vendido = nullableInt(rs, "Vendido");
                    boolean existe = rs.getBoolean("Existe");
                    boolean valido = rs.getBoolean("Valido");
                    encontrados.put(imei, new ProductoValidacion(
                            imei, existe, idRuta, vendido, valido, rs.getString("Motivo")));
                },
                xml.toString());
        return encontrados;
    }

    public Map<String, ProductoPedidoValidacion> validarProductosParaPedido(
            SucursalConnection sucursal,
            Integer idPedido,
            Integer idDetalle,
            List<Long> imeis) {
        JdbcTemplate jdbcTemplate = new JdbcTemplate(crearDataSource(sucursal));
        StringBuilder xml = new StringBuilder("<imeis>");
        for (Long imei : imeis) {
            xml.append("<i v=\"").append(imei).append("\"/>");
        }
        xml.append("</imeis>");
        Map<String, ProductoPedidoValidacion> encontrados = new LinkedHashMap<>();
        jdbcTemplate.query(
                "EXEC dbo.spj_LoginGeneral_Scanner_ValidarImeisPedido ?, ?, ?",
                rs -> {
                    String imei = rs.getString("Imei");
                    encontrados.put(imei, new ProductoPedidoValidacion(
                            imei,
                            rs.getBoolean("Existe"),
                            nullableInt(rs, "IdRuta"),
                            nullableInt(rs, "Vendido"),
                            nullableInt(rs, "IdProductoEncontrado"),
                            rs.getString("ProductoEncontrado"),
                            rs.getInt("IdProductoEsperado"),
                            rs.getString("ProductoEsperado"),
                            rs.getInt("CantidadSolicitada"),
                            rs.getBoolean("Valido"),
                            rs.getString("Motivo")));
                },
                idPedido,
                idDetalle,
                xml.toString());
        return encontrados;
    }

    public Map<String, ProductoPedidoValidacion> validarProductosPedidoDirecto(
            SucursalConnection sucursal, Integer idProducto, Integer cantidadSolicitada, List<Long> imeis) {
        StringBuilder xml = new StringBuilder("<imeis>");
        for (Long imei : imeis) xml.append("<i v=\"").append(imei).append("\"/>");
        xml.append("</imeis>");
        Map<String, ProductoPedidoValidacion> encontrados = new LinkedHashMap<>();
        new JdbcTemplate(crearDataSource(sucursal)).query(
                "EXEC dbo.spj_LoginGeneral_Scanner_ValidarImeisPedidoDirecto ?, ?, ?",
                rs -> {
                    String imei = rs.getString("Imei");
                    encontrados.put(imei, new ProductoPedidoValidacion(
                            imei, rs.getBoolean("Existe"), nullableInt(rs,"IdRuta"), nullableInt(rs,"Vendido"),
                            nullableInt(rs,"IdProductoEncontrado"), rs.getString("ProductoEncontrado"),
                            rs.getInt("IdProductoEsperado"), rs.getString("ProductoEsperado"),
                            rs.getInt("CantidadSolicitada"), rs.getBoolean("Valido"), rs.getString("Motivo")));
                }, idProducto, cantidadSolicitada, xml.toString());
        return encontrados;
    }

    public Map<String, com.logingeneral.back.auth.AlmacenDtos.ImeiDirectoValidacionResponse> identificarImeisPedidoDirecto(
            SucursalConnection sucursal, List<Long> imeis) {
        if (imeis.isEmpty()) return Map.of();
        String placeholders = String.join(",", java.util.Collections.nCopies(imeis.size(), "?"));
        String sql = "SELECT CONVERT(VARCHAR(25), f.Imei) Imei, f.Id_Producto IdProducto, p.Nombre Producto "
                + "FROM dbo.tbl_Productos f WITH (INDEX(IX_tbl_Productos_Imei_Disponibilidad)) "
                + "JOIN dbo.tbl_Producto p ON p.Id_Producto=f.Id_Producto WHERE f.Imei IN (" + placeholders + ")";
        Map<String, com.logingeneral.back.auth.AlmacenDtos.ImeiDirectoValidacionResponse> encontrados = new LinkedHashMap<>();
        new JdbcTemplate(crearDataSource(sucursal)).query(sql, rs -> {
            String imei = rs.getString("Imei");
            encontrados.put(imei, new com.logingeneral.back.auth.AlmacenDtos.ImeiDirectoValidacionResponse(
                    imei, rs.getInt("IdProducto"), rs.getString("Producto"), false, "Pendiente de validar."));
        }, imeis.toArray());
        return encontrados;
    }

    public void reservarContextoScanner(
            SucursalConnection sucursal,
            Integer idPedido,
            Integer idDetalle,
            String tokenVinculacion,
            Integer idUsuario,
            List<Long> imeisConservar) {
        StringBuilder xml = new StringBuilder("<imeis>");
        for (Long imei : imeisConservar) {
            xml.append("<i v=\"").append(imei).append("\"/>");
        }
        xml.append("</imeis>");
        new JdbcTemplate(crearDataSource(sucursal)).query(
                "EXEC dbo.spj_LoginGeneral_Scanner_ReservarContexto ?, ?, ?, ?, ?",
                rs -> { },
                idPedido,
                idDetalle,
                tokenVinculacion,
                idUsuario,
                xml.toString());
    }

    public Map<String, ProductoPedidoValidacion> validarYReservarProductosParaPedido(
            SucursalConnection sucursal,
            Integer idPedido,
            Integer idDetalle,
            String tokenVinculacion,
            Integer idUsuario,
            List<Long> imeis) {
        StringBuilder xml = new StringBuilder("<imeis>");
        for (Long imei : imeis) {
            xml.append("<i v=\"").append(imei).append("\"/>");
        }
        xml.append("</imeis>");
        Map<String, ProductoPedidoValidacion> encontrados = new LinkedHashMap<>();
        new JdbcTemplate(crearDataSource(sucursal)).query(
                "EXEC dbo.spj_LoginGeneral_Scanner_ValidarYReservarImeisPedido ?, ?, ?, ?, ?",
                rs -> {
                    String imei = rs.getString("Imei");
                    encontrados.put(imei, new ProductoPedidoValidacion(
                            imei,
                            rs.getBoolean("Existe"),
                            nullableInt(rs, "IdRuta"),
                            nullableInt(rs, "Vendido"),
                            nullableInt(rs, "IdProductoEncontrado"),
                            rs.getString("ProductoEncontrado"),
                            rs.getInt("IdProductoEsperado"),
                            rs.getString("ProductoEsperado"),
                            rs.getInt("CantidadSolicitada"),
                            rs.getBoolean("Valido"),
                            rs.getString("Motivo")));
                },
                idPedido,
                idDetalle,
                tokenVinculacion,
                idUsuario,
                xml.toString());
        return encontrados;
    }

    public void liberarReservasScanner(
            SucursalConnection sucursal,
            String tokenVinculacion,
            Integer idUsuario,
            Integer idPedido) {
        new JdbcTemplate(crearDataSource(sucursal)).update(
                "EXEC dbo.spj_LoginGeneral_Scanner_LiberarReservas ?, ?, ?",
                tokenVinculacion,
                idUsuario,
                idPedido);
    }

    public CrearPedidoResponse crearPedidoEnRuta(
            SucursalConnection sucursal,
            Integer idRuta,
            Integer idVendedor,
            Integer idUsuario,
            List<DetallePedidoRequest> detalles,
            String observacion) {
        JdbcTemplate jdbcTemplate = new JdbcTemplate(crearDataSource(sucursal));
        StringBuilder xml = new StringBuilder("<pedido>");
        for (DetallePedidoRequest detalle : detalles) {
            xml.append("<item idProducto=\"")
                    .append(detalle.idProducto())
                    .append("\" cantidad=\"")
                    .append(detalle.cantidad())
                    .append("\"/>");
        }
        xml.append("</pedido>");
        return jdbcTemplate.query(
                "EXEC dbo.spj_LoginGeneral_CrearPedidoEnRuta ?, ?, ?, ?, ?",
                (rs, rowNum) -> new CrearPedidoResponse(
                        rs.getInt("IdPedido"),
                        rs.getInt("CantidadProductos"),
                        rs.getInt("CantidadUnidades"),
                        rs.getBigDecimal("Total"),
                        rs.getTimestamp("FechaRegistro").toLocalDateTime(),
                        rs.getInt("EstadoAprobado")),
                idRuta,
                idVendedor,
                idUsuario,
                xml.toString(),
                observacion).stream().findFirst()
                .orElseThrow(() -> new IllegalStateException("El procedimiento no devolvió el pedido creado."));
    }

    public List<TipoProductoResponse> listarTiposProducto(SucursalConnection sucursal) {
        return new JdbcTemplate(crearDataSource(sucursal)).query(
                "EXEC dbo.spj_LoginGeneral_ListarTiposProducto",
                (rs, rowNum) -> new TipoProductoResponse(
                        rs.getInt("Id_TipoProducto"),
                        rs.getString("Nombre")));
    }

    public List<ProductoPedidoResponse> listarProductosPorTipo(
            SucursalConnection sucursal,
            Integer idTipoProducto) {
        return new JdbcTemplate(crearDataSource(sucursal)).query(
                "EXEC dbo.spj_LoginGeneral_ListarProductosPorTipo ?",
                (rs, rowNum) -> new ProductoPedidoResponse(
                        rs.getInt("Id_Producto"),
                        rs.getString("Nombre"),
                        rs.getBigDecimal("PrecioVenta")),
                idTipoProducto);
    }

    public List<PromedioVentaResponse> obtenerPromedioVentaRuta(
            SucursalConnection sucursal,
            java.time.LocalDate fecha,
            Integer idRuta) {
        return new JdbcTemplate(crearDataSource(sucursal)).query(
                "EXEC dbo.spy_PromedioVenta_X_Dia ?, ?",
                (rs, rowNum) -> new PromedioVentaResponse(
                        rs.getInt("Id_Producto"),
                        rs.getString("Producto"),
                        rs.getBigDecimal("PromedioVenta"),
                        rs.getBigDecimal("Pedido")),
                java.sql.Date.valueOf(fecha),
                idRuta);
    }

    public List<PedidoResumenResponse> listarPedidosEnRuta(
            SucursalConnection sucursal,
            Integer idUsuario,
            Integer idRuta) {
        return new JdbcTemplate(crearDataSource(sucursal)).query(
                "EXEC dbo.spj_LoginGeneral_ListarPedidosEnRuta ?, ?",
                (rs, rowNum) -> new PedidoResumenResponse(
                        rs.getInt("IdPedido"),
                        rs.getTimestamp("FechaRegistro").toLocalDateTime(),
                        rs.getString("Observacion"),
                        rs.getInt("ModificadoPorAlmacen"),
                        rs.getString("ComentarioAlmacen"),
                        rs.getBigDecimal("Total"),
                        rs.getInt("EstadoAprobado"),
                        rs.getInt("CantidadProductos"),
                        rs.getInt("CantidadUnidades")),
                idUsuario,
                idRuta);
    }

    public List<DetallePedidoResponse> obtenerDetallePedidoEnRuta(
            SucursalConnection sucursal,
            Integer idPedido,
            Integer idUsuario,
            Integer idRuta) {
        return new JdbcTemplate(crearDataSource(sucursal)).query(
                "EXEC dbo.spj_LoginGeneral_ObtenerDetallePedidoEnRuta ?, ?, ?",
                (rs, rowNum) -> new DetallePedidoResponse(
                        rs.getInt("IdDetalle"),
                        rs.getInt("IdProducto"),
                        rs.getString("Producto"),
                        rs.getString("TipoProducto"),
                        rs.getInt("Cantidad"),
                        rs.getBigDecimal("Precio"),
                        rs.getBigDecimal("TotalParcial")),
                idPedido,
                idUsuario,
                idRuta);
    }

    public List<TecnicoPendientesResponse> listarTecnicosParaAlmacen(SucursalConnection sucursal) {
        return new JdbcTemplate(crearDataSource(sucursal)).query(
                "EXEC dbo.spj_LoginGeneral_Almacen_ListarTecnicos",
                (rs, rowNum) -> new TecnicoPendientesResponse(
                        rs.getInt("IdUsuario"),
                        rs.getString("Nombre"),
                        nullableInt(rs, "IdVendedor"),
                        nullableInt(rs, "IdRuta"),
                        rs.getString("Ruta"),
                        rs.getInt("PedidosPendientes")));
    }

    public List<PedidoTecnicoResponse> listarPedidosPendientesTecnico(
            SucursalConnection sucursal,
            Integer idUsuarioTecnico) {
        return new JdbcTemplate(crearDataSource(sucursal)).query(
                "EXEC dbo.spj_LoginGeneral_Almacen_ListarPedidosTecnico ?",
                (rs, rowNum) -> new PedidoTecnicoResponse(
                        rs.getInt("IdPedido"),
                        rs.getInt("IdRuta"),
                        rs.getString("Ruta"),
                        rs.getTimestamp("FechaRegistro").toLocalDateTime(),
                        rs.getString("Observacion"),
                        rs.getInt("ModificadoPorAlmacen"),
                        rs.getString("ComentarioAlmacen"),
                        rs.getBigDecimal("Total"),
                        rs.getInt("EstadoAprobado"),
                        rs.getInt("CantidadProductos"),
                        rs.getInt("CantidadUnidades")),
                idUsuarioTecnico);
    }

    public List<DetallePedidoResponse> obtenerDetallePedidoParaAlmacen(
            SucursalConnection sucursal,
            Integer idPedido,
            Integer idUsuarioTecnico) {
        return new JdbcTemplate(crearDataSource(sucursal)).query(
                "EXEC dbo.spj_LoginGeneral_Almacen_ObtenerDetallePedido ?, ?",
                (rs, rowNum) -> new DetallePedidoResponse(
                        rs.getInt("IdDetalle"),
                        rs.getInt("IdProducto"),
                        rs.getString("Producto"),
                        rs.getString("TipoProducto"),
                        rs.getInt("Cantidad"),
                        rs.getBigDecimal("Precio"),
                        rs.getBigDecimal("TotalParcial")),
                idPedido,
                idUsuarioTecnico);
    }

    public List<RutaPendientesResponse> listarRutasParaAlmacen(
            SucursalConnection sucursal,
            java.time.LocalDate fechaDesde,
            java.time.LocalDate fechaHasta) {
        return new JdbcTemplate(crearDataSource(sucursal)).query(
                "EXEC dbo.spj_LoginGeneral_Almacen_ListarRutas ?, ?",
                (rs, rowNum) -> new RutaPendientesResponse(
                        rs.getInt("IdRuta"),
                        rs.getString("Ruta"),
                        nullableInt(rs, "IdVendedor"),
                        rs.getString("Tecnico"),
                        rs.getInt("PedidosPendientes")),
                java.sql.Date.valueOf(fechaDesde),
                java.sql.Date.valueOf(fechaHasta));
    }

    public List<PedidoPendienteAlmacenResponse> listarPedidosPendientesAlmacen(
            SucursalConnection sucursal,
            java.time.LocalDate fechaDesde,
            java.time.LocalDate fechaHasta,
            Integer idRuta,
            Integer estadoAprobado) {
        return new JdbcTemplate(crearDataSource(sucursal)).query(
                "EXEC dbo.spj_LoginGeneral_Almacen_ListarPedidosPendientes ?, ?, ?, ?",
                (rs, rowNum) -> new PedidoPendienteAlmacenResponse(
                        rs.getInt("IdPedido"),
                        rs.getInt("IdUsuarioTecnico"),
                        rs.getInt("IdVendedor"),
                        rs.getString("Tecnico"),
                        rs.getInt("IdRuta"),
                        rs.getString("Ruta"),
                        rs.getTimestamp("FechaRegistro").toLocalDateTime(),
                        rs.getString("Observacion"),
                        rs.getInt("ModificadoPorAlmacen"),
                        rs.getString("ComentarioAlmacen"),
                        rs.getBigDecimal("Total"),
                        rs.getInt("EstadoAprobado"),
                        rs.getString("AprobadoPor"),
                        rs.getInt("CantidadProductos"),
                        rs.getInt("CantidadUnidades")),
                java.sql.Date.valueOf(fechaDesde),
                java.sql.Date.valueOf(fechaHasta),
                idRuta,
                estadoAprobado);
    }

    public List<EstadisticaPedidosDiaRutaResponse> obtenerEstadisticasPedidosAlmacen(
            SucursalConnection sucursal,
            java.time.LocalDate fechaDesde,
            java.time.LocalDate fechaHasta) {
        return new JdbcTemplate(crearDataSource(sucursal)).query(
                "EXEC dbo.spj_LoginGeneral_Almacen_EstadisticasPedidos ?, ?",
                (rs, rowNum) -> new EstadisticaPedidosDiaRutaResponse(
                        rs.getDate("Fecha").toLocalDate(),
                        rs.getInt("IdRuta"),
                        rs.getString("Ruta"),
                        rs.getInt("Realizados"),
                        rs.getInt("Aprobados"),
                        rs.getInt("Pendientes"),
                        rs.getInt("Modificados"),
                        rs.getInt("UnidadesSolicitadas"),
                        rs.getInt("UnidadesAprobadas"),
                        rs.getBigDecimal("MontoSolicitado"),
                        rs.getBigDecimal("MontoAprobado"),
                        rs.getInt("CuadresEnviados"),
                        rs.getInt("CuadresRealizados"),
                        rs.getInt("CuadresPendientes"),
                        rs.getInt("CuadresModificados"),
                        rs.getInt("UnidadesSobrantes"),
                        rs.getInt("UnidadesVendidas"),
                        rs.getBigDecimal("MontoVendido")),
                java.sql.Date.valueOf(fechaDesde),
                java.sql.Date.valueOf(fechaHasta));
    }

    public List<EstadisticaCuadreProductoResponse> obtenerDetalleEstadisticasCuadres(
            SucursalConnection sucursal,
            java.time.LocalDate fechaDesde,
            java.time.LocalDate fechaHasta) {
        return new JdbcTemplate(crearDataSource(sucursal)).query(
                "EXEC dbo.spj_LoginGeneral_Almacen_EstadisticasCuadresDetalle ?, ?",
                (rs, rowNum) -> new EstadisticaCuadreProductoResponse(
                        rs.getDate("Fecha").toLocalDate(),
                        rs.getInt("IdRuta"),
                        rs.getString("Ruta"),
                        rs.getInt("IdCuadre"),
                        rs.getInt("IdProducto"),
                        rs.getString("Producto"),
                        rs.getString("TipoProducto"),
                        rs.getInt("Sobrantes"),
                        rs.getInt("Vendidos"),
                        rs.getBigDecimal("Precio"),
                        rs.getBigDecimal("TotalVendido")),
                java.sql.Date.valueOf(fechaDesde),
                java.sql.Date.valueOf(fechaHasta));
    }

    public List<EstadisticaVendedorResponse> obtenerEstadisticasVendedores(
            SucursalConnection sucursal, java.time.LocalDate fechaDesde, java.time.LocalDate fechaHasta) {
        return new JdbcTemplate(crearDataSource(sucursal)).query(
                "EXEC dbo.spj_LoginGeneral_Almacen_EstadisticasVendedores ?, ?",
                (rs, rowNum) -> new EstadisticaVendedorResponse(
                        rs.getInt("IdVendedor"), rs.getString("Vendedor"),
                        rs.getInt("Pedidos"), rs.getInt("Aprobados"),
                        rs.getInt("Pendientes"), rs.getInt("Modificados"),
                        rs.getInt("UnidadesSolicitadas"), rs.getBigDecimal("MontoSolicitado")),
                java.sql.Date.valueOf(fechaDesde), java.sql.Date.valueOf(fechaHasta));
    }

    public List<EstadisticaConsumoProductoDiaResponse> obtenerConsumoProductosDiario(
            SucursalConnection sucursal, java.time.LocalDate fechaDesde, java.time.LocalDate fechaHasta) {
        return new JdbcTemplate(crearDataSource(sucursal)).query(
                "EXEC dbo.spj_LoginGeneral_Almacen_EstadisticasConsumoProductosDiario ?, ?",
                (rs, rowNum) -> new EstadisticaConsumoProductoDiaResponse(
                        rs.getDate("Fecha").toLocalDate(), rs.getInt("IdProducto"),
                        rs.getString("Producto"), rs.getString("TipoProducto"),
                        rs.getInt("UnidadesVendidas"), rs.getInt("UnidadesSobrantes"),
                        rs.getBigDecimal("TotalVendido"), rs.getInt("RutasConMovimiento"),
                        rs.getInt("Cuadres")),
                java.sql.Date.valueOf(fechaDesde), java.sql.Date.valueOf(fechaHasta));
    }

    public List<EstadisticaDemoraCajaResponse> obtenerDemorasCaja(
            SucursalConnection sucursal, java.time.LocalDate fechaDesde, java.time.LocalDate fechaHasta) {
        return new JdbcTemplate(crearDataSource(sucursal)).query(
                "EXEC dbo.spj_LoginGeneral_Almacen_EstadisticasDemorasCaja ?, ?",
                (rs, rowNum) -> new EstadisticaDemoraCajaResponse(
                        rs.getDate("Fecha").toLocalDate(), rs.getInt("IdCuadre"),
                        rs.getInt("IdRuta"), rs.getString("Ruta"),
                        rs.getInt("IdVendedor"), rs.getString("Vendedor"),
                        rs.getTimestamp("FechaCuadre").toLocalDateTime(), rs.getInt("IdCaja"),
                        rs.getTimestamp("FechaCaja").toLocalDateTime(), rs.getInt("MinutosDemora")),
                java.sql.Date.valueOf(fechaDesde), java.sql.Date.valueOf(fechaHasta));
    }

    public List<DetallePedidoResponse> obtenerDetallePendienteParaAlmacen(
            SucursalConnection sucursal,
            Integer idPedido) {
        return new JdbcTemplate(crearDataSource(sucursal)).query(
                "EXEC dbo.spj_LoginGeneral_Almacen_ObtenerDetallePendiente ?",
                (rs, rowNum) -> new DetallePedidoResponse(
                        rs.getInt("IdDetalle"),
                        rs.getInt("IdProducto"),
                        rs.getString("Producto"),
                        rs.getString("TipoProducto"),
                        rs.getInt("Cantidad"),
                        rs.getBigDecimal("Precio"),
                        rs.getBigDecimal("TotalParcial")),
                idPedido);
    }

    public List<ProductoFisicoPedidoResponse> obtenerProductosFisicosPedido(
            SucursalConnection sucursal,
            Integer idPedido) {
        return new JdbcTemplate(crearDataSource(sucursal)).query(
                """
                SELECT
                    fisico.Id_PedidoProductoFisico AS IdAsignacion,
                    fisico.Id_CodigoPedidoVendedor_EnRuta AS IdDetalle,
                    fisico.Id_Producto AS IdProducto,
                    producto.Nombre AS Producto,
                    tipo.Nombre AS TipoProducto,
                    CONVERT(VARCHAR(30), fisico.Imei) AS Imei,
                    fisico.Id_Ruta AS IdRuta,
                    fisico.Numero_Tira AS NumeroTira,
                    fisico.Modo_Tira AS ModoTira,
                    fisico.Fecha_Registro AS FechaRegistro
                FROM dbo.PedidoVendedor_EnRuta_ProductoFisico fisico
                INNER JOIN dbo.tbl_Producto producto
                    ON producto.Id_Producto = fisico.Id_Producto
                LEFT JOIN dbo.tbl_TipoProducto tipo
                    ON tipo.Id_TipoProducto = producto.Id_TipoProducto
                WHERE fisico.Id_PedidoVendedor_EnRuta = ?
                  AND fisico.E_Eliminado = 2
                ORDER BY fisico.Id_CodigoPedidoVendedor_EnRuta, fisico.Id_PedidoProductoFisico
                """,
                (rs, rowNum) -> new ProductoFisicoPedidoResponse(
                        rs.getInt("IdAsignacion"),
                        rs.getInt("IdDetalle"),
                        rs.getInt("IdProducto"),
                        rs.getString("Producto"),
                        rs.getString("TipoProducto"),
                        rs.getString("Imei"),
                        rs.getInt("IdRuta"),
                        rs.getInt("NumeroTira"),
                        rs.getString("ModoTira"),
                        rs.getTimestamp("FechaRegistro").toLocalDateTime()),
                idPedido);
    }

    public com.logingeneral.back.auth.AlmacenDtos.ValidacionTigoMoneyResponse validarTigoMoneyPedido(
            SucursalConnection sucursal,
            Integer idPedido) {
        return new JdbcTemplate(crearDataSource(sucursal)).query(
                "EXEC dbo.spj_LoginGeneral_Almacen_ValidarTigoMoneyPedido ?",
                (rs, rowNum) -> new com.logingeneral.back.auth.AlmacenDtos.ValidacionTigoMoneyResponse(
                        rs.getBigDecimal("SaldoDisponible"),
                        rs.getBigDecimal("MontoPedido"),
                        rs.getBigDecimal("SaldoRestante"),
                        rs.getBoolean("Valido")),
                idPedido).stream().findFirst()
                .orElseThrow(() -> new IllegalStateException("La validación de Tigo Money no devolvió resultado."));
    }

    public ModificarPedidoAlmacenResponse modificarPedidoAlmacen(
            SucursalConnection sucursal,
            Integer idPedido,
            Integer idUsuarioAlmacenero,
            String comentarioAlmacen,
            List<ModificarDetallePedidoRequest> detalles) {
        StringBuilder xml = new StringBuilder("<detalles>");
        for (ModificarDetallePedidoRequest detalle : detalles) {
            xml.append("<item idDetalle=\"")
                    .append(detalle.idDetalle())
                    .append("\" cantidad=\"")
                    .append(detalle.cantidad())
                    .append("\"/>");
        }
        xml.append("</detalles>");
        return new JdbcTemplate(crearDataSource(sucursal)).query(
                "EXEC dbo.spj_LoginGeneral_Almacen_ModificarPedido ?, ?, ?, ?",
                (rs, rowNum) -> new ModificarPedidoAlmacenResponse(
                        rs.getInt("IdPedido"),
                        rs.getBigDecimal("Total"),
                        rs.getInt("CantidadProductos"),
                        rs.getInt("CantidadUnidades"),
                        rs.getInt("ModificadoPorAlmacen"),
                        rs.getString("ComentarioAlmacen")),
                idPedido,
                idUsuarioAlmacenero,
                comentarioAlmacen,
                xml.toString()).stream().findFirst()
                .orElseThrow(() -> new IllegalStateException("El procedimiento no devolvió el pedido modificado."));
    }

    public List<PromedioVentaResponse> obtenerPromedioVentaPedidoAlmacen(
            SucursalConnection sucursal,
            Integer idPedido,
            java.time.LocalDate fecha) {
        return new JdbcTemplate(crearDataSource(sucursal)).query(
                "EXEC dbo.spj_LoginGeneral_Almacen_ObtenerPromedioPedido ?, ?",
                (rs, rowNum) -> new PromedioVentaResponse(
                        rs.getInt("Id_Producto"),
                        rs.getString("Producto"),
                        rs.getBigDecimal("PromedioVenta"),
                        rs.getBigDecimal("Pedido")),
                idPedido,
                java.sql.Date.valueOf(fecha));
    }

    public SaldoRutaResponse obtenerSaldoRutaPedidoAlmacen(
            SucursalConnection sucursal,
            Integer idPedido) {
        return new JdbcTemplate(crearDataSource(sucursal)).query(
                "EXEC dbo.spj_LoginGeneral_Almacen_ObtenerSaldoRutaPedido ?",
                rs -> {
                    if (!rs.next()) {
                        throw new IllegalStateException("El procedimiento no devolvió la ruta del pedido.");
                    }
                    Integer idRuta = rs.getInt("IdRuta");
                    String ruta = rs.getString("Ruta");
                    List<SaldoProducto> productos = new java.util.ArrayList<>();
                    do {
                        if (rs.getObject("Id_Producto") == null) continue;
                        int cantidad = rs.getInt("Cantidad");
                        BigDecimal precio = rs.getBigDecimal("PrecioVenta");
                        if (precio == null) precio = BigDecimal.ZERO;
                        productos.add(new SaldoProducto(
                                rs.getInt("Id_Producto"),
                                rs.getString("Producto"),
                                cantidad,
                                rs.getString("TipoProducto"),
                                precio,
                                precio.multiply(BigDecimal.valueOf(cantidad))));
                    } while (rs.next());
                    int totalUnidades = productos.stream().mapToInt(SaldoProducto::cantidad).sum();
                    BigDecimal valorTotal = productos.stream()
                            .map(SaldoProducto::valorTotal)
                            .reduce(BigDecimal.ZERO, BigDecimal::add);
                    return new SaldoRutaResponse(
                            idRuta, ruta, productos.size(), totalUnidades, valorTotal, productos);
                },
                idPedido);
    }

    public AprobarPedidoResponse aprobarPedido(
            SucursalConnection sucursal,
            Integer idPedido,
            java.time.LocalDate fechaEntrega,
            String aprobadoPor,
            Integer idUsuarioAlmacenero,
            String tokenVinculacion,
            List<ProductoFisicoAsignadoRequest> productos) {
        StringBuilder xml = new StringBuilder("<productos>");
        for (ProductoFisicoAsignadoRequest producto : productos) {
            xml.append("<i detalle=\"")
                    .append(producto.idDetalle())
                    .append("\" imei=\"")
                    .append(producto.imei())
                    .append("\" tira=\"")
                    .append(producto.numeroTira())
                    .append("\" modo=\"")
                    .append(producto.modoTira())
                    .append("\"/>");
        }
        xml.append("</productos>");
        JdbcTemplate jdbcTemplate = new JdbcTemplate(crearDataSource(sucursal));
        boolean usaReserva = tokenVinculacion != null && !tokenVinculacion.isBlank();
        String procedimiento = usaReserva
                ? "EXEC dbo.spj_LoginGeneral_Almacen_AprobarPedidoReservado ?, ?, ?, ?, ?, ?"
                : "EXEC dbo.spj_LoginGeneral_Almacen_AprobarPedidoConProductos ?, ?, ?, ?, ?";
        Object[] parametros = usaReserva
                ? new Object[] { idPedido, java.sql.Date.valueOf(fechaEntrega), aprobadoPor,
                        idUsuarioAlmacenero, tokenVinculacion, xml.toString() }
                : new Object[] { idPedido, java.sql.Date.valueOf(fechaEntrega), aprobadoPor,
                        idUsuarioAlmacenero, xml.toString() };
        return jdbcTemplate.query(
                procedimiento,
                (rs, rowNum) -> new AprobarPedidoResponse(
                        rs.getInt("IdPedido"),
                        rs.getTimestamp("FechaEntrega").toLocalDateTime(),
                        rs.getInt("EstadoAprobado"),
                        rs.getString("AprobadoPor")),
                parametros).stream().findFirst()
                .orElseThrow(() -> new IllegalStateException("El procedimiento no devolvió el pedido aprobado."));
    }

    public CrearPedidoDirectoResponse crearPedidoDirecto(
            SucursalConnection sucursal,
            Integer idRuta,
            Integer idUsuarioAlmacenero,
            String creadoPor,
            String observacion,
            List<DetallePedidoDirectoRequest> detalles,
            List<ProductoFisicoDirectoRequest> productos) {
        StringBuilder detalleXml = new StringBuilder("<pedido>");
        for (DetallePedidoDirectoRequest detalle : detalles) {
            detalleXml.append("<i producto=\"").append(detalle.idProducto())
                    .append("\" cantidad=\"").append(detalle.cantidad()).append("\"/>");
        }
        detalleXml.append("</pedido>");
        StringBuilder productosXml = new StringBuilder("<productos>");
        for (ProductoFisicoDirectoRequest producto : productos) {
            productosXml.append("<i producto=\"").append(producto.idProducto())
                    .append("\" imei=\"").append(producto.imei())
                    .append("\" tira=\"").append(producto.numeroTira())
                    .append("\" modo=\"").append(producto.modoTira()).append("\"/>");
        }
        productosXml.append("</productos>");
        return new JdbcTemplate(crearDataSource(sucursal)).query(
                "EXEC dbo.spj_LoginGeneral_Almacen_CrearPedidoDirecto ?, ?, ?, ?, ?, ?",
                (rs, rowNum) -> new CrearPedidoDirectoResponse(
                        rs.getInt("IdPedidoVendedor"), rs.getInt("IdAlmacenVendedor"),
                        rs.getInt("IdRuta"), rs.getInt("CantidadProductos"),
                        rs.getInt("CantidadUnidades"), rs.getBigDecimal("Total"),
                        rs.getTimestamp("FechaRegistro").toLocalDateTime()),
                idRuta, idUsuarioAlmacenero, creadoPor,
                observacion == null ? "" : observacion, detalleXml.toString(), productosXml.toString())
                .stream().findFirst()
                .orElseThrow(() -> new IllegalStateException("El procedimiento no devolvio el pedido directo creado."));
    }

    public com.logingeneral.back.auth.AlmacenDtos.ValidacionTigoMoneyResponse validarTigoMoneyDirecto(
            SucursalConnection sucursal, java.math.BigDecimal cantidad) {
        return new JdbcTemplate(crearDataSource(sucursal)).query(
                "EXEC dbo.spj_LoginGeneral_Almacen_ValidarTigoMoneyDirecto ?",
                (rs, rowNum) -> new com.logingeneral.back.auth.AlmacenDtos.ValidacionTigoMoneyResponse(
                        rs.getBigDecimal("SaldoDisponible"), rs.getBigDecimal("MontoPedido"),
                        rs.getBigDecimal("SaldoRestante"), rs.getBoolean("Valido")), cantidad)
                .stream().findFirst().orElseThrow(() -> new IllegalStateException("No se pudo validar Tigo Money."));
    }

    public List<CierreAlmacenProductoResponse> obtenerCierreAlmacen(
            SucursalConnection sucursal, java.time.LocalDate fecha) {
        return new JdbcTemplate(crearDataSource(sucursal)).query(
                "EXEC dbo.sp_ObtenerCierreAlmacen_ ?",
                (rs, rowNum) -> new CierreAlmacenProductoResponse(
                        rs.getInt("Id_Producto"), rs.getString("Nombre"), rs.getBigDecimal("PrecioVenta"),
                        rs.getBigDecimal("SaldoDiaAnterior"), rs.getBigDecimal("TotalSaldoDiaAnterior"),
                        rs.getBigDecimal("SaldoDiaAnteriorTIGO"), rs.getBigDecimal("TotalSaldoDiaAnteriorTIGO"),
                        rs.getBigDecimal("CompraDia"), rs.getBigDecimal("TotalCompraDia"),
                        rs.getBigDecimal("CompraDiaTIGO"), rs.getBigDecimal("TotalCompraDiaTIGO"),
                        rs.getBigDecimal("DevolucionIngreso"), rs.getBigDecimal("TotalDevolucionIngreso"),
                        rs.getBigDecimal("VentaDia"), rs.getBigDecimal("TotalVentaDia"),
                        rs.getBigDecimal("SaldoDiaHoy"), rs.getBigDecimal("TotalSaldoDiaHoy"),
                        rs.getBigDecimal("SaldoDiaHoyTIGO"), rs.getBigDecimal("TotalSaldoDiaHoyTIGO")),
                java.sql.Date.valueOf(fecha))
                .stream()
                .filter(producto -> (producto.saldoDiaHoy() != null && producto.saldoDiaHoy().signum() > 0)
                        || (producto.saldoDiaHoyTigo() != null && producto.saldoDiaHoyTigo().signum() > 0))
                .toList();
    }

    public CierreAlmacenDtos.EstadoCierreAlmacenResponse obtenerEstadoCierreAlmacen(
            SucursalConnection sucursal, java.time.LocalDate fecha) {
        return new JdbcTemplate(crearDataSource(sucursal)).query(
                "EXEC dbo.spj_LoginGeneral_Almacen_ObtenerEstadoCierre ?",
                (rs, rowNum) -> new CierreAlmacenDtos.EstadoCierreAlmacenResponse(
                        rs.getBoolean("Existe"), rs.getInt("IdCierreAlmacen"),
                        rs.getTimestamp("Fecha").toLocalDateTime().toLocalDate(),
                        rs.getString("Observacion"), rs.getInt("CantidadProductos")),
                java.sql.Date.valueOf(fecha))
                .stream().findFirst()
                .orElseGet(() -> new CierreAlmacenDtos.EstadoCierreAlmacenResponse(
                        false, null, fecha, null, 0));
    }

    public CierreAlmacenDtos.GuardarCierreAlmacenResponse guardarCierreAlmacen(
            SucursalConnection sucursal, Integer idUsuario, java.time.LocalDate fecha, String observacion) {
        return new JdbcTemplate(crearDataSource(sucursal)).query(
                "EXEC dbo.spj_LoginGeneral_Almacen_GuardarCierre ?, ?, ?",
                (rs, rowNum) -> new CierreAlmacenDtos.GuardarCierreAlmacenResponse(
                        rs.getInt("IdCierreAlmacen"),
                        rs.getTimestamp("Fecha").toLocalDateTime().toLocalDate(),
                        rs.getInt("CantidadProductos")),
                idUsuario, java.sql.Date.valueOf(fecha), observacion == null ? "" : observacion.trim())
                .stream().findFirst()
                .orElseThrow(() -> new IllegalStateException("El procedimiento no devolvio el cierre registrado."));
    }

    public List<EntidadResponse> listarEntidades(SucursalConnection sucursal) {
        return new JdbcTemplate(crearDataSource(sucursal)).query(
                "EXEC dbo.spj_LoginGeneral_ListarEntidades",
                (rs, rowNum) -> new EntidadResponse(
                        rs.getInt("IdEntidad"),
                        rs.getString("Nombre")));
    }

    public RegistrarDepositoResponse registrarDeposito(
            SucursalConnection sucursal,
            Integer idRuta,
            Integer idVendedor,
            Integer idUsuario,
            Integer idEntidad,
            String cuenta,
            BigDecimal monto,
            String op) {
        return new JdbcTemplate(crearDataSource(sucursal)).query(
                "EXEC dbo.spj_LoginGeneral_RegistrarDepositoEnRuta ?, ?, ?, ?, ?, ?, ?",
                (rs, rowNum) -> new RegistrarDepositoResponse(
                        rs.getInt("IdDeposito"),
                        rs.getString("Mensaje")),
                idRuta,
                idVendedor,
                idUsuario,
                idEntidad,
                cuenta,
                monto,
                op).stream().findFirst()
                .orElseThrow(() -> new IllegalStateException("El procedimiento no devolvió el depósito creado."));
    }

    public List<DepositoResponse> listarDepositosEnRuta(
            SucursalConnection sucursal,
            Integer idRuta) {
        return new JdbcTemplate(crearDataSource(sucursal)).query(
                "EXEC dbo.spj_LoginGeneral_ListarDepositosEnRuta ?",
                (rs, rowNum) -> {
                    var fechaRegistro = rs.getTimestamp("FechaRegistro");
                    return new DepositoResponse(
                            rs.getInt("IdDeposito"),
                            rs.getInt("IdRuta"),
                            rs.getInt("IdVendedor"),
                            rs.getInt("IdUsuario"),
                            rs.getInt("IdEntidad"),
                            rs.getString("NombreBanco"),
                            rs.getString("Cuenta"),
                            rs.getBigDecimal("Monto"),
                            rs.getString("OP"),
                            fechaRegistro == null ? null : fechaRegistro.toLocalDateTime(),
                            rs.getInt("EstadoAprobacion"),
                            rs.getString("EstadoTexto"));
                },
                idRuta);
    }

    public List<DepositoContabilidadResponse> listarDepositosPendientesContabilidad(
            SucursalConnection sucursal) {
        return new JdbcTemplate(crearDataSource(sucursal)).query(
                "EXEC dbo.spj_LoginGeneral_Contabilidad_ListarDepositosPendientes",
                (rs, rowNum) -> new DepositoContabilidadResponse(
                        rs.getInt("IdDeposito"), rs.getInt("IdRuta"), rs.getString("Ruta"),
                        rs.getInt("IdVendedor"), rs.getString("Vendedor"), rs.getInt("IdUsuario"),
                        rs.getInt("IdEntidad"), rs.getString("NombreBanco"), rs.getString("Cuenta"),
                        rs.getBigDecimal("Monto"), rs.getString("OP"),
                        rs.getTimestamp("FechaRegistro").toLocalDateTime(),
                        rs.getInt("EstadoAprobacion"), rs.getString("EstadoTexto"),
                        rs.getString("AprobadoPor"),
                        rs.getTimestamp("FechaAprobacion") == null ? null : rs.getTimestamp("FechaAprobacion").toLocalDateTime(),
                        rs.getBoolean("PuedeEditar"),
                        rs.getBoolean("PuedeAprobar")));
    }

    public RegistrarDepositoResponse editarDepositoContabilidad(
            SucursalConnection sucursal, Integer idDeposito, Integer idEntidad,
            String cuenta, BigDecimal monto, String op) {
        return new JdbcTemplate(crearDataSource(sucursal)).query(
                "EXEC dbo.spj_LoginGeneral_Contabilidad_EditarDepositoSinOP ?, ?, ?, ?, ?",
                (rs, rowNum) -> new RegistrarDepositoResponse(
                        rs.getInt("IdDeposito"), rs.getString("Mensaje")),
                idDeposito, idEntidad, cuenta, monto, op).stream().findFirst()
                .orElseThrow(() -> new IllegalStateException("El procedimiento no devolvió el depósito actualizado."));
    }

    public RegistrarDepositoResponse aprobarDepositoContabilidad(
            SucursalConnection sucursal, Integer idDeposito, String aprobadoPor, Integer idUsuarioAprobador) {
        return new JdbcTemplate(crearDataSource(sucursal)).query(
                "EXEC dbo.spj_LoginGeneral_Contabilidad_AprobarDeposito ?, ?, ?",
                (rs, rowNum) -> new RegistrarDepositoResponse(
                        rs.getInt("IdDeposito"), rs.getString("Mensaje")),
                idDeposito, aprobadoPor, idUsuarioAprobador).stream().findFirst()
                .orElseThrow(() -> new IllegalStateException("El procedimiento no devolvió el depósito aprobado."));
    }

    public java.util.List<com.logingeneral.back.auth.SistemasDtos.RutaSistemasResponse> listarRutasSistemas(
            SucursalConnection sucursal) {
        return new JdbcTemplate(crearDataSource(sucursal)).query(
                "EXEC dbo.spj_LoginGeneral_Sistemas_ListarRutas",
                (rs, rowNum) -> new com.logingeneral.back.auth.SistemasDtos.RutaSistemasResponse(
                        rs.getInt("IdRuta"),
                        rs.getString("Ruta"),
                        nullableInt(rs, "IdVendedor"),
                        rs.getString("Tecnico"),
                        rs.getTimestamp("UltimoMovimiento") == null
                                ? null : rs.getTimestamp("UltimoMovimiento").toLocalDateTime()));
    }

    public java.util.List<com.logingeneral.back.auth.SistemasDtos.MovimientoRutaResponse> listarMovimientosRutaSistemas(
            SucursalConnection sucursal,
            Integer idRuta,
            java.time.LocalDate fechaDesde,
            java.time.LocalDate fechaHasta) {
        return new JdbcTemplate(crearDataSource(sucursal)).query(
                "EXEC dbo.spj_LoginGeneral_Sistemas_ListarMovimientosRuta ?, ?, ?",
                (rs, rowNum) -> new com.logingeneral.back.auth.SistemasDtos.MovimientoRutaResponse(
                        rs.getString("Tipo"),
                        rs.getInt("IdReferencia"),
                        rs.getTimestamp("Fecha").toLocalDateTime(),
                        rs.getBigDecimal("Total"),
                        rs.getString("Estado"),
                        rs.getString("Observacion")),
                idRuta,
                java.sql.Date.valueOf(fechaDesde),
                java.sql.Date.valueOf(fechaHasta));
    }

    public java.util.List<com.logingeneral.back.auth.SistemasDtos.PreviewCascadaItemResponse> previewCascadaRutaSistemas(
            SucursalConnection sucursal,
            Integer idRuta,
            java.time.LocalDateTime desdeFecha) {
        return new JdbcTemplate(crearDataSource(sucursal)).query(
                "EXEC dbo.spj_LoginGeneral_Sistemas_PreviewCascadaRuta ?, ?",
                (rs, rowNum) -> new com.logingeneral.back.auth.SistemasDtos.PreviewCascadaItemResponse(
                        rs.getString("Tipo"),
                        rs.getInt("IdReferencia"),
                        rs.getTimestamp("Fecha").toLocalDateTime(),
                        rs.getBigDecimal("Total")),
                idRuta,
                java.sql.Timestamp.valueOf(desdeFecha));
    }

    public java.util.List<com.logingeneral.back.auth.SistemasDtos.PreviewCascadaDetalleResponse> previewDetalleCascadaRutaSistemas(
            SucursalConnection sucursal,
            Integer idRuta,
            java.time.LocalDateTime desdeFecha) {
        return new JdbcTemplate(crearDataSource(sucursal)).query(
                "EXEC dbo.spj_LoginGeneral_Sistemas_PreviewDetalleCascadaRuta ?, ?",
                (rs, rowNum) -> new com.logingeneral.back.auth.SistemasDtos.PreviewCascadaDetalleResponse(
                        rs.getString("Tipo"),
                        rs.getInt("IdReferencia"),
                        rs.getTimestamp("Fecha").toLocalDateTime(),
                        rs.getBigDecimal("Total"),
                        rs.getString("EstadoActual"),
                        rs.getString("EstadoProyectado"),
                        rs.getString("Observacion"),
                        rs.getInt("IdProducto"),
                        rs.getString("Producto"),
                        rs.getInt("CantidadMovimiento"),
                        rs.getInt("SaldoActual"),
                        rs.getInt("SaldoAntesMovimiento"),
                        rs.getInt("SaldoDespuesMovimiento"),
                        rs.getInt("SaldoProyectadoFinal"),
                        rs.getInt("FisicosAfectados"),
                        rs.getInt("FisicosVendidos"),
                        rs.getString("Codigos"),
                        rs.getString("TablaPrincipal"),
                        rs.getString("TablasAfectadas"),
                        rs.getBoolean("Bloqueado"),
                        rs.getString("MotivoBloqueo")),
                idRuta,
                java.sql.Timestamp.valueOf(desdeFecha));
    }

    public java.util.List<com.logingeneral.back.auth.SistemasDtos.PreviewTablaCascadaResponse> previewTablasCascadaRutaSistemas(
            SucursalConnection sucursal,
            Integer idRuta,
            java.time.LocalDateTime desdeFecha) throws java.sql.SQLException {
        java.util.List<com.logingeneral.back.auth.SistemasDtos.PreviewTablaCascadaResponse> resultado = new java.util.ArrayList<>();
        try (java.sql.Connection connection = crearDataSource(sucursal).getConnection()) {
            java.util.List<Movimiento> movimientos = new java.util.ArrayList<>();
            try (java.sql.PreparedStatement ps = connection.prepareStatement(
                    "EXEC dbo.spj_LoginGeneral_Sistemas_PreviewCascadaRuta ?, ?")) {
                ps.setInt(1, idRuta);
                ps.setTimestamp(2, java.sql.Timestamp.valueOf(desdeFecha));
                try (java.sql.ResultSet rs = ps.executeQuery()) {
                    while (rs.next()) {
                        movimientos.add(new Movimiento(rs.getString("Tipo"), rs.getInt("IdReferencia")));
                    }
                }
            }

            for (Movimiento movimiento : movimientos) {
                if ("CUADRE".equals(movimiento.tipo())) {
                    agregarTablasCuadre(connection, movimiento, idRuta, resultado);
                } else if ("PEDIDO".equals(movimiento.tipo())) {
                    agregarTablasPedido(connection, movimiento, idRuta, resultado);
                }
            }
        }
        return resultado;
    }

    private void agregarTablasCuadre(
            java.sql.Connection connection,
            Movimiento movimiento,
            Integer idRuta,
            java.util.List<com.logingeneral.back.auth.SistemasDtos.PreviewTablaCascadaResponse> resultado)
            throws java.sql.SQLException {
        int idCuadre = movimiento.idReferencia();
        java.util.Map<Integer, Integer> saldosAntes = new java.util.HashMap<>();
        try (java.sql.PreparedStatement ps = connection.prepareStatement(
                "SELECT Id_Producto, ItemsSobrantes + ItemsVendidos AS SaldoAntes FROM dbo.tbl_CodigoCuadre WHERE Id_Cuadre = ? AND E_Eliminado = 2")) {
            ps.setInt(1, idCuadre);
            try (java.sql.ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    saldosAntes.put(rs.getInt("Id_Producto"), rs.getInt("SaldoAntes"));
                }
            }
        }

        agregarTabla(connection, resultado, movimiento, "tbl_Cuadre",
                "SELECT * FROM dbo.tbl_Cuadre WHERE Id_Cuadre = " + idCuadre,
                filas -> filas.forEach(fila -> fila.put("E_Eliminado", 1)));
        agregarTabla(connection, resultado, movimiento, "tbl_CodigoCuadre",
                "SELECT * FROM dbo.tbl_CodigoCuadre WHERE Id_Cuadre = " + idCuadre + " ORDER BY Id_CodigoCuadre",
                filas -> filas.forEach(fila -> fila.put("E_Eliminado", 1)));
        agregarTabla(connection, resultado, movimiento, "tbl_SaldoCuadre",
                "SELECT * FROM dbo.tbl_SaldoCuadre WHERE Id_Cuadre = " + idCuadre + " ORDER BY Id_SaldoCuadre",
                filas -> filas.forEach(fila -> fila.put("E_Eliminado", 1)));
        agregarTabla(connection, resultado, movimiento, "tbl_GiroTigo",
                "SELECT * FROM dbo.tbl_GiroTigo WHERE Id_Cuadre = " + idCuadre + " ORDER BY Id_GiroTigo",
                filas -> filas.forEach(fila -> fila.put("E_Eliminado", 1)));
        agregarTabla(connection, resultado, movimiento, "tbl_Productos",
                "SELECT * FROM dbo.tbl_Productos WHERE Id_Cuadre = " + idCuadre + " AND Id_Ruta = " + idRuta + " ORDER BY Imei",
                filas -> filas.forEach(fila -> {
                    fila.put("Vendido", 1);
                    fila.put("Id_Cuadre", null);
                }));
        agregarTabla(connection, resultado, movimiento, "tbl_SaldoTarjetas",
                "SELECT * FROM dbo.tbl_SaldoTarjetas WHERE Id_Ruta = " + idRuta
                        + " AND Id_Producto IN (SELECT Id_Producto FROM dbo.tbl_CodigoCuadre WHERE Id_Cuadre = " + idCuadre
                        + " AND E_Eliminado = 2) ORDER BY Id_Producto, Id_SaldoTarjetas",
                filas -> filas.forEach(fila -> {
                    Integer idProducto = numeroEntero(fila.get("Id_Producto"));
                    if (idProducto != null && saldosAntes.containsKey(idProducto)) {
                        fila.put("Cantidad", saldosAntes.get(idProducto));
                    }
                }));
        agregarTabla(connection, resultado, movimiento, "tbl_Cuadre_EnRuta",
                "SELECT Id_Cuadre_EnRuta,Id_Ruta,Id_Vendedor,Id_Usuario,Fecha,Observacion,Total,E_Aprobado,AprobadoPor,Id_Cuadre,E_Eliminado,Modificado,FechaAprobacion "
                        + "FROM dbo.tbl_Cuadre_EnRuta WHERE Id_Cuadre = " + idCuadre + " ORDER BY Id_Cuadre_EnRuta",
                filas -> filas.forEach(fila -> {
                    fila.put("E_Aprobado", 1);
                    fila.put("AprobadoPor", null);
                    fila.put("Id_Cuadre", 0);
                    fila.put("FechaAprobacion", null);
                }));
        agregarTabla(connection, resultado, movimiento, "tbl_CodigoCuadre_EnRuta",
                "SELECT * FROM dbo.tbl_CodigoCuadre_EnRuta WHERE Id_Cuadre_EnRuta IN (SELECT Id_Cuadre_EnRuta FROM dbo.tbl_Cuadre_EnRuta WHERE Id_Cuadre = " + idCuadre + ") ORDER BY Id_CodigoCuadre_EnRuta",
                filas -> { });
        agregarTabla(connection, resultado, movimiento, "tbl_TransaccionCuadre",
                "SELECT * FROM dbo.tbl_TransaccionCuadre WHERE Id_Cuadre = " + idCuadre + " ORDER BY Id_TransaccionCuadre",
                filas -> filas.forEach(fila -> fila.put("E_Eliminado", 1)));
        agregarTabla(connection, resultado, movimiento, "tbl_Deuda",
                "SELECT * FROM dbo.tbl_Deuda WHERE Id_Cuadre = " + idCuadre + " ORDER BY Id_Deuda",
                filas -> filas.forEach(fila -> fila.put("E_Eliminado", 1)));
        agregarTabla(connection, resultado, movimiento, "tbl_Caja",
                "SELECT * FROM dbo.tbl_Caja WHERE Id_Caja IN (SELECT Id_Caja FROM dbo.tbl_TransaccionCuadre WHERE Id_Cuadre = " + idCuadre
                        + " UNION SELECT Id_CajaDeuda FROM dbo.tbl_Deuda WHERE Id_Cuadre = " + idCuadre
                        + " UNION SELECT Id_CajaPago FROM dbo.tbl_Deuda WHERE Id_Cuadre = " + idCuadre + ") ORDER BY Id_Caja",
                filas -> filas.forEach(fila -> fila.put("E_Eliminado", 1)));
    }

    private void agregarTablasPedido(
            java.sql.Connection connection,
            Movimiento movimiento,
            Integer idRuta,
            java.util.List<com.logingeneral.back.auth.SistemasDtos.PreviewTablaCascadaResponse> resultado)
            throws java.sql.SQLException {
        int idPedido = movimiento.idReferencia();
        Integer idPedidoNormal = null;
        try (java.sql.PreparedStatement ps = connection.prepareStatement(
                "SELECT NULLIF(Id_PedidoVendedorNormal, 0) FROM dbo.tbl_PedidoVendedor_EnRuta WHERE Id_PedidoVendedor_EnRuta = ?")) {
            ps.setInt(1, idPedido);
            try (java.sql.ResultSet rs = ps.executeQuery()) {
                if (rs.next()) idPedidoNormal = numeroEntero(rs.getObject(1));
            }
        }
        final Integer normal = idPedidoNormal;
        java.util.Map<Integer, Integer> saldosAntes = new java.util.HashMap<>();
        if (normal != null) {
            try (java.sql.PreparedStatement ps = connection.prepareStatement(
                    "SELECT Id_Producto, Saldo FROM dbo.tbl_CodigoPedidoVendedor WHERE Id_PedidoVendedor = ? AND E_Eliminado = 2")) {
                ps.setInt(1, normal);
                try (java.sql.ResultSet rs = ps.executeQuery()) {
                    while (rs.next()) saldosAntes.put(rs.getInt("Id_Producto"), rs.getInt("Saldo"));
                }
            }
        }

        agregarTabla(connection, resultado, movimiento, "tbl_PedidoVendedor_EnRuta",
                "SELECT * FROM dbo.tbl_PedidoVendedor_EnRuta WHERE Id_PedidoVendedor_EnRuta = " + idPedido,
                filas -> filas.forEach(fila -> {
                    fila.put("E_Aprobado", 1);
                    fila.put("AprobadoPor", null);
                    fila.put("Id_PedidoVendedorNormal", 0);
                }));
        agregarTabla(connection, resultado, movimiento, "tbl_CodigoPedidoVendedor_EnRuta",
                "SELECT * FROM dbo.tbl_CodigoPedidoVendedor_EnRuta WHERE Id_PedidoVendedor_EnRuta = " + idPedido + " ORDER BY Id_CodigoPedidoVendedor_EnRuta",
                filas -> { });
        if (normal != null) {
            agregarTabla(connection, resultado, movimiento, "tbl_PedidoVendedor",
                    "SELECT * FROM dbo.tbl_PedidoVendedor WHERE Id_PedidoVendedor = " + normal,
                    filas -> filas.forEach(fila -> fila.put("E_Eliminado", 1)));
            agregarTabla(connection, resultado, movimiento, "tbl_CodigoPedidoVendedor",
                    "SELECT * FROM dbo.tbl_CodigoPedidoVendedor WHERE Id_PedidoVendedor = " + normal + " ORDER BY Id_CodigoPedidoVendedor",
                    filas -> filas.forEach(fila -> fila.put("E_Eliminado", 1)));
            agregarTabla(connection, resultado, movimiento, "tbl_AlmacenVendedor",
                    "SELECT * FROM dbo.tbl_AlmacenVendedor WHERE Id_PedidoVendedor = " + normal + " ORDER BY Id_AlmacenVendedor",
                    filas -> filas.forEach(fila -> fila.put("E_Eliminado", 1)));
            agregarTabla(connection, resultado, movimiento, "tbl_CodigoAlmacenVendedor",
                    "SELECT * FROM dbo.tbl_CodigoAlmacenVendedor WHERE Id_AlmacenVendedor IN (SELECT Id_AlmacenVendedor FROM dbo.tbl_AlmacenVendedor WHERE Id_PedidoVendedor = " + normal + ") ORDER BY Id_CodigoAlmacenVendedor",
                    filas -> filas.forEach(fila -> fila.put("E_Eliminado", 1)));
        }
        agregarTabla(connection, resultado, movimiento, "PedidoVendedor_EnRuta_ProductoFisico",
                "SELECT * FROM dbo.PedidoVendedor_EnRuta_ProductoFisico WHERE Id_PedidoVendedor_EnRuta = " + idPedido + " ORDER BY Id_PedidoProductoFisico",
                filas -> filas.forEach(fila -> fila.put("E_Eliminado", 1)));
        agregarTabla(connection, resultado, movimiento, "tbl_Productos",
                "SELECT * FROM dbo.tbl_Productos WHERE Id_PedidoVendedor = " + (normal == null ? 0 : normal)
                        + " OR Imei IN (SELECT Imei FROM dbo.PedidoVendedor_EnRuta_ProductoFisico WHERE Id_PedidoVendedor_EnRuta = " + idPedido + " AND E_Eliminado = 2) ORDER BY Imei",
                filas -> filas.forEach(fila -> {
                    fila.put("Id_Ruta", 0);
                    fila.put("Id_PedidoVendedor", 0);
                    fila.put("Id_Cuadre", null);
                    fila.put("Vendido", 0);
                }));
        agregarTabla(connection, resultado, movimiento, "tbl_SaldoTarjetas",
                "SELECT * FROM dbo.tbl_SaldoTarjetas WHERE Id_Ruta = " + idRuta
                        + " AND Id_Producto IN (SELECT Id_Producto FROM dbo.tbl_CodigoPedidoVendedor WHERE Id_PedidoVendedor = "
                        + (normal == null ? 0 : normal) + " AND E_Eliminado = 2) ORDER BY Id_Producto, Id_SaldoTarjetas",
                filas -> filas.forEach(fila -> {
                    Integer idProducto = numeroEntero(fila.get("Id_Producto"));
                    if (idProducto != null && saldosAntes.containsKey(idProducto)) fila.put("Cantidad", saldosAntes.get(idProducto));
                }));
    }

    private void agregarTabla(
            java.sql.Connection connection,
            java.util.List<com.logingeneral.back.auth.SistemasDtos.PreviewTablaCascadaResponse> resultado,
            Movimiento movimiento,
            String tabla,
            String consulta,
            java.util.function.Consumer<java.util.List<java.util.Map<String, Object>>> proyectar)
            throws java.sql.SQLException {
        ResultadoTabla actual = consultarTabla(connection, consulta);
        java.util.List<java.util.Map<String, Object>> proyectado = new java.util.ArrayList<>();
        for (java.util.Map<String, Object> fila : actual.filas()) {
            proyectado.add(new java.util.LinkedHashMap<>(fila));
        }
        proyectar.accept(proyectado);
        resultado.add(new com.logingeneral.back.auth.SistemasDtos.PreviewTablaCascadaResponse(
                movimiento.tipo(), movimiento.idReferencia(), tabla, consulta + ";",
                actual.columnas(), actual.filas(), proyectado));
    }

    private ResultadoTabla consultarTabla(java.sql.Connection connection, String consulta) throws java.sql.SQLException {
        java.util.List<String> columnas = new java.util.ArrayList<>();
        java.util.List<java.util.Map<String, Object>> filas = new java.util.ArrayList<>();
        try (java.sql.PreparedStatement ps = connection.prepareStatement(consulta);
             java.sql.ResultSet rs = ps.executeQuery()) {
            java.sql.ResultSetMetaData metadata = rs.getMetaData();
            for (int i = 1; i <= metadata.getColumnCount(); i++) columnas.add(metadata.getColumnLabel(i));
            while (rs.next()) {
                java.util.Map<String, Object> fila = new java.util.LinkedHashMap<>();
                for (int i = 1; i <= metadata.getColumnCount(); i++) {
                    fila.put(metadata.getColumnLabel(i), valorSerializable(rs.getObject(i)));
                }
                filas.add(fila);
            }
        }
        return new ResultadoTabla(columnas, filas);
    }

    private Object valorSerializable(Object valor) throws java.sql.SQLException {
        if (valor instanceof java.sql.Timestamp timestamp) return timestamp.toLocalDateTime().toString();
        if (valor instanceof java.sql.Date fecha) return fecha.toLocalDate().toString();
        if (valor instanceof java.sql.Time hora) return hora.toLocalTime().toString();
        if (valor instanceof java.sql.SQLXML xml) return xml.getString();
        if (valor instanceof byte[] bytes) return java.util.HexFormat.of().formatHex(bytes);
        return valor;
    }

    private Integer numeroEntero(Object valor) {
        if (valor instanceof Number numero) return numero.intValue();
        if (valor == null) return null;
        return Integer.valueOf(valor.toString());
    }

    private record ResultadoTabla(
            java.util.List<String> columnas,
            java.util.List<java.util.Map<String, Object>> filas) {
    }

    /**
     * Revierte la cascada movimiento por movimiento (más reciente al más antiguo) usando UNA sola
     * conexión/transacción JDBC, para poder avisar por SSE cada paso mientras ocurre. La atomicidad
     * es la misma que el procedimiento monolítico: si algo falla, se hace ROLLBACK de todo.
     */
    public com.logingeneral.back.auth.SistemasDtos.EjecutarCascadaResponse ejecutarCascadaRutaConProgreso(
            SucursalConnection sucursal,
            Integer idRuta,
            java.time.LocalDateTime desdeFecha,
            Integer idUsuarioSistemas,
            String nombreUsuarioSistemas,
            String justificacion,
            String jobId,
            java.util.function.Consumer<com.logingeneral.back.auth.SistemasEventService.CascadaEvento> progreso)
            throws java.sql.SQLException {
        // Sin pool: el SET XACT_ABORT/ARITHABORT de abajo quedaria en la sesion reutilizada.
        try (java.sql.Connection connection = dataSources.obtenerSinPool(sucursal).getConnection()) {
            connection.setAutoCommit(false);
            try {
                try (java.sql.Statement statement = connection.createStatement()) {
                    statement.execute("SET XACT_ABORT ON; SET ARITHABORT ON;");
                }

                // Además de resolver la idempotencia, esta lectura inicia materialmente la
                // transacción en jTDS. El applock con propietario Transaction debe pedirse después.
                try (java.sql.PreparedStatement ps = connection.prepareStatement(
                        "SELECT Id_ReversionRuta, Id_Ruta, CantidadMovimientos, Fecha_Registro "
                                + "FROM dbo.tbl_Sistemas_ReversionRuta WITH (UPDLOCK, HOLDLOCK) WHERE JobId = ?")) {
                    ps.setString(1, jobId);
                    try (java.sql.ResultSet rs = ps.executeQuery()) {
                        if (rs.next()) {
                            connection.commit();
                            return new com.logingeneral.back.auth.SistemasDtos.EjecutarCascadaResponse(
                                    rs.getInt("Id_ReversionRuta"), rs.getInt("Id_Ruta"),
                                    rs.getInt("CantidadMovimientos"),
                                    rs.getTimestamp("Fecha_Registro").toLocalDateTime());
                        }
                    }
                }

                String recurso = "LoginGeneral:Sistemas:CascadaRuta:" + idRuta;
                // jTDS puede quedarse esperando hasta el socketTimeout al leer el valor de retorno
                // de sp_getapplock mediante CallableStatement. Ejecutarlo como T-SQL y devolver el
                // resultado con SELECT evita que la conexión sea cerrada por el driver.
                try (java.sql.PreparedStatement lock = connection.prepareStatement(
                        "DECLARE @resultado int; "
                                + "EXEC @resultado = sys.sp_getapplock "
                                + "@Resource = ?, @LockMode = 'Exclusive', "
                                + "@LockOwner = 'Transaction', @LockTimeout = 15000; "
                                + "SELECT @resultado;")) {
                    lock.setString(1, recurso);
                    try (java.sql.ResultSet rs = lock.executeQuery()) {
                        if (!rs.next() || rs.getInt(1) < 0) {
                            throw new java.sql.SQLException("No se pudo bloquear la ruta para revertir sus movimientos. Intenta nuevamente.");
                        }
                    }
                }

                List<Movimiento> movimientos = new java.util.ArrayList<>();
                try (java.sql.PreparedStatement ps = connection.prepareStatement(
                        "EXEC dbo.spj_LoginGeneral_Sistemas_PreviewCascadaRuta ?, ?")) {
                    ps.setInt(1, idRuta);
                    ps.setTimestamp(2, java.sql.Timestamp.valueOf(desdeFecha));
                    try (java.sql.ResultSet rs = ps.executeQuery()) {
                        while (rs.next()) {
                            movimientos.add(new Movimiento(rs.getString("Tipo"), rs.getInt("IdReferencia")));
                        }
                    }
                }

                if (movimientos.isEmpty()) {
                    throw new java.sql.SQLException("No hay movimientos de esta ruta desde la fecha indicada.");
                }

                StringBuilder detalleAuditoria = new StringBuilder();
                for (Movimiento movimiento : movimientos) {
                    if (detalleAuditoria.length() > 0) detalleAuditoria.append("; ");
                    detalleAuditoria.append(construirDetalleAuditoria(connection, movimiento));
                }

                int total = movimientos.size();
                int indice = 0;
                for (Movimiento movimiento : movimientos) {
                    indice++;
                    emitir(progreso, "procesando", movimiento, indice, total, null);
                    switch (movimiento.tipo()) {
                        case "CUADRE" -> ejecutarProcedimiento(
                                connection, "EXEC dbo.spj_LoginGeneral_Sistemas_RevertirCuadreInterno ?, ?, ?",
                                movimiento.idReferencia(), idRuta, desdeFecha);
                        case "PEDIDO" -> ejecutarProcedimiento(
                                connection, "EXEC dbo.spj_LoginGeneral_Sistemas_RevertirPedidoInterno ?, ?, ?",
                                movimiento.idReferencia(), idRuta, desdeFecha);
                        default -> throw new java.sql.SQLException("Tipo de movimiento desconocido: " + movimiento.tipo());
                    }
                    emitir(progreso, "revertido", movimiento, indice, total, null);
                }

                Integer idReversion;
                try (java.sql.PreparedStatement ps = connection.prepareStatement(
                        "INSERT INTO dbo.tbl_Sistemas_ReversionRuta "
                                + "(Id_Ruta, DesdeFecha, Id_UsuarioSistemas, NombreUsuarioSistemas, Justificacion, CantidadMovimientos, DetalleJson, JobId) "
                                + "OUTPUT INSERTED.Id_ReversionRuta VALUES (?, ?, ?, ?, ?, ?, ?, ?)")) {
                    ps.setInt(1, idRuta);
                    ps.setTimestamp(2, java.sql.Timestamp.valueOf(desdeFecha));
                    ps.setInt(3, idUsuarioSistemas);
                    ps.setString(4, nombreUsuarioSistemas);
                    ps.setString(5, justificacion);
                    ps.setInt(6, total);
                    ps.setString(7, detalleAuditoria.toString());
                    ps.setString(8, jobId);
                    try (java.sql.ResultSet rs = ps.executeQuery()) {
                        if (!rs.next()) {
                            throw new java.sql.SQLException("No se pudo obtener el identificador de la restauracion.");
                        }
                        idReversion = rs.getInt(1);
                    }
                }

                connection.commit();
                java.time.LocalDateTime ahora = java.time.LocalDateTime.now();
                emitir(progreso, "completado", null, total, total, "Se revirtieron " + total + " movimientos.");
                return new com.logingeneral.back.auth.SistemasDtos.EjecutarCascadaResponse(
                        idReversion, idRuta, total, ahora);
            } catch (java.sql.SQLException ex) {
                // Si un timeout de red ya cerró la conexión, rollback() también falla. No debe
                // reemplazar el error que realmente originó la reversión fallida.
                try {
                    if (!connection.isClosed()) connection.rollback();
                } catch (java.sql.SQLException rollbackEx) {
                    ex.addSuppressed(rollbackEx);
                }
                emitir(progreso, "error", null, 0, 0, ex.getMessage());
                throw ex;
            }
        }
    }

    private String construirDetalleAuditoria(java.sql.Connection connection, Movimiento movimiento) throws java.sql.SQLException {
        if ("CUADRE".equals(movimiento.tipo())) {
            String transacciones = listarIds(connection,
                    "SELECT Id_TransaccionCuadre FROM dbo.tbl_TransaccionCuadre WHERE Id_Cuadre = ? ORDER BY Id_TransaccionCuadre",
                    movimiento.idReferencia());
            String cajas = listarIds(connection,
                    "SELECT DISTINCT Id_Caja FROM (SELECT Id_Caja FROM dbo.tbl_TransaccionCuadre WHERE Id_Cuadre = ? UNION SELECT Id_CajaDeuda FROM dbo.tbl_Deuda WHERE Id_Cuadre = ? UNION SELECT Id_CajaPago FROM dbo.tbl_Deuda WHERE Id_Cuadre = ?) x WHERE Id_Caja IS NOT NULL ORDER BY Id_Caja",
                    movimiento.idReferencia(), movimiento.idReferencia(), movimiento.idReferencia());
            String deudas = listarIds(connection,
                    "SELECT Id_Deuda FROM dbo.tbl_Deuda WHERE Id_Cuadre = ? ORDER BY Id_Deuda",
                    movimiento.idReferencia());
            return "CUADRE#" + movimiento.idReferencia() + "{TransaccionCuadre:[" + transacciones
                    + "],Caja:[" + cajas + "],Deuda:[" + deudas + "]}";
        }
        String pedidoNormal = listarIds(connection,
                "SELECT Id_PedidoVendedorNormal FROM dbo.tbl_PedidoVendedor_EnRuta WHERE Id_PedidoVendedor_EnRuta = ?",
                movimiento.idReferencia());
        return "PEDIDO#" + movimiento.idReferencia() + "{PedidoVendedorNormal:[" + pedidoNormal + "]}";
    }

    private String listarIds(java.sql.Connection connection, String sql, Object... parametros) throws java.sql.SQLException {
        StringBuilder ids = new StringBuilder();
        try (java.sql.PreparedStatement ps = connection.prepareStatement(sql)) {
            for (int i = 0; i < parametros.length; i++) ps.setObject(i + 1, parametros[i]);
            try (java.sql.ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    if (ids.length() > 0) ids.append(',');
                    ids.append(rs.getObject(1));
                }
            }
        }
        return ids.toString();
    }

    private void ejecutarProcedimiento(java.sql.Connection connection, String sql, Object... parametros) throws java.sql.SQLException {
        try (java.sql.PreparedStatement ps = connection.prepareStatement(sql)) {
            for (int i = 0; i < parametros.length; i++) {
                Object parametro = parametros[i];
                if (parametro instanceof Integer numero) {
                    ps.setInt(i + 1, numero);
                } else if (parametro instanceof java.time.LocalDateTime fecha) {
                    ps.setTimestamp(i + 1, java.sql.Timestamp.valueOf(fecha));
                } else {
                    ps.setObject(i + 1, parametro);
                }
            }
            ps.execute();
        }
    }

    private void emitir(
            java.util.function.Consumer<com.logingeneral.back.auth.SistemasEventService.CascadaEvento> progreso,
            String etapa, Movimiento movimiento, int indice, int total, String mensaje) {
        if (progreso == null) {
            return;
        }
        progreso.accept(new com.logingeneral.back.auth.SistemasEventService.CascadaEvento(
                etapa,
                movimiento == null ? null : movimiento.tipo(),
                movimiento == null ? null : movimiento.idReferencia(),
                indice, total, mensaje));
    }

    private record Movimiento(String tipo, Integer idReferencia) {
    }

    private Integer nullableInt(java.sql.ResultSet rs, String column) throws java.sql.SQLException {
        try {
            int value = rs.getInt(column);
            return rs.wasNull() ? null : value;
        } catch (java.sql.SQLException ex) {
            return null;
        }
    }

    private String optionalString(
            java.sql.ResultSet rs,
            String column,
            String defaultValue) throws java.sql.SQLException {
        try {
            String value = rs.getString(column);
            return value == null || value.isBlank() ? defaultValue : value;
        } catch (java.sql.SQLException ex) {
            return defaultValue;
        }
    }

    private DataSource crearDataSource(SucursalConnection sucursal) {
        return dataSources.obtener(sucursal);
    }

    private DataSource crearDataSourceCuadre(SucursalConnection sucursal) {
        return dataSources.obtenerCuadre(sucursal);
    }

    public List<ChatDtos.MensajeChatResponse> listarMensajesChat(
            SucursalConnection sucursal,
            Integer idRuta,
            long desdeId,
            int limite) {
        return new JdbcTemplate(crearDataSource(sucursal)).query(
                "EXEC dbo.spj_LoginGeneral_Chat_Listar ?, ?, ?",
                (rs, rowNum) -> mensajeChat(rs),
                idRuta, desdeId, limite);
    }

    public Optional<ChatDtos.MensajeChatResponse> enviarMensajeChat(
            SucursalConnection sucursal,
            Integer idRuta,
            Integer idUsuario,
            String origen,
            String nombreEmisor,
            String texto,
            Integer idPedido) {
        return new JdbcTemplate(crearDataSource(sucursal)).query(
                "EXEC dbo.spj_LoginGeneral_Chat_Enviar ?, ?, ?, ?, ?, ?",
                (rs, rowNum) -> mensajeChat(rs),
                idRuta, idUsuario, origen, nombreEmisor, texto, idPedido).stream().findFirst();
    }

    public void marcarLeidoChat(SucursalConnection sucursal, Integer idRuta, String origen, long hastaId) {
        new JdbcTemplate(crearDataSource(sucursal)).update(
                "EXEC dbo.spj_LoginGeneral_Chat_MarcarLeido ?, ?, ?", idRuta, origen, hastaId);
    }

    public List<ChatDtos.ResumenChatResponse> resumenChat(SucursalConnection sucursal, String lector, Integer idRuta) {
        return new JdbcTemplate(crearDataSource(sucursal)).query(
                "EXEC dbo.spj_LoginGeneral_Chat_Resumen ?, ?",
                (rs, rowNum) -> new ChatDtos.ResumenChatResponse(
                        rs.getInt("IdRuta"),
                        rs.getInt("NoLeidos"),
                        rs.getTimestamp("UltimaFecha") == null ? null : rs.getTimestamp("UltimaFecha").toLocalDateTime(),
                        rs.getString("UltimoTexto"),
                        rs.getString("UltimoOrigen")),
                lector, idRuta);
    }

    private ChatDtos.MensajeChatResponse mensajeChat(java.sql.ResultSet rs) throws java.sql.SQLException {
        return new ChatDtos.MensajeChatResponse(
                rs.getLong("IdMensaje"),
                rs.getInt("IdRuta"),
                rs.getInt("IdUsuario"),
                rs.getString("Origen"),
                rs.getString("NombreEmisor"),
                rs.getString("Texto"),
                nullableInt(rs, "IdPedido"),
                rs.getTimestamp("Fecha").toLocalDateTime());
    }

    record SucursalUser(Integer id, String nombre, String loggin, Integer idRol, String rol) {
    }
}
