package com.logingeneral.back.auth;

import java.util.List;

import org.springframework.http.HttpHeaders;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.http.MediaType;
import org.springframework.web.servlet.mvc.method.annotation.SseEmitter;

import com.logingeneral.back.auth.AuthDtos.LoginRequest;
import com.logingeneral.back.auth.AuthDtos.LoginResponse;
import com.logingeneral.back.auth.AuthDtos.SucursalResponse;
import com.logingeneral.back.auth.AuthDtos.UsuarioResponse;
import com.logingeneral.back.auth.AlmacenDtos.PedidoTecnicoResponse;
import com.logingeneral.back.auth.AlmacenDtos.TecnicoPendientesResponse;
import com.logingeneral.back.auth.AlmacenDtos.PedidoPendienteAlmacenResponse;
import com.logingeneral.back.auth.AlmacenDtos.RutaPendientesResponse;
import com.logingeneral.back.auth.AlmacenDtos.AprobarPedidoRequest;
import com.logingeneral.back.auth.AlmacenDtos.AprobarPedidoResponse;
import com.logingeneral.back.auth.AlmacenDtos.ProductoFisicoPedidoResponse;
import com.logingeneral.back.auth.AlmacenDtos.ModificarPedidoAlmacenRequest;
import com.logingeneral.back.auth.AlmacenDtos.ModificarPedidoAlmacenResponse;
import com.logingeneral.back.auth.AlmacenDtos.CrearPedidoDirectoRequest;
import com.logingeneral.back.auth.AlmacenDtos.CrearPedidoDirectoResponse;
import com.logingeneral.back.auth.CierreAlmacenDtos.CierreAlmacenProductoResponse;
import com.logingeneral.back.auth.CierreAlmacenDtos.EstadoCierreAlmacenResponse;
import com.logingeneral.back.auth.CierreAlmacenDtos.GuardarCierreAlmacenRequest;
import com.logingeneral.back.auth.CierreAlmacenDtos.GuardarCierreAlmacenResponse;
import com.logingeneral.back.auth.PedidoEnRutaDtos.CrearPedidoRequest;
import com.logingeneral.back.auth.PedidoEnRutaDtos.CrearPedidoResponse;
import com.logingeneral.back.auth.PedidoEnRutaDtos.ProductoPedidoResponse;
import com.logingeneral.back.auth.PedidoEnRutaDtos.PromedioVentaResponse;
import com.logingeneral.back.auth.PedidoEnRutaDtos.DetallePedidoResponse;
import com.logingeneral.back.auth.PedidoEnRutaDtos.PedidoResumenResponse;
import com.logingeneral.back.auth.PedidoEnRutaDtos.TipoProductoResponse;
import com.logingeneral.back.auth.SaldoRutaDtos.SaldoRutaResponse;
import com.logingeneral.back.auth.EstadisticasAlmacenDtos.EstadisticaPedidosDiaRutaResponse;
import com.logingeneral.back.auth.EstadisticasAlmacenDtos.EstadisticaCuadreProductoResponse;
import com.logingeneral.back.auth.EstadisticasAlmacenDtos.EstadisticaVendedorResponse;
import com.logingeneral.back.auth.EstadisticasAlmacenDtos.EstadisticaConsumoProductoDiaResponse;
import com.logingeneral.back.auth.EstadisticasAlmacenDtos.EstadisticaDemoraCajaResponse;
import com.logingeneral.back.auth.CuadreDtos.ProductoCuadreResponse;
import com.logingeneral.back.auth.CuadreDtos.EstadoCuadreHoyResponse;
import com.logingeneral.back.auth.CuadreDtos.ValidarImeisCuadreRequest;
import com.logingeneral.back.auth.CuadreDtos.ValidacionCuadreResponse;
import com.logingeneral.back.auth.CuadreDtos.FinalizarCuadreRequest;
import com.logingeneral.back.auth.CuadreDtos.FinalizarCuadreResponse;
import com.logingeneral.back.auth.CuadreAlmacenDtos.RutaCuadreResponse;
import com.logingeneral.back.auth.CuadreAlmacenDtos.DetalleCuadreAlmacenResponse;
import com.logingeneral.back.auth.CuadreEnRutaDtos.ResumenCuadreEnRutaResponse;
import com.logingeneral.back.auth.CuadreEnRutaDtos.DetalleCuadreEnRutaResponse;
import com.logingeneral.back.auth.DepositoEnRutaDtos.EntidadResponse;
import com.logingeneral.back.auth.DepositoEnRutaDtos.RegistrarDepositoRequest;
import com.logingeneral.back.auth.DepositoEnRutaDtos.RegistrarDepositoResponse;
import com.logingeneral.back.auth.DepositoEnRutaDtos.DepositoResponse;
import com.logingeneral.back.auth.DepositoEnRutaDtos.DepositoContabilidadResponse;
import com.logingeneral.back.auth.DepositoEnRutaDtos.EditarDepositoContabilidadRequest;

