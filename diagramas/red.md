# Mapa lógico de la red

Todas las máquinas se encuentran dentro de la red de **SAN LUIS**. Esta red
contiene dos segmentos principales: la red de Proxmox, donde se alojan las
máquinas virtuales y pfSense, y la red de intranet, donde se encuentra el
servidor web de la intranet.

```mermaid
flowchart TB
    SANLUIS["Red SAN LUIS"]

    subgraph PROXMOX["Red de Proxmox"]
        Aula["Red del aula<br/>172.26.44.0/24"]
        WAN["pfSense WAN<br/>172.26.46.53"]
        LANFW["pfSense LAN<br/>192.168.3.1"]
        Servidores["Red interna de servidores<br/>192.168.3.0/24"]
        DNS1["server1-g3<br/>DNS maestro<br/>192.168.3.101"]
        DNS2["server2-g3<br/>DNS esclavo<br/>192.168.3.102"]
        WEB["server3-g3<br/>Apache + Monitorix<br/>192.168.3.103"]
        DHCP["server4-g3<br/>ISC DHCP<br/>192.168.3.104"]
        Cliente["Cliente de aula"]

        Aula --- WAN
        WAN --- LANFW
        LANFW --- Servidores
        Servidores --- DNS1
        Servidores --- DNS2
        Servidores --- WEB
        Servidores --- DHCP
        Aula --- Cliente
    end

    subgraph INTRANET["Red de intranet"]
        Intranet["Servidor intranet<br/>172.16.250.103"]
    end

    SANLUIS --- PROXMOX
    SANLUIS --- INTRANET
    LANFW --- Intranet
```

## Direccionamiento y servicios

- Todas las máquinas pertenecen a la red general de SAN LUIS.
- La red de Proxmox contiene la red del aula (`172.26.44.0/24`) y la red
  interna de servidores (`192.168.3.0/24`).
- La red de intranet utiliza `172.16.250.0/24`.
- La puerta de enlace de los servidores es `192.168.3.1`.
- Los servidores DNS son `192.168.3.101` y `192.168.3.102`.
- DHCP entrega direcciones `192.168.3.150`–`192.168.3.200`.
- pfSense publica HTTP (`3880`), HTTPS (`443`), DNS (`53`), Monitorix
  (`8381`) y SSH mediante los puertos `2231`–`2234`.

## Configuración relacionada

- [`config/dhcpd.conf`](../config/dhcpd.conf): servicio DHCP de `server4-g3`.
- [`config/`](../config): configuraciones de DNS, Netplan/Cloud-Init, Apache y
  Monitorix.
- [`scripts/enrutamiento.sh`](../scripts/enrutamiento.sh): reglas de
  enrutamiento.
- [`scripts/comprobacion.sh`](../scripts/comprobacion.sh): comprobaciones de
  conectividad y servicios.
