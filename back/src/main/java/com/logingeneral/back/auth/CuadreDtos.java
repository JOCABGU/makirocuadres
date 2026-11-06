package com.logingeneral.back.auth;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.List;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

public final class CuadreDtos {

    private CuadreDtos() {
    }

    public record ProductoCuadreResponse(
            Integer idProducto,
            String producto,
            String tipoProducto,
            Integer cantidadAsignada) {
    }

    public record EstadoCuadreHoyResponse(
            boolean existe,
            Integer idCuadre,
            Integer idRuta,
            LocalDateTime fecha,
            boolean esPreliminar,
            Integer estadoAprobado,
            boolean modificado) {
    }

    public record ValidarImeisCuadreRequest(
            @NotNull(message = "El producto es requerido.") Integer idProducto,
            @NotEmpty(message = "Debes ingresar al menos un IMEI.") List<String> imeis) {
    }

    public record ImeiCuadreValidacion(
            String imei,
            boolean existe,
            Integer idRuta,
            Integer vendido,
            Integer idProductoEncontrado,
            String productoEncontrado,
            Integer idProductoEsperado,
            String productoEsperado,
            boolean valido,
            String motivo) {
    }

    public record ValidacionCuadreResponse(
            Integer total,
            Integer validos,
            boolean tiraValida,
            List<ImeiCuadreValidacion> productos) {
    }

    public record TiraCuadreRequest(
            @NotNull(message = "El producto es requerido.") Integer idProducto,
            @NotNull(message = "El numero de tira es requerido.") Integer numeroTira,
            @NotNull(message = "El modo es requerido.") String modo,
            @NotNull(message = "La lista de IMEI es requerida.") List<String> imeis,
            Integer cantidadManual,
            Integer cantidadEfectivizada) {
    }

    public record FinalizarCuadreRequest(
            @Size(max = 100, message = "La observacion no puede superar 100 caracteres.") String observacion,
            @NotEmpty(message = "La Lista Master debe contener al menos una tira.")
            List<@Valid TiraCuadreRequest> tiras) {
    }

    public record FinalizarCuadreResponse(
            Integer idCuadre,
            Integer idRuta,
            LocalDateTime fecha,
            Integer totalSobrantes,
            Integer totalVendidos,
            BigDecimal total) {
    }
}
