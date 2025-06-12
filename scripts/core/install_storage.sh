#!/bin/bash
set -e  # Stop the script if any command fails

# Samba installation
apt update
apt install -y samba

# Get custom Samba username
echo "Samba Configuration:"
read -p "Enter Samba username: " samba_username
while [ -z "$samba_username" ]; do
    echo "Username cannot be empty!"
    read -p "Enter Samba username: " samba_username
done

# Create dedicated samba user
useradd -r -s /bin/false "$samba_username" 2>/dev/null || true

# Add samba user to root group for full datapool access (no chown needed)
usermod -a -G root "$samba_username"

# Samba configuration with full access but no ownership changes
cat >> /etc/samba/smb.conf << EOF

[datapool]
   path = /datapool
   browseable = yes
   read only = no
   create mask = 0664
   directory mask = 0775
   valid users = $samba_username
   admin users = $samba_username
   # Security settings
   guest ok = no
   security = user
   # Performance optimizations
   socket options = TCP_NODELAY IPTOS_LOWDELAY
   read raw = yes
   write raw = yes
   strict locking = no
EOF

# No ownership changes - Samba user gets access via root group membership

# Set Samba password for custom user
echo "Please enter the Samba password for user '$samba_username':"
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
(echo "$samba_password"; echo "$samba_password") | smbpasswd -a "$samba_username" > /dev/null 2>&1

if [ $? -eq 0 ]; then
    echo "Samba password configured successfully for user '$samba_username'."
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
