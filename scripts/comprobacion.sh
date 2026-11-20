#!/usr/bin/env bash
set -euo pipefail

# Comprobaciones básicas de conectividad y servicios.
# Sustituir el destino y los puertos pendientes antes de ejecutar.

readonly TARGET="PENDIENTE_IP_DESTINO"

echo "== Dirección IP ==" 
ip -brief address

echo "== Tabla de rutas ==" 
ip route

echo "== Prueba ICMP ==" 
ping -c 4 "$TARGET"

echo "== Resolución DNS ==" 
getent hosts PENDIENTE_DOMINIO

echo "== Puertos principales ==" 
for port in 53 80 8080; do
    if timeout 2 bash -c "</dev/tcp/$TARGET/$port" 2>/dev/null; then
        echo "Puerto $port: abierto"
    else
        echo "Puerto $port: cerrado o filtrado"
    fi
done
