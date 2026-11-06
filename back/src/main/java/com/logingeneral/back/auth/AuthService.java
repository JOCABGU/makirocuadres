package com.logingeneral.back.auth;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.Base64;
import java.util.List;
import java.math.BigDecimal;

import org.springframework.http.HttpStatus;
import org.springframework.dao.DataAccessException;
import org.springframework.stereotype.Service;
import org.springframework.web.server.ResponseStatusException;

import com.logingeneral.back.auth.AuthDtos.LoginRequest;
import com.logingeneral.back.auth.AuthDtos.LoginResponse;
import com.logingeneral.back.auth.AuthDtos.SucursalResponse;
import com.logingeneral.back.auth.AuthDtos.TecnicoResponse;
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
import com.logingeneral.back.auth.AlmacenDtos.ProductoFisicoDirectoRequest;
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
import com.logingeneral.back.auth.SaldoRutaDtos.SaldoProducto;
import com.logingeneral.back.auth.SaldoRutaDtos.SaldoRutaResponse;
import com.logingeneral.back.auth.EstadisticasAlmacenDtos.EstadisticaPedidosDiaRutaResponse;
import com.logingeneral.back.auth.EstadisticasAlmacenDtos.EstadisticaCuadreProductoResponse;
import com.logingeneral.back.auth.EstadisticasAlmacenDtos.EstadisticaVendedorResponse;
import com.logingeneral.back.auth.EstadisticasAlmacenDtos.EstadisticaConsumoProductoDiaResponse;
import com.logingeneral.back.auth.EstadisticasAlmacenDtos.EstadisticaDemoraCajaResponse;
import com.logingeneral.back.auth.CuadreDtos.ProductoCuadreResponse;
import com.logingeneral.back.auth.CuadreDtos.ValidarImeisCuadreRequest;
import com.logingeneral.back.auth.CuadreDtos.ValidacionCuadreResponse;
import com.logingeneral.back.auth.CuadreDtos.FinalizarCuadreRequest;
import com.logingeneral.back.auth.CuadreDtos.FinalizarCuadreResponse;
import com.logingeneral.back.auth.CuadreDtos.TiraCuadreRequest;
import com.logingeneral.back.scanner.ProductoScanDtos.ProductoValidacion;
import com.logingeneral.back.scanner.ProductoScanDtos.ValidarProductosResponse;
import com.logingeneral.back.scanner.ProductoScanDtos.ProductoPedidoValidacion;
import com.logingeneral.back.scanner.ProductoScanDtos.ValidarProductosPedidoResponse;
import com.logingeneral.back.auth.DepositoEnRutaDtos.EntidadResponse;
import com.logingeneral.back.auth.DepositoEnRutaDtos.RegistrarDepositoRequest;
import com.logingeneral.back.auth.DepositoEnRutaDtos.RegistrarDepositoResponse;
import com.logingeneral.back.auth.DepositoEnRutaDtos.DepositoResponse;
import com.logingeneral.back.auth.DepositoEnRutaDtos.DepositoContabilidadResponse;
import com.logingeneral.back.auth.DepositoEnRutaDtos.EditarDepositoContabilidadRequest;

@Service
public class AuthService {

    private final CentralProcedureClient centralProcedureClient;
    private final SucursalAuthProcedureClient sucursalAuthProcedureClient;
    private final JwtService jwtService;
    private final PedidoEventService pedidoEventService;
    private final SistemasEventService sistemasEventService;
    private final PasswordResetService passwordResetService;

    public AuthService(
            CentralProcedureClient centralProcedureClient,
            SucursalAuthProcedureClient sucursalAuthProcedureClient,
            JwtService jwtService,
            PedidoEventService pedidoEventService,
            SistemasEventService sistemasEventService,
            PasswordResetService passwordResetService) {
        this.centralProcedureClient = centralProcedureClient;
        this.sucursalAuthProcedureClient = sucursalAuthProcedureClient;
        this.jwtService = jwtService;
        this.pedidoEventService = pedidoEventService;
        this.sistemasEventService = sistemasEventService;
        this.passwordResetService = passwordResetService;
    }

    public List<SucursalResponse> listarSucursales() {
        return centralProcedureClient.listarSucursalesActivas();
    }

    public LoginResponse login(LoginRequest request) {
        String login = request.usuario().trim();
        String passwordHash = hashMd5Base64(request.password());

        SucursalConnection sucursal = centralProcedureClient.obtenerConexion(request.idSucursal())
                .orElseThrow(() -> new ResponseStatusException(
                        HttpStatus.BAD_REQUEST,
                        "La sucursal seleccionada no está disponible."));

        SucursalAuthProcedureClient.SucursalUser usuarioSucursal = sucursalAuthProcedureClient
                .autenticar(sucursal, login, passwordHash)
                .orElseThrow(() -> new ResponseStatusException(
                        HttpStatus.UNAUTHORIZED,
                        "Usuario, contraseña o sucursal incorrectos."));

        TecnicoResponse tecnico = sucursalAuthProcedureClient.obtenerTecnico(sucursal, usuarioSucursal.id());
        UsuarioResponse usuario = new UsuarioResponse(
                usuarioSucursal.id(),
                usuarioSucursal.nombre(),
                usuarioSucursal.loggin(),
                usuarioSucursal.idRol(),
                usuarioSucursal.rol(),
                new SucursalResponse(sucursal.id(), sucursal.nombre()),
                tecnico);

        JwtService.GeneratedToken generated = jwtService.generate(usuario);
        return new LoginResponse(generated.token(), generated.expira(), usuario);
    }

    public UsuarioResponse usuarioActual(String authorization) {
        UsuarioResponse usuario = usuarioActualSinBloqueo(authorization);
        if (passwordResetService.pendiente(usuario)) {
            throw new ResponseStatusException(HttpStatus.LOCKED, "Primero debes cambiar tu contraseña.");
        }
        return usuario;
    }

    public UsuarioResponse usuarioActualSinBloqueo(String authorization) {
        return jwtService.parse(obtenerBearerToken(authorization));
    }

    public void logout(String authorization) {
        // JWT es stateless: se valida el token y el cliente lo elimina localmente.
        jwtService.parse(obtenerBearerToken(authorization));
    }

