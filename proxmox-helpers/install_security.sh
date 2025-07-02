#!/bin/bash
set -e  # Stop the script if any command fails

apt update
apt install -y fail2ban

cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
cat > /etc/fail2ban/filter.d/proxmox.conf << 'EOF'
[Definition]
failregex = pvedaemon\[.*authentication failure; rhost=<HOST> user=.* msg=.*
ignoreregex =
journalmatch = _SYSTEMD_UNIT=pvedaemon.service
EOF

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

systemctl restart fail2ban
sleep 3
echo "Fail2ban status:"
systemctl is-active fail2ban && echo "✓ Fail2ban is running"
echo "Active jails:"
fail2ban-client status
