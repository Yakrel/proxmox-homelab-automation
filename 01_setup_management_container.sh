#!/bin/bash
# Proxmox Homelab Setup - Management Container Kurulumu
# İlk adım: Management container oluşturma ve yapılandırma

set -e

# Renk kodları
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Değişkenleri tanımla
CONTAINER_ID=${CONTAINER_ID:-900}
DISK_SIZE=${DISK_SIZE:-"20"}
REPO_DIR="/opt/proxmox-automation"

echo -e "${GREEN}=== Proxmox Homelab Automation - All-in-One Setup ===${NC}"
echo -e "${YELLOW}Bu script, management container oluşturma ve yapılandırmayı tek adımda yapar${NC}"
echo

# Proxmox bilgilerini al
read -p "Proxmox API URL (varsayılan: https://192.168.1.10:8006/api2/json): " PROXMOX_API_URL_INPUT
PROXMOX_API_URL=${PROXMOX_API_URL_INPUT:-"https://192.168.1.10:8006/api2/json"}

# Container IP için varsayılan değer ekle
read -p "Management container IP (varsayılan: 192.168.1.200): " CONTAINER_IP_INPUT
CONTAINER_IP=${CONTAINER_IP_INPUT:-"192.168.1.200"}
if [[ -z "$CONTAINER_IP" ]]; then
    echo -e "${RED}Hata: IP adresi boş olamaz!${NC}"
    exit 1
fi

# Gateway için varsayılan değer ekle
read -p "Network Gateway (varsayılan: 192.168.1.1): " GATEWAY_INPUT
GATEWAY=${GATEWAY_INPUT:-"192.168.1.1"}
if [[ -z "$GATEWAY" ]]; then
    echo -e "${RED}Hata: Gateway adresi boş olamaz!${NC}"
    exit 1
fi

read -p "GitHub repository (varsayılan: Yakrel/proxmox-homelab-automation): " GITHUB_REPO_INPUT
GITHUB_REPO=${GITHUB_REPO_INPUT:-"Yakrel/proxmox-homelab-automation"}
REPO_URL="git@github.com:${GITHUB_REPO}.git"
REPO_HTTPS_URL="https://github.com/${GITHUB_REPO}.git"

# Template kontrolü ve indirme işlemlerini ayarla
echo -e "\n${YELLOW}Template kontrolü ve indirme işlemi yapılıyor...${NC}"

# pveam kullanılabilir mi kontrol et
if ! command -v pveam &> /dev/null; then
    echo -e "${RED}Hata: pveam komutu bulunamadı. Bu script Proxmox host üzerinde çalıştırılmalıdır.${NC}"
    exit 1
fi

# Kullanılabilir depoları kontrol et
echo -e "${YELLOW}Kullanılabilir template depoları kontrol ediliyor...${NC}"
pveam update

# datapool'un var olup olmadığını kontrol et
if pvesm status | grep -q "datapool"; then
    echo -e "${GREEN}Datapool storage bulundu.${NC}"
    STORAGE="datapool"
else
    echo -e "${YELLOW}Datapool storage bulunamadı, varsayılan local kullanılacak.${NC}"
    STORAGE="local"
fi

# Debian template kontrolü ve indirme
echo -e "\n${YELLOW}Debian template kontrol ediliyor...${NC}"
DEBIAN_TEMPLATE=$(pveam available -section system | grep -E 'debian.*12.*standard' | sort -V | tail -n 1 | awk '{print $2}')

if [ -z "$DEBIAN_TEMPLATE" ]; then
    echo -e "${RED}Kullanılabilir Debian template'i bulunamadı!${NC}"
else
    DEBIAN_TEMPLATE_FILENAME=$(basename "$DEBIAN_TEMPLATE")
    
    # Template indirme
    if pveam list $STORAGE | grep -q "$DEBIAN_TEMPLATE_FILENAME"; then
        echo -e "${GREEN}Debian template ($DEBIAN_TEMPLATE_FILENAME) zaten indirilmiş.${NC}"
    else
        echo -e "${YELLOW}Debian template indiriliyor: $DEBIAN_TEMPLATE${NC}"
        pveam download $STORAGE $DEBIAN_TEMPLATE
    fi
    
    # Template yolunu belirle
    MANAGEMENT_TEMPLATE_PATH="${STORAGE}:vztmpl/${DEBIAN_TEMPLATE_FILENAME}"
    echo -e "${GREEN}Management template yolu: $MANAGEMENT_TEMPLATE_PATH${NC}"
fi