import jakarta.validation.Valid;

@RestController
@RequestMapping("/api/auth")
public class AuthController {

    private final AuthService authService;

    public AuthController(AuthService authService) {
        this.authService = authService;
    }

    @GetMapping("/sucursales")
    public List<SucursalResponse> sucursales() {
        return authService.listarSucursales();
    }

    @PostMapping("/login")
    public LoginResponse login(@Valid @RequestBody LoginRequest request) {
        return authService.login(request);
    }

    @GetMapping("/me")
    public UsuarioResponse me(@RequestHeader(HttpHeaders.AUTHORIZATION) String authorization) {
        return authService.usuarioActualSinBloqueo(authorization);
    }

    @PostMapping("/logout")
    public ResponseEntity<Void> logout(@RequestHeader(HttpHeaders.AUTHORIZATION) String authorization) {
        authService.logout(authorization);
        return ResponseEntity.noContent().build();
    }

    @GetMapping("/saldo-ruta")
    public SaldoRutaResponse saldoRuta(
            @RequestHeader(HttpHeaders.AUTHORIZATION) String authorization) {
        return authService.obtenerSaldoRuta(authorization);
    }

    @GetMapping("/cuadre/productos")
    public List<ProductoCuadreResponse> productosCuadre(
            @RequestHeader(HttpHeaders.AUTHORIZATION) String authorization) {
        return authService.listarProductosCuadre(authorization);
    }

    @GetMapping("/cuadre/hoy")
    public EstadoCuadreHoyResponse estadoCuadreHoy(
            @RequestHeader(HttpHeaders.AUTHORIZATION) String authorization) {
        return authService.obtenerEstadoCuadreHoy(authorization);
    }

    @PostMapping("/cuadre/validar")
    public ValidacionCuadreResponse validarCuadre(
            @RequestHeader(HttpHeaders.AUTHORIZATION) String authorization,
            @Valid @RequestBody ValidarImeisCuadreRequest request) {
        return authService.validarImeisCuadre(authorization, request);
    }

    @PostMapping("/cuadre/finalizar")
    public FinalizarCuadreResponse finalizarCuadre(
            @RequestHeader(HttpHeaders.AUTHORIZATION) String authorization,
            @Valid @RequestBody FinalizarCuadreRequest request) {
        return authService.finalizarCuadre(authorization, request);
    }

    @PostMapping("/pedido-en-ruta")
    public CrearPedidoResponse crearPedidoEnRuta(
            @RequestHeader(HttpHeaders.AUTHORIZATION) String authorization,
            @Valid @RequestBody CrearPedidoRequest request) {
        return authService.crearPedidoEnRuta(authorization, request);
    }

    @GetMapping("/tipos-producto")
    public List<TipoProductoResponse> tiposProducto(
            @RequestHeader(HttpHeaders.AUTHORIZATION) String authorization) {
        return authService.listarTiposProducto(authorization);
    }

    @GetMapping("/productos")
    public List<ProductoPedidoResponse> productos(
            @RequestHeader(HttpHeaders.AUTHORIZATION) String authorization,
            @RequestParam Integer idTipoProducto) {
        return authService.listarProductosPorTipo(authorization, idTipoProducto);
    }

    @GetMapping("/promedio-venta-ruta")
    public List<PromedioVentaResponse> promedioVentaRuta(
            @RequestHeader(HttpHeaders.AUTHORIZATION) String authorization) {
        return authService.obtenerPromedioVentaRuta(authorization);
    }

    @GetMapping("/pedidos-en-ruta")
    public List<PedidoResumenResponse> pedidosEnRuta(
            @RequestHeader(HttpHeaders.AUTHORIZATION) String authorization) {
        return authService.listarPedidosEnRuta(authorization);
    }

    @GetMapping("/pedidos-en-ruta/{idPedido}/detalle")
    public List<DetallePedidoResponse> detallePedidoEnRuta(
            @RequestHeader(HttpHeaders.AUTHORIZATION) String authorization,
            @org.springframework.web.bind.annotation.PathVariable Integer idPedido) {
        return authService.obtenerDetallePedidoEnRuta(authorization, idPedido);
    }

