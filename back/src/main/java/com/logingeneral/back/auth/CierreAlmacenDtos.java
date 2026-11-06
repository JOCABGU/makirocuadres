package com.logingeneral.back.auth;

import java.math.BigDecimal;
import java.time.LocalDate;

import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

public final class CierreAlmacenDtos {
    private CierreAlmacenDtos() {
    }

    public record CierreAlmacenProductoResponse(
            Integer idProducto,
            String nombre,
            BigDecimal precioVenta,
            BigDecimal saldoDiaAnterior,
            BigDecimal totalSaldoDiaAnterior,
            BigDecimal saldoDiaAnteriorTigo,
            BigDecimal totalSaldoDiaAnteriorTigo,
            BigDecimal compraDia,
            BigDecimal totalCompraDia,
            BigDecimal compraDiaTigo,
            BigDecimal totalCompraDiaTigo,
            BigDecimal devolucionIngreso,
            BigDecimal totalDevolucionIngreso,
            BigDecimal ventaDia,
            BigDecimal totalVentaDia,
            BigDecimal saldoDiaHoy,
            BigDecimal totalSaldoDiaHoy,
            BigDecimal saldoDiaHoyTigo,
            BigDecimal totalSaldoDiaHoyTigo) {
    }

    public record EstadoCierreAlmacenResponse(
            boolean existe,
            Integer idCierreAlmacen,
            LocalDate fecha,
            String observacion,
            Integer cantidadProductos) {
    }

    public record GuardarCierreAlmacenRequest(
            @NotNull(message = "La fecha del cierre es requerida.") LocalDate fecha,
            @Size(max = 28, message = "La observacion admite hasta 28 caracteres.") String observacion) {
    }

    public record GuardarCierreAlmacenResponse(
            Integer idCierreAlmacen,
            LocalDate fecha,
            Integer cantidadProductos) {
    }
}
