#!/bin/bash

# ======================================================
# Proxmox Güvenlik Yapılandırma Scripti
# ======================================================

# Hata yönetimi
set -e
trap 'echo "Bir hata oluştu. Script sonlandırılıyor..."; exit 1' ERR

# Root kontrolü
if [ "$(id -u)" -ne 0 ]; then
    echo "Bu script root yetkisi gerektirir. 'sudo' ile çalıştırın."
    exit 1
fi

echo "===== Proxmox Güvenlik Yapılandırması Başlatılıyor ====="

# --------------------------------------
# Fail2ban Kurulumu
# --------------------------------------
echo "[1/5] Fail2ban Kurulumu"
apt update
apt install -y fail2ban
if [ $? -ne 0 ]; then
    echo "Fail2ban kurulumu başarısız oldu!"
    exit 1
fi

# --------------------------------------
# Temel Yapılandırma
# --------------------------------------
echo "[2/5] Temel Yapılandırma Dosyası Oluşturuluyor"
cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
if [ $? -ne 0 ]; then
    echo "Yapılandırma dosyası kopyalama başarısız oldu!"
    exit 1
fi

# --------------------------------------
# Proxmox Filter Yapılandırması
# --------------------------------------
echo "[3/5] Proxmox Filter Yapılandırması"
cat > /etc/fail2ban/filter.d/proxmox.conf << 'EOF'
[Definition]
failregex = pvedaemon\[.*authentication failure; rhost=<HOST> user=.* msg=.*
ignoreregex =
journalmatch = _SYSTEMD_UNIT=pvedaemon.service
EOF

# --------------------------------------
# SSH ve Proxmox Jail Yapılandırması
# --------------------------------------
echo "[4/5] SSH ve Proxmox Jail Yapılandırması"
cat > /etc/fail2ban/jail.local << 'EOF'
[sshd]
backend = systemd
enabled = true

[proxmox]
enabled = true
port = https,http,8006
filter = proxmox
backend = systemd
maxretry = 3
findtime = 2d
bantime = 1h
EOF

# --------------------------------------
# Servisi Yeniden Başlatma
# --------------------------------------
echo "[5/5] Fail2ban Servisi Yeniden Başlatılıyor"
systemctl restart fail2ban
if [ $? -ne 0 ]; then
    echo "Fail2ban servisi başlatılamadı!"
    exit 1
fi

# --------------------------------------
# Kurulum Kontrolü
# --------------------------------------
echo "===== Kurulum Tamamlandı. Durum Kontrolü Yapılıyor ====="

# Servis durumu kontrolü
echo "Fail2ban servis durumu:"
systemctl status fail2ban | grep "Active:"

# Jail durumu kontrolü
echo "Aktif jail'ler:"
fail2ban-client status | grep "Jail list"

# Proxmox jail kontrolü
echo "Proxmox jail konfigürasyonu:"
fail2ban-client status proxmox | grep "Status"

echo ""
echo "===== Güvenlik Yapılandırması Tamamlandı ====="
echo ""
echo "Sistem Güvenliği Başarıyla Yapılandırıldı."
echo ""
echo "# Kullanılabilecek Yönetim Komutları:"
echo "fail2ban-client status proxmox        # Durum Kontrolü"
echo "fail2ban-client get proxmox banned    # Banlı IP'ler"
echo "fail2ban-client unban IP_ADRESINIZ    # Ban Kaldırma"
echo ""

exit 0
