#!/usr/bin/env bash
set -euo pipefail

# Plantilla de enrutamiento para Linux.
# Ejecutar solo después de sustituir los valores pendientes.

readonly WAN_IFACE="PENDIENTE_WAN"
readonly LAN_IFACE="PENDIENTE_LAN"
readonly LAN_NETWORK="PENDIENTE_RED/PENDIENTE_PREFIJO"

# Habilitar el reenvío IP de forma temporal.
sudo sysctl -w net.ipv4.ip_forward=1

# Repartir tráfico de la LAN hacia Internet.
sudo iptables -t nat -A POSTROUTING \
    -s "$LAN_NETWORK" -o "$WAN_IFACE" -j MASQUERADE

# Permitir el tráfico reenviado entre WAN y LAN.
sudo iptables -A FORWARD -i "$LAN_IFACE" -o "$WAN_IFACE" -j ACCEPT
sudo iptables -A FORWARD -i "$WAN_IFACE" -o "$LAN_IFACE" \
    -m state --state RELATED,ESTABLISHED -j ACCEPT
