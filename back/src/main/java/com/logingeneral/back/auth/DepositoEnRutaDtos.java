package com.logingeneral.back.auth;

import java.math.BigDecimal;
import java.time.LocalDateTime;

import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Positive;

public class DepositoEnRutaDtos {

    public record EntidadResponse(
            Integer idEntidad,
            String nombre) {
    }

    public record RegistrarDepositoRequest(
            @NotNull(message = "El banco es obligatorio")
            Integer idEntidad,

            @NotBlank(message = "La cuenta es obligatoria")
            String cuenta,

            @NotNull(message = "El monto es obligatorio")
            @Positive(message = "El monto debe ser mayor a cero")
            BigDecimal monto,

            String op) {
    }

    public record RegistrarDepositoResponse(
            Integer idDeposito,
            String mensaje) {
    }

    public record DepositoResponse(
            Integer idDeposito,
            Integer idRuta,
            Integer idVendedor,
            Integer idUsuario,
            Integer idEntidad,
            String nombreBanco,
            String cuenta,
            BigDecimal monto,
            String op,
            LocalDateTime fechaRegistro,
            Integer estadoAprobacion,
            String estadoTexto) {
    }

    public record DepositoContabilidadResponse(
            Integer idDeposito,
            Integer idRuta,
            String ruta,
            Integer idVendedor,
            String vendedor,
            Integer idUsuario,
            Integer idEntidad,
            String nombreBanco,
            String cuenta,
            BigDecimal monto,
            String op,
            LocalDateTime fechaRegistro,
            Integer estadoAprobacion,
            String estadoTexto,
            String aprobadoPor,
            LocalDateTime fechaAprobacion,
            boolean puedeEditar,
            boolean puedeAprobar) {
    }

    public record EditarDepositoContabilidadRequest(
            @NotNull(message = "El banco es obligatorio")
            Integer idEntidad,
            @NotBlank(message = "La cuenta es obligatoria")
            String cuenta,
            @NotNull(message = "El monto es obligatorio")
            @Positive(message = "El monto debe ser mayor a cero")
            BigDecimal monto,
            String op) {
    }
}
