package com.logingeneral.back.scanner;

import java.io.IOException;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.Collection;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.CopyOnWriteArrayList;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicReference;

import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.web.server.ResponseStatusException;
import org.springframework.web.servlet.mvc.method.annotation.SseEmitter;

@Service
public class ScannerLinkService {

    private static final long DURACION_HORAS = 1;
    private final Map<String, ScannerSession> sesiones = new ConcurrentHashMap<>();

    public ScannerSession crear(Integer idSucursal, Integer idUsuario, String usuario) {
        limpiarExpiradas();
        String token = UUID.randomUUID().toString().replace("-", "")
                + UUID.randomUUID().toString().replace("-", "");
        ScannerSession session = new ScannerSession(
                token, idSucursal, idUsuario, usuario, Instant.now(),
                Instant.now().plus(DURACION_HORAS, ChronoUnit.HOURS),
                new AtomicBoolean(false), new AtomicReference<>(),
                ConcurrentHashMap.newKeySet(), new CopyOnWriteArrayList<>());
        sesiones.put(token, session);
        return session;
    }

    public PublicSession obtenerPublica(String token) {
        ScannerSession session = exigirActiva(token);
        return new PublicSession(session.token(), session.expira(), session.usuario(), session.contexto().get());
    }

    public ScannerSession obtenerSesion(String token) {
        return exigirActiva(token);
    }

    public ScannerSession validarPropietario(String token, Integer idSucursal, Integer idUsuario) {
        return exigirPropietario(token, idSucursal, idUsuario);
    }

    public ScanContext configurarContexto(
            String token, Integer idSucursal, Integer idUsuario,
            ScanContext contexto, Collection<String> imeisExistentes) {
        ScannerSession session = exigirPropietario(token, idSucursal, idUsuario);
        session.contexto().set(contexto);
        session.imeisContexto().clear();
        if (imeisExistentes != null) {
            imeisExistentes.stream().map(this::normalizar).filter(value -> !value.isEmpty())
                    .forEach(session.imeisContexto()::add);
        }
        session.cerrada().set(false);
        return contexto;
    }

    public ScanContext contexto(String token) {
        ScannerSession session = exigirActiva(token);
        ScanContext contexto = session.contexto().get();
        if (contexto == null) {
            throw new ResponseStatusException(
                    HttpStatus.CONFLICT,
                    "Selecciona un pedido y un producto en la computadora antes de escanear.");
        }
        return contexto;
    }

    public boolean contieneEnContexto(String token, String codigo) {
        return exigirActiva(token).imeisContexto().contains(normalizar(codigo));
    }

    public int cantidadEnContexto(String token) {
        return exigirActiva(token).imeisContexto().size();
    }

    public SseEmitter suscribir(String token, Integer idSucursal, Integer idUsuario) {
        ScannerSession session = exigirPropietario(token, idSucursal, idUsuario);
        SseEmitter emitter = new SseEmitter(3_700_000L);
        session.emitters().add(emitter);
        Runnable remover = () -> session.emitters().remove(emitter);
        emitter.onCompletion(remover);
        emitter.onTimeout(remover);
        emitter.onError(error -> remover.run());
        enviar(emitter, "vinculado", new LinkStatus(session.token(), session.expira()));
        return emitter;
    }

    public ScanEvent registrar(
            String token,
            String codigo,
        ProductoScanDtos.ProductoPedidoValidacion validacion) {
        ScannerSession session = exigirActiva(token);
        ScanContext contexto = contexto(token);
        String normalizado = normalizar(codigo);
        if (normalizado.isEmpty()) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "El codigo leido esta vacio.");
        }
        if (normalizado.length() > 18) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "El IMEI leido es demasiado largo.");
        }
        if (!validacion.valido()) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, validacion.motivo());
        }
        if (session.imeisContexto().size() >= contexto.cantidadSolicitada()) {
            throw new ResponseStatusException(
                    HttpStatus.CONFLICT,
                    "Ya se completo la cantidad solicitada para este producto.");
        }
        if (!session.imeisContexto().add(normalizado)) {
            throw new ResponseStatusException(
                    HttpStatus.CONFLICT,
                    "El IMEI ya fue agregado a este producto del pedido.");
        }
        ScanEvent event = new ScanEvent(
                normalizado, Instant.now(), contexto.idPedido(), contexto.idDetalle(),
                validacion.idProductoEsperado(), validacion.productoEsperado());
        for (SseEmitter emitter : session.emitters()) {
            if (!enviar(emitter, "codigo", event)) session.emitters().remove(emitter);
        }
        return event;
    }

    public ListClosedEvent cerrarLista(String token) {
        ScannerSession session = exigirActiva(token);
        ListClosedEvent event = new ListClosedEvent(Instant.now());
        return event;
    }

    public PublicSession reanudarLista(String token) {
        ScannerSession session = exigirActiva(token);
        return new PublicSession(session.token(), session.expira(), session.usuario(), session.contexto().get());
    }

    public void cerrar(String token, Integer idSucursal, Integer idUsuario) {
        ScannerSession session = sesiones.get(token);
        if (session == null) return;
        if (!session.idSucursal().equals(idSucursal) || !session.idUsuario().equals(idUsuario)) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN, "La vinculacion no pertenece a esta sesion.");
        }
        sesiones.remove(token);
        session.emitters().forEach(SseEmitter::complete);
    }

    private ScannerSession exigirPropietario(String token, Integer idSucursal, Integer idUsuario) {
        ScannerSession session = exigirActiva(token);
        if (!session.idSucursal().equals(idSucursal) || !session.idUsuario().equals(idUsuario)) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN, "La vinculacion no pertenece a esta sesion.");
        }
        return session;
    }

    private ScannerSession exigirActiva(String token) {
        ScannerSession session = sesiones.get(token);
        if (session == null) throw new ResponseStatusException(HttpStatus.NOT_FOUND, "La vinculacion no existe.");
        if (!session.expira().isAfter(Instant.now())) {
            sesiones.remove(token);
            session.emitters().forEach(SseEmitter::complete);
            throw new ResponseStatusException(HttpStatus.GONE, "La vinculacion expiro. Vuelve a vincular el telefono.");
        }
        return session;
    }

    private String normalizar(String codigo) {
        return codigo == null ? "" : codigo.trim().replaceAll("[^0-9]", "");
    }

    private boolean enviar(SseEmitter emitter, String nombre, Object datos) {
        try {
            emitter.send(SseEmitter.event().name(nombre).data(datos));
            return true;
        } catch (IOException | IllegalStateException ex) {
            emitter.complete();
            return false;
        }
    }

    private void limpiarExpiradas() {
        sesiones.values().removeIf(session -> !session.expira().isAfter(Instant.now()));
    }

    public record ScannerSession(
            String token, Integer idSucursal, Integer idUsuario, String usuario,
            Instant creado, Instant expira, AtomicBoolean cerrada,
            AtomicReference<ScanContext> contexto, Set<String> imeisContexto,
            CopyOnWriteArrayList<SseEmitter> emitters) {
    }

    public record ScanContext(
            Integer idPedido, Integer idDetalle, Integer idProducto,
            String producto, Integer cantidadSolicitada, Integer idRutaCuadre) {
    }

    public record PublicSession(String token, Instant expira, String usuario, ScanContext contexto) {
    }

    public record LinkStatus(String token, Instant expira) {
    }

    public record ScanEvent(
            String codigo, Instant fecha, Integer idPedido, Integer idDetalle,
            Integer idProducto, String producto) {
    }

    public record ListClosedEvent(Instant fecha) {
    }
}
