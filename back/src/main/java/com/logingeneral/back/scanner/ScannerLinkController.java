package com.logingeneral.back.scanner;

import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.servlet.mvc.method.annotation.SseEmitter;

import com.logingeneral.back.auth.AuthDtos.UsuarioResponse;
import com.logingeneral.back.auth.AuthService;
import com.logingeneral.back.scanner.ProductoScanDtos.ValidarProductosRequest;
import com.logingeneral.back.scanner.ProductoScanDtos.ValidarProductosResponse;
import com.logingeneral.back.scanner.ProductoScanDtos.ValidarProductosPedidoRequest;
import com.logingeneral.back.scanner.ProductoScanDtos.ValidarProductosDirectosRequest;
import com.logingeneral.back.scanner.ProductoScanDtos.ValidarProductosPedidoResponse;
import com.logingeneral.back.scanner.ProductoScanDtos.ProductoPedidoValidacion;
import com.logingeneral.back.auth.PedidoEnRutaDtos.DetallePedidoResponse;
import com.logingeneral.back.auth.CuadreDtos.ProductoCuadreResponse;
import com.logingeneral.back.auth.CuadreDtos.ValidacionCuadreResponse;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;

@RestController
@RequestMapping("/api/scanner")
public class ScannerLinkController {

    private final ScannerLinkService scannerLinkService;
    private final AuthService authService;
    private final NgrokPublicUrlService ngrokPublicUrlService;

    public ScannerLinkController(
            ScannerLinkService scannerLinkService,
            AuthService authService,
            NgrokPublicUrlService ngrokPublicUrlService) {
        this.scannerLinkService = scannerLinkService;
        this.authService = authService;
        this.ngrokPublicUrlService = ngrokPublicUrlService;
    }

    @PostMapping("/vinculaciones")
    public LinkResponse crear(@RequestHeader(HttpHeaders.AUTHORIZATION) String authorization) {
        UsuarioResponse usuario = exigirAlmacenero(authorization);
        ScannerLinkService.ScannerSession session = scannerLinkService.crear(
                usuario.sucursal().id(), usuario.id(), usuario.nombre());
        return new LinkResponse(
                session.token(),
                session.expira(),
                ngrokPublicUrlService.obtenerUrlPublica().orElse(null));
    }

    @PostMapping("/cuadre/vinculaciones")
    public LinkResponse crearVinculacionCuadre(
            @RequestHeader(HttpHeaders.AUTHORIZATION) String authorization) {
        UsuarioResponse usuario = exigirTecnico(authorization);
        ScannerLinkService.ScannerSession session = scannerLinkService.crear(
                usuario.sucursal().id(), usuario.id(), usuario.nombre());
        return new LinkResponse(
                session.token(), session.expira(), ngrokPublicUrlService.obtenerUrlPublica().orElse(null));
    }

    @PostMapping("/cuadre/vinculaciones/{token}/contexto")
    public ScannerLinkService.ScanContext configurarContextoCuadre(
            @RequestHeader(HttpHeaders.AUTHORIZATION) String authorization,
            @PathVariable String token,
            @Valid @RequestBody ContextoCuadreRequest request) {
        UsuarioResponse usuario = exigirTecnico(authorization);
        scannerLinkService.validarPropietario(token, usuario.sucursal().id(), usuario.id());
        ProductoCuadreResponse producto = authService.listarProductosCuadre(authorization).stream()
                .filter(item -> item.idProducto().equals(request.idProducto()))
                .findFirst()
                .orElseThrow(() -> new org.springframework.web.server.ResponseStatusException(
                        HttpStatus.NOT_FOUND, "El producto no tiene saldo fisico en la ruta."));
        return scannerLinkService.configurarContexto(
                token, usuario.sucursal().id(), usuario.id(),
                new ScannerLinkService.ScanContext(
                        0, 0, producto.idProducto(), producto.producto(), producto.cantidadAsignada(), null),
                request.imeisRegistrados());
    }