    @GetMapping("/almacen/tecnicos")
    public List<TecnicoPendientesResponse> tecnicosParaAlmacen(
            @RequestHeader(HttpHeaders.AUTHORIZATION) String authorization) {
        return authService.listarTecnicosParaAlmacen(authorization);
    }

    @GetMapping("/almacen/tecnicos/{idUsuarioTecnico}/pedidos")
    public List<PedidoTecnicoResponse> pedidosPendientesTecnico(
            @RequestHeader(HttpHeaders.AUTHORIZATION) String authorization,
            @org.springframework.web.bind.annotation.PathVariable Integer idUsuarioTecnico) {
        return authService.listarPedidosPendientesTecnico(authorization, idUsuarioTecnico);
    }

    @GetMapping("/almacen/tecnicos/{idUsuarioTecnico}/pedidos/{idPedido}/detalle")
    public List<DetallePedidoResponse> detallePedidoParaAlmacen(
            @RequestHeader(HttpHeaders.AUTHORIZATION) String authorization,
            @org.springframework.web.bind.annotation.PathVariable Integer idUsuarioTecnico,
            @org.springframework.web.bind.annotation.PathVariable Integer idPedido) {
        return authService.obtenerDetallePedidoParaAlmacen(
                authorization, idUsuarioTecnico, idPedido);
    }

    @GetMapping("/almacen/rutas")
    public List<RutaPendientesResponse> rutasParaAlmacen(
            @RequestHeader(HttpHeaders.AUTHORIZATION) String authorization,
            @RequestParam @org.springframework.format.annotation.DateTimeFormat(iso = org.springframework.format.annotation.DateTimeFormat.ISO.DATE) java.time.LocalDate fechaDesde,
            @RequestParam @org.springframework.format.annotation.DateTimeFormat(iso = org.springframework.format.annotation.DateTimeFormat.ISO.DATE) java.time.LocalDate fechaHasta) {
        return authService.listarRutasParaAlmacen(authorization, fechaDesde, fechaHasta);
    }

    @GetMapping(value = "/almacen/eventos", produces = MediaType.TEXT_EVENT_STREAM_VALUE)
    public SseEmitter eventosPedidos(
            @RequestHeader(HttpHeaders.AUTHORIZATION) String authorization) {
        return authService.eventosPedidos(authorization);
    }

    @GetMapping("/almacen/pedidos")
    public List<PedidoPendienteAlmacenResponse> pedidosPendientesAlmacen(
            @RequestHeader(HttpHeaders.AUTHORIZATION) String authorization,
            @RequestParam @org.springframework.format.annotation.DateTimeFormat(iso = org.springframework.format.annotation.DateTimeFormat.ISO.DATE) java.time.LocalDate fechaDesde,
            @RequestParam @org.springframework.format.annotation.DateTimeFormat(iso = org.springframework.format.annotation.DateTimeFormat.ISO.DATE) java.time.LocalDate fechaHasta,
            @RequestParam(required = false) Integer idRuta,
            @RequestParam(required = false) Integer estadoAprobado) {
        return authService.listarPedidosPendientesAlmacen(
                authorization, fechaDesde, fechaHasta, idRuta, estadoAprobado);
    }

    @GetMapping("/almacen/estadisticas")
    public List<EstadisticaPedidosDiaRutaResponse> estadisticasPedidosAlmacen(
            @RequestHeader(HttpHeaders.AUTHORIZATION) String authorization,
            @RequestParam @org.springframework.format.annotation.DateTimeFormat(iso = org.springframework.format.annotation.DateTimeFormat.ISO.DATE) java.time.LocalDate fechaDesde,
            @RequestParam @org.springframework.format.annotation.DateTimeFormat(iso = org.springframework.format.annotation.DateTimeFormat.ISO.DATE) java.time.LocalDate fechaHasta) {
        return authService.obtenerEstadisticasPedidosAlmacen(authorization, fechaDesde, fechaHasta);
    }

    @GetMapping("/almacen/estadisticas/cuadres-detalle")
    public List<EstadisticaCuadreProductoResponse> detalleEstadisticasCuadres(
            @RequestHeader(HttpHeaders.AUTHORIZATION) String authorization,
            @RequestParam @org.springframework.format.annotation.DateTimeFormat(iso = org.springframework.format.annotation.DateTimeFormat.ISO.DATE) java.time.LocalDate fechaDesde,
            @RequestParam @org.springframework.format.annotation.DateTimeFormat(iso = org.springframework.format.annotation.DateTimeFormat.ISO.DATE) java.time.LocalDate fechaHasta) {
        return authService.obtenerDetalleEstadisticasCuadres(authorization, fechaDesde, fechaHasta);
    }

