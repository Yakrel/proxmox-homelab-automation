#!/bin/bash
set -e  # Stop the script if any command fails

# Samba installation
apt update
apt install -y samba

# Create dedicated samba user instead of root
useradd -r -s /bin/false smbuser 2>/dev/null || true

# Samba configuration with security improvements
cat >> /etc/samba/smb.conf << 'EOF'

[datapool]
   path = /datapool
   browseable = yes
   read only = no
   force create mode = 0660
   force directory mode = 0770
   valid users = smbuser
   force user = smbuser
   force group = smbuser
   # Security settings
   guest ok = no
   security = user
   # Performance optimizations
   socket options = TCP_NODELAY IPTOS_LOWDELAY
   read raw = yes
   write raw = yes
   strict locking = no
EOF

# Set ownership of datapool to smbuser
chown -R smbuser:smbuser /datapool 2>/dev/null || true

# Set Samba password for smbuser
echo "Please enter the Samba password for user 'smbuser':"
read -s samba_password
echo
echo "Please confirm the Samba password:"
read -s samba_password_confirm
echo

# Check if passwords match
if [ "$samba_password" != "$samba_password_confirm" ]; then
    echo "Error: Passwords do not match. Please try again."
    exit 1
fi

echo "Configuring Samba password..."
(echo "$samba_password"; echo "$samba_password") | smbpasswd -a smbuser > /dev/null 2>&1

if [ $? -eq 0 ]; then
    echo "Samba password configured successfully for user 'smbuser'."
else
    echo "Failed to set Samba password. Please check the error and try again."
    exit 1
fi

# Clear password variables for security
unset samba_password
unset samba_password_confirm

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

# Detect available ZFS datasets for sanoid configuration
echo "Detecting ZFS datasets for snapshot configuration..."

# Create configuration file with detected datasets
cat > /etc/sanoid/sanoid.conf << 'EOF'
# Sanoid configuration - automatically configured

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

# Add system pools if they exist
if zfs list rpool/ROOT >/dev/null 2>&1; then
    echo "" >> /etc/sanoid/sanoid.conf
    echo "[rpool/ROOT]" >> /etc/sanoid/sanoid.conf
    echo "        use_template = system" >> /etc/sanoid/sanoid.conf
    echo "        recursive = yes" >> /etc/sanoid/sanoid.conf
    echo "✓ Added rpool/ROOT to sanoid configuration"
fi

# Add data pools if they exist
if zfs list datapool >/dev/null 2>&1; then
    echo "" >> /etc/sanoid/sanoid.conf
    echo "[datapool]" >> /etc/sanoid/sanoid.conf
    echo "        use_template = data" >> /etc/sanoid/sanoid.conf
    echo "        recursive = yes" >> /etc/sanoid/sanoid.conf
    echo "✓ Added datapool to sanoid configuration"
fi

# Enable and start the service
systemctl enable sanoid.timer
systemctl start sanoid.timer

# Check the service status
sleep 3
systemctl status sanoid.timer
