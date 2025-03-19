#!/bin/bash
set -e  # Herhangi bir komut hata verdiğinde scripti durdur

# 1. Fail2ban Kurulumu
apt update
apt install -y fail2ban

# 2. Temel Yapılandırma
cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local

# 3. Proxmox Filter Yapılandırması
cat > /etc/fail2ban/filter.d/proxmox.conf << 'EOF'
[Definition]
failregex = pvedaemon\[.*authentication failure; rhost=<HOST> user=.* msg=.*
ignoreregex =
journalmatch = _SYSTEMD_UNIT=pvedaemon.service
EOF

# 4. SSH ve Proxmox Jail Yapılandırması
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

# 5. Servisi Yeniden Başlat
systemctl restart fail2ban

# 6. Servis durumunu kontrol et
sleep 3
systemctl status fail2ban
