package com.logingeneral.back.auth;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.List;

import jakarta.validation.Valid;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

public final class PedidoEnRutaDtos {

    private PedidoEnRutaDtos() {
    }

    public record TipoProductoResponse(Integer idTipoProducto, String nombre) {
    }

    public record ProductoPedidoResponse(
            Integer idProducto,
            String nombre,
            BigDecimal precioVenta) {
    }

    public record PromedioVentaResponse(
            Integer idProducto,
            String producto,
            BigDecimal promedioVenta,
            BigDecimal diferencia) {
    }

    public record DetallePedidoRequest(
            @NotNull(message = "El producto es requerido.") Integer idProducto,
            @NotNull(message = "La cantidad es requerida.")
            @Min(value = 1, message = "La cantidad debe ser mayor a cero.") Integer cantidad) {
    }

    public record CrearPedidoRequest(
            @NotEmpty(message = "El pedido debe contener al menos un producto.")
            List<@Valid DetallePedidoRequest> detalles,
            @Size(max = 50, message = "La observación no puede superar los 50 caracteres.")
            String observacion) {
    }

    public record CrearPedidoResponse(
            Integer idPedido,
            Integer cantidadProductos,
            Integer cantidadUnidades,
            BigDecimal total,
            LocalDateTime fechaRegistro,
            Integer estadoAprobado) {
    }

    public record PedidoResumenResponse(
            Integer idPedido,
            LocalDateTime fechaRegistro,
            String observacion,
            Integer modificadoPorAlmacen,
            String comentarioAlmacen,
            BigDecimal total,
            Integer estadoAprobado,
            Integer cantidadProductos,
            Integer cantidadUnidades) {
    }

    public record DetallePedidoResponse(
            Integer idDetalle,
            Integer idProducto,
            String producto,
            String tipoProducto,
            Integer cantidad,
            BigDecimal precio,
            BigDecimal totalParcial) {
    }
}
