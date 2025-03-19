#!/bin/bash

# Başlık
echo "======================================================"
echo "Proxmox Homelab Automation - Basitleştirilmiş Kurulum Aracı"
echo "======================================================"

# Root kontrolü
if [ "$(id -u)" -ne 0 ]; then
   echo "Bu script root olarak çalıştırılmalıdır" 
   exit 1
fi

# İlgili repo uyarısı
echo "Bu script artık kurulumları otomatik olarak yapmaz."
echo "Docker Compose dosyalarını manuel olarak kurmanız gerekecek."
echo "Detaylı bilgi için README.md dosyasını inceleyiniz."
echo ""

# Geçici çalışma dizini
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "Script dosyalarını $SCRIPT_DIR/scripts/ konumundan alıyorum."

# Güvenlik kurulumu
read -p "Güvenlik kurulumunu yapmak istiyor musunuz? (e/h): " security_choice
if [[ $security_choice == "e" || $security_choice == "E" ]]; then
    if [ -f "$SCRIPT_DIR/scripts/install_security.sh" ]; then
        echo "Güvenlik kurulumu başlatılıyor..."
        bash "$SCRIPT_DIR/scripts/install_security.sh"
    else
        echo "HATA: $SCRIPT_DIR/scripts/install_security.sh dosyası bulunamadı!"
    fi
fi

# Depolama kurulumu
read -p "Depolama kurulumunu yapmak istiyor musunuz? (e/h): " storage_choice
if [[ $storage_choice == "e" || $storage_choice == "E" ]]; then
    if [ -f "$SCRIPT_DIR/scripts/install_storage.sh" ]; then
        echo "Depolama kurulumu başlatılıyor..."
        bash "$SCRIPT_DIR/scripts/install_storage.sh"
    else
        echo "HATA: $SCRIPT_DIR/scripts/install_storage.sh dosyası bulunamadı!"
    fi
fi

echo "======================================================"
echo "Kurulum tamamlandı!"
echo "======================================================"
exit 0
