# Proxmox Homelab Automation

Bu repo, Proxmox sunucunuzu özelleştirmek ve çeşitli hizmetleri hızlıca kurmak için hazırlanmış otomasyon araçları koleksiyonudur.

## Genel Bakış

Bu projede aşağıdaki hizmetleri kurmanıza yardımcı olacak scriptler ve Docker Compose dosyaları bulunmaktadır:

- **Güvenlik Kurulumu**: Fail2Ban ile Proxmox ve SSH güvenliği
- **Depolama Kurulumu**: Samba paylaşımı ve Sanoid ile ZFS snapshot yönetimi
- **Media Sunucusu**: Sonarr, Radarr, Jellyfin, Bazarr, Prowlarr vb.
- **Monitoring Sistemi**: Prometheus, Grafana, Alertmanager ve Node Exporter
- **Logging Sistemi**: ELK Stack (Elasticsearch, Logstash, Kibana) ve Filebeat
- **Proxy Sistemi**: Cloudflared ve AdGuard Home

## Kurulum

### Ön Koşullar

- Proxmox VE 7.0 veya üzeri
- ZFS depolama alanı (datapool)
- LXC konteynerleri için ayrılmış ID'ler (100, 101, 102, 103)

### Kurulum Adımları

1. Bu repoyu klonlayın:

```bash
git clone https://github.com/Yakrel/proxmox-homelab-automation.git
cd proxmox-homelab-automation
```

2. LXC konteynerlerini oluşturun:

Aşağıdaki LXC konteynerlerini manuel olarak oluşturmanız gerekmektedir:
- **Proxy** (ID: 100): Cloudflared ve AdGuard Home için
- **Media** (ID: 101): Sonarr, Radarr, Jellyfin vb. için
- **Monitoring** (ID: 102): Prometheus ve Grafana için  
- **Logging** (ID: 103): ELK Stack için

> **Not**: Tüm konteynerlerde Docker kurulu olmalıdır.

3. Setup scriptini çalıştırın:

```bash
chmod +x setup.sh
./setup.sh
```

4. Kurulum sırasında:
   - Güvenlik kurulumunu yapmak isteyip istemediğiniz sorulacak
   - Depolama kurulumunu yapmak isteyip istemediğiniz sorulacak
   - Mevcut LXC konteynerlerine gerekli dosyaları kopyalayacak

## Dosya Yapısı

```
proxmox-homelab-automation/
├── docker/
│   ├── media/
│   │   └── docker-compose.yml
│   ├── monitoring/
│   │   ├── docker-compose.yml
│   │   └── .env.example
│   ├── logging/
│   │   └── docker-compose.yml
│   └── proxy/
│       ├── docker-compose.yml
│       └── .env.example
├── scripts/
│   ├── install_security.sh
│   └── install_storage.sh
├── setup.sh
└── README.md
```

## LXC Konteynerleri

### Media Server (ID: 101)

Bu konteyner şunları içerir:
- Sonarr - TV şovlarını takip etmek için
- Radarr - Filmleri takip etmek için
- Bazarr - Altyazı yönetimi
- Jellyfin - Medya sunucusu
- Jellyseerr - Medya istekleri için web arayüzü
- qBittorrent - Torrent indirme
- Prowlarr - İndirme indeksleri
- Flaresolverr - Cloudflare korumalı sitelere erişim
- Recyclarr - Kalite profilleri
- Youtube-dl - YouTube video indirme
- Watchtower - Konteyner güncellemeleri

### Monitoring (ID: 102)

Bu konteyner şunları içerir:
- Prometheus - Metrik toplama
- Grafana - Metrik görselleştirme
- Alertmanager - Alarm yönetimi
- Node Exporter - Host metrikleri
- Watchtower - Konteyner güncellemeleri

### Logging (ID: 103)

Bu konteyner şunları içerir:
- Elasticsearch - Log depolama
- Logstash - Log işleme
- Kibana - Log görselleştirme 
- Filebeat - Log toplama
- Watchtower - Konteyner güncellemeleri

### Proxy (ID: 100)

Bu konteyner şunları içerir:
- Cloudflared - Cloudflare Tunnel
- AdGuard Home - DNS filtreleme
- Watchtower - Konteyner güncellemeleri

## Özelleştirme

Her hizmet için özel ayarları şu dosyalarda bulabilirsiniz:
- `/datapool/config/<service-name>` dizinleri
- Docker Compose dosyaları `/root/docker/` altında her LXC konteynerinde bulunur

## Notlar

- Bu scriptler ve dosyalar sadece Proxmox üzerinde test edilmiştir
- ZFS snapshots ve replikasyon için Sanoid kurulumu içerir
- Tüm hizmetler aynı ağda çalışır, ancak her konteyner kendi ağ alanına sahiptir

## Lisans

MIT