    @GetMapping("/almacen/estadisticas/vendedores")
    public List<EstadisticaVendedorResponse> estadisticasVendedores(
            @RequestHeader(HttpHeaders.AUTHORIZATION) String authorization,
            @RequestParam @org.springframework.format.annotation.DateTimeFormat(iso = org.springframework.format.annotation.DateTimeFormat.ISO.DATE) java.time.LocalDate fechaDesde,
            @RequestParam @org.springframework.format.annotation.DateTimeFormat(iso = org.springframework.format.annotation.DateTimeFormat.ISO.DATE) java.time.LocalDate fechaHasta) {
        return authService.obtenerEstadisticasVendedores(authorization, fechaDesde, fechaHasta);
    }

    @GetMapping("/almacen/estadisticas/consumo-productos")
    public List<EstadisticaConsumoProductoDiaResponse> consumoProductosDiario(
            @RequestHeader(HttpHeaders.AUTHORIZATION) String authorization,
            @RequestParam @org.springframework.format.annotation.DateTimeFormat(iso = org.springframework.format.annotation.DateTimeFormat.ISO.DATE) java.time.LocalDate fechaDesde,
            @RequestParam @org.springframework.format.annotation.DateTimeFormat(iso = org.springframework.format.annotation.DateTimeFormat.ISO.DATE) java.time.LocalDate fechaHasta) {
        return authService.obtenerConsumoProductosDiario(authorization, fechaDesde, fechaHasta);
    }

    @GetMapping("/almacen/estadisticas/demoras-caja")
    public List<EstadisticaDemoraCajaResponse> demorasCaja(
            @RequestHeader(HttpHeaders.AUTHORIZATION) String authorization,
            @RequestParam @org.springframework.format.annotation.DateTimeFormat(iso = org.springframework.format.annotation.DateTimeFormat.ISO.DATE) java.time.LocalDate fechaDesde,
            @RequestParam @org.springframework.format.annotation.DateTimeFormat(iso = org.springframework.format.annotation.DateTimeFormat.ISO.DATE) java.time.LocalDate fechaHasta) {
        return authService.obtenerDemorasCaja(authorization, fechaDesde, fechaHasta);
    }

    @GetMapping("/almacen/cuadres/rutas")
    public List<RutaCuadreResponse> rutasCuadreAlmacen(
            @RequestHeader(HttpHeaders.AUTHORIZATION) String authorization,
            @RequestParam @org.springframework.format.annotation.DateTimeFormat(iso = org.springframework.format.annotation.DateTimeFormat.ISO.DATE) java.time.LocalDate fecha) {
        return authService.listarRutasCuadreAlmacen(authorization, fecha);
    }

    @GetMapping("/almacen/cuadres/{idCuadre}")
    public DetalleCuadreAlmacenResponse detalleCuadreAlmacen(
            @RequestHeader(HttpHeaders.AUTHORIZATION) String authorization,
            @org.springframework.web.bind.annotation.PathVariable Integer idCuadre) {
        return authService.obtenerDetalleCuadreAlmacen(authorization, idCuadre);
    }

    @GetMapping("/almacen/cuadres/rutas/{idRuta}/saldo")
    public SaldoRutaResponse saldoRutaCuadreAlmacen(
            @RequestHeader(HttpHeaders.AUTHORIZATION) String authorization,
            @org.springframework.web.bind.annotation.PathVariable Integer idRuta) {
        return authService.obtenerSaldoRutaCuadreAlmacen(authorization, idRuta);
    }

    @GetMapping("/almacen/cuadres/rutas/{idRuta}/productos")
    public List<ProductoCuadreResponse> productosCuadreAlmacen(
            @RequestHeader(HttpHeaders.AUTHORIZATION) String authorization,
            @org.springframework.web.bind.annotation.PathVariable Integer idRuta) {
        return authService.listarProductosCuadreAlmacen(authorization, idRuta);
    }

    @GetMapping("/almacen/cuadres/rutas/{idRuta}/hoy")
    public EstadoCuadreHoyResponse estadoCuadreAlmacenHoy(
            @RequestHeader(HttpHeaders.AUTHORIZATION) String authorization,
            @org.springframework.web.bind.annotation.PathVariable Integer idRuta) {
        return authService.obtenerEstadoCuadreAlmacenHoy(authorization, idRuta);
    }

