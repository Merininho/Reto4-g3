# Documentación Técnica de Infraestructura y Servicios — Grupo 3 (Reto 4)

Documentación completa del despliegue de red dentro de la infraestructura del centro **San Luis**, articulada a través del router central **SAN LUIS** hacia **Internet** y sus tres entornos de red (**AULA 44**, **PROXMOX** y **VMWARE ESXi**), incluyendo el cortafuegos **pfSense**, DNS redundante (**BIND9 Maestro/Esclavo**), **DHCP Failover**, servidores web **Apache2 con SSL/TLS**, **Monitorix** y **NTP** (`hora.roa.es`) para el dominio **`grupo3reto4.eus`**.

---

## 1. Mapa de Red e Infraestructura — Centro San Luis

La topología parte del enrutador troncal **SAN LUIS**, que da salida a **INTERNET** y comunica tres entornos diferenciados:

1. **AULA 44 (`172.26.44.0/24`):** Red física del aula conectada mediante `Switch2` a los puestos de trabajo de los integrantes del grupo (**IKER**, **AIMAR**, **ARITZ**, **EDER**, **IAN**).
2. **PROXMOX (`192.168.3.0/24`):** Entorno de virtualización del Grupo 3 protegido por **PFSENSE** (`WAN: 172.26.46.53` / `LAN: 192.168.3.1`), conectado mediante `Switch0` a los cuatro servidores internos (**DHCP1 + DNS1**, **DHCP2 + DNS2**, **APACHE + MONITORIX** y **SISTEMAS**).
3. **VMWARE ESXi (`172.16.250.0/24`):** Entorno de virtualización corporativo protegido por el cortafuegos **ASA1** y conectado mediante `Switch1` a **PC3** y al servidor **INTRANET** (`172.16.250.103`).

### Topología Lógica de la Red

```text
                                                             ( INTERNET )
                                                                  |
                                                                  v
+-----------------------------------+                     +---------------+
|             AULA 44               |                     |   SAN LUIS    |
|          172.26.44.0/24           |                     | (Router Core) |
|                                   |                     +---+-------+---+
|  [IKER]  [AIMAR]  [ARITZ]         |                         |       |
|       \     |     /               |                         |       |
|       [  Switch2  ]---------------+-------------------------+       |
|       /           \               |                                 |
|  [EDER]           [IAN]           |                                 |
+-----------------------------------+                                 |
                  +---------------------------------------------------+
                  |                                                   |
                  |  NAT Port Forward                                 |
                  |  SSH (2231-2234) | HTTP (3880) | HTTPS (443)      |
                  |  Monitorix (8381) | DNS (53)                      |
                  v                                                   v
+---------------------------------------------------+   +---------------------------+
|               PROXMOX (192.168.3.0/24)            |   |        VMWARE ESXi        |
|                                                   |   |      172.16.250.0/24      |
|              WAN: 172.26.46.53                    |   |                           |
|              +---------------+                    |   |       +-----------+       |
|              |    PFSENSE    |                    |   |       |   ASA1    |       |
|              +-------+-------+                    |   |       +-----+-----+       |
|              LAN: 192.168.3.1                     |   |             |             |
|                      |                            |   |       +-----+-----+       |
|                      v                            |   |       |  Switch1  |       |
|              +---------------+                    |   |       +--+-----+--+       |
|              |    Switch0    |                    |   |          |     |          |
|              +--+--+---+--+--+                    |   |          v     v          |
|                 |  |   |  |                       |   |      [PC3]   [INTRANET]   |
|     +-----------+  |   |  +-----------+           |   |            172.16.250.103 |
|     |              |   |              |           |   +---------------------------+
|     v              v   v              v           |
| [DHCP1+DNS1] [DHCP2+DNS2] [SISTEMAS] [APACHE+MON] |
|   .101         .102         .104        .103      |
| (Server 1)   (Server 2)   (Server 4) (Server 3)   |
+---------------------------------------------------+
```

### Tabla de Direccionamiento IP y Roles

