package com.logingeneral.back.auth;

import java.util.List;
import java.util.Map;

import org.springframework.http.HttpHeaders;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/auth/password")
public class PasswordResetController {
    private final PasswordResetService service;

    public PasswordResetController(PasswordResetService service) { this.service = service; }

    @GetMapping("/estado")
    public Map<String, Boolean> estado(@RequestHeader(HttpHeaders.AUTHORIZATION) String authorization) {
        return service.estado(authorization);
    }

    @PostMapping("/cambiar")
    public ResponseEntity<Void> cambiar(@RequestHeader(HttpHeaders.AUTHORIZATION) String authorization,
            @RequestBody PasswordResetService.CambioRequest request) {
        service.cambiar(authorization, request);
        return ResponseEntity.noContent().build();
    }

    @GetMapping("/roles")
    public List<PasswordResetService.RolClave> roles(@RequestHeader(HttpHeaders.AUTHORIZATION) String authorization) {
        return service.roles(authorization);
    }

    @GetMapping("/usuarios")
    public List<PasswordResetService.UsuarioClave> usuarios(@RequestHeader(HttpHeaders.AUTHORIZATION) String authorization,
            @RequestParam(defaultValue = "") String buscar, @RequestParam(required = false) Integer rolId) {
        return service.usuarios(authorization, buscar, rolId);
    }

    @PostMapping("/solicitar")
    public PasswordResetService.SolicitudResultado solicitar(@RequestHeader(HttpHeaders.AUTHORIZATION) String authorization,
            @RequestBody PasswordResetService.SolicitudRequest request) {
        return service.solicitar(authorization, request);
    }
}
