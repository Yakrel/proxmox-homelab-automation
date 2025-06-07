#!/bin/bash
set -e  # Stop the script if any command fails

# 1. Fail2ban Installation
apt update
apt install -y fail2ban

# 2. Basic Configuration
cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local

# 3. Proxmox Filter Configuration
cat > /etc/fail2ban/filter.d/proxmox.conf << 'EOF'
[Definition]
failregex = pvedaemon\[.*authentication failure; rhost=<HOST> user=.* msg=.*
ignoreregex =
journalmatch = _SYSTEMD_UNIT=pvedaemon.service
EOF

# 4. SSH and Proxmox Jail Configuration
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

# 5. Restart the Service
systemctl restart fail2ban

# 6. Check the Service Status
sleep 3
systemctl status fail2ban
