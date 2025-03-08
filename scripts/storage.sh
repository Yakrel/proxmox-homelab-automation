#!/bin/bash

# ======================================================
# Proxmox Storage Yapılandırma Scripti
# ======================================================

# Hata yönetimi
set -e
trap 'echo "Bir hata oluştu. Script sonlandırılıyor..."; exit 1' ERR

# Root kontrolü
if [ "$(id -u)" -ne 0 ]; then
    echo "Bu script root yetkisi gerektirir. 'sudo' ile çalıştırın."
    exit 1
fi

echo "===== Proxmox Storage Yapılandırması Başlatılıyor ====="

# --------------------------------------
# Samba Paylaşımı
# --------------------------------------
echo "[1/4] Samba Kurulumu"
apt update
apt install -y samba
if [ $? -ne 0 ]; then
    echo "Samba kurulumu başarısız oldu!"
    exit 1
fi

echo "[2/4] Samba Konfigürasyonu"
cat >> /etc/samba/smb.conf << 'EOF'

[datapool]
   path = /datapool
   browseable = yes
   read only = no
   force create mode = 0660
   force directory mode = 0770
   valid users = root
   # Performans optimizasyonları
   socket options = TCP_NODELAY IPTOS_LOWDELAY
   read raw = yes
   write raw = yes
   strict locking = no
EOF

echo "[*] Root kullanıcısı için Samba şifresi belirleme"
echo "Not: Proxmox root şifresi ile aynı şifreyi girmeniz önerilir"
smbpasswd -a root

echo "[3/4] Samba Servisi Yeniden Başlatılıyor"
systemctl restart smbd
if [ $? -ne 0 ]; then
    echo "Samba servisi başlatılamadı!"
    exit 1
fi

# --------------------------------------
# Sanoid Kurulumu
# --------------------------------------
echo "[4/4] Sanoid Snapshot Yönetimi Kurulumu"

# Backup dizini oluştur
mkdir -p /datapool/backups

# Sanoid kurulumu
apt update
apt install -y sanoid
if [ $? -ne 0 ]; then
    echo "Sanoid kurulumu başarısız oldu!"
    exit 1
fi

# Sanoid config klasörünü oluştur
mkdir -p /etc/sanoid

# Yapılandırma dosyasını oluştur
cat > /etc/sanoid/sanoid.conf << EOF
[rpool/ROOT/pve-1]
        use_template = system
        recursive = yes

[datapool]
        use_template = data
        recursive = yes

[template_system]
        frequently = 0
        hourly = 0
        daily = 7
        monthly = 1
        yearly = 0
        autosnap = yes
        autoprune = yes

[template_data]
        frequently = 0
        hourly = 0
        daily = 15
        monthly = 2
        yearly = 0
        autosnap = yes
        autoprune = yes
EOF

# Sanoid servisi etkinleştir ve başlat
echo "[*] Sanoid Servisi Etkinleştiriliyor"
systemctl enable sanoid.timer
systemctl start sanoid.timer

# İlk snapshot'ları oluştur
echo "[*] İlk Snapshot'lar Oluşturuluyor"
sanoid --take-snapshots --verbose

# --------------------------------------
# Kurulum Kontrolü
# --------------------------------------
echo "===== Kurulum Tamamlandı. Durum Kontrolü Yapılıyor ====="

# Samba servisi durumu
echo "Samba servis durumu:"
systemctl status smbd | grep "Active:"

# Samba paylaşımları
echo "Samba paylaşımları:"
smbclient -L localhost -U%

# Sanoid servis durumu
echo "Sanoid servis durumu:"
systemctl status sanoid.timer | grep "Active:"

# ZFS snapshot durumu
echo "ZFS snapshot'lar:"
zfs list -t snapshot | head -n 5

echo ""
echo "===== Storage Yapılandırması Tamamlandı ====="
echo ""
echo "Storage Sistemi Başarıyla Yapılandırıldı."
echo ""
echo "# Samba Erişim Bilgileri:"
echo "- Kullanıcı adı: root"
echo "- Windows'ta bağlantı: \\\\$(hostname -I | awk '{print $1}')\\datapool"
echo ""
echo "# Snapshot Yönetimi:"
echo "sanoid --take-snapshots           # Manuel snapshot alma"
echo "zfs list -t snapshot              # Snapshot'ları listeleme"
echo ""
echo "# Backup Komutları:"
echo "zfs send rpool/ROOT/pve-1@snapshot_adi | gzip > /datapool/backups/system_backup.gz   # Sistem backupu alma"
echo "zfs send datapool@snapshot_adi | gzip > /datapool/backups/data_backup.gz             # Data backupu alma"
echo ""

exit 0
