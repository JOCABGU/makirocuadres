package com.logingeneral.back.scanner;

import java.util.List;

import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

public final class ProductoScanDtos {

    private ProductoScanDtos() {
    }

    public record ValidarProductosRequest(
            @NotEmpty(message = "La tira debe contener al menos un IMEI.")
            @Size(max = 1000, message = "No se pueden validar más de 1000 IMEI a la vez.")
            List<String> imeis) {
    }

    public record ProductoValidacion(
            String imei,
            boolean existe,
            Integer idRuta,
            Integer vendido,
            boolean valido,
            String motivo) {
    }

    public record ValidarProductosResponse(
            int total,
            int validos,
            boolean tiraValida,
            List<ProductoValidacion> productos) {
    }

    public record ValidarProductosPedidoRequest(
            @NotNull(message = "El pedido es requerido.") Integer idPedido,
            @NotNull(message = "El detalle del pedido es requerido.") Integer idDetalle,
            String tokenVinculacion,
            @NotEmpty(message = "La tira debe contener al menos un IMEI.")
            @Size(max = 1000, message = "No se pueden validar mas de 1000 IMEI a la vez.")
            List<String> imeis) {
    }

    public record ValidarProductosDirectosRequest(
            @NotNull(message = "El producto es requerido.") Integer idProducto,
            @NotNull(message = "La cantidad solicitada es requerida.") Integer cantidadSolicitada,
            @NotEmpty(message = "La tira debe contener al menos un IMEI.")
            @Size(max = 1000, message = "No se pueden validar mas de 1000 IMEI a la vez.")
            List<String> imeis) {
    }

    public record ProductoPedidoValidacion(
            String imei,
            boolean existe,
            Integer idRuta,
            Integer vendido,
            Integer idProductoEncontrado,
            String productoEncontrado,
            Integer idProductoEsperado,
            String productoEsperado,
            Integer cantidadSolicitada,
            boolean valido,
            String motivo) {
    }

    public record ValidarProductosPedidoResponse(
            int total,
            int validos,
            boolean tiraValida,
            List<ProductoPedidoValidacion> productos) {
    }
}