    @PostMapping("/almacen/cuadres/rutas/{idRuta}/validar")
    public ValidacionCuadreResponse validarCuadreAlmacen(
            @RequestHeader(HttpHeaders.AUTHORIZATION) String authorization,
            @org.springframework.web.bind.annotation.PathVariable Integer idRuta,
            @Valid @RequestBody ValidarImeisCuadreRequest request) {
        return authService.validarImeisCuadreAlmacen(authorization, idRuta, request);
    }

    @PostMapping("/almacen/cuadres/rutas/{idRuta}/finalizar")
    public FinalizarCuadreResponse finalizarCuadreAlmacen(
            @RequestHeader(HttpHeaders.AUTHORIZATION) String authorization,
            @org.springframework.web.bind.annotation.PathVariable Integer idRuta,
            @Valid @RequestBody FinalizarCuadreRequest request) {
        return authService.finalizarCuadreAlmacen(authorization, idRuta, request);
    }

    @GetMapping("/almacen/cuadres-preliminares")
    public List<ResumenCuadreEnRutaResponse> cuadresPreliminaresAlmacen(
            @RequestHeader(HttpHeaders.AUTHORIZATION) String authorization,
            @RequestParam @org.springframework.format.annotation.DateTimeFormat(iso = org.springframework.format.annotation.DateTimeFormat.ISO.DATE) java.time.LocalDate fecha) {
        return authService.listarCuadresEnRutaAlmacen(authorization, fecha);
    }

    @GetMapping("/almacen/cuadres-preliminares/{idCuadreEnRuta}")
    public DetalleCuadreEnRutaResponse detalleCuadrePreliminarAlmacen(
            @RequestHeader(HttpHeaders.AUTHORIZATION) String authorization,
            @org.springframework.web.bind.annotation.PathVariable Integer idCuadreEnRuta) {
        return authService.obtenerDetalleCuadreEnRutaAlmacen(authorization, idCuadreEnRuta);
    }

    @PostMapping("/almacen/cuadres-preliminares/{idCuadreEnRuta}/aprobar")
    public FinalizarCuadreResponse aprobarCuadrePreliminarAlmacen(
            @RequestHeader(HttpHeaders.AUTHORIZATION) String authorization,
            @org.springframework.web.bind.annotation.PathVariable Integer idCuadreEnRuta) {
        return authService.aprobarCuadreEnRutaAlmacen(authorization, idCuadreEnRuta);
    }

    @PostMapping("/almacen/cuadres-preliminares/{idCuadreEnRuta}/modificar-aprobar")
    public FinalizarCuadreResponse modificarYAprobarCuadrePreliminarAlmacen(
            @RequestHeader(HttpHeaders.AUTHORIZATION) String authorization,
            @org.springframework.web.bind.annotation.PathVariable Integer idCuadreEnRuta,
            @Valid @RequestBody FinalizarCuadreRequest request) {
        return authService.modificarYAprobarCuadreEnRutaAlmacen(
                authorization, idCuadreEnRuta, request);
    }

    @GetMapping("/almacen/pedidos/{idPedido}/detalle")
    public List<DetallePedidoResponse> detallePendienteAlmacen(
            @RequestHeader(HttpHeaders.AUTHORIZATION) String authorization,
            @org.springframework.web.bind.annotation.PathVariable Integer idPedido) {
        return authService.obtenerDetallePendienteParaAlmacen(authorization, idPedido);
    }

    @GetMapping("/almacen/pedidos/{idPedido}/productos-asignados")
    public List<ProductoFisicoPedidoResponse> productosAsignadosAlmacen(
            @RequestHeader(HttpHeaders.AUTHORIZATION) String authorization,
            @org.springframework.web.bind.annotation.PathVariable Integer idPedido) {
        return authService.obtenerProductosFisicosPedido(authorization, idPedido);
    }

    @GetMapping("/almacen/pedidos/{idPedido}/validar-tigo-money")
    public com.logingeneral.back.auth.AlmacenDtos.ValidacionTigoMoneyResponse validarTigoMoneyPedido(
            @RequestHeader(HttpHeaders.AUTHORIZATION) String authorization,
            @org.springframework.web.bind.annotation.PathVariable Integer idPedido) {
        return authService.validarTigoMoneyPedido(authorization, idPedido);
    }