| Nodo / Equipo | Entorno / Switch | Dirección IP | Máscara | Gateway | Rol y Servicios |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **IKER, AIMAR, ARITZ, EDER, IAN** | AULA 44 (`Switch2`) | `172.26.44.x` | `255.255.255.0` | Router San Luis | Puestos cliente del equipo de trabajo |
| **PFSENSE (WAN)** | Troncal hacia San Luis | `172.26.46.53` | `255.255.255.0` | Router San Luis | Interfaz externa, NAT Port Forward |
| **PFSENSE (LAN)** | PROXMOX (`Switch0`) | `192.168.3.1` | `255.255.255.0` | — | Gateway interno, Firewall restrictivo, NTP |
| **DHCP1 + DNS1 (`Server 1`)** | PROXMOX (`Switch0`) | `192.168.3.101` (Estática) | `255.255.255.0` | `192.168.3.1` | DNS Maestro (`grupo3reto4.eus`), DHCP Primario (Failover) |
| **DHCP2 + DNS2 (`Server 2`)** | PROXMOX (`Switch0`) | `192.168.3.102` (Estática) | `255.255.255.0` | `192.168.3.1` | DNS Esclavo (`grupo3reto4.eus`), DHCP Secundario (Failover) |
| **APACHE + MONITORIX (`Server 3`)** | PROXMOX (`Switch0`) | `192.168.3.103` (Estática) | `255.255.255.0` | `192.168.3.1` | Web Principal (`www`), SSL/TLS, Monitorix |
| **SISTEMAS (`Server 4`)** | PROXMOX (`Switch0`) | `192.168.3.104` (Reserva DHCP) | `255.255.255.0` | `192.168.3.1` | Nodo de sistemas con reserva MAC (`bc:24:11:62:47:98`) |
| **INTRANET** | VMWARE ESXi (`Switch1` / `ASA1`) | `172.16.250.103` (Estática) | `255.255.255.0` | ASA1 | Web Intranet (`intranet.grupo3reto4.eus`) con SSL |
| **PC3** | VMWARE ESXi (`Switch1` / `ASA1`) | `172.16.250.x` | `255.255.255.0` | ASA1 | Equipo cliente en entorno ESXi |

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

En **`SISTEMAS` (`Server 4`)**, `dhcp4: true` obtiene automáticamente la reserva estática `192.168.3.104` mediante su dirección MAC (`bc:24:11:62:47:98`).

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

* **DHCP en pfSense:** Desactivado en la interfaz LAN (**Services > DHCP Server > LAN**) para delegar el servicio al clúster DHCP interno (`DHCP1` + `DHCP2`).
* **Política restrictiva en LAN:** Eliminadas reglas permisivas `any`; únicamente se permite tráfico saliente necesario (`DNS 53`, `HTTP 80`, `HTTPS 443`, `NTP 123`) e interno entre los nodos de `Switch0`.

### Tabla de Reglas Port Forward (WAN `172.26.46.53` → LAN Proxmox `192.168.3.0/24`)

| Interfaz | Protocolo | Origen (AULA 44) | Destino | Puerto Externo (WAN) | IP Interna (NAT) | Puerto Interno | Descripción |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| WAN | TCP | `172.26.44.0/24` | WAN address | `2231` | `192.168.3.101` | `22` (SSH) | server1 (DHCP1+DNS1) |
| WAN | TCP | `172.26.44.0/24` | WAN address | `2232` | `192.168.3.102` | `22` (SSH) | server2 (DHCP2+DNS2) |
| WAN | TCP | `172.26.44.0/24` | WAN address | `2233` | `192.168.3.103` | `22` (SSH) | server3 (APACHE+MONITORIX) |
| WAN | TCP | `172.26.44.0/24` | WAN address | `2234` | `192.168.3.104` | `22` (SSH) | server4 (SISTEMAS) |
| WAN | TCP | `172.26.44.0/24` | WAN address | `3880` | `192.168.3.103` | `80` (HTTP) | apache |
| WAN | TCP | `172.26.44.0/24` | WAN address | `8381` | `192.168.3.103` | `8080` | monitorix |
| WAN | TCP/UDP | `172.26.44.0/24` | WAN address | `53` (DNS) | `192.168.3.101` | `53` (DNS) | dns |
| WAN | TCP | `172.26.44.0/24` | WAN address | `443` (HTTPS) | `192.168.3.103` | `443` (HTTPS) | Pagina web https |

---

## 4. Servidor DHCP en Alta Disponibilidad (ISC DHCP Failover)

Configurado entre **`DHCP1 + DNS1` (`primary`)** y **`DHCP2 + DNS2` (`secondary`)** sobre el puerto TCP `647`, repartiendo el rango dinámico `192.168.3.150` – `192.168.3.199` y manteniendo reserva fija por MAC para **`SISTEMAS` (`Server 4`)** (`192.168.3.104`).

