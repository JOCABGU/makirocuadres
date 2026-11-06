package com.logingeneral.back.auth;

record SucursalConnection(
        Integer id,
        String nombre,
        String agente,
        String host,
        String database,
        Integer port) {
}
