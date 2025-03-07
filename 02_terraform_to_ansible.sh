#!/bin/bash
# Bu script, Terraform çıktılarını Ansible inventory'sine dönüştürür
# Hata kontrolü ve daha güvenilir çalışma için geliştirilmiş versiyon

set -e

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

PROJE_DIZINI=$(pwd)

echo -e "${GREEN}🔄 Ansible Inventory Oluşturuluyor...${NC}"

# Terraform dizinine geç
cd "${PROJE_DIZINI}/terraform"

# Terraform state kontrolü
if [ ! -f terraform.tfstate ]; then
    echo -e "${RED}❌ Terraform state dosyası bulunamadı!${NC}"
    echo -e "${YELLOW}Lütfen önce 'terraform apply' çalıştırın.${NC}"
    exit 1
fi

# Terraform çıktısını al
echo -e "${GREEN}🔄 Terraform çıktıları alınıyor...${NC}"
terraform output -json lxc_containers > "${PROJE_DIZINI}/containers.json" || { 
    echo -e "${RED}❌ Terraform çıktısı alınamadı!${NC}" 
    echo -e "${YELLOW}Hata detayı: terraform output komutu başarısız oldu.${NC}"
    exit 1 
}

# Çıktı dosyası kontrol
if [ ! -s "${PROJE_DIZINI}/containers.json" ]; then
    echo -e "${RED}❌ Terraform çıktısı boş veya oluşturulamadı.${NC}"
    echo -e "${YELLOW}Lütfen terraform.tfstate dosyasını kontrol edin ve tekrar deneyin.${NC}"
    exit 1
fi

# Container'ların boot işlemini tamamlamasını bekle
echo -e "${GREEN}🔄 Container'ların boot işlemini tamamlaması bekleniyor...${NC}"

wait_for_ssh() {
    local host=$1
    local max_attempts=30
    local delay=5
    local attempt=1

    echo -e "  ${YELLOW}🖥️ $host için SSH bağlantısı kontrol ediliyor...${NC}"
    while [ $attempt -le $max_attempts ]; do
        if nc -z -w5 $host 22 &> /dev/null; then
            echo -e "  ${GREEN}✅ $host SSH hazır! ($attempt. deneme)${NC}"
            return 0
        fi
        echo -e "  ${YELLOW}⏳ $host henüz hazır değil, bekleniyor... ($attempt/$max_attempts)${NC}"
        sleep $delay
        attempt=$((attempt+1))
    done
    
    echo -e "  ${RED}❌ $host için SSH zaman aşımı! Manuel kontrol gerekiyor.${NC}"
    return 1
}

# Inventory dizinini oluştur
mkdir -p "${PROJE_DIZINI}/ansible/inventory"

# Tüm IP adreslerini çıkar
CONTAINER_IPS=($(jq -r '.[] | .ip' "${PROJE_DIZINI}/containers.json" | cut -d'/' -f1))

if [ ${#CONTAINER_IPS[@]} -eq 0 ]; then
    echo -e "${RED}❌ Terraform çıktısından IP adresleri alınamadı!${NC}"
    echo -e "${YELLOW}containers.json dosyasını kontrol edin.${NC}"
    cat "${PROJE_DIZINI}/containers.json"
    exit 1
fi

# IP'lerin bağlanabilirliği kontrol et
for host in "${CONTAINER_IPS[@]}"; do
    wait_for_ssh $host
done

# Inventory dosyasını oluştur
echo -e "${GREEN}📝 Ansible inventory oluşturuluyor...${NC}"

# Önce temel inventory dosyasını oluştur
{
echo "[proxy]"
jq -r '.["lxc-proxy-01"].ip' "${PROJE_DIZINI}/containers.json" | cut -d'/' -f1 | awk '{print "lxc-proxy-01 ansible_host="$1}'
echo ""
echo "[media]"
jq -r '.["lxc-media-01"].ip' "${PROJE_DIZINI}/containers.json" | cut -d'/' -f1 | awk '{print "lxc-media-01 ansible_host="$1}'
echo ""
echo "[monitoring]"
jq -r '.["lxc-monitoring-01"].ip' "${PROJE_DIZINI}/containers.json" | cut -d'/' -f1 | awk '{print "lxc-monitoring-01 ansible_host="$1}'
echo ""
echo "[logging]"
jq -r '.["lxc-logging-01"].ip' "${PROJE_DIZINI}/containers.json" | cut -d'/' -f1 | awk '{print "lxc-logging-01 ansible_host="$1}'
echo ""
echo "[lxc:children]"
echo "proxy"
echo "media"
echo "monitoring"
echo "logging"
echo ""
echo "[lxc:vars]"
echo "ansible_user=root"
echo "ansible_ssh_common_args='-o StrictHostKeyChecking=no'"
} > "${PROJE_DIZINI}/ansible/inventory/all"

# Temizlik
rm "${PROJE_DIZINI}/containers.json"

echo -e "${GREEN}✅ Ansible inventory başarıyla oluşturuldu: ${PROJE_DIZINI}/ansible/inventory/all${NC}"
echo -e "${YELLOW}Şimdi Ansible playbook'u çalıştırabilirsiniz:${NC}"
echo -e "${GREEN}cd ${PROJE_DIZINI}/ansible && ansible-playbook -i inventory/all playbook.yml${NC}"
