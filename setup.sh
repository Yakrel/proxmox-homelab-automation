#!/bin/bash

# GitHub repo adresi
REPO_URL="https://raw.githubusercontent.com/Yakrel/proxmox-homelab-automation/main"

# Başlık
echo "======================================================"
echo "Proxmox Homelab Automation - Kurulum Aracı"
echo "======================================================"

# Root kontrolü
if [ "$(id -u)" -ne 0 ]; then
   echo "Bu script root olarak çalıştırılmalıdır" 
   exit 1
fi

# Geçici çalışma dizini
TEMP_DIR="/tmp/proxmox-homelab"
mkdir -p $TEMP_DIR

# Gerekli scriptleri indir
wget -q $REPO_URL/scripts/install_security.sh -O $TEMP_DIR/install_security.sh
wget -q $REPO_URL/scripts/install_storage.sh -O $TEMP_DIR/install_storage.sh
chmod +x $TEMP_DIR/install_security.sh $TEMP_DIR/install_storage.sh

# Docker Compose dosyalarını indir
mkdir -p $TEMP_DIR/docker/{media,logging,proxy,monitoring}
wget -q $REPO_URL/docker/media/docker-compose.yml -O $TEMP_DIR/docker/media/docker-compose.yml
wget -q $REPO_URL/docker/logging/docker-compose.yml -O $TEMP_DIR/docker/logging/docker-compose.yml
wget -q $REPO_URL/docker/proxy/docker-compose.yml -O $TEMP_DIR/docker/proxy/docker-compose.yml
wget -q $REPO_URL/docker/monitoring/docker-compose.yml -O $TEMP_DIR/docker/monitoring/docker-compose.yml
wget -q $REPO_URL/docker/proxy/.env.example -O $TEMP_DIR/docker/proxy/.env.example
wget -q $REPO_URL/docker/monitoring/.env.example -O $TEMP_DIR/docker/monitoring/.env.example

# Güvenlik kurulumu
read -p "Güvenlik kurulumunu yapmak istiyor musunuz? (e/h): " security_choice
if [[ $security_choice == "e" || $security_choice == "E" ]]; then
    $TEMP_DIR/install_security.sh
fi

# Depolama kurulumu
read -p "Depolama kurulumunu yapmak istiyor musunuz? (e/h): " storage_choice
if [[ $storage_choice == "e" || $storage_choice == "E" ]]; then
    $TEMP_DIR/install_storage.sh
fi

# LXC işlemleri
echo "LXC konteynerlerine kurulum yapılıyor..."

# LXC ID'leri
LXC_IDS=("100" "101" "102" "103")
LXC_NAMES=("proxy" "media" "monitoring" "logging")

# LXC'leri kontrol et ve işlemleri yap
for i in "${!LXC_IDS[@]}"; do
    LXC_ID=${LXC_IDS[$i]}
    LXC_NAME=${LXC_NAMES[$i]}
    
    if pct status $LXC_ID &>/dev/null; then
        # LXC'nin çalışır durumda olup olmadığını kontrol et
        if ! pct status $LXC_ID | grep -q "status.*running"; then
            echo "UYARI: LXC $LXC_ID ($LXC_NAME) çalışmıyor. Başlatılıyor..."
            pct start $LXC_ID
            sleep 5 # LXC'nin başlaması için bekle
        fi
        
        echo "LXC $LXC_ID ($LXC_NAME) için dosyalar kuruluyor..."
        
        if [ -f "$TEMP_DIR/docker/$LXC_NAME/docker-compose.yml" ]; then
            # mkdir komutlarını çalıştır
            grep -A 10 "STEP 1: PROXMOX HOST COMMANDS" $TEMP_DIR/docker/$LXC_NAME/docker-compose.yml | grep "mkdir -p" | sed 's/^#\s*//' | sh
            
            # chown komutlarını çalıştır
            grep -A 15 "STEP 1: PROXMOX HOST COMMANDS" $TEMP_DIR/docker/$LXC_NAME/docker-compose.yml | grep "chown" | sed 's/^#\s*//' | sh
            
            # mount komutlarını çalıştır
            grep -A 20 "STEP 1: PROXMOX HOST COMMANDS" $TEMP_DIR/docker/$LXC_NAME/docker-compose.yml | grep "pct set" | sed "s/pct set [0-9]\\{1,3\\}/pct set $LXC_ID/" | sed 's/^#\s*//' | sh
            
            # LXC içerisinde docker klasörünü oluştur ve dosyaları kopyala
            pct exec $LXC_ID -- mkdir -p /root/docker
            pct push $LXC_ID $TEMP_DIR/docker/$LXC_NAME/docker-compose.yml /root/docker/docker-compose.yml
            
            # .env.example dosyasını .env olarak kopyala
            if [ -f "$TEMP_DIR/docker/$LXC_NAME/.env.example" ]; then
                pct push $LXC_ID $TEMP_DIR/docker/$LXC_NAME/.env.example /root/docker/.env
            fi
        fi
    else
        echo "LXC $LXC_ID ($LXC_NAME) bulunamadı, atlanıyor."
    fi
done

# Temizlik
rm -rf $TEMP_DIR

echo "======================================================"
echo "Kurulum tamamlandı!"
echo "======================================================"
exit 0
