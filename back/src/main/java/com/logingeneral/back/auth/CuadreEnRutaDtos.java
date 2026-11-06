package com.logingeneral.back.auth;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.List;

public final class CuadreEnRutaDtos {
    private CuadreEnRutaDtos() {}

    public record ResumenCuadreEnRutaResponse(
            Integer idCuadreEnRuta, Integer idRuta, String ruta,
            Integer idVendedor, String tecnico, Integer idUsuario,
            LocalDateTime fecha, String observacion, BigDecimal total,
            Integer estadoAprobado, String aprobadoPor, Integer idCuadre,
            boolean modificado, LocalDateTime fechaAprobacion) {}

    public record ProductoCuadreEnRutaResponse(
            Integer idProducto, String producto, String tipoProducto,
            Integer itemsSobrantes, Integer itemsVendidos,
            BigDecimal precio, BigDecimal totalVendidos) {}

    public record DetalleCuadreEnRutaResponse(
            Integer idCuadreEnRuta, Integer idRuta, String ruta,
            Integer idVendedor, String tecnico, Integer idUsuario,
            LocalDateTime fecha, String observacion, BigDecimal total,
            Integer estadoAprobado, String aprobadoPor, Integer idCuadre,
            boolean modificado, LocalDateTime fechaAprobacion,
            String tirasXml, List<ProductoCuadreEnRutaResponse> productos,
            CuadreAlmacenDtos.DetalleCuadreAlmacenResponse versionDefinitiva) {}
}
