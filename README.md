# Proxmox Homelab Automation

Bu repo, Proxmox sunucunuzu özelleştirmek ve çeşitli hizmetleri hızlıca kurmak için hazırlanmış otomasyon araçları koleksiyonudur.

## Hızlı Kurulum

**Tek komutla kurulum:**

```bash
bash -c "$(wget -qO - https://raw.githubusercontent.com/Yakrel/proxmox-homelab-automation/main/setup.sh)"
```

## Genel Bakış

Bu projeyle aşağıdaki hizmetleri kurabilirsiniz:

- **Güvenlik Kurulumu**: Fail2Ban ile Proxmox ve SSH güvenliği
- **Depolama Kurulumu**: Samba paylaşımı ve Sanoid ile ZFS snapshot yönetimi
- **Media Sunucusu**: Sonarr, Radarr, Jellyfin ve daha fazlası
- **Monitoring Sistemi**: Prometheus, Grafana, Alertmanager
- **Logging Sistemi**: ELK Stack (Elasticsearch, Logstash, Kibana)
- **Proxy Sistemi**: Cloudflared ve AdGuard Home

## Kurulum Gereksinimleri

- Proxmox VE 7.0 veya üzeri
- ZFS depolama alanı (datapool)
- Aşağıdaki LXC konteynerleri:
  - **Proxy** (ID: 100): Cloudflared ve AdGuard Home için
  - **Media** (ID: 101): Sonarr, Radarr, Jellyfin vb. için
  - **Monitoring** (ID: 102): Prometheus ve Grafana için  
  - **Logging** (ID: 103): ELK Stack için

> **Not**: Tüm konteynerlerde Docker kurulu olmalıdır.

## LXC Konteynerleri İçerikleri

### Proxy (ID: 100)
- Cloudflared - Cloudflare Tunnel
- AdGuard Home - DNS filtreleme

### Media Server (ID: 101)
- Sonarr, Radarr - TV şovları ve film takibi
- Bazarr - Altyazı yönetimi
- Jellyfin - Medya sunucusu
- Jellyseerr - Medya istekleri
- qBittorrent, Prowlarr, Flaresolverr, Recyclarr
- Youtube-dl - YouTube video indirme

### Monitoring (ID: 102)
- Prometheus - Metrik toplama
- Grafana - Metrik görselleştirme
- Alertmanager - Alarm yönetimi
- Node Exporter - Host metrikleri

### Logging (ID: 103)
- Elasticsearch - Log depolama
- Logstash - Log işleme
- Kibana - Log görselleştirme 
- Filebeat - Log toplama


## Lisans

MIT
