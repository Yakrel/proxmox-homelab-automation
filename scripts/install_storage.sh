#!/bin/bash

# Samba kurulumu
apt update
apt install -y samba

# Samba konfigürasyonu
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

# Root kullanıcısı için Samba şifresi belirleme
echo "Lütfen Samba root şifresini girin:"
read -s samba_root_password
(echo "$samba_root_password"; echo "$samba_root_password") | smbpasswd -a root

# Servisi yeniden başlat
systemctl restart smbd

# Servis durumunu kontrol et
sleep 3
systemctl status smbd

# Sanoid kurulumu
apt update
apt install -y sanoid

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

# Servisi etkinleştir ve başlat
systemctl enable sanoid.timer
systemctl start sanoid.timer

# Servis durumunu kontrol et
sleep 3
systemctl status sanoid.timer