    @PostMapping("/almacen/cuadre/vinculaciones")
    public LinkResponse crearVinculacionCuadreAlmacen(
            @RequestHeader(HttpHeaders.AUTHORIZATION) String authorization) {
        UsuarioResponse usuario = exigirAlmacenero(authorization);
        ScannerLinkService.ScannerSession session = scannerLinkService.crear(
                usuario.sucursal().id(), usuario.id(), usuario.nombre());
        return new LinkResponse(
                session.token(), session.expira(), ngrokPublicUrlService.obtenerUrlPublica().orElse(null));
    }

    @PostMapping("/almacen/cuadre/vinculaciones/{token}/contexto")
    public ScannerLinkService.ScanContext configurarContextoCuadreAlmacen(
            @RequestHeader(HttpHeaders.AUTHORIZATION) String authorization,
            @PathVariable String token,
            @Valid @RequestBody ContextoCuadreAlmacenRequest request) {
        UsuarioResponse usuario = exigirAlmacenero(authorization);
        scannerLinkService.validarPropietario(token, usuario.sucursal().id(), usuario.id());
        ProductoCuadreResponse producto = authService
                .listarProductosCuadreAlmacen(authorization, request.idRuta()).stream()
                .filter(item -> item.idProducto().equals(request.idProducto()))
                .findFirst()
                .orElseThrow(() -> new org.springframework.web.server.ResponseStatusException(
                        HttpStatus.NOT_FOUND, "El producto no tiene saldo fisico en la ruta."));
        return scannerLinkService.configurarContexto(
                token, usuario.sucursal().id(), usuario.id(),
                new ScannerLinkService.ScanContext(
                        0, 0, producto.idProducto(), producto.producto(),
                        producto.cantidadAsignada(), request.idRuta()),
                request.imeisRegistrados());
    }

    @GetMapping(value = "/almacen/cuadre/vinculaciones/{token}/eventos", produces = MediaType.TEXT_EVENT_STREAM_VALUE)
    public SseEmitter eventosCuadreAlmacen(
            @RequestHeader(HttpHeaders.AUTHORIZATION) String authorization,
            @PathVariable String token) {
        UsuarioResponse usuario = exigirAlmacenero(authorization);
        return scannerLinkService.suscribir(token, usuario.sucursal().id(), usuario.id());
    }

    @DeleteMapping("/almacen/cuadre/vinculaciones/{token}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void cerrarVinculacionCuadreAlmacen(
            @RequestHeader(HttpHeaders.AUTHORIZATION) String authorization,
            @PathVariable String token) {
        UsuarioResponse usuario = exigirAlmacenero(authorization);
        scannerLinkService.cerrar(token, usuario.sucursal().id(), usuario.id());
    }

    @GetMapping(value = "/cuadre/vinculaciones/{token}/eventos", produces = MediaType.TEXT_EVENT_STREAM_VALUE)
    public SseEmitter eventosCuadre(
            @RequestHeader(HttpHeaders.AUTHORIZATION) String authorization,
            @PathVariable String token) {
        UsuarioResponse usuario = exigirTecnico(authorization);
        return scannerLinkService.suscribir(token, usuario.sucursal().id(), usuario.id());
    }

    @DeleteMapping("/cuadre/vinculaciones/{token}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void cerrarVinculacionCuadre(
            @RequestHeader(HttpHeaders.AUTHORIZATION) String authorization,
            @PathVariable String token) {
        UsuarioResponse usuario = exigirTecnico(authorization);
        scannerLinkService.cerrar(token, usuario.sucursal().id(), usuario.id());
    }

    @PostMapping("/productos/validar")
    public ValidarProductosResponse validarProductos(
            @RequestHeader(HttpHeaders.AUTHORIZATION) String authorization,
            @Valid @RequestBody ValidarProductosRequest request) {
        return authService.validarProductosParaTira(authorization, request.imeis());
    }

