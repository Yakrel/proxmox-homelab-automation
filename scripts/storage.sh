#!/bin/bash

# ======================================================
# Proxmox Storage Configuration Script
# ======================================================

# Error handling
set -e
trap 'echo "An error occurred. Script terminating..."; exit 1' ERR

# Root check
if [ "$(id -u)" -ne 0 ]; then
    echo "This script requires root privileges. Please run with 'sudo'."
    exit 1
fi

echo "===== Starting Proxmox Storage Configuration ====="

# --------------------------------------
# Samba Share
# --------------------------------------
echo "[1/4] Installing Samba"
apt update
apt install -y samba
if [ $? -ne 0 ]; then
    echo "Samba installation failed!"
    exit 1
fi

echo "[2/4] Configuring Samba"
cat >> /etc/samba/smb.conf << 'EOF'

[datapool]
   path = /datapool
   browseable = yes
   read only = no
   force create mode = 0660
   force directory mode = 0770
   valid users = root
   # Performance optimizations
   socket options = TCP_NODELAY IPTOS_LOWDELAY
   read raw = yes
   write raw = yes
   strict locking = no
EOF

echo "[*] Setting Samba password for root user"
echo "Note: It's recommended to use the same password as your Proxmox root password"
smbpasswd -a root

echo "[3/4] Restarting Samba Service"
systemctl restart smbd
if [ $? -ne 0 ]; then
    echo "Failed to start Samba service!"
    exit 1
fi

# --------------------------------------
# Sanoid Installation
# --------------------------------------
echo "[4/4] Installing Sanoid Snapshot Management"

# Create backup directory
mkdir -p /datapool/backups

# Install Sanoid
apt update
apt install -y sanoid
if [ $? -ne 0 ]; then
    echo "Sanoid installation failed!"
    exit 1
fi

# Create Sanoid config directory
mkdir -p /etc/sanoid

# Create configuration file
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

# Enable and start Sanoid service
echo "[*] Enabling Sanoid Service"
systemctl enable sanoid.timer
systemctl start sanoid.timer

# --------------------------------------
# Installation Check
# --------------------------------------
echo "===== Installation Complete. Checking Status ====="

# Samba service status
echo "Samba service status:"
systemctl status smbd | grep "Active:"

# Samba shares
echo "Samba shares:"
smbclient -L localhost -U%

# Sanoid service status
echo "Sanoid service status:"
systemctl status sanoid.timer | grep "Active:"

# ZFS snapshot status
echo "ZFS snapshots:"
zfs list -t snapshot | head -n 5

echo ""
echo "===== Storage Configuration Completed ====="
echo ""
echo "Storage System Successfully Configured."
echo ""
echo "# Samba Access Information:"
echo "- Username: root"
echo "- Windows connection: \\\\$(hostname -I | awk '{print $1}')\\datapool"
echo ""
echo "# Snapshot Management:"
echo "sanoid --take-snapshots           # Manual snapshot creation"
echo "zfs list -t snapshot              # List snapshots"
echo ""
echo "# Backup Commands:"
echo "zfs send rpool/ROOT/pve-1@snapshot_name | gzip > /datapool/backups/system_backup.gz   # System backup"
echo "zfs send datapool@snapshot_name | gzip > /datapool/backups/data_backup.gz             # Data backup"
echo ""

exit 0
