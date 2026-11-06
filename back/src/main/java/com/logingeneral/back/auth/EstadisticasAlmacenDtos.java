package com.logingeneral.back.auth;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalDateTime;

public final class EstadisticasAlmacenDtos {

    private EstadisticasAlmacenDtos() {
    }

    public record EstadisticaPedidosDiaRutaResponse(
            LocalDate fecha,
            Integer idRuta,
            String ruta,
            Integer realizados,
            Integer aprobados,
            Integer pendientes,
            Integer modificados,
            Integer unidadesSolicitadas,
            Integer unidadesAprobadas,
            BigDecimal montoSolicitado,
            BigDecimal montoAprobado,
            Integer cuadresEnviados,
            Integer cuadresRealizados,
            Integer cuadresPendientes,
            Integer cuadresModificados,
            Integer unidadesSobrantes,
            Integer unidadesVendidas,
            BigDecimal montoVendido) {
    }

    public record EstadisticaCuadreProductoResponse(
            LocalDate fecha,
            Integer idRuta,
            String ruta,
            Integer idCuadre,
            Integer idProducto,
            String producto,
            String tipoProducto,
            Integer sobrantes,
            Integer vendidos,
            BigDecimal precio,
            BigDecimal totalVendido) {
    }

    public record EstadisticaVendedorResponse(
            Integer idVendedor,
            String vendedor,
            Integer pedidos,
            Integer aprobados,
            Integer pendientes,
            Integer modificados,
            Integer unidadesSolicitadas,
            BigDecimal montoSolicitado) {
    }

    public record EstadisticaConsumoProductoDiaResponse(
            LocalDate fecha,
            Integer idProducto,
            String producto,
            String tipoProducto,
            Integer unidadesVendidas,
            Integer unidadesSobrantes,
            BigDecimal totalVendido,
            Integer rutasConMovimiento,
            Integer cuadres) {
    }

    public record EstadisticaDemoraCajaResponse(
            LocalDate fecha,
            Integer idCuadre,
            Integer idRuta,
            String ruta,
            Integer idVendedor,
            String vendedor,
            LocalDateTime fechaCuadre,
            Integer idCaja,
            LocalDateTime fechaCaja,
            Integer minutosDemora) {
    }
}