# Alpine template kontrolü ve indirme
echo -e "\n${YELLOW}Alpine template kontrol ediliyor...${NC}"
ALPINE_TEMPLATE=$(pveam available -section system | grep -E 'alpine.*3\..*default' | sort -V | tail -n 1 | awk '{print $2}')

if [ -z "$ALPINE_TEMPLATE" ]; then
    echo -e "${RED}Kullanılabilir Alpine template'i bulunamadı!${NC}"
else
    ALPINE_TEMPLATE_FILENAME=$(basename "$ALPINE_TEMPLATE")
    
    # Template indirme
    if pveam list $STORAGE | grep -q "$ALPINE_TEMPLATE_FILENAME"; then
        echo -e "${GREEN}Alpine template ($ALPINE_TEMPLATE_FILENAME) zaten indirilmiş.${NC}"
    else
        echo -e "${YELLOW}Alpine template indiriliyor: $ALPINE_TEMPLATE${NC}"
        pveam download $STORAGE $ALPINE_TEMPLATE
    fi
    
    # Template yolunu belirle
    ALPINE_TEMPLATE_PATH="${STORAGE}:vztmpl/${ALPINE_TEMPLATE_FILENAME}"
    echo -e "${GREEN}Alpine template yolu: $ALPINE_TEMPLATE_PATH${NC}"
fi

# Mevcut template'leri listele
echo -e "\n${YELLOW}Kullanılabilir template'ler kontrol ediliyor...${NC}"
TEMPLATES=$(pveam list $STORAGE 2>/dev/null | grep -E 'alpine|debian' | awk '{print $1}' || echo "")

if [ -z "$TEMPLATES" ]; then
    # Lokal depoları kontrol et
    echo -e "${YELLOW}Lokal template'ler kontrol ediliyor...${NC}"
    
    # Olası template konumları
    TEMPLATE_LOCATIONS=(
        "${STORAGE}:vztmpl"
        "local:vztmpl"
        "${STORAGE}:template/cache"
    )
    
    for LOCATION in "${TEMPLATE_LOCATIONS[@]}"; do
        echo -e "${YELLOW}$LOCATION konumu kontrol ediliyor...${NC}"
        LOCATION_TEMPLATES=$(pct template list 2>/dev/null | grep "$LOCATION" | grep -E 'debian|alpine' || echo "")
        if [ ! -z "$LOCATION_TEMPLATES" ]; then
            TEMPLATES="$LOCATION_TEMPLATES"
            echo -e "${GREEN}Template'ler bulundu!${NC}"
            echo "$TEMPLATES"
            break
        fi
    done
    
    if [ -z "$TEMPLATES" ]; then
        echo -e "${RED}Hiçbir template bulunamadı!${NC}"
        echo -e "${YELLOW}Lütfen mevcut template yolunu ve adını girin (örn: datapool:vztmpl/debian-12-standard_12.1-1_amd64.tar.zst):${NC}"
        read -p "Template tam yolu: " TEMPLATE_PATH
        if [ -z "$TEMPLATE_PATH" ]; then
            echo -e "${RED}Template yolu boş olamaz. Script sonlandırılıyor.${NC}"
            exit 1
        fi
    else
        echo -e "${GREEN}Kullanılabilir template'ler:${NC}"
        echo "$TEMPLATES"
        echo
        echo -e "${YELLOW}Management container için Debian template kullanılacak.${NC}"
        if [ ! -z "$MANAGEMENT_TEMPLATE_PATH" ]; then
            echo -e "${GREEN}Management template otomatik seçildi: $MANAGEMENT_TEMPLATE_PATH${NC}"
            TEMPLATE_PATH="$MANAGEMENT_TEMPLATE_PATH"
        else
            read -p "Kullanmak istediğiniz template'in tam yolunu girin: " TEMPLATE_PATH
            if [ -z "$TEMPLATE_PATH" ]; then
                echo -e "${RED}Template yolu boş olamaz. Script sonlandırılıyor.${NC}"
                exit 1
            fi
        fi
    fi
else
    echo -e "${GREEN}Kullanılabilir template'ler:${NC}"
    echo "$TEMPLATES"
    echo
    echo -e "${YELLOW}Management container için Debian template kullanılacak.${NC}"
    if [ ! -z "$MANAGEMENT_TEMPLATE_PATH" ]; then
        echo -e "${GREEN}Management template otomatik seçildi: $MANAGEMENT_TEMPLATE_PATH${NC}"
        TEMPLATE_PATH="$MANAGEMENT_TEMPLATE_PATH"
    else
        read -p "Kullanmak istediğiniz template'in tam yolunu girin: " TEMPLATE_PATH
        if [ -z "$TEMPLATE_PATH" ]; then
            echo -e "${RED}Template yolu boş olamaz. Script sonlandırılıyor.${NC}"
            exit 1
        fi
    fi
