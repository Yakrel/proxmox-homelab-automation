# Monitoring Stack - Manuel Kurulum Kılavuzu

Bu monitoring stack artık otomatik kurulum yerine manuel konfigürasyon kullanmaktadır. Aşağıdaki adımları takip ederek tam fonksiyonel bir monitoring sistemi kurabilirsiniz.

## Hızlı Başlangıç

### 1. Temel Kurulum
```bash
# Monitoring LXC konteynerine girin
pct enter 104

# Monitoring stack dizinine gidin
cd /opt/monitoring-stack

# Environment dosyasını oluşturun
cp .env.example .env
nano .env

# Sadece GRAFANA_ADMIN_PASSWORD değerini düzenleyin
# Örnek: GRAFANA_ADMIN_PASSWORD=mysecurepassword123

# Servisleri başlatın
docker compose up -d
```

### 2. Temel Erişim
- **Grafana**: http://192.168.1.104:3000 (admin/şifreniz)
- **Prometheus**: http://192.168.1.104:9090
- **Alertmanager**: http://192.168.1.104:9093

Bu adımlar sonunda Grafana dashboard'una erişebilir ve temel monitoring yapabilirsiniz. Grafana otomatik olarak Prometheus'u data source olarak ekleyecek ve kullanıma hazır olacaktır.

## İleri Düzey Konfigürasyon (İsteğe Bağlı)

### A. Proxmox Monitoring (PVE Exporter)

Proxmox sunucunuzu izlemek için:

1. **Proxmox'da monitoring kullanıcısı oluşturun:**
```bash
# Proxmox host'unda çalıştırın
pveum user add monitoring@pve --password "secure_password_here" --comment "Monitoring user for Prometheus"
pveum acl modify / --users monitoring@pve --roles PVEAuditor
```

2. **Environment dosyasını güncelleyin:**
```bash
nano /opt/monitoring-stack/.env
```

Bu satırları uncomment edin ve düzenleyin:
```
PVE_USER=monitoring@pve
PVE_PASSWORD=secure_password_here
PVE_URL=https://192.168.1.10:8006
PVE_VERIFY_SSL=false
```

3. **Servisleri yeniden başlatın:**
```bash
docker compose restart prometheus-pve-exporter
```

### B. Email Uyarıları (Alertmanager)

Gmail ile email uyarıları için:

1. **Gmail App Password oluşturun:**
   - Gmail hesabınızda 2-factor authentication'ı aktifleştirin
   - https://myaccount.google.com/apppasswords adresinden App Password oluşturun

2. **Alertmanager konfigürasyonunu düzenleyin:**
```bash
nano /datapool/config/monitoring/alertmanager/alertmanager.yml
```

Bu değerleri kendi bilgilerinizle değiştirin:
```yaml
global:
  smtp_from: 'your-email@gmail.com'
  smtp_auth_username: 'your-email@gmail.com'
  smtp_auth_password: 'your-gmail-app-password'
```

Ayrıca tüm `your-email@gmail.com` referanslarını kendi email adresinizle değiştirin.

3. **Alertmanager'ı yeniden başlatın:**
```bash
docker compose restart alertmanager
```

### C. Diğer LXC Konteynerlerdan Metrik Toplama

Diğer LXC konteynerlerden (proxy, media, files, webtools) metrik toplamak için her birinde node-exporter kurmanız gerekir:

1. **Her LXC konteynerine girin ve node-exporter kurun:**
```bash
# Örnek: Media LXC (101) için
pct enter 101

# Node exporter'ı indirin ve kurun
wget https://github.com/prometheus/node_exporter/releases/download/v1.7.0/node_exporter-1.7.0.linux-amd64.tar.gz
tar xvfz node_exporter-1.7.0.linux-amd64.tar.gz
sudo cp node_exporter-1.7.0.linux-amd64/node_exporter /usr/local/bin/
rm -rf node_exporter-1.7.0.linux-amd64*

# Systemd servisini oluşturun
cat > /etc/systemd/system/node_exporter.service << EOF
[Unit]
Description=Node Exporter
After=network.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/usr/local/bin/node_exporter

[Install]
WantedBy=multi-user.target
EOF

# Kullanıcı oluşturun ve servisi başlatın
sudo useradd --no-create-home --shell /bin/false node_exporter
sudo systemctl daemon-reload
sudo systemctl enable node_exporter
sudo systemctl start node_exporter
```

2. **Port 9100'ün açık olduğunu kontrol edin:**
```bash
curl localhost:9100/metrics
```

## Prometheus Konfigürasyonu

Prometheus konfigürasyonu `/datapool/config/monitoring/prometheus/prometheus.yml` dosyasında bulunur ve şu LXC konteynerlerini izleyecek şekilde ayarlanmıştır:

- **Monitoring LXC (104)**: Dahili node-exporter
- **Proxy LXC (100)**: 192.168.1.100:9100
- **Media LXC (101)**: 192.168.1.101:9100  
- **Files LXC (102)**: 192.168.1.102:9100
- **Webtools LXC (103)**: 192.168.1.103:9100
- **Content LXC (105)**: 192.168.1.105:9100

Farklı IP adresleri kullanıyorsanız bu dosyayı düzenleyin.

## Grafana Dashboard'ları

Grafana'ya giriş yaptıktan sonra:

1. **Data Source ekleyin:**
   - Configuration > Data Sources > Add data source
   - Prometheus seçin
   - URL: `http://prometheus:9090`

2. **Dashboard'ları import edin:**
   - Dashboards > Import
   - Bu popüler dashboard ID'lerini kullanabilirsiniz:
     - Node Exporter Full: 1860
     - Docker Container Monitoring: 193
     - Proxmox VE: 10347

**Not**: Grafana otomatik olarak Prometheus data source'u ile gelecek, manual eklemenize gerek yok.

## Sorun Giderme

### Prometheus Hedefleri Kontrol Etme
```bash
# Prometheus targets sayfasını kontrol edin
curl http://192.168.1.104:9090/api/v1/targets
```

### Container Loglarını İnceleme
```bash
docker compose logs prometheus
docker compose logs grafana
docker compose logs alertmanager
```

### Node Exporter Bağlantı Testi
```bash
# Her LXC için test edin
curl http://192.168.1.101:9100/metrics  # Media
curl http://192.168.1.102:9100/metrics  # Files
curl http://192.168.1.103:9100/metrics  # Webtools
```

## Servis Yönetimi

```bash
# Tüm servisleri görüntüle
docker compose ps

# Servis durumunu kontrol et
docker compose logs <service_name>

# Servis yeniden başlat
docker compose restart <service_name>

# Tüm servisleri yeniden başlat
docker compose restart

# Servisleri durdur
docker compose down

# Servisleri güncelle ve başlat
docker compose pull && docker compose up -d
```

Bu kurulum sonunda eksiksiz bir monitoring sisteminiz olacak ve homelab ortamınızın tüm metriklerini izleyebileceksiniz.