# Proxmox Terraform ve Ansible ile Homelab Otomasyon

Bu repo, Proxmox üzerinde LXC container'ları oluşturmak ve yapılandırmak için Terraform ve Ansible kullanımını içerir. Özellikle Docker Compose ile çalışan servislerin otomatik kurulumunu hedeflemektedir.

## Hızlı Başlangıç

Bu projeyi kullanmak için aşağıdaki adımları izleyin:

1. **Management Container Kurulumu**:
   - `setup_homelab.sh` scriptini GitHub'dan indirin
   - Proxmox host üzerinde bu scripti çalıştırın
   - Script, Proxmox'ta management container (ID:900) oluşturacak ve gerekli araçları kuracaktır

2. **Diğer LXC'lerin Kurulumu (Management Container İçinde)**:
   - Management container'a SSH veya Console ile girin
   - Repository'yi klonlayın
   - Terraform, Ansible ile diğer container'ları oluşturun ve yapılandırın

## Sistem Mimarisi

### LXC Containerları
Her biri izole edilmiş ve özel networke sahip servis grupları:

1. **Management Container**: ID 900 (veya sizin belirlediğiniz)
   - **İşletim Sistemi**: Ubuntu 24.04 veya Debian 12 (kurulum sırasında seçilebilir)
   - Terraform, Ansible ve diğer otomasyon araçları
   - Diğer container'ların oluşturulması ve yapılandırması buradan yönetilir

2. **Proxy Stack**: ID 125, IP 192.168.1.125
   - **İşletim Sistemi**: Alpine Linux
   - **Kaynaklar**: 2GB RAM, 2 CPU çekirdek
   - Cloudflared (Cloudflare tunnel)
   - AdGuard Home (DNS Server)
   - Watchtower

3. **Media Stack**: ID 102, IP 192.168.1.102
   - **İşletim Sistemi**: Alpine Linux
   - **Kaynaklar**: 16GB RAM, 4 CPU çekirdek
   - Medya servisleri (Sonarr, Radarr, Bazarr, Jellyfin, Jellyseerr)
   - İndirme araçları (qBittorrent, Prowlarr)
   - Destek servisleri (FlareSolverr, Watchtower, Recyclarr, Youtube-dl)

4. **Monitoring Stack**: ID 103, IP 192.168.1.103
   - **İşletim Sistemi**: Alpine Linux
   - **Kaynaklar**: 4GB RAM, 2 CPU çekirdek
   - Prometheus, Grafana, Alertmanager, Node Exporter, Watchtower

5. **Logging Stack**: ID 104, IP 192.168.1.104
   - **İşletim Sistemi**: Alpine Linux
   - **Kaynaklar**: 4GB RAM, 2 CPU çekirdek
   - Elasticsearch, Logstash, Kibana, Filebeat, Watchtower

### Erişim Yönetimi

- **Management Container**: Proxmox üzerinden konsoldan root erişimi (şifresiz)
- **Diğer LXC'ler**: 
  - Proxmox üzerinden konsoldan root erişimi (şifresiz)
  - Management container üzerinden Ansible erişimi (SSH key tabanlı)
  - Dış ağdan doğrudan erişim kapalı

## Depolama Yapısı

### Oluşturulan Dizin Yapısı
```
/datapool/                       # ZFS pool mount noktası (mevcut olmalı)
├── config/                      # Tüm servis konfigürasyonları (script oluşturur)
│   ├── sonarr-config/
│   ├── radarr-config/
│   ├── prometheus-config/
│   ├── elasticsearch-config/
│   └── ...
├── media/                       # Ana medya kütüphanesi (script oluşturur)
│   ├── movies/                  # Filmler
│   ├── tv/                      # Diziler
│   └── youtube/                 # Youtube indirmeleri
└── torrents/                    # İndirme klasörü (script oluşturur)
    ├── movies/                  # Film indirmeleri
    └── tv/                      # Dizi indirmeleri
```

## Önemli Notlar

- Tüm Docker verileri `/datapool` altında depolanır, böylece container'lar silinse bile veriler kalır
- Alpine Linux container'larında Docker ve Docker Compose otomatik olarak kurulur
- Management LXC için Ubuntu veya Debian seçeneği sunulmuştur - Debian daha hafiftir
- Watchtower her stack için ayrı çalışır ve güncellemeleri otomatik yapar
- Docker Compose dosyaları her LXC'nin kök dizinine (`/root`) kopyalanır ve çalıştırılır
- CPU ve RAM değerleri 32GB RAM'li bir sunucuya göre optimize edilmiştir, gerekirse değiştirebilirsiniz
- LXC Container'lar için RAM değerleri katı sınır değil, kullanılmayan RAM diğer container'lar tarafından kullanılabilir

## Yapılandırma

- `setup_homelab.sh`: Management LXC oluşturma ve yapılandırma işlemleri için tüm adımları içerir
- `terraform/terraform.tfvars.example`: LXC Container yapılandırma örneği, kullanmadan önce `terraform.tfvars` olarak kopyalayın
- `docker/`: Her servis için Docker Compose yapılandırma dosyaları
- `ansible/`: Tüm container'ların otomatik yapılandırılması için Ansible playbook'ları
