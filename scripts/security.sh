#!/bin/bash

# ======================================================
# Proxmox Security Configuration Script
# ======================================================

# Error handling
set -e
trap 'echo "An error occurred. Script terminating..."; exit 1' ERR

# Root check
if [ "$(id -u)" -ne 0 ]; then
    echo "This script requires root privileges. Please run with 'sudo'."
    exit 1
fi

echo "===== Starting Proxmox Security Configuration ====="

# --------------------------------------
# Fail2ban Installation
# --------------------------------------
echo "[1/5] Installing Fail2ban"
apt update
apt install -y fail2ban
if [ $? -ne 0 ]; then
    echo "Fail2ban installation failed!"
    exit 1
fi

# --------------------------------------
# Basic Configuration
# --------------------------------------
echo "[2/5] Creating Base Configuration File"
cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
if [ $? -ne 0 ]; then
    echo "Configuration file copy failed!"
    exit 1
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
    echo "Failed to start Fail2ban service!"
    exit 1
fi

# --------------------------------------
# Installation Check
# --------------------------------------
echo "===== Installation Complete. Checking Status ====="

# Service status check
echo "Fail2ban service status:"
systemctl status fail2ban | grep "Active:"

# Jail status check
echo "Active jails:"
fail2ban-client status | grep "Jail list"

# Proxmox jail check
echo "Proxmox jail configuration:"
fail2ban-client status proxmox | grep "Status"

echo ""
echo "===== Security Configuration Completed ====="
echo ""
echo "System Security Successfully Configured."
echo ""
echo "# Useful Management Commands:"
echo "fail2ban-client status proxmox        # Status Check"
echo "fail2ban-client get proxmox banned    # Banned IPs"
echo "fail2ban-client unban YOUR_IP_ADDRESS # Remove Ban"
echo ""

exit 0
