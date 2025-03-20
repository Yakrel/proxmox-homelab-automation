#!/bin/bash

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
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "Script dosyalarını $SCRIPT_DIR/scripts/ konumundan alıyorum."

# Menü
echo ""
echo "Lütfen yapmak istediğiniz işlemi seçin:"
echo "1) Güvenlik Kurulumu (Fail2Ban)"
echo "2) Depolama Kurulumu (Samba, Sanoid)"
echo "3) Proxy LXC (ID: 100) Hazırlama"
echo "4) Media LXC (ID: 101) Hazırlama"
echo "5) Çıkış"
echo ""

read -p "Seçiminiz (1-5): " choice

case $choice in
    1)
        # Güvenlik kurulumu
        if [ -f "$SCRIPT_DIR/scripts/install_security.sh" ]; then
            echo "Güvenlik kurulumu başlatılıyor..."
            bash "$SCRIPT_DIR/scripts/install_security.sh"
        else
            echo "HATA: $SCRIPT_DIR/scripts/install_security.sh dosyası bulunamadı!"
        fi
        ;;
    2)
        # Depolama kurulumu
        if [ -f "$SCRIPT_DIR/scripts/install_storage.sh" ]; then
            echo "Depolama kurulumu başlatılıyor..."
            bash "$SCRIPT_DIR/scripts/install_storage.sh"
        else
            echo "HATA: $SCRIPT_DIR/scripts/install_storage.sh dosyası bulunamadı!"
        fi
        ;;
    3)
        # Proxy LXC hazırlama
        if [ -f "$SCRIPT_DIR/scripts/setup_proxy_lxc.sh" ]; then
            echo "Proxy LXC hazırlama başlatılıyor..."
            bash "$SCRIPT_DIR/scripts/setup_proxy_lxc.sh"
        else
            echo "HATA: $SCRIPT_DIR/scripts/setup_proxy_lxc.sh dosyası bulunamadı!"
        fi
        ;;
    4)
        # Media LXC hazırlama
        if [ -f "$SCRIPT_DIR/scripts/setup_media_lxc.sh" ]; then
            echo "Media LXC hazırlama başlatılıyor..."
            bash "$SCRIPT_DIR/scripts/setup_media_lxc.sh"
        else
            echo "HATA: $SCRIPT_DIR/scripts/setup_media_lxc.sh dosyası bulunamadı!"
        fi
        ;;
    5)
        # Çıkış
        echo "Çıkış yapılıyor..."
        exit 0
        ;;
    *)
        echo "Geçersiz seçim!"
        exit 1
        ;;
esac

echo "======================================================"
echo "İşlem tamamlandı!"
echo "======================================================"
exit 0