    @PostMapping("/productos/validar-pedido")
    public ValidarProductosPedidoResponse validarProductosPedido(
            @RequestHeader(HttpHeaders.AUTHORIZATION) String authorization,
            @Valid @RequestBody ValidarProductosPedidoRequest request) {
        UsuarioResponse usuario = exigirAlmacenero(authorization);
        String tokenVinculacion = request.tokenVinculacion() == null
                ? ""
                : request.tokenVinculacion().trim();
        if (!tokenVinculacion.isEmpty()) {
            scannerLinkService.validarPropietario(
                    tokenVinculacion, usuario.sucursal().id(), usuario.id());
        }
        return authService.validarYReservarProductosParaPedido(
                usuario.sucursal().id(), usuario.id(), tokenVinculacion,
                request.idPedido(), request.idDetalle(), request.imeis());
    }

    @PostMapping("/productos/validar-directo")
    public ValidarProductosPedidoResponse validarProductosDirectos(
            @RequestHeader(HttpHeaders.AUTHORIZATION) String authorization,
            @Valid @RequestBody ValidarProductosDirectosRequest request) {
        return authService.validarProductosPedidoDirecto(
                authorization, request.idProducto(), request.cantidadSolicitada(), request.imeis());
    }

    @PostMapping("/vinculaciones/{token}/contexto")
    public ScannerLinkService.ScanContext configurarContexto(
            @RequestHeader(HttpHeaders.AUTHORIZATION) String authorization,
            @PathVariable String token,
            @Valid @RequestBody ContextoRequest request) {
        UsuarioResponse usuario = exigirAlmacenero(authorization);
        scannerLinkService.validarPropietario(token, usuario.sucursal().id(), usuario.id());
        DetallePedidoResponse detalle = authService
                .obtenerDetallePendienteParaAlmacen(authorization, request.idPedido())
                .stream()
                .filter(item -> item.idDetalle().equals(request.idDetalle()))
                .findFirst()
                .orElseThrow(() -> new org.springframework.web.server.ResponseStatusException(
                        HttpStatus.NOT_FOUND, "El detalle no pertenece al pedido."));
        if (request.imeisAsignados().size() > detalle.cantidad()) {
            throw new org.springframework.web.server.ResponseStatusException(
                    HttpStatus.BAD_REQUEST, "La cantidad asignada supera lo solicitado.");
        }
        authService.reservarContextoScanner(
                authorization, token, request.idPedido(), request.idDetalle(), request.imeisAsignados());
        return scannerLinkService.configurarContexto(
                token,
                usuario.sucursal().id(),
                usuario.id(),
                new ScannerLinkService.ScanContext(
                        request.idPedido(), detalle.idDetalle(), detalle.idProducto(),
                        detalle.producto(), detalle.cantidad(), null),
                request.imeisAsignados());
    }

    @PostMapping("/vinculaciones/{token}/contexto-directo")
    public ScannerLinkService.ScanContext configurarContextoDirecto(
            @RequestHeader(HttpHeaders.AUTHORIZATION) String authorization,
            @PathVariable String token,
            @Valid @RequestBody ContextoDirectoRequest request) {
        UsuarioResponse usuario = exigirAlmacenero(authorization);
        scannerLinkService.validarPropietario(token, usuario.sucursal().id(), usuario.id());
        if (request.cantidadSolicitada() < 1 || request.imeisAsignados().size() > request.cantidadSolicitada()) {
            throw new org.springframework.web.server.ResponseStatusException(HttpStatus.BAD_REQUEST, "La cantidad asignada no es valida.");
        }
        return scannerLinkService.configurarContexto(token, usuario.sucursal().id(), usuario.id(),
                new ScannerLinkService.ScanContext(-1, -request.idProducto(), request.idProducto(),
                        request.producto(), request.cantidadSolicitada(), null), request.imeisAsignados());
    }

