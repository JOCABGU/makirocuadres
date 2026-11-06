package com.logingeneral.back.auth;

import java.math.BigDecimal;
import java.util.List;

public final class SaldoRutaDtos {

    private SaldoRutaDtos() {
    }

    public record SaldoProducto(
            Integer idProducto,
            String producto,
            Integer cantidad,
            String tipoProducto,
            BigDecimal precioVenta,
            BigDecimal valorTotal) {
    }

    public record SaldoRutaResponse(
            Integer idRuta,
            String ruta,
            Integer totalProductos,
            Integer totalUnidades,
            BigDecimal valorTotal,
            List<SaldoProducto> productos) {
    }
}