    public ValidarProductosResponse validarProductosParaTira(
            String authorization,
            List<String> valores) {
        UsuarioResponse almacenero = exigirAlmacenero(authorization);
        java.util.LinkedHashSet<String> unicos = new java.util.LinkedHashSet<>();
        for (String valor : valores) {
            String imei = valor == null ? "" : valor.trim().replaceAll("[^0-9]", "");
            if (imei.isEmpty() || imei.length() > 18) {
                throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Todos los IMEI deben ser numéricos y válidos.");
            }
            if (!unicos.add(imei)) {
                throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "La tira contiene IMEI duplicados.");
            }
        }
        List<Long> numeros;
        try {
            numeros = unicos.stream().map(Long::valueOf).toList();
        } catch (NumberFormatException ex) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Uno de los IMEI está fuera del rango permitido.");
        }
        java.util.Map<String, ProductoValidacion> encontrados = sucursalAuthProcedureClient
                .validarProductosParaTira(obtenerSucursal(almacenero), numeros);
        List<ProductoValidacion> resultados = unicos.stream()
                .map(imei -> encontrados.getOrDefault(
                        imei,
                        new ProductoValidacion(imei, false, null, null, false, "El IMEI no existe en tbl_Productos.")))
                .toList();
        int validos = (int) resultados.stream().filter(ProductoValidacion::valido).count();
        return new ValidarProductosResponse(resultados.size(), validos, validos == resultados.size(), resultados);
    }

    public ValidarProductosPedidoResponse validarProductosParaPedido(
            Integer idSucursal,
            Integer idPedido,
            Integer idDetalle,
            List<String> valores) {
        java.util.LinkedHashSet<String> unicos = normalizarImeis(valores);
        List<Long> numeros;
        try {
            numeros = unicos.stream().map(Long::valueOf).toList();
        } catch (NumberFormatException ex) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Uno de los IMEI esta fuera del rango permitido.");
        }
        SucursalConnection sucursal = centralProcedureClient.obtenerConexion(idSucursal)
                .orElseThrow(() -> new ResponseStatusException(
                        HttpStatus.SERVICE_UNAVAILABLE,
                        "No se encontro la conexion de la sucursal."));
        java.util.Map<String, ProductoPedidoValidacion> encontrados = sucursalAuthProcedureClient
                .validarProductosParaPedido(sucursal, idPedido, idDetalle, numeros);
        List<ProductoPedidoValidacion> resultados = unicos.stream()
                .map(imei -> encontrados.getOrDefault(
                        imei,
                        new ProductoPedidoValidacion(
                                imei, false, null, null, null, null, null, null, null,
                                false, "El IMEI no existe en tbl_Productos.")))
                .toList();
        int validos = (int) resultados.stream().filter(ProductoPedidoValidacion::valido).count();
        return new ValidarProductosPedidoResponse(
                resultados.size(), validos, validos == resultados.size(), resultados);
    }

    public ValidarProductosPedidoResponse validarProductosParaPedido(
            String authorization,
            Integer idPedido,
            Integer idDetalle,
            List<String> valores) {
        UsuarioResponse almacenero = exigirAlmacenero(authorization);
        return validarProductosParaPedido(almacenero.sucursal().id(), idPedido, idDetalle, valores);
    }

    public ValidarProductosPedidoResponse validarProductosPedidoDirecto(
            Integer idSucursal, Integer idProducto, Integer cantidadSolicitada, List<String> valores) {
        if (cantidadSolicitada == null || cantidadSolicitada < 1) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "La cantidad solicitada no es valida.");
        }
        java.util.LinkedHashSet<String> unicos = normalizarImeis(valores);
        SucursalConnection sucursal = centralProcedureClient.obtenerConexion(idSucursal)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE, "No se encontro la conexion de la sucursal."));
        java.util.Map<String, ProductoPedidoValidacion> encontrados = sucursalAuthProcedureClient
                .validarProductosPedidoDirecto(sucursal, idProducto, cantidadSolicitada, convertirImeis(unicos));
        List<ProductoPedidoValidacion> resultados = unicos.stream().map(imei -> encontrados.getOrDefault(imei,
                new ProductoPedidoValidacion(imei,false,null,null,null,null,idProducto,null,cantidadSolicitada,false,"El IMEI no existe en tbl_Productos."))).toList();
        int validos = (int) resultados.stream().filter(ProductoPedidoValidacion::valido).count();
        return new ValidarProductosPedidoResponse(resultados.size(),validos,validos==resultados.size(),resultados);
    }

    public ValidarProductosPedidoResponse validarProductosPedidoDirecto(
            String authorization, Integer idProducto, Integer cantidadSolicitada, List<String> valores) {
        UsuarioResponse almacenero = exigirAlmacenero(authorization);
        return validarProductosPedidoDirecto(almacenero.sucursal().id(), idProducto, cantidadSolicitada, valores);
    }

    public void reservarContextoScanner(
            String authorization,
            String tokenVinculacion,
            Integer idPedido,
            Integer idDetalle,
            List<String> imeisConservar) {
        UsuarioResponse almacenero = exigirAlmacenero(authorization);
        java.util.LinkedHashSet<String> unicos = normalizarImeis(imeisConservar);
        try {
            sucursalAuthProcedureClient.reservarContextoScanner(
                    obtenerSucursal(almacenero),
                    idPedido,
                    idDetalle,
                    tokenVinculacion,
                    almacenero.id(),
                    convertirImeis(unicos));
        } catch (DataAccessException ex) {
            throw conflictoReserva(ex);
        }
    }

    public ValidarProductosPedidoResponse validarYReservarProductosParaPedido(
            Integer idSucursal,
            Integer idUsuario,
            String tokenVinculacion,
            Integer idPedido,
            Integer idDetalle,
            List<String> valores) {
        if (tokenVinculacion == null || tokenVinculacion.isBlank()) {
            return validarProductosParaPedido(idSucursal, idPedido, idDetalle, valores);
        }
        java.util.LinkedHashSet<String> unicos = normalizarImeis(valores);
        SucursalConnection sucursal = centralProcedureClient.obtenerConexion(idSucursal)
                .orElseThrow(() -> new ResponseStatusException(
                        HttpStatus.SERVICE_UNAVAILABLE,
                        "No se encontro la conexion de la sucursal."));
        try {
            java.util.Map<String, ProductoPedidoValidacion> encontrados = sucursalAuthProcedureClient
                    .validarYReservarProductosParaPedido(
                            sucursal, idPedido, idDetalle, tokenVinculacion, idUsuario, convertirImeis(unicos));
            List<ProductoPedidoValidacion> resultados = unicos.stream()
                    .map(imei -> encontrados.getOrDefault(
                            imei,
                            new ProductoPedidoValidacion(
                                    imei, false, null, null, null, null, null, null, null,
                                    false, "El IMEI no existe en tbl_Productos.")))
                    .toList();
            int validos = (int) resultados.stream().filter(ProductoPedidoValidacion::valido).count();
            return new ValidarProductosPedidoResponse(
                    resultados.size(), validos, validos == resultados.size(), resultados);
        } catch (DataAccessException ex) {
            throw conflictoReserva(ex);
        }
    }

    public void liberarReservasScanner(
            String authorization,
            String tokenVinculacion,
            Integer idPedido) {
        UsuarioResponse almacenero = exigirAlmacenero(authorization);
        try {
            sucursalAuthProcedureClient.liberarReservasScanner(
                    obtenerSucursal(almacenero), tokenVinculacion, almacenero.id(), idPedido);
        } catch (DataAccessException ex) {
            throw conflictoReserva(ex);
        }
    }

    private List<Long> convertirImeis(java.util.Collection<String> imeis) {
        try {
            return imeis.stream().map(Long::valueOf).toList();
        } catch (NumberFormatException ex) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Uno de los IMEI esta fuera del rango permitido.");
        }
    }

    private ResponseStatusException conflictoReserva(DataAccessException ex) {
        Throwable causa = ex.getMostSpecificCause();
        String mensaje = causa == null || causa.getMessage() == null
                ? "No se pudo reservar el pedido o sus productos."
                : causa.getMessage();
        return new ResponseStatusException(HttpStatus.CONFLICT, mensaje);
    }

    private java.util.LinkedHashSet<String> normalizarImeis(List<String> valores) {
        java.util.LinkedHashSet<String> unicos = new java.util.LinkedHashSet<>();
        for (String valor : valores) {
            String imei = valor == null ? "" : valor.trim().replaceAll("[^0-9]", "");
            if (imei.isEmpty() || imei.length() > 18) {
                throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Todos los IMEI deben ser numericos y validos.");
            }
            if (!unicos.add(imei)) {
                throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "La tira contiene IMEI duplicados.");
            }
        }
        return unicos;
    }

    public SaldoRutaResponse obtenerSaldoRuta(String authorization) {
        UsuarioResponse usuario = usuarioActual(authorization);
        TecnicoResponse tecnico = usuario.tecnico();
        if (tecnico == null || !tecnico.esTecnico()) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN, "El usuario no es técnico.");
        }
        if (tecnico.idRuta() == null) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "El técnico no tiene una ruta activa.");
        }

        SucursalConnection sucursal = centralProcedureClient.obtenerConexion(usuario.sucursal().id())
                .orElseThrow(() -> new ResponseStatusException(
                        HttpStatus.SERVICE_UNAVAILABLE,
                        "No se encontró la conexión de la sucursal."));
        List<SaldoProducto> productos = sucursalAuthProcedureClient
                .obtenerSaldoRuta(sucursal, tecnico.idRuta());
        int totalUnidades = productos.stream().mapToInt(SaldoProducto::cantidad).sum();
        BigDecimal valorTotal = productos.stream()
                .map(SaldoProducto::valorTotal)
                .reduce(BigDecimal.ZERO, BigDecimal::add);
        return new SaldoRutaResponse(
                tecnico.idRuta(),
                tecnico.nombreRuta(),
                productos.size(),
                totalUnidades,
                valorTotal,
                productos);
    }

    public CrearPedidoResponse crearPedidoEnRuta(
            String authorization,
            CrearPedidoRequest request) {
        UsuarioResponse usuario = usuarioActual(authorization);
        TecnicoResponse tecnico = usuario.tecnico();
        if (tecnico == null || !tecnico.esTecnico()) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN, "El usuario no es técnico.");
        }
        if (tecnico.idRuta() == null || tecnico.idVendedor() == null) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "El técnico no tiene una ruta activa.");
        }

        SucursalConnection sucursal = centralProcedureClient.obtenerConexion(usuario.sucursal().id())
                .orElseThrow(() -> new ResponseStatusException(
                        HttpStatus.SERVICE_UNAVAILABLE,
                        "No se encontró la conexión de la sucursal."));

        CrearPedidoResponse creado = sucursalAuthProcedureClient.crearPedidoEnRuta(
                sucursal,
                tecnico.idRuta(),
                tecnico.idVendedor(),
                usuario.id(),
                request.detalles(),
                request.observacion());
        pedidoEventService.publicar(
                usuario.sucursal().id(),
                new PedidoEventService.PedidoCreadoEvent(
                        creado.idPedido(),
                        tecnico.idRuta(),
                        tecnico.nombreRuta(),
                        usuario.nombre(),
                        creado.fechaRegistro()));
        return creado;
    }

    public org.springframework.web.servlet.mvc.method.annotation.SseEmitter eventosPedidos(
            String authorization) {
        UsuarioResponse almacenero = exigirAlmacenero(authorization);
        return pedidoEventService.suscribir(almacenero.sucursal().id());
    }

    public List<TipoProductoResponse> listarTiposProducto(String authorization) {
        UsuarioResponse usuario = usuarioActual(authorization);
        return sucursalAuthProcedureClient.listarTiposProducto(obtenerSucursal(usuario));
    }

    public List<ProductoPedidoResponse> listarProductosPorTipo(
            String authorization,
            Integer idTipoProducto) {
        UsuarioResponse usuario = usuarioActual(authorization);
        return sucursalAuthProcedureClient.listarProductosPorTipo(
                obtenerSucursal(usuario), idTipoProducto);
    }

    public List<PromedioVentaResponse> obtenerPromedioVentaRuta(String authorization) {
        UsuarioResponse usuario = usuarioActual(authorization);
        TecnicoResponse tecnico = usuario.tecnico();
        if (tecnico == null || !tecnico.esTecnico()) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN, "El usuario no es técnico.");
        }
        if (tecnico.idRuta() == null) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "El técnico no tiene una ruta activa.");
        }
        return sucursalAuthProcedureClient.obtenerPromedioVentaRuta(
                obtenerSucursal(usuario), java.time.LocalDate.now(), tecnico.idRuta());
    }

    private SucursalConnection obtenerSucursal(UsuarioResponse usuario) {
        return centralProcedureClient.obtenerConexion(usuario.sucursal().id())
                .orElseThrow(() -> new ResponseStatusException(
                        HttpStatus.SERVICE_UNAVAILABLE,
                        "No se encontró la conexión de la sucursal."));
    }

    public List<PedidoResumenResponse> listarPedidosEnRuta(String authorization) {
        UsuarioResponse usuario = usuarioActual(authorization);
        TecnicoResponse tecnico = exigirTecnicoConRuta(usuario);
        return sucursalAuthProcedureClient.listarPedidosEnRuta(
                obtenerSucursal(usuario), usuario.id(), tecnico.idRuta());
    }

    public List<DetallePedidoResponse> obtenerDetallePedidoEnRuta(
            String authorization,
            Integer idPedido) {
        UsuarioResponse usuario = usuarioActual(authorization);
        TecnicoResponse tecnico = exigirTecnicoConRuta(usuario);
        List<DetallePedidoResponse> detalles = sucursalAuthProcedureClient.obtenerDetallePedidoEnRuta(
                obtenerSucursal(usuario), idPedido, usuario.id(), tecnico.idRuta());
        if (detalles.isEmpty()) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "El pedido no existe o no pertenece al usuario.");
        }
        return detalles;
    }

    private TecnicoResponse exigirTecnicoConRuta(UsuarioResponse usuario) {
        TecnicoResponse tecnico = usuario.tecnico();
        if (tecnico == null || !tecnico.esTecnico()) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN, "El usuario no es técnico.");
        }
        if (tecnico.idRuta() == null) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "El técnico no tiene una ruta activa.");
        }
        return tecnico;
    }

    public List<ProductoCuadreResponse> listarProductosCuadre(String authorization) {
        UsuarioResponse usuario = usuarioActual(authorization);
        TecnicoResponse tecnico = exigirTecnicoConRuta(usuario);
        return sucursalAuthProcedureClient.listarProductosCuadre(
                obtenerSucursal(usuario), tecnico.idRuta());
    }

    public CuadreDtos.EstadoCuadreHoyResponse obtenerEstadoCuadreHoy(String authorization) {
        UsuarioResponse usuario = usuarioActual(authorization);
        TecnicoResponse tecnico = exigirTecnicoConRuta(usuario);
        return sucursalAuthProcedureClient.obtenerEstadoCuadreEnRutaHoy(
                obtenerSucursal(usuario), tecnico.idRuta());
    }

    public ValidacionCuadreResponse validarImeisCuadre(
            String authorization,
            ValidarImeisCuadreRequest request) {
        UsuarioResponse usuario = usuarioActual(authorization);
        TecnicoResponse tecnico = exigirTecnicoConRuta(usuario);
        List<String> imeis = normalizarImeisCuadre(request.imeis());
        return sucursalAuthProcedureClient.validarImeisCuadre(
                obtenerSucursal(usuario), tecnico.idRuta(), request.idProducto(), imeis);
    }

    public ValidacionCuadreResponse validarImeisCuadrePublico(
            Integer idSucursal,
            Integer idUsuario,
            Integer idProducto,
            List<String> valores) {
        SucursalConnection sucursal = centralProcedureClient.obtenerConexion(idSucursal)
                .orElseThrow(() -> new ResponseStatusException(
                        HttpStatus.SERVICE_UNAVAILABLE, "No se encontro la conexion de la sucursal."));
        TecnicoResponse tecnico = sucursalAuthProcedureClient.obtenerTecnico(sucursal, idUsuario);
        if (tecnico == null || !tecnico.esTecnico() || tecnico.idRuta() == null) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN, "La vinculacion no pertenece a un tecnico con ruta.");
        }
        return sucursalAuthProcedureClient.validarImeisCuadre(
                sucursal, tecnico.idRuta(), idProducto, normalizarImeisCuadre(valores));
    }

    public FinalizarCuadreResponse finalizarCuadre(
            String authorization,
            FinalizarCuadreRequest request) {
        UsuarioResponse usuario = usuarioActual(authorization);
        TecnicoResponse tecnico = exigirTecnicoConRuta(usuario);
        if (tecnico.idVendedor() == null) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "El tecnico no tiene vendedor asociado.");
        }
        List<TiraCuadreRequest> tiras = validarTirasCuadre(request);
        try {
            return sucursalAuthProcedureClient.crearCuadreEnRuta(
                    obtenerSucursal(usuario), tecnico.idRuta(), tecnico.idVendedor(), usuario.id(),
                    request.observacion() == null ? "" : request.observacion().trim(), tiras);
        } catch (DataAccessException ex) {
            throw conflictoReserva(ex);
        }
    }

    private List<String> normalizarImeisCuadre(List<String> valores) {
        java.util.LinkedHashSet<String> unicos = new java.util.LinkedHashSet<>();
        for (String valor : valores) {
            String imei = valor == null ? "" : valor.replaceAll("[^0-9]", "");
            if (imei.isEmpty() || imei.length() > 18) {
                throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Todos los IMEI deben ser numericos y validos.");
            }
            if (!unicos.add(imei)) {
                throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "La tira contiene IMEI duplicados.");
            }
        }
        return List.copyOf(unicos);
    }

    public List<TecnicoPendientesResponse> listarTecnicosParaAlmacen(String authorization) {
        UsuarioResponse almacenero = exigirAlmacenero(authorization);
        return sucursalAuthProcedureClient.listarTecnicosParaAlmacen(obtenerSucursal(almacenero));
    }

    public List<PedidoTecnicoResponse> listarPedidosPendientesTecnico(
            String authorization,
            Integer idUsuarioTecnico) {
        UsuarioResponse almacenero = exigirAlmacenero(authorization);
        return sucursalAuthProcedureClient.listarPedidosPendientesTecnico(
                obtenerSucursal(almacenero), idUsuarioTecnico);
    }

    public List<DetallePedidoResponse> obtenerDetallePedidoParaAlmacen(
            String authorization,
            Integer idUsuarioTecnico,
            Integer idPedido) {
        UsuarioResponse almacenero = exigirAlmacenero(authorization);
        List<DetallePedidoResponse> detalles = sucursalAuthProcedureClient.obtenerDetallePedidoParaAlmacen(
                obtenerSucursal(almacenero), idPedido, idUsuarioTecnico);
        if (detalles.isEmpty()) {
            throw new ResponseStatusException(
                    HttpStatus.NOT_FOUND,
                    "El pedido pendiente no existe o no pertenece al técnico seleccionado.");
        }
        return detalles;
    }

    private UsuarioResponse exigirAlmacenero(String authorization) {
        UsuarioResponse usuario = usuarioActual(authorization);
        if (usuario.rol() == null || !"Almacenero".equalsIgnoreCase(usuario.rol())) {
            throw new ResponseStatusException(
                    HttpStatus.FORBIDDEN,
                    "Esta operación requiere el rol Almacenero.");
        }
        return usuario;
    }

    public List<RutaPendientesResponse> listarRutasParaAlmacen(
            String authorization,
            java.time.LocalDate fechaDesde,
            java.time.LocalDate fechaHasta) {
        validarRango(fechaDesde, fechaHasta);
        UsuarioResponse almacenero = exigirAlmacenero(authorization);
        return sucursalAuthProcedureClient.listarRutasParaAlmacen(
                obtenerSucursal(almacenero), fechaDesde, fechaHasta);
    }

    public List<PedidoPendienteAlmacenResponse> listarPedidosPendientesAlmacen(
            String authorization,
            java.time.LocalDate fechaDesde,
            java.time.LocalDate fechaHasta,
            Integer idRuta,
            Integer estadoAprobado) {
        validarRango(fechaDesde, fechaHasta);
        UsuarioResponse almacenero = exigirAlmacenero(authorization);
        return sucursalAuthProcedureClient.listarPedidosPendientesAlmacen(
                obtenerSucursal(almacenero), fechaDesde, fechaHasta, idRuta, estadoAprobado);
    }

    public List<EstadisticaPedidosDiaRutaResponse> obtenerEstadisticasPedidosAlmacen(
            String authorization,
            java.time.LocalDate fechaDesde,
            java.time.LocalDate fechaHasta) {
        validarRango(fechaDesde, fechaHasta);
        if (java.time.temporal.ChronoUnit.DAYS.between(fechaDesde, fechaHasta) > 366) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "El rango estadístico no puede superar 366 días.");
        }
        UsuarioResponse almacenero = exigirAlmacenero(authorization);
        return sucursalAuthProcedureClient.obtenerEstadisticasPedidosAlmacen(
                obtenerSucursal(almacenero), fechaDesde, fechaHasta);
    }

    public List<EstadisticaCuadreProductoResponse> obtenerDetalleEstadisticasCuadres(
            String authorization,
            java.time.LocalDate fechaDesde,
            java.time.LocalDate fechaHasta) {
        validarRango(fechaDesde, fechaHasta);
        if (java.time.temporal.ChronoUnit.DAYS.between(fechaDesde, fechaHasta) > 366) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "El rango estadistico no puede superar 366 dias.");
        }
        UsuarioResponse almacenero = exigirAlmacenero(authorization);
        return sucursalAuthProcedureClient.obtenerDetalleEstadisticasCuadres(
                obtenerSucursal(almacenero), fechaDesde, fechaHasta);
    }

    public List<EstadisticaVendedorResponse> obtenerEstadisticasVendedores(
            String authorization, java.time.LocalDate fechaDesde, java.time.LocalDate fechaHasta) {
        validarRangoEstadistico(fechaDesde, fechaHasta);
        UsuarioResponse almacenero = exigirAlmacenero(authorization);
        return sucursalAuthProcedureClient.obtenerEstadisticasVendedores(
                obtenerSucursal(almacenero), fechaDesde, fechaHasta);
    }

    public List<EstadisticaConsumoProductoDiaResponse> obtenerConsumoProductosDiario(
            String authorization, java.time.LocalDate fechaDesde, java.time.LocalDate fechaHasta) {
        validarRangoEstadistico(fechaDesde, fechaHasta);
        UsuarioResponse almacenero = exigirAlmacenero(authorization);
        return sucursalAuthProcedureClient.obtenerConsumoProductosDiario(
                obtenerSucursal(almacenero), fechaDesde, fechaHasta);
    }

    public List<EstadisticaDemoraCajaResponse> obtenerDemorasCaja(
            String authorization, java.time.LocalDate fechaDesde, java.time.LocalDate fechaHasta) {
        validarRangoEstadistico(fechaDesde, fechaHasta);
        UsuarioResponse almacenero = exigirAlmacenero(authorization);
        return sucursalAuthProcedureClient.obtenerDemorasCaja(
                obtenerSucursal(almacenero), fechaDesde, fechaHasta);
    }

    private void validarRangoEstadistico(java.time.LocalDate fechaDesde, java.time.LocalDate fechaHasta) {
        validarRango(fechaDesde, fechaHasta);
        if (java.time.temporal.ChronoUnit.DAYS.between(fechaDesde, fechaHasta) > 366) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "El rango estadistico no puede superar 366 dias.");
        }
    }

    public List<CuadreAlmacenDtos.RutaCuadreResponse> listarRutasCuadreAlmacen(
            String authorization,
            java.time.LocalDate fecha) {
        UsuarioResponse almacenero = exigirAlmacenero(authorization);
        return sucursalAuthProcedureClient.listarRutasCuadreAlmacen(
                obtenerSucursal(almacenero), fecha);
    }

    public CuadreAlmacenDtos.DetalleCuadreAlmacenResponse obtenerDetalleCuadreAlmacen(
            String authorization,
            Integer idCuadre) {
        UsuarioResponse almacenero = exigirAlmacenero(authorization);
        return sucursalAuthProcedureClient.obtenerDetalleCuadreAlmacen(
                obtenerSucursal(almacenero), idCuadre);
    }

    public List<CuadreEnRutaDtos.ResumenCuadreEnRutaResponse> listarCuadresEnRutaAlmacen(
            String authorization, java.time.LocalDate fecha) {
        UsuarioResponse almacenero = exigirAlmacenero(authorization);
        return sucursalAuthProcedureClient.listarCuadresEnRutaAlmacen(obtenerSucursal(almacenero), fecha);
    }

    public CuadreEnRutaDtos.DetalleCuadreEnRutaResponse obtenerDetalleCuadreEnRutaAlmacen(
            String authorization, Integer idCuadreEnRuta) {
        UsuarioResponse almacenero = exigirAlmacenero(authorization);
        return sucursalAuthProcedureClient.obtenerDetalleCuadreEnRutaAlmacen(
                obtenerSucursal(almacenero), idCuadreEnRuta);
    }

    public FinalizarCuadreResponse aprobarCuadreEnRutaAlmacen(
            String authorization, Integer idCuadreEnRuta) {
        UsuarioResponse almacenero = exigirAlmacenero(authorization);
        try {
            return sucursalAuthProcedureClient.aprobarCuadreEnRuta(
                    obtenerSucursal(almacenero), idCuadreEnRuta, almacenero.nombre(), false, List.of());
        } catch (DataAccessException ex) {
            throw conflictoReserva(ex);
        }
    }

    public FinalizarCuadreResponse modificarYAprobarCuadreEnRutaAlmacen(
            String authorization, Integer idCuadreEnRuta, FinalizarCuadreRequest request) {
        UsuarioResponse almacenero = exigirAlmacenero(authorization);
        List<TiraCuadreRequest> tiras = validarTirasCuadre(request);
        try {
            return sucursalAuthProcedureClient.aprobarCuadreEnRuta(
                    obtenerSucursal(almacenero), idCuadreEnRuta, almacenero.nombre(), true, tiras);
        } catch (DataAccessException ex) {
            throw conflictoReserva(ex);
        }
    }

    private CuadreAlmacenDtos.RutaCuadreResponse exigirRutaCuadreAlmacen(
            UsuarioResponse almacenero, Integer idRuta) {
        if (idRuta == null || idRuta < 1) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "La ruta no es valida.");
        }
        return sucursalAuthProcedureClient.listarRutasCuadreAlmacen(
                        obtenerSucursal(almacenero), java.time.LocalDate.now())
                .stream().filter(ruta -> ruta.idRuta().equals(idRuta)).findFirst()
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "La ruta no existe."));
    }

    public SaldoRutaResponse obtenerSaldoRutaCuadreAlmacen(String authorization, Integer idRuta) {
        UsuarioResponse almacenero = exigirAlmacenero(authorization);
        CuadreAlmacenDtos.RutaCuadreResponse ruta = exigirRutaCuadreAlmacen(almacenero, idRuta);
        List<SaldoProducto> productos = sucursalAuthProcedureClient.obtenerSaldoRuta(
                obtenerSucursal(almacenero), idRuta);
        return new SaldoRutaResponse(
                idRuta, ruta.ruta(), productos.size(),
                productos.stream().mapToInt(SaldoProducto::cantidad).sum(),
                productos.stream().map(SaldoProducto::valorTotal)
                        .reduce(java.math.BigDecimal.ZERO, java.math.BigDecimal::add),
                productos);
    }

    public List<ProductoCuadreResponse> listarProductosCuadreAlmacen(
            String authorization, Integer idRuta) {
        UsuarioResponse almacenero = exigirAlmacenero(authorization);
        exigirRutaCuadreAlmacen(almacenero, idRuta);
        return sucursalAuthProcedureClient.listarProductosCuadre(obtenerSucursal(almacenero), idRuta);
    }

    public CuadreDtos.EstadoCuadreHoyResponse obtenerEstadoCuadreAlmacenHoy(
            String authorization, Integer idRuta) {
        UsuarioResponse almacenero = exigirAlmacenero(authorization);
        exigirRutaCuadreAlmacen(almacenero, idRuta);
        return sucursalAuthProcedureClient.obtenerEstadoCuadreHoy(obtenerSucursal(almacenero), idRuta);
    }

    public ValidacionCuadreResponse validarImeisCuadreAlmacen(
            String authorization, Integer idRuta, ValidarImeisCuadreRequest request) {
        UsuarioResponse almacenero = exigirAlmacenero(authorization);
        exigirRutaCuadreAlmacen(almacenero, idRuta);
        return sucursalAuthProcedureClient.validarImeisCuadre(
                obtenerSucursal(almacenero), idRuta, request.idProducto(), normalizarImeisCuadre(request.imeis()));
    }

    public ValidacionCuadreResponse validarImeisCuadreAlmacenPublico(
            Integer idSucursal, Integer idRuta, Integer idProducto, List<String> valores) {
        SucursalConnection sucursal = centralProcedureClient.obtenerConexion(idSucursal)
                .orElseThrow(() -> new ResponseStatusException(
                        HttpStatus.SERVICE_UNAVAILABLE, "No se encontro la conexion de la sucursal."));
        return sucursalAuthProcedureClient.validarImeisCuadre(
                sucursal, idRuta, idProducto, normalizarImeisCuadre(valores));
    }

    public FinalizarCuadreResponse finalizarCuadreAlmacen(
            String authorization, Integer idRuta, FinalizarCuadreRequest request) {
        UsuarioResponse almacenero = exigirAlmacenero(authorization);
        CuadreAlmacenDtos.RutaCuadreResponse ruta = exigirRutaCuadreAlmacen(almacenero, idRuta);
        if (ruta.idVendedor() == null) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, "La ruta no tiene vendedor asignado.");
        }
        List<TiraCuadreRequest> tiras = validarTirasCuadre(request);
        try {
            return sucursalAuthProcedureClient.finalizarCuadre(
                    obtenerSucursal(almacenero), idRuta, ruta.idVendedor(), almacenero.id(),
                    request.observacion() == null ? "" : request.observacion().trim(), tiras);
        } catch (DataAccessException ex) {
            throw conflictoReserva(ex);
        }
    }

    private List<TiraCuadreRequest> validarTirasCuadre(FinalizarCuadreRequest request) {
        java.util.LinkedHashSet<String> globales = new java.util.LinkedHashSet<>();
        return request.tiras().stream().map(tira -> {
            if (tira.numeroTira() == null || tira.numeroTira() < 1) {
                throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "El numero de tira no es valido.");
            }
            String modo = tira.modo() == null ? "" : tira.modo().trim().toLowerCase();
            if (!modo.equals("individual") && !modo.equals("rango") && !modo.equals("cantidad")
                    && !modo.equals("tigo_money") && !modo.equals("chip_cantidad")) {
                throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "El modo de tira no es valido.");
            }
            if (modo.equals("chip_cantidad")) {
                if (tira.cantidadManual() == null || tira.cantidadManual() < 0) {
                    throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "El sobrante de chips no es valido.");
                }
                if (tira.imeis() != null && !tira.imeis().isEmpty()) {
                    throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "El sobrante de chips no debe contener IMEI.");
                }
                return new TiraCuadreRequest(tira.idProducto(), tira.numeroTira(), modo, List.of(),
                        tira.cantidadManual(), null);
            }
            if (modo.equals("tigo_money")) {
                if (tira.cantidadManual() == null || tira.cantidadManual() < 0) {
                    throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "El sobrante de Tigo Money no es valido.");
                }
                if (tira.cantidadEfectivizada() == null || tira.cantidadEfectivizada() < 0) {
                    throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "La efectivizacion de Tigo Money no es valida.");
                }
                if (tira.imeis() != null && !tira.imeis().isEmpty()) {
                    throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Tigo Money no debe contener IMEI.");
                }
                return new TiraCuadreRequest(tira.idProducto(), tira.numeroTira(), modo, List.of(),
                        tira.cantidadManual(), tira.cantidadEfectivizada());
            }
            List<String> imeis = normalizarImeisCuadre(tira.imeis());
            if (imeis.isEmpty()) {
                throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "La tira debe contener al menos un IMEI.");
            }
            for (String imei : imeis) {
                if (!globales.add(imei)) {
                    throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "La Lista Master contiene IMEI duplicados.");
                }
            }
            return new TiraCuadreRequest(tira.idProducto(), tira.numeroTira(), modo, imeis, null, null);
        }).toList();
    }

    public List<DetallePedidoResponse> obtenerDetallePendienteParaAlmacen(
            String authorization,
            Integer idPedido) {
        UsuarioResponse almacenero = exigirAlmacenero(authorization);
        List<DetallePedidoResponse> detalles = sucursalAuthProcedureClient.obtenerDetallePendienteParaAlmacen(
                obtenerSucursal(almacenero), idPedido);
        if (detalles.isEmpty()) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "El pedido pendiente no existe.");
        }
        return detalles;
    }

    public List<ProductoFisicoPedidoResponse> obtenerProductosFisicosPedido(
            String authorization,
            Integer idPedido) {
        UsuarioResponse almacenero = exigirAlmacenero(authorization);
        return sucursalAuthProcedureClient.obtenerProductosFisicosPedido(
                obtenerSucursal(almacenero), idPedido);
    }

    public com.logingeneral.back.auth.AlmacenDtos.ValidacionTigoMoneyResponse validarTigoMoneyPedido(
            String authorization,
            Integer idPedido) {
        UsuarioResponse almacenero = exigirAlmacenero(authorization);
        try {
            return sucursalAuthProcedureClient.validarTigoMoneyPedido(
                    obtenerSucursal(almacenero), idPedido);
        } catch (DataAccessException ex) {
            throw conflictoReserva(ex);
        }
    }

    public List<PromedioVentaResponse> obtenerPromedioVentaPedidoAlmacen(
            String authorization,
            Integer idPedido) {
        UsuarioResponse almacenero = exigirAlmacenero(authorization);
        return sucursalAuthProcedureClient.obtenerPromedioVentaPedidoAlmacen(
                obtenerSucursal(almacenero), idPedido, java.time.LocalDate.now());
    }

    public SaldoRutaResponse obtenerSaldoRutaPedidoAlmacen(
            String authorization,
            Integer idPedido) {
        UsuarioResponse almacenero = exigirAlmacenero(authorization);
        return sucursalAuthProcedureClient.obtenerSaldoRutaPedidoAlmacen(
                obtenerSucursal(almacenero), idPedido);
    }

    public ModificarPedidoAlmacenResponse modificarPedidoAlmacen(
            String authorization,
            Integer idPedido,
            ModificarPedidoAlmacenRequest request) {
        UsuarioResponse almacenero = exigirAlmacenero(authorization);
        try {
            return sucursalAuthProcedureClient.modificarPedidoAlmacen(
                    obtenerSucursal(almacenero),
                    idPedido,
                    almacenero.id(),
                    request.comentarioAlmacen(),
                    request.detalles());
        } catch (DataAccessException ex) {
            throw conflictoReserva(ex);
        }
    }

    private void validarRango(java.time.LocalDate fechaDesde, java.time.LocalDate fechaHasta) {
        if (fechaDesde == null || fechaHasta == null) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Las fechas son requeridas.");
        }
        if (fechaDesde.isAfter(fechaHasta)) {
            throw new ResponseStatusException(
                    HttpStatus.BAD_REQUEST,
                    "La fecha inicial no puede ser posterior a la fecha final.");
        }
    }

    public AprobarPedidoResponse aprobarPedido(
            String authorization,
            Integer idPedido,
            AprobarPedidoRequest request) {
        UsuarioResponse almacenero = exigirAlmacenero(authorization);
        java.util.LinkedHashSet<String> imeis = new java.util.LinkedHashSet<>();
        List<com.logingeneral.back.auth.AlmacenDtos.ProductoFisicoAsignadoRequest> productos = request.productos().stream()
                .map(producto -> {
                    String imei = producto.imei() == null ? "" : producto.imei().replaceAll("[^0-9]", "");
                    if (imei.isEmpty() || imei.length() > 18) {
                        throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Todos los IMEI deben ser numericos y validos.");
                    }
                    if (!imeis.add(imei)) {
                        throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "El pedido contiene IMEI duplicados.");
                    }
                    if (producto.numeroTira() == null || producto.numeroTira() < 1) {
                        throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "El número de tira no es válido.");
                    }
                    String modoTira = producto.modoTira() == null ? "" : producto.modoTira().trim().toLowerCase();
                    if (!modoTira.equals("individual")
                            && !modoTira.equals("rango")
                            && !modoTira.equals("cantidad")) {
                        throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "El modo de tira no es válido.");
                    }
                    return new com.logingeneral.back.auth.AlmacenDtos.ProductoFisicoAsignadoRequest(
                            producto.idDetalle(), imei, producto.numeroTira(), modoTira);
                })
                .toList();
        try {
            return sucursalAuthProcedureClient.aprobarPedido(
                    obtenerSucursal(almacenero),
                    idPedido,
                    request.fechaEntrega(),
                    almacenero.nombre(),
                    almacenero.id(),
                    request.tokenVinculacion() == null ? "" : request.tokenVinculacion(),
                    productos);
        } catch (DataAccessException ex) {
            throw conflictoReserva(ex);
        }
    }

    public CrearPedidoDirectoResponse crearPedidoDirecto(
            String authorization,
            CrearPedidoDirectoRequest request) {
        UsuarioResponse almacenero = exigirAlmacenero(authorization);
        java.util.HashSet<Integer> productosDetalle = new java.util.HashSet<>();
        request.detalles().forEach(detalle -> {
            if (!productosDetalle.add(detalle.idProducto())) {
                throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "No repitas un producto en el pedido directo.");
            }
            if (detalle.idProducto() == 32) {
                throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "TM_Compra no se puede entregar a una ruta.");
            }
        });
        java.util.LinkedHashSet<String> imeis = new java.util.LinkedHashSet<>();
        List<ProductoFisicoDirectoRequest> fisicos = request.productos().stream().map(producto -> {
            String imei = producto.imei() == null ? "" : producto.imei().replaceAll("[^0-9]", "");
            if (imei.isEmpty() || imei.length() > 18) {
                throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Todos los IMEI deben ser numericos y validos.");
            }
            if (!imeis.add(imei)) {
                throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "El pedido directo contiene IMEI duplicados.");
            }
            if (!productosDetalle.contains(producto.idProducto())) {
                throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Un IMEI pertenece a un producto no incluido en el pedido.");
            }
            if (producto.numeroTira() == null || producto.numeroTira() < 1) {
                throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "El numero de tira no es valido.");
            }
            String modo = producto.modoTira() == null ? "" : producto.modoTira().trim().toLowerCase();
            if (!modo.equals("individual") && !modo.equals("rango") && !modo.equals("cantidad")) {
                throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "El modo de tira no es valido.");
            }
            return new ProductoFisicoDirectoRequest(producto.idProducto(), imei, producto.numeroTira(), modo);
        }).toList();
        try {
            return sucursalAuthProcedureClient.crearPedidoDirecto(
                    obtenerSucursal(almacenero), request.idRuta(), almacenero.id(),
                    almacenero.nombre(), request.observacion(), request.detalles(), fisicos);
        } catch (DataAccessException ex) {
            throw conflictoReserva(ex);
        }
    }

    public List<com.logingeneral.back.auth.AlmacenDtos.ImeiDirectoValidacionResponse> validarImeisPedidoDirectoAutomatico(
            String authorization, List<String> valores) {
        UsuarioResponse almacenero = exigirAlmacenero(authorization);
        java.util.LinkedHashSet<String> imeis = new java.util.LinkedHashSet<>();
        for (String valor : normalizarImeis(valores)) {
            String canonico;
            try {
                canonico = Long.toString(Long.parseLong(valor));
            } catch (NumberFormatException ex) {
                throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Uno de los IMEI esta fuera del rango permitido.");
            }
            if (!imeis.add(canonico)) {
                throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "La tira contiene IMEI duplicados.");
            }
        }
        if (imeis.size() > 1000) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Una tira no puede superar 1000 IMEI.");
        }
        var sucursal = obtenerSucursal(almacenero);
        var identificados = sucursalAuthProcedureClient.identificarImeisPedidoDirecto(
                sucursal, imeis.stream().map(Long::valueOf).toList());
        java.util.Map<String, com.logingeneral.back.auth.AlmacenDtos.ImeiDirectoValidacionResponse> resultados = new java.util.LinkedHashMap<>();
        for (String imei : imeis) {
            var identificado = identificados.get(imei);
            if (identificado == null) {
                resultados.put(imei, new com.logingeneral.back.auth.AlmacenDtos.ImeiDirectoValidacionResponse(
                        imei, null, null, false, "El IMEI no existe en tbl_Productos."));
            } else if (identificado.idProducto() == 31 || identificado.idProducto() == 32) {
                resultados.put(imei, new com.logingeneral.back.auth.AlmacenDtos.ImeiDirectoValidacionResponse(
                        imei, identificado.idProducto(), identificado.producto(), false, "Este producto no admite IMEI para entrega directa."));
            }
        }
        var grupos = identificados.values().stream().filter(item -> item.idProducto() != 31 && item.idProducto() != 32)
                .collect(java.util.stream.Collectors.groupingBy(
                        com.logingeneral.back.auth.AlmacenDtos.ImeiDirectoValidacionResponse::idProducto));
        for (var grupo : grupos.entrySet()) {
            List<Long> numeros = grupo.getValue().stream().map(item -> Long.valueOf(item.imei())).toList();
            var validados = sucursalAuthProcedureClient.validarProductosPedidoDirecto(
                    sucursal, grupo.getKey(), numeros.size(), numeros);
            for (var item : grupo.getValue()) {
                var validacion = validados.get(item.imei());
                resultados.put(item.imei(), new com.logingeneral.back.auth.AlmacenDtos.ImeiDirectoValidacionResponse(
                        item.imei(), item.idProducto(), item.producto(),
                        validacion != null && validacion.valido(),
                        validacion == null ? "No se pudo validar el IMEI." : validacion.motivo()));
            }
        }
        return imeis.stream().map(resultados::get).toList();
    }

    public List<CierreAlmacenProductoResponse> obtenerCierreAlmacen(
            String authorization, java.time.LocalDate fecha) {
        UsuarioResponse almacenero = exigirAlmacenero(authorization);
        if (fecha == null) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "La fecha del cierre es requerida.");
        }
        return sucursalAuthProcedureClient.obtenerCierreAlmacen(obtenerSucursal(almacenero), fecha);
    }

    public EstadoCierreAlmacenResponse obtenerEstadoCierreAlmacen(
            String authorization, java.time.LocalDate fecha) {
        UsuarioResponse almacenero = exigirAlmacenero(authorization);
        if (fecha == null) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "La fecha del cierre es requerida.");
        }
        return sucursalAuthProcedureClient.obtenerEstadoCierreAlmacen(obtenerSucursal(almacenero), fecha);
    }

    public GuardarCierreAlmacenResponse guardarCierreAlmacen(
            String authorization, GuardarCierreAlmacenRequest request) {
        UsuarioResponse almacenero = exigirAlmacenero(authorization);
        if (request.fecha().isAfter(java.time.LocalDate.now())) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "No se puede registrar un cierre con fecha futura.");
        }
        try {
            return sucursalAuthProcedureClient.guardarCierreAlmacen(
                    obtenerSucursal(almacenero), almacenero.id(), request.fecha(), request.observacion());
        } catch (DataAccessException ex) {
            Throwable causa = ex.getMostSpecificCause();
            String mensaje = causa == null || causa.getMessage() == null
                    ? "No se pudo guardar el cierre de almacen."
                    : causa.getMessage();
            throw new ResponseStatusException(HttpStatus.CONFLICT, mensaje);
        }
    }

    public com.logingeneral.back.auth.AlmacenDtos.ValidacionTigoMoneyResponse validarTigoMoneyDirecto(
            String authorization, BigDecimal cantidad) {
        UsuarioResponse almacenero = exigirAlmacenero(authorization);
        if (cantidad == null || cantidad.compareTo(BigDecimal.ZERO) <= 0) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "La cantidad de Tigo Money debe ser mayor a cero.");
        }
        var respuesta = sucursalAuthProcedureClient.validarTigoMoneyDirecto(obtenerSucursal(almacenero), cantidad);
        if (!respuesta.valido()) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "Saldo insuficiente de Tigo Money. Disponible: " + respuesta.saldoDisponible() + ".");
        }
        return respuesta;
    }

    public List<EntidadResponse> listarEntidades(String authorization) {
        UsuarioResponse usuario = usuarioActual(authorization);
        return sucursalAuthProcedureClient.listarEntidades(obtenerSucursal(usuario));
    }

    public RegistrarDepositoResponse registrarDeposito(
            String authorization,
            RegistrarDepositoRequest request) {
        UsuarioResponse usuario = usuarioActual(authorization);
        TecnicoResponse tecnico = exigirTecnicoConRuta(usuario);
        if (tecnico.idVendedor() == null) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "El técnico no tiene vendedor asociado.");
        }
        try {
            return sucursalAuthProcedureClient.registrarDeposito(
                    obtenerSucursal(usuario),
                    tecnico.idRuta(),
                    tecnico.idVendedor(),
                    usuario.id(),
                    request.idEntidad(),
                    request.cuenta(),
                    request.monto(),
                    request.op());
        } catch (DataAccessException ex) {
            Throwable causa = ex.getMostSpecificCause();
            String mensaje = causa == null || causa.getMessage() == null
                    ? "No se pudo registrar el depósito."
                    : causa.getMessage();
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, mensaje);
        }
    }

    public List<DepositoResponse> listarDepositosEnRuta(String authorization) {
        UsuarioResponse usuario = usuarioActual(authorization);
        TecnicoResponse tecnico = exigirTecnicoConRuta(usuario);
        return sucursalAuthProcedureClient.listarDepositosEnRuta(
                obtenerSucursal(usuario), tecnico.idRuta());
    }

    public List<DepositoContabilidadResponse> listarDepositosPendientesContabilidad(String authorization) {
        UsuarioResponse usuario = exigirContabilidad(authorization);
        return sucursalAuthProcedureClient.listarDepositosPendientesContabilidad(obtenerSucursal(usuario));
    }

    public RegistrarDepositoResponse editarDepositoContabilidad(
            String authorization, Integer idDeposito, EditarDepositoContabilidadRequest request) {
        UsuarioResponse usuario = exigirContabilidad(authorization);
        try {
            return sucursalAuthProcedureClient.editarDepositoContabilidad(
                    obtenerSucursal(usuario), idDeposito, request.idEntidad(),
                    request.cuenta(), request.monto(), request.op());
        } catch (DataAccessException ex) {
            Throwable causa = ex.getMostSpecificCause();
            String mensaje = causa == null || causa.getMessage() == null
                    ? "No se pudo actualizar el depósito."
                    : causa.getMessage();
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, mensaje);
        }
    }

    public RegistrarDepositoResponse aprobarDepositoContabilidad(
            String authorization, Integer idDeposito) {
        UsuarioResponse usuario = exigirContabilidad(authorization);
        try {
            return sucursalAuthProcedureClient.aprobarDepositoContabilidad(
                    obtenerSucursal(usuario), idDeposito, usuario.nombre(), usuario.id());
        } catch (DataAccessException ex) {
            Throwable causa = ex.getMostSpecificCause();
            String mensaje = causa == null || causa.getMessage() == null
                    ? "No se pudo aprobar el depósito."
                    : causa.getMessage();
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, mensaje);
        }
    }

    private UsuarioResponse exigirContabilidad(String authorization) {
        UsuarioResponse usuario = usuarioActual(authorization);
        if (usuario.rol() == null || !"Contabilidad".equalsIgnoreCase(usuario.rol())) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN,
                    "Esta operación requiere el rol Contabilidad.");
        }
        return usuario;
    }

    private UsuarioResponse exigirSistemas(String authorization) {
        UsuarioResponse usuario = usuarioActual(authorization);
        if (usuario.rol() == null || !"Sistemas".equalsIgnoreCase(usuario.rol())) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN,
                    "Esta operación requiere el rol Sistemas.");
        }
        return usuario;
    }

    public java.util.List<com.logingeneral.back.auth.SistemasDtos.RutaSistemasResponse> listarRutasSistemas(
            String authorization) {
        UsuarioResponse usuario = exigirSistemas(authorization);
        return sucursalAuthProcedureClient.listarRutasSistemas(obtenerSucursal(usuario));
    }

    public java.util.List<com.logingeneral.back.auth.SistemasDtos.MovimientoRutaResponse> listarMovimientosRutaSistemas(
            String authorization,
            Integer idRuta,
            java.time.LocalDate fechaDesde,
            java.time.LocalDate fechaHasta) {
        validarRango(fechaDesde, fechaHasta);
        UsuarioResponse usuario = exigirSistemas(authorization);
        return sucursalAuthProcedureClient.listarMovimientosRutaSistemas(
                obtenerSucursal(usuario), idRuta, fechaDesde, fechaHasta);
    }

    public java.util.List<com.logingeneral.back.auth.SistemasDtos.PreviewCascadaItemResponse> previewCascadaRutaSistemas(
            String authorization,
            Integer idRuta,
            java.time.LocalDateTime desdeFecha) {
        UsuarioResponse usuario = exigirSistemas(authorization);
        return sucursalAuthProcedureClient.previewCascadaRutaSistemas(
                obtenerSucursal(usuario), idRuta, desdeFecha);
    }

    public java.util.List<com.logingeneral.back.auth.SistemasDtos.PreviewCascadaDetalleResponse> previewDetalleCascadaRutaSistemas(
            String authorization,
            Integer idRuta,
            java.time.LocalDateTime desdeFecha) {
        UsuarioResponse usuario = exigirSistemas(authorization);
        return sucursalAuthProcedureClient.previewDetalleCascadaRutaSistemas(
                obtenerSucursal(usuario), idRuta, desdeFecha);
    }

    public java.util.List<com.logingeneral.back.auth.SistemasDtos.PreviewTablaCascadaResponse> previewTablasCascadaRutaSistemas(
            String authorization,
            Integer idRuta,
            java.time.LocalDateTime desdeFecha) {
        UsuarioResponse usuario = exigirSistemas(authorization);
        try {
            return sucursalAuthProcedureClient.previewTablasCascadaRutaSistemas(
                    obtenerSucursal(usuario), idRuta, desdeFecha);
        } catch (java.sql.SQLException ex) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, ex.getMessage());
        }
    }

    public org.springframework.web.servlet.mvc.method.annotation.SseEmitter eventosCascadaSistemas(
            String authorization, String jobId) {
        exigirSistemas(authorization);
        return sistemasEventService.suscribir(jobId);
    }

    public com.logingeneral.back.auth.SistemasDtos.EjecutarCascadaResponse ejecutarCascadaRutaSistemas(
            String authorization,
            Integer idRuta,
            com.logingeneral.back.auth.SistemasDtos.EjecutarCascadaRequest request) {
        UsuarioResponse usuario = exigirSistemas(authorization);
        String jobId = request.jobId();
        try {
            return sucursalAuthProcedureClient.ejecutarCascadaRutaConProgreso(
                    obtenerSucursal(usuario),
                    idRuta,
                    request.desdeFecha(),
                    usuario.id(),
                    usuario.nombre(),
                    request.justificacion().trim(),
                    jobId,
                    jobId == null ? null : evento -> sistemasEventService.publicar(jobId, evento));
        } catch (java.sql.SQLException ex) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, ex.getMessage());
        } finally {
            if (jobId != null) {
                sistemasEventService.completar(jobId);
            }
        }
    }

    private String obtenerBearerToken(String authorization) {
        if (authorization == null || !authorization.startsWith("Bearer ")) {
            throw new ResponseStatusException(HttpStatus.UNAUTHORIZED, "Se requiere una sesión válida.");
        }
        String token = authorization.substring(7).trim();
        if (token.isEmpty()) {
            throw new ResponseStatusException(HttpStatus.UNAUTHORIZED, "Se requiere una sesión válida.");
        }
        return token;
    }

    private String hashMd5Base64(String value) {
        try {
            MessageDigest md5 = MessageDigest.getInstance("MD5");
            byte[] digest = md5.digest(value.getBytes(StandardCharsets.UTF_8));
            return Base64.getEncoder().encodeToString(digest);
        } catch (NoSuchAlgorithmException ex) {
            throw new IllegalStateException("MD5 no está disponible en esta JVM.", ex);
        }
    }

    // ---------------------------------------------------------------------------------------------
    // Chat almacén ↔ técnico por ruta.
    // Seguridad: el técnico solo accede a la ruta de su token; el almacenero, a las rutas de su sucursal.
    // El emisor (usuario, nombre y origen) sale siempre del token, nunca del cliente.
    // ---------------------------------------------------------------------------------------------
    private static final int CHAT_LIMITE_MENSAJES = 100;
    private static final int CHAT_MAXIMO_POR_MINUTO = 20;
    private static final int CHAT_LARGO_MAXIMO = 1000;
    private final java.util.concurrent.ConcurrentHashMap<Integer, java.util.ArrayDeque<Long>> chatEnviosPorUsuario =
            new java.util.concurrent.ConcurrentHashMap<>();

    public List<ChatDtos.MensajeChatResponse> listarMensajesChatTecnico(String authorization, Long desdeId) {
        UsuarioResponse usuario = usuarioActual(authorization);
        TecnicoResponse tecnico = exigirTecnicoConRuta(usuario);
        return conChat(() -> sucursalAuthProcedureClient.listarMensajesChat(
                obtenerSucursal(usuario), tecnico.idRuta(), normalizarDesdeChat(desdeId), CHAT_LIMITE_MENSAJES));
    }

    public ChatDtos.MensajeChatResponse enviarMensajeChatTecnico(
            String authorization,
            ChatDtos.EnviarMensajeChatRequest request) {
        UsuarioResponse usuario = usuarioActual(authorization);
        TecnicoResponse tecnico = exigirTecnicoConRuta(usuario);
        return enviarMensajeChat(usuario, tecnico.idRuta(), "T", request);
    }

    public void marcarLeidoChatTecnico(String authorization, ChatDtos.MarcarLeidoChatRequest request) {
        UsuarioResponse usuario = usuarioActual(authorization);
        TecnicoResponse tecnico = exigirTecnicoConRuta(usuario);
        conChat(() -> {
            sucursalAuthProcedureClient.marcarLeidoChat(obtenerSucursal(usuario), tecnico.idRuta(), "T", request.hastaId());
            return null;
        });
    }

    public ChatDtos.ResumenChatResponse resumenChatTecnico(String authorization) {
        UsuarioResponse usuario = usuarioActual(authorization);
        TecnicoResponse tecnico = exigirTecnicoConRuta(usuario);
        return conChat(() -> sucursalAuthProcedureClient.resumenChat(obtenerSucursal(usuario), "T", tecnico.idRuta()))
                .stream().findFirst()
                .orElse(new ChatDtos.ResumenChatResponse(tecnico.idRuta(), 0, null, null, null));
    }

    public List<ChatDtos.ResumenChatResponse> resumenChatAlmacen(String authorization) {
        UsuarioResponse almacenero = exigirAlmacenero(authorization);
        return conChat(() -> sucursalAuthProcedureClient.resumenChat(obtenerSucursal(almacenero), "A", null));
    }

    public List<ChatDtos.MensajeChatResponse> listarMensajesChatAlmacen(
            String authorization,
            Integer idRuta,
            Long desdeId) {
        UsuarioResponse almacenero = exigirAlmacenero(authorization);
        validarRutaChat(idRuta);
        return conChat(() -> sucursalAuthProcedureClient.listarMensajesChat(
                obtenerSucursal(almacenero), idRuta, normalizarDesdeChat(desdeId), CHAT_LIMITE_MENSAJES));
    }

    public ChatDtos.MensajeChatResponse enviarMensajeChatAlmacen(
            String authorization,
            Integer idRuta,
            ChatDtos.EnviarMensajeChatRequest request) {
        UsuarioResponse almacenero = exigirAlmacenero(authorization);
        validarRutaChat(idRuta);
        return enviarMensajeChat(almacenero, idRuta, "A", request);
    }

    public void marcarLeidoChatAlmacen(String authorization, Integer idRuta, ChatDtos.MarcarLeidoChatRequest request) {
        UsuarioResponse almacenero = exigirAlmacenero(authorization);
        validarRutaChat(idRuta);
        conChat(() -> {
            sucursalAuthProcedureClient.marcarLeidoChat(obtenerSucursal(almacenero), idRuta, "A", request.hastaId());
            return null;
        });
    }

    private ChatDtos.MensajeChatResponse enviarMensajeChat(
            UsuarioResponse usuario,
            Integer idRuta,
            String origen,
            ChatDtos.EnviarMensajeChatRequest request) {
        String texto = limpiarTextoChat(request.texto());
        if (texto.isEmpty()) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Escribe un mensaje.");
        }
        if (texto.length() > CHAT_LARGO_MAXIMO) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "El mensaje no puede superar 1000 caracteres.");
        }
        if (request.idPedido() != null && request.idPedido() <= 0) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "El pedido indicado no es válido.");
        }
        controlarFrecuenciaChat(usuario.id());
        String nombre = usuario.nombre() == null || usuario.nombre().isBlank() ? usuario.loggin() : usuario.nombre().strip();
        return conChat(() -> sucursalAuthProcedureClient.enviarMensajeChat(
                        obtenerSucursal(usuario), idRuta, usuario.id(), origen, nombre, texto, request.idPedido()))
                .orElseThrow(() -> new ResponseStatusException(
                        HttpStatus.BAD_REQUEST, "La ruta o el pedido indicado no son válidos para este chat."));
    }

    /** Quita caracteres de control (salvo salto de línea y tabulación) y saltos de línea repetidos. */
    static String limpiarTextoChat(String texto) {
        if (texto == null) {
            return "";
        }
        return texto.replace("\r\n", "\n").replace('\r', '\n')
                .replaceAll("[\\p{Cc}&&[^\\n\\t]]", "")
                .replaceAll("\\n{3,}", "\n\n")
                .strip();
    }

    private void controlarFrecuenciaChat(Integer idUsuario) {
        long ahora = System.currentTimeMillis();
        java.util.ArrayDeque<Long> envios = chatEnviosPorUsuario.computeIfAbsent(idUsuario, clave -> new java.util.ArrayDeque<>());
        synchronized (envios) {
            while (!envios.isEmpty() && ahora - envios.peekFirst() > 60_000L) {
                envios.pollFirst();
            }
            if (envios.size() >= CHAT_MAXIMO_POR_MINUTO) {
                throw new ResponseStatusException(
                        HttpStatus.TOO_MANY_REQUESTS, "Estás enviando mensajes muy seguido. Espera un momento.");
            }
            envios.addLast(ahora);
        }
    }

    private static void validarRutaChat(Integer idRuta) {
        if (idRuta == null || idRuta <= 0) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "La ruta indicada no es válida.");
        }
    }

    private static long normalizarDesdeChat(Long desdeId) {
        return desdeId == null || desdeId < 0 ? 0L : desdeId;
    }

    /** Si la sucursal todavía no tiene los objetos del chat, responde con un mensaje claro en lugar de un error genérico. */
    private <T> T conChat(java.util.function.Supplier<T> operacion) {
        try {
            return operacion.get();
        } catch (DataAccessException ex) {
            String detalle = String.valueOf(ex.getMostSpecificCause().getMessage());
            if (detalle.contains("spj_LoginGeneral_Chat") || detalle.contains("tbl_ChatRuta")) {
                throw new ResponseStatusException(
                        HttpStatus.SERVICE_UNAVAILABLE, "El chat todavía no está habilitado en esta sucursal.");
            }
            throw ex;
        }
    }
}