    @GetMapping(value = "/vinculaciones/{token}/eventos", produces = MediaType.TEXT_EVENT_STREAM_VALUE)
    public SseEmitter eventos(
            @RequestHeader(HttpHeaders.AUTHORIZATION) String authorization,
            @PathVariable String token) {
        UsuarioResponse usuario = exigirAlmacenero(authorization);
        return scannerLinkService.suscribir(token, usuario.sucursal().id(), usuario.id());
    }

    @DeleteMapping("/vinculaciones/{token}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void cerrar(
            @RequestHeader(HttpHeaders.AUTHORIZATION) String authorization,
            @PathVariable String token) {
        UsuarioResponse usuario = exigirAlmacenero(authorization);
        scannerLinkService.validarPropietario(token, usuario.sucursal().id(), usuario.id());
        authService.liberarReservasScanner(authorization, token, null);
        scannerLinkService.cerrar(token, usuario.sucursal().id(), usuario.id());
    }

    @DeleteMapping("/vinculaciones/{token}/pedidos/{idPedido}/reservas")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void liberarPedido(
            @RequestHeader(HttpHeaders.AUTHORIZATION) String authorization,
            @PathVariable String token,
            @PathVariable Integer idPedido) {
        UsuarioResponse usuario = exigirAlmacenero(authorization);
        scannerLinkService.validarPropietario(token, usuario.sucursal().id(), usuario.id());
        authService.liberarReservasScanner(authorization, token, idPedido);
    }

    @GetMapping("/publico/{token}")
    public ScannerLinkService.PublicSession estadoPublico(@PathVariable String token) {
        return scannerLinkService.obtenerPublica(token);
    }

    @PostMapping("/publico/{token}/lecturas")
    public ScannerLinkService.ScanEvent registrar(
            @PathVariable String token,
            @Valid @RequestBody ScanRequest request) {
        ProductoPedidoValidacion validacion = validarLectura(token, request).productos().get(0);
        return scannerLinkService.registrar(token, request.codigo(), validacion);
    }

    @PostMapping("/publico/{token}/validar")
    public ValidarProductosPedidoResponse validarLectura(
            @PathVariable String token,
            @Valid @RequestBody ScanRequest request) {
        ScannerLinkService.ScanContext contexto = scannerLinkService.contexto(token);
        String imei = request.codigo().replaceAll("[^0-9]", "");
        if (scannerLinkService.contieneEnContexto(token, imei)) {
            return respuestaInvalida(imei, contexto, "El IMEI ya fue agregado a este producto del pedido.");
        }
        if (scannerLinkService.cantidadEnContexto(token) >= contexto.cantidadSolicitada()) {
            return respuestaInvalida(imei, contexto, "Ya se completo la cantidad solicitada para este producto.");
        }
        ScannerLinkService.ScannerSession session = scannerLinkService.obtenerSesion(token);
        if (contexto.idPedido() < 0) {
            return authService.validarProductosPedidoDirecto(
                    session.idSucursal(), contexto.idProducto(), contexto.cantidadSolicitada(), java.util.List.of(imei));
        }
        if (contexto.idPedido() == 0) {
            ValidacionCuadreResponse validacion = contexto.idRutaCuadre() == null
                    ? authService.validarImeisCuadrePublico(
                            session.idSucursal(), session.idUsuario(), contexto.idProducto(), java.util.List.of(imei))
                    : authService.validarImeisCuadreAlmacenPublico(
                            session.idSucursal(), contexto.idRutaCuadre(), contexto.idProducto(), java.util.List.of(imei));
            var item = validacion.productos().get(0);
            ProductoPedidoValidacion convertido = new ProductoPedidoValidacion(
                    item.imei(), item.existe(), item.idRuta(), item.vendido(),
                    item.idProductoEncontrado(), item.productoEncontrado(),
                    item.idProductoEsperado(), item.productoEsperado(), contexto.cantidadSolicitada(),
                    item.valido(), item.motivo());
            return new ValidarProductosPedidoResponse(
                    validacion.total(), validacion.validos(), validacion.tiraValida(),
                    java.util.List.of(convertido));
        }
        return authService.validarYReservarProductosParaPedido(
                session.idSucursal(), session.idUsuario(), token,
                contexto.idPedido(), contexto.idDetalle(), java.util.List.of(imei));
    }