### Configuración `/etc/dhcp/dhcpd.conf` (`Server 1` — Primario)

```text
option domain-name "grupo3reto4.eus";
option domain-name-servers 192.168.3.101, 192.168.3.102;
option routers 192.168.3.1;
default-lease-time 600;
max-lease-time 7200;

ddns-updates-style none;
authoritative;

failover peer "dhcp-failover" {
  primary;
  address 192.168.3.101;
  port 647;
  peer address 192.168.3.102;
  peer port 647;
  max-response-delay 60;
  max-unacked-updates 10;
  mclt 1800;
  split 128;
  load balance max seconds 3;
}

subnet 192.168.3.0 netmask 255.255.255.0 {
  option routers 192.168.3.1;
  option domain-name-servers 192.168.3.101, 192.168.3.102;
  option domain-name "grupo3reto4.eus";

  pool {
    failover peer "dhcp-failover";
    range 192.168.3.150 192.168.3.199;
  }

  host server4 {
    hardware ethernet bc:24:11:62:47:98;
    fixed-address 192.168.3.104;
  }
}
```

*(En `Server 2` se replica la misma subred y reserva `host server4`, cambiando `primary;` por `secondary;`, `address 192.168.3.102;` y `peer address 192.168.3.101;`).*

---

## 5. Servicio DNS Redundante (BIND9 Maestro / Esclavo)

* **Dominio:** `grupo3reto4.eus`
* **Maestro (`DHCP1 + DNS1` - `192.168.3.101`):** Aloja las zonas directa e inversa y permite transferencia de zona (`allow-transfer`) hacia `192.168.3.102`.
* **Esclavo (`DHCP2 + DNS2` - `192.168.3.102`):** Replica automáticamente las zonas desde el maestro (`type slave; masters { 192.168.3.101; };`).

### Registros Principales de la Zona Directa (`db.grupo3reto4.eus`)

```dns
$TTL    604800
@       IN      SOA     ns1.grupo3reto4.eus. admin.grupo3reto4.eus. (
                              3         ; Serial
                         604800         ; Refresh
                          86400         ; Retry
                        2419200         ; Expire
                         604800 )       ; Negative Cache TTL
;
@           IN      NS      ns1.grupo3reto4.eus.
@           IN      NS      ns2.grupo3reto4.eus.

ns1         IN      A       192.168.3.101
ns2         IN      A       192.168.3.102
server1     IN      A       192.168.3.101
server2     IN      A       192.168.3.102
server3     IN      A       192.168.3.103
server4     IN      A       192.168.3.104
www         IN      A       192.168.3.103
monitorix   IN      CNAME   server3.grupo3reto4.eus.
intranet    IN      A       172.16.250.103
```

---

## 6. Servidores Web Apache2 (SSL/TLS) y Monitorix

* **Web Principal (`APACHE + MONITORIX` — `192.168.3.103`):**
  * VirtualHost HTTP (`:80`, accesible desde `AULA 44` vía `http://www.grupo3reto4.eus:3880`) y VirtualHost HTTPS (`:443`, accesible vía `https://www.grupo3reto4.eus`) con certificado SSL autofirmado.
* **Intranet (`VMWARE ESXi` — `172.16.250.103`):**
  * VirtualHost HTTPS (`https://intranet.grupo3reto4.eus`) protegido tras `ASA1`.
* **Monitorix (`APACHE + MONITORIX` — puerto interno `8080`):**
  * Accesible desde `AULA 44` mediante `http://172.26.46.53:8381/monitorix`.

---

## 7. Guía Rápida de Acceso y Verificación

### Acceso SSH desde AULA 44 (`172.26.44.0/24`)

```bash
ssh -p 2231 alumno@172.26.46.53   # Server 1 (DHCP1 + DNS1)
ssh -p 2232 alumno@172.26.46.53   # Server 2 (DHCP2 + DNS2)
ssh -p 2233 alumno@172.26.46.53   # Server 3 (APACHE + MONITORIX)
ssh -p 2234 alumno@172.26.46.53   # Server 4 (SISTEMAS - IP fija .104)
```

### Comprobación de Servicios

```bash
# Resolución DNS contra pfSense WAN
nslookup www.grupo3reto4.eus 172.26.46.53

# Estado de sincronización NTP y zona horaria
timedatectl status

# Estado del failover DHCP y concesiones
sudo journalctl -u isc-dhcp-server -n 15
```