package com.logingeneral.back.auth;

import java.io.IOException;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.CopyOnWriteArrayList;

import org.springframework.stereotype.Service;
import org.springframework.web.servlet.mvc.method.annotation.SseEmitter;

@Service
public class SistemasEventService {

    private final Map<String, CopyOnWriteArrayList<SseEmitter>> emittersPorJob =
            new ConcurrentHashMap<>();

    public SseEmitter suscribir(String jobId) {
        SseEmitter emitter = new SseEmitter(120_000L);
        CopyOnWriteArrayList<SseEmitter> emitters = emittersPorJob.computeIfAbsent(
                jobId, ignored -> new CopyOnWriteArrayList<>());
        emitters.add(emitter);
        Runnable remover = () -> remover(jobId, emitter);
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

    public void publicar(String jobId, CascadaEvento evento) {
        List<SseEmitter> emitters = emittersPorJob.get(jobId);
        if (emitters == null || emitters.isEmpty()) {
            return;
        }
        for (SseEmitter emitter : emitters) {
            try {
                emitter.send(SseEmitter.event().name("progreso").data(evento));
            } catch (IOException | IllegalStateException ex) {
                remover(jobId, emitter);
                emitter.complete();
            }
        }
    }

    public void completar(String jobId) {
        List<SseEmitter> emitters = emittersPorJob.get(jobId);
        if (emitters == null) {
            return;
        }
        for (SseEmitter emitter : emitters) {
            emitter.complete();
        }
        emittersPorJob.remove(jobId);
    }

    private void remover(String jobId, SseEmitter emitter) {
        CopyOnWriteArrayList<SseEmitter> emitters = emittersPorJob.get(jobId);
        if (emitters == null) {
            return;
        }
        emitters.remove(emitter);
        if (emitters.isEmpty()) {
            emittersPorJob.remove(jobId, emitters);
        }
    }

    public record CascadaEvento(
            String etapa,
            String tipo,
            Integer idReferencia,
            int indice,
            int total,
            String mensaje) {
    }
}
