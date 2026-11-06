package com.logingeneral.back.auth;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

public final class SistemasDtos {

    private SistemasDtos() {
    }

    public record RutaSistemasResponse(
            Integer idRuta,
            String ruta,
            Integer idVendedor,
            String tecnico,
            LocalDateTime ultimoMovimiento) {
    }

    public record MovimientoRutaResponse(
            String tipo,
            Integer idReferencia,
            LocalDateTime fecha,
            BigDecimal total,
            String estado,
            String observacion) {
    }

    public record PreviewCascadaItemResponse(
            String tipo,
            Integer idReferencia,
            LocalDateTime fecha,
            BigDecimal total) {
    }

    public record PreviewCascadaDetalleResponse(
            String tipo,
            Integer idReferencia,
            LocalDateTime fecha,
            BigDecimal total,
            String estadoActual,
            String estadoProyectado,
            String observacion,
            Integer idProducto,
            String producto,
            Integer cantidadMovimiento,
            Integer saldoActual,
            Integer saldoAntesMovimiento,
            Integer saldoDespuesMovimiento,
            Integer saldoProyectadoFinal,
            Integer fisicosAfectados,
            Integer fisicosVendidos,
            String codigos,
            String tablaPrincipal,
            String tablasAfectadas,
            boolean bloqueado,
            String motivoBloqueo) {
    }

    public record PreviewTablaCascadaResponse(
            String tipoMovimiento,
            Integer idReferencia,
            String tabla,
            String consultaSql,
            List<String> columnas,
            List<Map<String, Object>> filasActuales,
            List<Map<String, Object>> filasProyectadas) {
    }

    public record EjecutarCascadaRequest(
            @NotNull(message = "La fecha desde la cual revertir es requerida.") LocalDateTime desdeFecha,
            @NotBlank(message = "Debes indicar una justificación.") String justificacion,
            @NotBlank @Size(max = 100) String jobId) {
    }

    public record EjecutarCascadaResponse(
            Integer idReversion,
            Integer idRuta,
            Integer cantidadMovimientos,
            LocalDateTime fechaEjecucion) {
    }
}