    @GetMapping("/almacen/pedidos/{idPedido}/promedio-venta")
    public List<PromedioVentaResponse> promedioVentaPedidoAlmacen(
            @RequestHeader(HttpHeaders.AUTHORIZATION) String authorization,
            @org.springframework.web.bind.annotation.PathVariable Integer idPedido) {
        return authService.obtenerPromedioVentaPedidoAlmacen(authorization, idPedido);
    }

    @GetMapping("/almacen/pedidos/{idPedido}/saldo-ruta")
    public SaldoRutaResponse saldoRutaPedidoAlmacen(
            @RequestHeader(HttpHeaders.AUTHORIZATION) String authorization,
            @org.springframework.web.bind.annotation.PathVariable Integer idPedido) {
        return authService.obtenerSaldoRutaPedidoAlmacen(authorization, idPedido);
    }

    @PutMapping("/almacen/pedidos/{idPedido}")
    public ModificarPedidoAlmacenResponse modificarPedidoAlmacen(
            @RequestHeader(HttpHeaders.AUTHORIZATION) String authorization,
            @org.springframework.web.bind.annotation.PathVariable Integer idPedido,
            @Valid @RequestBody ModificarPedidoAlmacenRequest request) {
        return authService.modificarPedidoAlmacen(authorization, idPedido, request);
    }

    @PostMapping("/almacen/pedidos/{idPedido}/aprobar")
    public AprobarPedidoResponse aprobarPedido(
            @RequestHeader(HttpHeaders.AUTHORIZATION) String authorization,
            @org.springframework.web.bind.annotation.PathVariable Integer idPedido,
            @Valid @RequestBody AprobarPedidoRequest request) {
        return authService.aprobarPedido(authorization, idPedido, request);
    }

    @PostMapping("/almacen/pedidos-directos")
    public CrearPedidoDirectoResponse crearPedidoDirecto(
            @RequestHeader(HttpHeaders.AUTHORIZATION) String authorization,
            @Valid @RequestBody CrearPedidoDirectoRequest request) {
        return authService.crearPedidoDirecto(authorization, request);
    }

    @PostMapping("/almacen/pedidos-directos/validar-imeis")
    public List<com.logingeneral.back.auth.AlmacenDtos.ImeiDirectoValidacionResponse> validarImeisPedidoDirectoAutomatico(
            @RequestHeader(HttpHeaders.AUTHORIZATION) String authorization,
            @Valid @RequestBody com.logingeneral.back.auth.AlmacenDtos.ValidarImeisDirectosRequest request) {
        return authService.validarImeisPedidoDirectoAutomatico(authorization, request.imeis());
    }

    @GetMapping("/almacen/cierre")
    public List<CierreAlmacenProductoResponse> cierreAlmacen(
            @RequestHeader(HttpHeaders.AUTHORIZATION) String authorization,
            @RequestParam java.time.LocalDate fecha) {
        return authService.obtenerCierreAlmacen(authorization, fecha);
    }

    @GetMapping("/almacen/cierre/estado")
    public EstadoCierreAlmacenResponse estadoCierreAlmacen(
            @RequestHeader(HttpHeaders.AUTHORIZATION) String authorization,
            @RequestParam java.time.LocalDate fecha) {
        return authService.obtenerEstadoCierreAlmacen(authorization, fecha);
    }

    @PostMapping("/almacen/cierre")
    public GuardarCierreAlmacenResponse guardarCierreAlmacen(
            @RequestHeader(HttpHeaders.AUTHORIZATION) String authorization,
            @Valid @RequestBody GuardarCierreAlmacenRequest request) {
        return authService.guardarCierreAlmacen(authorization, request);
    }

    @GetMapping("/almacen/pedidos-directos/validar-tigo-money")
    public com.logingeneral.back.auth.AlmacenDtos.ValidacionTigoMoneyResponse validarTigoMoneyDirecto(
            @RequestHeader(HttpHeaders.AUTHORIZATION) String authorization,
            @RequestParam java.math.BigDecimal cantidad) {
        return authService.validarTigoMoneyDirecto(authorization, cantidad);
    }

    @GetMapping("/entidades")
    public List<EntidadResponse> listarEntidades(
            @RequestHeader(HttpHeaders.AUTHORIZATION) String authorization) {
        return authService.listarEntidades(authorization);
    }

    @PostMapping("/depositos")
    public RegistrarDepositoResponse registrarDeposito(
            @RequestHeader(HttpHeaders.AUTHORIZATION) String authorization,
            @Valid @RequestBody RegistrarDepositoRequest request) {
        return authService.registrarDeposito(authorization, request);
    }

