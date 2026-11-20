# Documentación Técnica de Infraestructura y Servicios — Grupo 3 (Reto 4)

Documentación completa del despliegue de red, cortafuegos perimetral **pfSense**, resolución de nombres redundante (**BIND9 Maestro/Esclavo**), servicio **DHCP en alta disponibilidad (Failover)**, servidores web **Apache2 con SSL/TLS**, monitorización (**Monitorix**) y sincronización horaria (**NTP**) para el dominio **`grupo3reto4.eus`**.

---

## 1. Mapa de Red e Infraestructura

### Topología Lógica de la Red

```text
                        [ Red del Aula / Exterior ]
                             172.26.44.0/24
                                    |
                                    |  Acceso filtrado por NAT (Port Forward)
                                    |  SSH (2231-2234) | HTTP (3880) | HTTPS (443)
                                    |  Monitorix (8381) | DNS (53)
                                    v
                     +-----------------------------+
                     |      Cortafuegos pfSense    |
                     |    WAN: 172.26.46.53/24     |
                     |    LAN: 192.168.3.1/24      |
                     +--------------+--------------+
                                    |
                                    |  Subred Interna de Servidores (192.168.3.0/24)
                                    |  Política restrictiva (puertos 53, 80, 123, 443)
                                    |  NTP: hora.roa.es (Europe/Madrid)
        +---------------------------+---------------------------+
        |                           |                           |
        v                           v                           v
+---------------+           +---------------+           +---------------+
|   Server 1    |           |   Server 2    |           |   Server 3    |
| 192.168.3.101 |<--------->| 192.168.3.102 |           | 192.168.3.103 |
+---------------+  Sync     +---------------+           +---------------+
| - DNS Master  |  DNS/DHCP | - DNS Slave   |           | - Apache2 Web |
| - DHCP Primary|  (p. 647) | - DHCP Sec.   |           | - SSL (HTTPS) |
| - SSH (:2231) |           | - SSH (:2232) |           | - Monitorix   |
+---------------+           +---------------+           | - SSH (:2233) |
                                                        +---------------+
        |
        |  Enrutamiento hacia Intranet (172.16.250.0/24)
        +---------------------------+
        |                           |
        v                           v
+---------------+           +---------------+
|   Server 4    |           |   Intranet    |
| 192.168.3.104 |           | 172.16.250.103|
+---------------+           +---------------+
| - Cliente/Srv |           | - Apache2 Web |
| - Reserva DHCP|           | - SSL (HTTPS) |
|   por MAC     |           | - intranet.   |
| - SSH (:2234) |           |   grupo3reto4 |
+---------------+           +---------------+
```

### Tabla de Direccionamiento IP y Roles

| Dispositivo | Interfaz / Red | Dirección IP | Máscara | Puerta de Enlace | Servicios Principales |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **pfSense (WAN)** | Red Aula (`172.26.44.0/24`) | `172.26.46.53` | `255.255.255.0` | — | NAT Port Forward, Firewall perimetral |
| **pfSense (LAN)** | Red Interna (`192.168.3.0/24`) | `192.168.3.1` | `255.255.255.0` | — | Gateway interno, Firewall restrictivo, NTP |
| **Server 1 (`server1-g3`)** | LAN Interna | `192.168.3.101` (Estática) | `255.255.255.0` | `192.168.3.1` | DNS Maestro (`grupo3reto4.eus`), DHCP Primario (Failover) |
| **Server 2 (`server2-g3`)** | LAN Interna | `192.168.3.102` (Estática) | `255.255.255.0` | `192.168.3.1` | DNS Esclavo (`grupo3reto4.eus`), DHCP Secundario (Failover) |
| **Server 3 (`server3-g3`)** | LAN Interna | `192.168.3.103` (Estática) | `255.255.255.0` | `192.168.3.1` | Servidor Web Principal (`www`), SSL/TLS, Monitorix |
| **Server 4 (`server4-g3`)** | LAN Interna | `192.168.3.104` (Reserva DHCP) | `255.255.255.0` | `192.168.3.1` | Nodo interno asignado por reserva MAC (`bc:24:11:62:47:98`) |
| **Servidor Intranet** | Red Intranet (`172.16.250.0/24`) | `172.16.250.103` (Estática) | `255.255.255.0` | — | Servidor Web Intranet (`intranet.grupo3reto4.eus`) con SSL |

---

## 2. Configuración de Red (Netplan) y NTP

### Netplan en Servidores Estáticos (`Server 1`, `Server 2`, `Server 3`)

Ejemplo de `/etc/netplan/00-installer-config.yaml` (ajustando la IP a `.101`, `.102` o `.103`):

```yaml
network:
  version: 2
  ethernets:
    eth0:
      dhcp4: false
      addresses:
        - 192.168.3.101/24
      routes:
        - to: default
          via: 192.168.3.1
      nameservers:
        search: [grupo3reto4.eus]
        addresses: [192.168.3.101, 192.168.3.102]
```

En **`Server 4`**, `dhcp4: true` obtiene automáticamente la reserva estática `192.168.3.104` mediante su dirección MAC (`bc:24:11:62:47:98`).

### Sincronización Horaria NTP (`hora.roa.es`)

Todos los servidores y pfSense están configurados en la zona horaria **`Europe/Madrid`** sincronizando contra el Real Instituto y Observatorio de la Armada (**`hora.roa.es`**):

```bash
sudo timedatectl set-timezone Europe/Madrid
```

Archivo `/etc/systemd/timesyncd.conf`:

```ini
[Time]
NTP=hora.roa.es
FallbackNTP=ntp.ubuntu.com
```

---

## 3. Cortafuegos y NAT (pfSense)

* **DHCP en pfSense:** Desactivado en la interfaz LAN (**Services > DHCP Server > LAN**) para delegar el servicio al clúster DHCP interno.
* **Política restrictiva en LAN:** Eliminadas reglas permisivas `any`; únicamente se permite tráfico saliente necesario (`DNS 53`, `HTTP 80`, `HTTPS 443`, `NTP 123`) e interno entre servidores.

### Tabla de Reglas Port Forward (WAN `172.26.46.53` → LAN)

| Interfaz | Protocolo | Origen | Destino | Puerto Externo (WAN) | IP Interna (NAT) | Puerto Interno | Descripción |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| WAN | TCP | `172.26.44.0/24` | WAN address | `2231` | `192.168.3.101` | `22` (SSH) | server1 |
| WAN | TCP | `172.26.44.0/24` | WAN address | `2232` | `192.168.3.10