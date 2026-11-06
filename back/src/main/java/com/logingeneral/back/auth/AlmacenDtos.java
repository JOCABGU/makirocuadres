package com.logingeneral.back.auth;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.time.LocalDate;
import java.util.List;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.Size;

public final class AlmacenDtos {

    private AlmacenDtos() {
    }

    public record TecnicoPendientesResponse(
            Integer idUsuario,
            String nombre,
            Integer idVendedor,
            Integer idRuta,
            String ruta,
            Integer pedidosPendientes) {
    }

    public record PedidoTecnicoResponse(
            Integer idPedido,
            Integer idRuta,
            String ruta,
            LocalDateTime fechaRegistro,
            String observacion,
            Integer modificadoPorAlmacen,
            String comentarioAlmacen,
            BigDecimal total,
            Integer estadoAprobado,
            Integer cantidadProductos,
            Integer cantidadUnidades) {
    }

    public record RutaPendientesResponse(
            Integer idRuta,
            String ruta,
            Integer idVendedor,
            String tecnico,
            Integer pedidosPendientes) {
    }

    public record PedidoPendienteAlmacenResponse(
            Integer idPedido,
            Integer idUsuarioTecnico,
            Integer idVendedor,
            String tecnico,
            Integer idRuta,
            String ruta,
            LocalDateTime fechaRegistro,
            String observacion,
            Integer modificadoPorAlmacen,
            String comentarioAlmacen,
            BigDecimal total,
            Integer estadoAprobado,
            String aprobadoPor,
            Integer cantidadProductos,
            Integer cantidadUnidades) {
    }

    public record ModificarDetallePedidoRequest(
            @NotNull(message = "El detalle es requerido.") Integer idDetalle,
            @NotNull(message = "La cantidad es requerida.")
            @Min(value = 0, message = "La cantidad no puede ser negativa.") Integer cantidad) {
    }

    public record ModificarPedidoAlmacenRequest(
            @NotEmpty(message = "Debe enviar el detalle completo del pedido.")
            List<@Valid ModificarDetallePedidoRequest> detalles,
            @NotBlank(message = "Debe ingresar el motivo de la modificación.")
            @Size(max = 250, message = "El comentario de almacén no puede superar los 250 caracteres.")
            String comentarioAlmacen) {
    }

    public record ModificarPedidoAlmacenResponse(
            Integer idPedido,
            BigDecimal total,
            Integer cantidadProductos,
            Integer cantidadUnidades,
            Integer modificadoPorAlmacen,
            String comentarioAlmacen) {
    }

    public record AprobarPedidoRequest(
            @NotNull(message = "La fecha de entrega es requerida.") LocalDate fechaEntrega,
            String tokenVinculacion,
            @NotNull(message = "La lista de productos fisicos es requerida.")
            List<@Valid ProductoFisicoAsignadoRequest> productos) {
    }

    public record ProductoFisicoAsignadoRequest(
            @NotNull(message = "El detalle del pedido es requerido.") Integer idDetalle,
            @NotNull(message = "El IMEI es requerido.") String imei,
            @NotNull(message = "El número de tira es requerido.") Integer numeroTira,
            @NotNull(message = "El modo de tira es requerido.") String modoTira) {
    }

    public record ProductoFisicoPedidoResponse(
            Integer idAsignacion,
            Integer idDetalle,
            Integer idProducto,
            String producto,
            String tipoProducto,
            String imei,
            Integer idRuta,
            Integer numeroTira,
            String modoTira,
            LocalDateTime fechaRegistro) {
    }

    public record AprobarPedidoResponse(
            Integer idPedido,
            LocalDateTime fechaEntrega,
            Integer estadoAprobado,
            String aprobadoPor) {
    }

    public record DetallePedidoDirectoRequest(
            @NotNull(message = "El producto es requerido.") Integer idProducto,
            @NotNull(message = "La cantidad es requerida.")
            @Min(value = 1, message = "La cantidad debe ser mayor a cero.") Integer cantidad) {
    }

    public record ProductoFisicoDirectoRequest(
            @NotNull(message = "El producto es requerido.") Integer idProducto,
            @NotBlank(message = "El IMEI es requerido.") String imei,
            @NotNull(message = "El numero de tira es requerido.") Integer numeroTira,
            @NotBlank(message = "El modo de tira es requerido.") String modoTira) {
    }

    public record CrearPedidoDirectoRequest(
            @NotNull(message = "La ruta es requerida.") Integer idRuta,
            @Size(max = 50, message = "La observacion no puede superar los 50 caracteres.") String observacion,
            @NotEmpty(message = "El pedido debe contener al menos un producto.")
            List<@Valid DetallePedidoDirectoRequest> detalles,
            @NotNull(message = "La lista de productos fisicos es requerida.")
            List<@Valid ProductoFisicoDirectoRequest> productos) {
    }

    public record CrearPedidoDirectoResponse(
            Integer idPedidoVendedor,
            Integer idAlmacenVendedor,
            Integer idRuta,
            Integer cantidadProductos,
            Integer cantidadUnidades,
            BigDecimal total,
            LocalDateTime fechaRegistro) {
    }

    public record ValidarImeisDirectosRequest(
            @NotEmpty(message = "Ingresa al menos un IMEI.") List<@NotBlank String> imeis) {
    }

    public record ImeiDirectoValidacionResponse(
            String imei, Integer idProducto, String producto, boolean valido, String motivo) {
    }

    public record ValidacionTigoMoneyResponse(
            BigDecimal saldoDisponible,
            BigDecimal montoPedido,
            BigDecimal saldoRestante,
            Boolean valido) {
    }
}