    @GetMapping("/depositos")
    public List<DepositoResponse> listarDepositos(
            @RequestHeader(HttpHeaders.AUTHORIZATION) String authorization) {
        return authService.listarDepositosEnRuta(authorization);
    }

    @GetMapping("/contabilidad/depositos-pendientes")
    public List<DepositoContabilidadResponse> listarDepositosPendientesContabilidad(
            @RequestHeader(HttpHeaders.AUTHORIZATION) String authorization) {
        return authService.listarDepositosPendientesContabilidad(authorization);
    }

    @PutMapping("/contabilidad/depositos/{idDeposito}")
    public RegistrarDepositoResponse editarDepositoContabilidad(
            @RequestHeader(HttpHeaders.AUTHORIZATION) String authorization,
            @org.springframework.web.bind.annotation.PathVariable Integer idDeposito,
            @Valid @RequestBody EditarDepositoContabilidadRequest request) {
        return authService.editarDepositoContabilidad(authorization, idDeposito, request);
    }

    @PostMapping("/contabilidad/depositos/{idDeposito}/aprobar")
    public RegistrarDepositoResponse aprobarDepositoContabilidad(
            @RequestHeader(HttpHeaders.AUTHORIZATION) String authorization,
            @org.springframework.web.bind.annotation.PathVariable Integer idDeposito) {
        return authService.aprobarDepositoContabilidad(authorization, idDeposito);
    }

    @GetMapping(value = "/sistemas/cascada/eventos/{jobId}", produces = MediaType.TEXT_EVENT_STREAM_VALUE)
    public SseEmitter eventosCascadaSistemas(
            @RequestHeader(HttpHeaders.AUTHORIZATION) String authorization,
            @org.springframework.web.bind.annotation.PathVariable String jobId) {
        return authService.eventosCascadaSistemas(authorization, jobId);
    }

    @GetMapping("/sistemas/rutas")
    public java.util.List<com.logingeneral.back.auth.SistemasDtos.RutaSistemasResponse> rutasSistemas(
            @RequestHeader(HttpHeaders.AUTHORIZATION) String authorization) {
        return authService.listarRutasSistemas(authorization);
    }

    @GetMapping("/sistemas/rutas/{idRuta}/movimientos")
    public java.util.List<com.logingeneral.back.auth.SistemasDtos.MovimientoRutaResponse> movimientosRutaSistemas(
            @RequestHeader(HttpHeaders.AUTHORIZATION) String authorization,
            @org.springframework.web.bind.annotation.PathVariable Integer idRuta,
            @RequestParam @org.springframework.format.annotation.DateTimeFormat(iso = org.springframework.format.annotation.DateTimeFormat.ISO.DATE) java.time.LocalDate fechaDesde,
            @RequestParam @org.springframework.format.annotation.DateTimeFormat(iso = org.springframework.format.annotation.DateTimeFormat.ISO.DATE) java.time.LocalDate fechaHasta) {
        return authService.listarMovimientosRutaSistemas(authorization, idRuta, fechaDesde, fechaHasta);
    }

    @GetMapping("/sistemas/rutas/{idRuta}/cascada/preview")
    public java.util.List<com.logingeneral.back.auth.SistemasDtos.PreviewCascadaItemResponse> previewCascadaSistemas(
            @RequestHeader(HttpHeaders.AUTHORIZATION) String authorization,
            @org.springframework.web.bind.annotation.PathVariable Integer idRuta,
            @RequestParam @org.springframework.format.annotation.DateTimeFormat(iso = org.springframework.format.annotation.DateTimeFormat.ISO.DATE_TIME) java.time.LocalDateTime desdeFecha) {
        return authService.previewCascadaRutaSistemas(authorization, idRuta, desdeFecha);
    }

    @GetMapping("/sistemas/rutas/{idRuta}/cascada/preview-detalle")
    public java.util.List<com.logingeneral.back.auth.SistemasDtos.PreviewCascadaDetalleResponse> previewDetalleCascadaSistemas(
            @RequestHeader(HttpHeaders.AUTHORIZATION) String authorization,
            @org.springframework.web.bind.annotation.PathVariable Integer idRuta,
            @RequestParam @org.springframework.format.annotation.DateTimeFormat(iso = org.springframework.format.annotation.DateTimeFormat.ISO.DATE_TIME) java.time.LocalDateTime desdeFecha) {
        return authService.previewDetalleCascadaRutaSistemas(authorization, idRuta, desdeFecha);
    }

