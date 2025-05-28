#!/bin/bash
set -e  # Stop the script if any command fails

# Samba installation
apt update
apt install -y samba

# Samba configuration
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

# Set Samba password for root user
echo "Please enter the Samba root password:"
read -s samba_root_password
echo
echo "Please confirm the Samba root password:"
read -s samba_root_password_confirm
echo

# Check if passwords match
if [ "$samba_root_password" != "$samba_root_password_confirm" ]; then
    echo "Error: Passwords do not match. Please try again."
    exit 1
fi

echo "Configuring Samba password..."
(echo "$samba_root_password"; echo "$samba_root_password") | smbpasswd -a root > /dev/null 2>&1

if [ $? -eq 0 ]; then
    echo "Samba password configured successfully."
else
    echo "Failed to set Samba password. Please check the error and try again."
    exit 1
fi

# Restart the service
systemctl restart smbd

# Check the service status
sleep 3
systemctl status smbd | head -20

# Sanoid installation
apt update
apt install -y sanoid

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

# Enable and start the service
systemctl enable sanoid.timer
systemctl start sanoid.timer

# Check the service status
sleep 3
systemctl status sanoid.timer
