package com.logingeneral.back.auth;

import java.io.IOException;
import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.CopyOnWriteArrayList;

import org.springframework.stereotype.Service;
import org.springframework.web.servlet.mvc.method.annotation.SseEmitter;

@Service
public class PedidoEventService {

    private final Map<Integer, CopyOnWriteArrayList<SseEmitter>> emittersPorSucursal =
            new ConcurrentHashMap<>();

    public SseEmitter suscribir(Integer idSucursal) {
        SseEmitter emitter = new SseEmitter(0L);
        CopyOnWriteArrayList<SseEmitter> emitters = emittersPorSucursal.computeIfAbsent(
                idSucursal, ignored -> new CopyOnWriteArrayList<>());
        emitters.add(emitter);
        Runnable remover = () -> remover(idSucursal, emitter);
        emitter.onCompletion(remover);
        emitter.onTimeout(remover);
        emitter.onError(error -> remover.run());
        try {
            emitter.send(SseEmitter.event().name("conectado").data(Map.of("estado", "ok")));
        } catch (IOException ex) {
            remover.run();
            emitter.completeWithError(ex);
        }
        return emitter;
    }

    public void publicar(Integer idSucursal, PedidoCreadoEvent evento) {
        List<SseEmitter> emitters = emittersPorSucursal.get(idSucursal);
        if (emitters == null || emitters.isEmpty()) {
            return;
        }
        for (SseEmitter emitter : emitters) {
            try {
                emitter.send(SseEmitter.event().name("pedido-nuevo").data(evento));
            } catch (IOException | IllegalStateException ex) {
                remover(idSucursal, emitter);
                emitter.complete();
            }
        }
    }

    private void remover(Integer idSucursal, SseEmitter emitter) {
        CopyOnWriteArrayList<SseEmitter> emitters = emittersPorSucursal.get(idSucursal);
        if (emitters == null) {
            return;
        }
        emitters.remove(emitter);
        if (emitters.isEmpty()) {
            emittersPorSucursal.remove(idSucursal, emitters);
        }
    }

    public record PedidoCreadoEvent(
            Integer idPedido,
            Integer idRuta,
            String ruta,
            String tecnico,
            LocalDateTime fechaRegistro) {
    }
}