    @GetMapping("/sistemas/rutas/{idRuta}/cascada/preview-tablas")
    public java.util.List<com.logingeneral.back.auth.SistemasDtos.PreviewTablaCascadaResponse> previewTablasCascadaSistemas(
            @RequestHeader(HttpHeaders.AUTHORIZATION) String authorization,
            @org.springframework.web.bind.annotation.PathVariable Integer idRuta,
            @RequestParam @org.springframework.format.annotation.DateTimeFormat(iso = org.springframework.format.annotation.DateTimeFormat.ISO.DATE_TIME) java.time.LocalDateTime desdeFecha) {
        return authService.previewTablasCascadaRutaSistemas(authorization, idRuta, desdeFecha);
    }

    @PostMapping("/sistemas/rutas/{idRuta}/cascada/ejecutar")
    public com.logingeneral.back.auth.SistemasDtos.EjecutarCascadaResponse ejecutarCascadaSistemas(
            @RequestHeader(HttpHeaders.AUTHORIZATION) String authorization,
            @org.springframework.web.bind.annotation.PathVariable Integer idRuta,
            @Valid @RequestBody com.logingeneral.back.auth.SistemasDtos.EjecutarCascadaRequest request) {
        return authService.ejecutarCascadaRutaSistemas(authorization, idRuta, request);
    }

    // ---------- Chat almacén ↔ técnico (la autorización la hace AuthService con el token) ----------

    @GetMapping("/chat/mensajes")
    public List<ChatDtos.MensajeChatResponse> mensajesChatTecnico(
            @RequestHeader(HttpHeaders.AUTHORIZATION) String authorization,
            @RequestParam(defaultValue = "0") Long desde) {
        return authService.listarMensajesChatTecnico(authorization, desde);
    }

    @PostMapping("/chat/mensajes")
    public ChatDtos.MensajeChatResponse enviarMensajeChatTecnico(
            @RequestHeader(HttpHeaders.AUTHORIZATION) String authorization,
            @Valid @RequestBody ChatDtos.EnviarMensajeChatRequest request) {
        return authService.enviarMensajeChatTecnico(authorization, request);
    }

    @PostMapping("/chat/leido")
    public ResponseEntity<Void> marcarLeidoChatTecnico(
            @RequestHeader(HttpHeaders.AUTHORIZATION) String authorization,
            @Valid @RequestBody ChatDtos.MarcarLeidoChatRequest request) {
        authService.marcarLeidoChatTecnico(authorization, request);
        return ResponseEntity.noContent().build();
    }

    @GetMapping("/chat/resumen")
    public ChatDtos.ResumenChatResponse resumenChatTecnico(
            @RequestHeader(HttpHeaders.AUTHORIZATION) String authorization) {
        return authService.resumenChatTecnico(authorization);
    }

    @GetMapping("/almacen/chat/rutas")
    public List<ChatDtos.ResumenChatResponse> resumenChatAlmacen(
            @RequestHeader(HttpHeaders.AUTHORIZATION) String authorization) {
        return authService.resumenChatAlmacen(authorization);
    }

    @GetMapping("/almacen/chat/rutas/{idRuta}/mensajes")
    public List<ChatDtos.MensajeChatResponse> mensajesChatAlmacen(
            @RequestHeader(HttpHeaders.AUTHORIZATION) String authorization,
            @org.springframework.web.bind.annotation.PathVariable Integer idRuta,
            @RequestParam(defaultValue = "0") Long desde) {
        return authService.listarMensajesChatAlmacen(authorization, idRuta, desde);
    }

    @PostMapping("/almacen/chat/rutas/{idRuta}/mensajes")
    public ChatDtos.MensajeChatResponse enviarMensajeChatAlmacen(
            @RequestHeader(HttpHeaders.AUTHORIZATION) String authorization,
            @org.springframework.web.bind.annotation.PathVariable Integer idRuta,
            @Valid @RequestBody ChatDtos.EnviarMensajeChatRequest request) {
        return authService.enviarMensajeChatAlmacen(authorization, idRuta, request);
    }

    @PostMapping("/almacen/chat/rutas/{idRuta}/leido")
    public ResponseEntity<Void> marcarLeidoChatAlmacen(
            @RequestHeader(HttpHeaders.AUTHORIZATION) String authorization,
            @org.springframework.web.bind.annotation.PathVariable Integer idRuta,
            @Valid @RequestBody ChatDtos.MarcarLeidoChatRequest request) {
        authService.marcarLeidoChatAlmacen(authorization, idRuta, request);
        return ResponseEntity.noContent().build();
    }
}
