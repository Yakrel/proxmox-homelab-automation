#!/bin/bash

# ======================================================
# Proxmox Security Configuration Script
# ======================================================

# Daha esnek hata yönetimi - çıkış yapmak yerine hataları raporla
set -e
trap 'echo "An error occurred. Script terminating..."; exit 1' ERR

echo "===== Starting Proxmox Security Configuration ====="

# Root check
if [ "$(id -u)" -ne 0 ]; then
    echo "This script requires root privileges. Please run with 'sudo'."
    exit 1
fi

# --------------------------------------
# Fail2ban Installation
# --------------------------------------
echo "[1/5] Installing Fail2ban"
apt update
apt install -y fail2ban
if [ $? -ne 0 ]; then
    echo "Warning: Fail2ban installation may have issues but continuing..."
fi

# --------------------------------------
# Basic Configuration
# --------------------------------------
echo "[2/5] Creating Base Configuration File"
if [ -f /etc/fail2ban/jail.conf ]; then
    cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local 2>/dev/null || echo "Warning: Configuration file copy had issues but continuing..."
else
    echo "Warning: /etc/fail2ban/jail.conf does not exist. Skipping copy."
fi

# --------------------------------------
# Proxmox Filter Configuration
# --------------------------------------
echo "[3/5] Setting Up Proxmox Filter"
cat > /etc/fail2ban/filter.d/proxmox.conf << 'EOF'
[Definition]
failregex = pvedaemon\[.*authentication failure; rhost=<HOST> user=.* msg=.*
ignoreregex =
journalmatch = _SYSTEMD_UNIT=pvedaemon.service
EOF

# --------------------------------------
# SSH and Proxmox Jail Configuration
# --------------------------------------
echo "[4/5] Configuring SSH and Proxmox Jails"
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
# Restart Service
# --------------------------------------
echo "[5/5] Restarting Fail2ban Service"
systemctl restart fail2ban
if [ $? -ne 0 ]; then
    echo "Warning: Failed to start Fail2ban service but continuing..."
fi

# Servisin başlayabilmesi için bekleme süresi
echo "Waiting for Fail2ban service to start..."
sleep 10

# --------------------------------------
# Installation Check
# --------------------------------------
echo "===== Installation Complete. Checking Status ====="

# Service status check - hata olursa çıkış yapmasın
echo "Fail2ban service status:"
systemctl status fail2ban | grep "Active:" || echo "Could not get service status"

# Jail status check - hata olursa çıkış yapmasın
echo "Active jails (may not show if service just started):"
fail2ban-client status 2>/dev/null || echo "Could not get jail status - this is normal if service just started"

# Proxmox jail check - hata olursa çıkış yapmasın
echo "Proxmox jail configuration (may not show if service just started):"
fail2ban-client status proxmox 2>/dev/null || echo "Could not get Proxmox jail status - this is normal if service just started"

echo ""
echo "===== Security Configuration Completed ====="
echo ""
echo "System Security Configuration Completed."
echo ""
echo "# Useful Management Commands:"
echo "fail2ban-client status proxmox        # Status Check"
echo "fail2ban-client get proxmox banned    # Banned IPs"
echo "fail2ban-client unban YOUR_IP_ADDRESS # Remove Ban"
echo ""

exit 0
