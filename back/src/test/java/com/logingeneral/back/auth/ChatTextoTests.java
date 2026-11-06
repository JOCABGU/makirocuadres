package com.logingeneral.back.auth;

import static org.junit.jupiter.api.Assertions.assertEquals;

import org.junit.jupiter.api.Test;

class ChatTextoTests {

    @Test
    void quitaCaracteresDeControlYConservaSaltosDeLinea() {
        assertEquals("Hola\nmodifica el pedido", AuthService.limpiarTextoChat("  Hola\u0000\u0007\r\nmodifica el pedido\u001b  "));
    }

    @Test
    void reduceSaltosDeLineaRepetidos() {
        assertEquals("Uno\n\nDos", AuthService.limpiarTextoChat("Uno\n\n\n\n\nDos"));
    }

    @Test
    void textoVacioONuloQuedaVacio() {
        assertEquals("", AuthService.limpiarTextoChat(null));
        assertEquals("", AuthService.limpiarTextoChat(" \u0000 \r\n "));
    }

    @Test
    void elHtmlSeGuardaComoTextoPlano() {
        // No se interpreta ni se elimina: el front lo muestra como texto (React escapa el contenido).
        assertEquals("<script>alert(1)</script>", AuthService.limpiarTextoChat("<script>alert(1)</script>"));
    }
}
