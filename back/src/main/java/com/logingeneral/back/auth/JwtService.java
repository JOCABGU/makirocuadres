package com.logingeneral.back.auth;

import java.time.Duration;
import java.time.Instant;
import java.util.Date;
import java.util.UUID;

import javax.crypto.SecretKey;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Component;
import org.springframework.web.server.ResponseStatusException;

import com.logingeneral.back.auth.AuthDtos.SucursalResponse;
import com.logingeneral.back.auth.AuthDtos.TecnicoResponse;
import com.logingeneral.back.auth.AuthDtos.UsuarioResponse;

import io.jsonwebtoken.Claims;
import io.jsonwebtoken.JwtException;
import io.jsonwebtoken.JwtParser;
import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.io.Decoders;
import io.jsonwebtoken.security.Keys;

@Component
public class JwtService {

    private static final String ISSUER = "login-general-back";

    private final SecretKey key;
    private final JwtParser parser;
    private final Duration expiration;

    public JwtService(
            @Value("${app.jwt.secret}") String secret,
            @Value("${app.jwt.expiration-hours:8}") long expirationHours) {
        this.key = Keys.hmacShaKeyFor(Decoders.BASE64.decode(secret));
        this.parser = Jwts.parser()
                .verifyWith(key)
                .requireIssuer(ISSUER)
                .build();
        this.expiration = Duration.ofHours(expirationHours);
    }

    public GeneratedToken generate(UsuarioResponse usuario) {
        Instant issuedAt = Instant.now();
        Instant expiresAt = issuedAt.plus(expiration);
        String token = Jwts.builder()
                .issuer(ISSUER)
                .subject(String.valueOf(usuario.id()))
                .id(UUID.randomUUID().toString())
                .issuedAt(Date.from(issuedAt))
                .expiration(Date.from(expiresAt))
                .claim("nombre", usuario.nombre())
                .claim("loggin", usuario.loggin())
                .claim("idRol", usuario.idRol())
                .claim("rol", usuario.rol())
                .claim("idSucursal", usuario.sucursal().id())
                .claim("sucursal", usuario.sucursal().nombre())
                .claim("esTecnico", usuario.tecnico().esTecnico())
                .claim("idUsuarioTecnico", usuario.tecnico().idUsuarioTecnico())
                .claim("idVendedor", usuario.tecnico().idVendedor())
                .claim("idRuta", usuario.tecnico().idRuta())
                .claim("nombreRuta", usuario.tecnico().nombreRuta())
                .claim("nombreTecnico", usuario.tecnico().nombre())
                .claim("ciTecnico", usuario.tecnico().ci())
                .claim("telefonoTecnico", usuario.tecnico().telefono())
                .claim("direccionTecnico", usuario.tecnico().direccion())
                .claim("observacionTecnico", usuario.tecnico().observacion())
                .signWith(key, Jwts.SIG.HS256)
                .compact();
        return new GeneratedToken(token, expiresAt);
    }

    public UsuarioResponse parse(String token) {
        try {
            Claims claims = parser.parseSignedClaims(token).getPayload();
            Integer idUsuario = Integer.valueOf(claims.getSubject());
            Integer idSucursal = asInteger(claims.get("idSucursal"));
            TecnicoResponse tecnico = new TecnicoResponse(
                    Boolean.TRUE.equals(claims.get("esTecnico", Boolean.class)),
                    asNullableInteger(claims.get("idUsuarioTecnico")),
                    asNullableInteger(claims.get("idVendedor")),
                    asNullableInteger(claims.get("idRuta")),
                    claims.get("nombreRuta", String.class),
                    claims.get("nombreTecnico", String.class),
                    claims.get("ciTecnico", String.class),
                    claims.get("telefonoTecnico", String.class),
                    claims.get("direccionTecnico", String.class),
                    claims.get("observacionTecnico", String.class));
            return new UsuarioResponse(
                    idUsuario,
                    claims.get("nombre", String.class),
                    claims.get("loggin", String.class),
                    asNullableInteger(claims.get("idRol")),
                    claims.get("rol", String.class) == null ? "Tecnico" : claims.get("rol", String.class),
                    new SucursalResponse(
                            idSucursal,
                            claims.get("sucursal", String.class)),
                    tecnico);
        } catch (JwtException | IllegalArgumentException ex) {
            throw new ResponseStatusException(
                    HttpStatus.UNAUTHORIZED,
                    "El token JWT no es válido o expiró.");
        }
    }

    private Integer asInteger(Object value) {
        if (value instanceof Number number) {
            return number.intValue();
        }
        return Integer.valueOf(String.valueOf(value));
    }

    private Integer asNullableInteger(Object value) {
        return value == null ? null : asInteger(value);
    }

    public record GeneratedToken(String token, Instant expira) {
    }
}
