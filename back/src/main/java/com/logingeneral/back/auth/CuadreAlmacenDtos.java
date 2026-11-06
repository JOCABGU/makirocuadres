package com.logingeneral.back.auth;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.List;

public final class CuadreAlmacenDtos {

    private CuadreAlmacenDtos() {
    }

    public record RutaCuadreResponse(
            Integer idRuta,
            String ruta,
            Integer idVendedor,
            String tecnico,
            boolean realizoCuadre,
            Integer idCuadre,
            LocalDateTime fecha,
            BigDecimal total) {
    }

    public record TiraCuadreAlmacenResponse(
            Integer idSaldoCuadre,
            Integer cantidad,
            String codigoInicio,
            String codigoFinal) {
    }

    public record ProductoCuadreAlmacenResponse(
            Integer idProducto,
            String producto,
            String tipoProducto,
            Integer saldoAnterior,
            Integer sobranteIngresado,
            Integer vendido,
            Integer saldoActual,
            BigDecimal precio,
            BigDecimal totalVendido,
            List<TiraCuadreAlmacenResponse> tiras) {
    }

    public record DetalleCuadreAlmacenResponse(
            Integer idCuadre,
            Integer idRuta,
            String ruta,
            Integer idVendedor,
            String tecnico,
            LocalDateTime fecha,
            String observacion,
            BigDecimal total,
            List<ProductoCuadreAlmacenResponse> productos) {
    }
}