fi

# Alpine template'ini terraform.tfvars için kaydet
if [ ! -z "$ALPINE_TEMPLATE_PATH" ]; then
    # Alpine template yolunu değişkene kaydet
    ALPINE_TEMPLATE_FOR_TFVARS="$ALPINE_TEMPLATE_PATH"
else
    # Eğer otomatik indirilmediyse, kullanıcıdan Alpine template yolunu iste
    echo -e "\n${YELLOW}LXC containerlar için Alpine template yolunu girin:${NC}"
    read -p "Alpine template yolu (örn: datapool:vztmpl/alpine-3.21-default_20241217_amd64.tar.xz): " ALPINE_TEMPLATE_FOR_TFVARS
    
    if [ -z "$ALPINE_TEMPLATE_FOR_TFVARS" ]; then
        echo -e "${YELLOW}Alpine template yolu girilmedi, varsayılan değer kullanılacak.${NC}"
        ALPINE_TEMPLATE_FOR_TFVARS="${STORAGE}:template/cache/alpine-3.21-default_20241217_amd64.tar.xz"
    fi
fi

# Management container oluştur
echo -e "\n${GREEN}Management container oluşturuluyor (ID: $CONTAINER_ID)...${NC}"

# Debug bilgileri göster
echo -e "${YELLOW}DEBUG: Template yolu: $TEMPLATE_PATH${NC}"
echo -e "${YELLOW}DEBUG: IP: $CONTAINER_IP${NC}"
echo -e "${YELLOW}DEBUG: Gateway: $GATEWAY${NC}"
echo -e "${YELLOW}DEBUG: Disk boyutu: ${DISK_SIZE}G${NC}"

# Container oluşturma komutu
pct create $CONTAINER_ID "$TEMPLATE_PATH" \
    --hostname management \
    --memory 2048 \
    --swap 512 \
    --cores 2 \
    --rootfs "${STORAGE}:${DISK_SIZE}" \
    --net0 name=eth0,bridge=vmbr0,ip=$CONTAINER_IP/24,gw=$GATEWAY \
    --password debian \
    --unprivileged 1 \
    --features nesting=1,keyctl=1,fuse=1 \
    --start 1

echo -e "\n${YELLOW}Container'ın başlaması bekleniyor...${NC}"
sleep 15

# Container çalışıyor mu kontrol et
echo -e "${YELLOW}Container'ın durumu kontrol ediliyor...${NC}"
CONTAINER_STATUS=$(pct status $CONTAINER_ID 2>/dev/null || echo "unknown")
if [[ "$CONTAINER_STATUS" != *"running"* ]]; then
    echo -e "${RED}Uyarı: Container çalışmıyor görünüyor. Durum: $CONTAINER_STATUS${NC}"
    echo -e "${YELLOW}Container'ın başlaması için biraz daha bekleniyor...${NC}"
    sleep 15
    CONTAINER_STATUS=$(pct status $CONTAINER_ID 2>/dev/null || echo "unknown")
    if [[ "$CONTAINER_STATUS" != *"running"* ]]; then
        echo -e "${RED}Hata: Container çalışmıyor. Lütfen manuel olarak kontrol edin.${NC}"
        echo -e "${YELLOW}pct start $CONTAINER_ID${NC} komutunu çalıştırabilirsiniz."
        exit 1
    fi
fi

# Gerekli yazılımları kur
echo -e "\n${GREEN}Gerekli yazılımları kuruyorum...${NC}"
pct exec $CONTAINER_ID -- bash -c "apt update && DEBIAN_FRONTEND=noninteractive apt install -y git python3 python3-pip curl jq unzip software-properties-common wget gpg locales" || {
    echo -e "${RED}Hata: Gerekli yazılımlar kurulamadı. Container'a erişim kontrol ediliyor.${NC}"
    exit 1
}

# Locale ayarları
echo -e "\n${GREEN}Locale yapılandırması yapılıyor...${NC}"
pct exec $CONTAINER_ID -- bash -c "
    sed -i 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen && \
    locale-gen en_US.UTF-8 && \
    update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 && \
    echo 'export LC_ALL=en_US.UTF-8' >> /root/.bashrc && \
    echo 'export LANG=en_US.UTF-8' >> /root/.bashrc
