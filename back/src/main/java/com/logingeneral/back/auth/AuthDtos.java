package com.logingeneral.back.auth;

import java.time.Instant;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;

public final class AuthDtos {

    private AuthDtos() {
    }

    public record SucursalResponse(Integer id, String nombre) {
    }

    public record LoginRequest(
            @NotBlank(message = "El usuario es requerido.") String usuario,
            @NotBlank(message = "La contraseña es requerida.") String password,
            @NotNull(message = "La sucursal es requerida.") Integer idSucursal) {
    }

    public record UsuarioResponse(
            Integer id,
            String nombre,
            String loggin,
            Integer idRol,
            String rol,
            SucursalResponse sucursal,
            TecnicoResponse tecnico) {
    }

    public record TecnicoResponse(
            boolean esTecnico,
            Integer idUsuarioTecnico,
            Integer idVendedor,
            Integer idRuta,
            String nombreRuta,
            String nombre,
            String ci,
            String telefono,
            String direccion,
            String observacion) {
    }

    public record LoginResponse(
            String token,
            Instant expira,
            UsuarioResponse usuario) {
    }
}
