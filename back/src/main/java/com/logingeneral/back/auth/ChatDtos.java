package com.logingeneral.back.auth;

import java.time.LocalDateTime;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.PositiveOrZero;
import jakarta.validation.constraints.Size;

/** Chat entre almacén y el técnico de cada ruta. */
public final class ChatDtos {

    private ChatDtos() {
    }

    /** origen: "A" almacén, "T" técnico. idPedido: pedido al que se refiere el mensaje, si lo hay. */
    public record MensajeChatResponse(
            Long idMensaje,
            Integer idRuta,
            Integer idUsuario,
            String origen,
            String nombreEmisor,
            String texto,
            Integer idPedido,
            LocalDateTime fecha) {
    }

    public record EnviarMensajeChatRequest(
            @NotBlank(message = "Escribe un mensaje.")
            @Size(max = 1000, message = "El mensaje no puede superar 1000 caracteres.")
            String texto,
            Integer idPedido) {
    }

    public record MarcarLeidoChatRequest(
            @NotNull(message = "Indica hasta qué mensaje leíste.")
            @PositiveOrZero(message = "El mensaje leído no es válido.")
            Long hastaId) {
    }

    public record ResumenChatResponse(
            Integer idRuta,
            Integer noLeidos,
            LocalDateTime ultimaFecha,
            String ultimoTexto,
            String ultimoOrigen) {
    }
}