"

# Terraform kurulumu - HashiCorp resmi yöntemi
echo -e "\n${GREEN}Terraform kuruluyor...${NC}"
pct exec $CONTAINER_ID -- bash -c "
    # HashiCorp GPG anahtarını ekle
    wget -O- https://apt.releases.hashicorp.com/gpg | \
    gpg --dearmor | \
    tee /usr/share/keyrings/hashicorp-archive-keyring.gpg > /dev/null && \
    
    # Repository ekle
    echo \"deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
    https://apt.releases.hashicorp.com \$(lsb_release -cs) main\" | \
    tee /etc/apt/sources.list.d/hashicorp.list && \
    
    # Güncelle ve kur
    apt update && \
    apt install -y terraform
"

# Ansible kurulumu - Debian için resmi yöntem 
echo -e "\n${GREEN}Ansible kuruluyor...${NC}"
pct exec $CONTAINER_ID -- bash -c "
    # Ubuntu PPA için uygun kod adını belirle (Debian 12 için jammy)
    UBUNTU_CODENAME=jammy && \
    
    # Ansible GPG anahtarını indir
    wget -O- \"https://keyserver.ubuntu.com/pks/lookup?fingerprint=on&op=get&search=0x6125E2A8C77F2818FB7BD15B93C4A3FD7BB9C367\" | \
    gpg --dearmor -o /usr/share/keyrings/ansible-archive-keyring.gpg && \
    
    # Repository ekle
    echo \"deb [signed-by=/usr/share/keyrings/ansible-archive-keyring.gpg] \
    http://ppa.launchpad.net/ansible/ansible/ubuntu \$UBUNTU_CODENAME main\" | \
    tee /etc/apt/sources.list.d/ansible.list && \
    
    # Güncelle ve kur
    apt update && \
    apt install -y ansible && \
    
    # Ansible koleksiyonlarını yükle
    ansible-galaxy collection install community.docker && \
    ansible-galaxy collection install community.general
"

# SSH anahtarı oluşturma
echo -e "\n${GREEN}SSH anahtarı oluşturuluyor...${NC}"
pct exec $CONTAINER_ID -- bash -c "ssh-keygen -t rsa -b 4096 -f /root/.ssh/id_rsa -N ''"

# SSH anahtarını göster ve GitHub'a eklenmesi için beklet
echo -e "\n${BLUE}===============================================================${NC}"
echo -e "${YELLOW}ÖNEMLİ: Aşağıdaki SSH public key'i GitHub hesabınıza eklemeniz gerekiyor${NC}"
echo -e "${BLUE}===============================================================${NC}"
echo
pct exec $CONTAINER_ID -- cat /root/.ssh/id_rsa.pub
echo
echo -e "${BLUE}===============================================================${NC}"
echo -e "${YELLOW}Lütfen yukarıdaki SSH anahtarını GitHub hesabınıza ekleyin:${NC}"
echo -e "1. ${GREEN}https://github.com/settings/keys${NC} adresine gidin"
echo -e "2. 'New SSH key' butonuna tıklayın"
echo -e "3. Yukarıdaki anahtarı kopyalayıp yapıştırın ve bir başlık girin"
echo -e "4. 'Add SSH key' butonuna tıklayın"
echo
read -p "SSH anahtarını GitHub'a ekledikten sonra ENTER tuşuna basın..." reply

# GitHub SSH bağlantısını test et
echo -e "\n${YELLOW}GitHub SSH bağlantısı test ediliyor...${NC}"
pct exec $CONTAINER_ID -- bash -c "ssh -o StrictHostKeyChecking=no -T git@github.com || true"
echo -e "${GREEN}Not: Yukarıdaki mesaj 'Permission denied' içeriyorsa sorun yok, bu beklenen bir durumdur.${NC}"

# Repo'yu klonla - önce SSH ile dene, başarısız olursa HTTPS kullan
echo -e "\n${GREEN}Repo klonlanıyor (${REPO_URL})...${NC}"
pct exec $CONTAINER_ID -- bash -c "mkdir -p $(dirname $REPO_DIR) && \
(GIT_SSH_COMMAND='ssh -o StrictHostKeyChecking=no' git clone $REPO_URL $REPO_DIR 2>/dev/null || \
 (echo 'SSH ile klonlama başarısız oldu, HTTPS ile deneniyor...' && \
  git clone $REPO_HTTPS_URL $REPO_DIR))"