    private Integer obtenerSucursalId(String token) {
        return scannerLinkService.obtenerSesion(token).idSucursal();
    }

    private ValidarProductosPedidoResponse respuestaInvalida(
            String imei,
            ScannerLinkService.ScanContext contexto,
            String motivo) {
        ProductoPedidoValidacion producto = new ProductoPedidoValidacion(
                imei, true, 0, 0, contexto.idProducto(), contexto.producto(),
                contexto.idProducto(), contexto.producto(), contexto.cantidadSolicitada(), false, motivo);
        return new ValidarProductosPedidoResponse(1, 0, false, java.util.List.of(producto));
    }

    @PostMapping("/publico/{token}/cerrar-lista")
    public ScannerLinkService.ListClosedEvent cerrarLista(@PathVariable String token) {
        return scannerLinkService.cerrarLista(token);
    }

    @PostMapping("/publico/{token}/reanudar-lista")
    public ScannerLinkService.PublicSession reanudarLista(@PathVariable String token) {
        return scannerLinkService.reanudarLista(token);
    }

    private UsuarioResponse exigirAlmacenero(String authorization) {
        UsuarioResponse usuario = authService.usuarioActual(authorization);
        if (usuario.rol() == null || !"Almacenero".equalsIgnoreCase(usuario.rol())) {
            throw new org.springframework.web.server.ResponseStatusException(
                    HttpStatus.FORBIDDEN, "Esta operación requiere el rol Almacenero.");
        }
        return usuario;
    }

    private UsuarioResponse exigirTecnico(String authorization) {
        UsuarioResponse usuario = authService.usuarioActual(authorization);
        if (usuario.tecnico() == null || !usuario.tecnico().esTecnico() || usuario.tecnico().idRuta() == null) {
            throw new org.springframework.web.server.ResponseStatusException(
                    HttpStatus.FORBIDDEN, "Esta operacion requiere un tecnico con ruta.");
        }
        return usuario;
    }


    public record LinkResponse(String token, java.time.Instant expira, String publicUrl) {
    }

    public record ScanRequest(@NotBlank(message = "El código es requerido.") String codigo) {
    }

    public record ContextoRequest(
            @jakarta.validation.constraints.NotNull(message = "El pedido es requerido.") Integer idPedido,
            @jakarta.validation.constraints.NotNull(message = "El detalle es requerido.") Integer idDetalle,
            @jakarta.validation.constraints.NotNull(message = "Los IMEI asignados son requeridos.")
            java.util.List<String> imeisAsignados) {
    }

    public record ContextoDirectoRequest(
            @jakarta.validation.constraints.NotNull(message = "El producto es requerido.") Integer idProducto,
            @jakarta.validation.constraints.NotBlank(message = "El nombre del producto es requerido.") String producto,
            @jakarta.validation.constraints.NotNull(message = "La cantidad es requerida.") Integer cantidadSolicitada,
            @jakarta.validation.constraints.NotNull(message = "Los IMEI asignados son requeridos.")
            java.util.List<String> imeisAsignados) {
    }

    public record ContextoCuadreRequest(
            @jakarta.validation.constraints.NotNull(message = "El producto es requerido.") Integer idProducto,
            @jakarta.validation.constraints.NotNull(message = "Los IMEI registrados son requeridos.")
            java.util.List<String> imeisRegistrados) {
    }

    public record ContextoCuadreAlmacenRequest(
            @jakarta.validation.constraints.NotNull(message = "La ruta es requerida.") Integer idRuta,
            @jakarta.validation.constraints.NotNull(message = "El producto es requerido.") Integer idProducto,
            @jakarta.validation.constraints.NotNull(message = "Los IMEI registrados son requeridos.")
            java.util.List<String> imeisRegistrados) {
    }
}