# Repo başarıyla klonlandı mı kontrol et
pct exec $CONTAINER_ID -- bash -c "if [ -d \"$REPO_DIR/.git\" ]; then \
    echo -e \"${GREEN}✅ Repository başarıyla klonlandı: $REPO_DIR${NC}\"; \
else \
    echo -e \"${RED}❌ Repository klonlanamadı. Lütfen GitHub bağlantınızı kontrol edin.${NC}\"; \
    exit 1; \
fi"

# Proxmox şifresi
echo -e "\n${GREEN}Yapılandırma bilgilerini alıyorum...${NC}"
read -sp "Proxmox root şifrenizi girin: " PROXMOX_PASSWORD
echo

# Cloudflare Tunnel token
read -sp "Cloudflare Tunnel token (yoksa boş bırakın): " CLOUDFLARE_TOKEN
echo

# Grafana şifresi
read -sp "Grafana admin şifrenizi girin (boş bırakırsanız 'homelab' olacak): " GRAFANA_PASSWORD_INPUT
GRAFANA_PASSWORD=${GRAFANA_PASSWORD_INPUT:-"homelab"}
echo

# terraform.tfvars dosyasını oluştur
echo -e "\n${YELLOW}Terraform yapılandırma dosyası oluşturuluyor...${NC}"
pct exec $CONTAINER_ID -- bash -c "if [ -f \"$REPO_DIR/terraform/terraform.tfvars.example\" ]; then \
    cp \"$REPO_DIR/terraform/terraform.tfvars.example\" \"$REPO_DIR/terraform/terraform.tfvars\" && \
    sed -i \"s|proxmox_api_url = \\\".*\\\"|proxmox_api_url = \\\"$PROXMOX_API_URL\\\"|g\" \"$REPO_DIR/terraform/terraform.tfvars\" && \
    sed -i \"s|proxmox_password = \\\".*\\\"|proxmox_password = \\\"$PROXMOX_PASSWORD\\\"|g\" \"$REPO_DIR/terraform/terraform.tfvars\" && \
    sed -i \"s|gateway = \\\".*\\\"|gateway = \\\"$GATEWAY\\\"|g\" \"$REPO_DIR/terraform/terraform.tfvars\" && \
    sed -i \"s|alpine_template = \\\".*\\\"|alpine_template = \\\"$ALPINE_TEMPLATE_FOR_TFVARS\\\"|g\" \"$REPO_DIR/terraform/terraform.tfvars\" && \
    sed -i \"s|grafana_password = \\\".*\\\"|grafana_password = \\\"$GRAFANA_PASSWORD\\\"|g\" \"$REPO_DIR/terraform/terraform.tfvars\" && \
    echo '✅ terraform.tfvars dosyası oluşturuldu'; \
else \
    echo '❌ terraform.tfvars.example dosyası bulunamadı!'; \
    exit 1; \
fi"

# docker/monitoring/.env dosyasını oluştur
echo -e "\n${YELLOW}Grafana yapılandırma dosyası oluşturuluyor...${NC}"
pct exec $CONTAINER_ID -- bash -c "if [ -f \"$REPO_DIR/docker/monitoring/.env.example\" ]; then \
    cp \"$REPO_DIR/docker/monitoring/.env.example\" \"$REPO_DIR/docker/monitoring/.env\" && \
    sed -i \"s|GRAFANA_PASSWORD=.*|GRAFANA_PASSWORD=$GRAFANA_PASSWORD|g\" \"$REPO_DIR/docker/monitoring/.env\" && \
    echo '✅ docker/monitoring/.env dosyası oluşturuldu'; \
else \
    echo '⚠️ docker/monitoring/.env.example dosyası bulunamadı, atlanıyor.'; \
fi"

# 02_terraform_to_ansible.sh dosyasını çalıştırılabilir yap
pct exec $CONTAINER_ID -- bash -c "if [ -f \"$REPO_DIR/02_terraform_to_ansible.sh\" ]; then \
    chmod +x \"$REPO_DIR/02_terraform_to_ansible.sh\"; \
fi"

# Klasör yapısı oluşturma (opsiyonel)
echo -e "\n${YELLOW}LXC containerlar için klasör yapısı oluşturmak ister misiniz?${NC}"
echo -e "Bu işlem sadece /datapool/config, /datapool/media ve /datapool/torrents dizinlerini oluşturacak"
read -p "Klasör yapısı oluşturulsun mu? (e/h): " CREATE_DIRECTORIES

if [[ "$CREATE_DIRECTORIES" =~ ^[Ee]$ ]]; then
    echo -e "\n${YELLOW}Klasör yapısı oluşturuluyor...${NC}"
    
    # Config dizinleri - Container içinde değil host üzerinde çalıştırıyoruz
    mkdir -p /datapool/config/{sonarr-config,radarr-config,bazarr-config,jellyfin-config,jellyseerr-config,qbittorrent-config,prowlarr-config,flaresolverr-config,watchtower-media-config,recyclarr-config,youtube-dl-config,prometheus-config,grafana-config,alertmanager-config,watchtower-monitoring-config,elasticsearch-config,logstash-config,kibana-config,filebeat-config,watchtower-logging-config,cloudflared-config,watchtower-proxy-config,adguard-config/{work,conf}}
    
    # Medya ve torrent dizinleri
    mkdir -p /datapool/media/{tv,movies,youtube/{playlists,channels}}
    mkdir -p /datapool/torrents/{tv,movies}
    
    # İzinleri ayarla
    chown -R 100000:100000 /datapool/config
    chown -R 100000:100000 /datapool/media
    chown -R 100000:100000 /datapool/torrents
    
    echo -e "${GREEN}✅ Klasör yapısı başarıyla oluşturuldu!${NC}"
else
    echo -e "${YELLOW}Klasör yapısı oluşturulmadı. Lütfen gerekli dizinleri manuel olarak oluşturun.${NC}"
fi

# Yapılandırma bilgilerini göster
echo -e "\n${GREEN}=== Yapılandırma Özeti ===${NC}"
echo -e "${YELLOW}Proxmox API URL:${NC} $PROXMOX_API_URL"
echo -e "${YELLOW}Gateway IP:${NC} $GATEWAY"
echo -e "${YELLOW}Management IP:${NC} $CONTAINER_IP"
echo -e "${YELLOW}Management Template:${NC} $TEMPLATE_PATH"
echo -e "${YELLOW}Alpine Template:${NC} $ALPINE_TEMPLATE_FOR_TFVARS"
echo -e "${YELLOW}Grafana Şifresi:${NC} $GRAFANA_PASSWORD"
if [ -n "$CLOUDFLARE_TOKEN" ]; then
    echo -e "${YELLOW}Cloudflare Token:${NC} ${CLOUDFLARE_TOKEN:0:5}*****"
else
    echo -e "${YELLOW}Cloudflare Token:${NC} Not provided"
fi

echo -e "\n${GREEN}✅ Kurulum ve yapılandırma tamamlandı!${NC}"
echo -e "${YELLOW}Homelab kurulumuna devam etmek için şu adımları izleyin:${NC}"
echo -e "1. Management container'a giriş yapın: ${GREEN}pct enter $CONTAINER_ID${NC}"
echo -e "2. Terraform ile LXC container'ları oluşturun: ${GREEN}cd $REPO_DIR/terraform && terraform init && terraform apply${NC}"
echo -e "3. Ansible inventory oluşturun: ${GREEN}cd $REPO_DIR && ./02_terraform_to_ansible.sh${NC}"
echo -e "4. Ansible ile yapılandırın: ${GREEN}cd $REPO_DIR/ansible && ansible-playbook -i inventory/all playbook.yml${NC}"

# Otomatik devam etmek istiyor mu?
echo
read -p "Terraform ve Ansible adımlarını otomatik olarak çalıştırmak ister misiniz? (e/h): " AUTO_CONTINUE

if [[ "$AUTO_CONTINUE" =~ ^[Ee]$ ]]; then
    echo -e "\n${GREEN}Terraform ile LXC container'ları oluşturuluyor...${NC}"
    pct exec $CONTAINER_ID -- bash -c "cd $REPO_DIR/terraform && terraform init && terraform apply -auto-approve"
    
    echo -e "\n${GREEN}Ansible inventory oluşturuluyor...${NC}"
    pct exec $CONTAINER_ID -- bash -c "cd $REPO_DIR && ./02_terraform_to_ansible.sh"
    
    echo -e "\n${GREEN}Ansible ile yapılandırılıyor...${NC}"
    pct exec $CONTAINER_ID -- bash -c "cd $REPO_DIR/ansible && ansible-playbook -i inventory/all playbook.yml"
    
    echo -e "\n${GREEN}✅ Tüm işlemler tamamlandı! Homelab'iniz hazır.${NC}"
else
    echo -e "\n${YELLOW}İşlem durduruldu. Manuel olarak devam edebilirsiniz.${NC}"
fi