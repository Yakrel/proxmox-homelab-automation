#!/bin/bash

# This script displays a menu for various Proxmox helper functions.

set -e

# --- Global Variables ---
WORK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)"

# --- Helper Functions ---
print_info() { echo -e "\033[36m[INFO]\033[0m $1"; }

# --- Unpack Helper Scripts ---
unpack_helper_scripts() {
    print_info "Unpacking Proxmox helper scripts..."
    mkdir -p "$WORK_DIR/scripts/proxmox-helpers"

    cat <<'EOF' > "$WORK_DIR/scripts/proxmox-helpers/configure_timezone.sh"
#!/bin/bash
set -e
if [ "$(id -u)" -ne 0 ]; then echo "ERROR: Must be run as root"; exit 1; fi
echo "Configuring timezone to Europe/Istanbul..."
timedatectl set-timezone Europe/Istanbul
echo "Configuring NTP servers for Turkey..."
cp /etc/chrony/chrony.conf /etc/chrony/chrony.conf.bak 2>/dev/null || true
cat > /etc/chrony/chrony.conf << EOT
pool tr.pool.ntp.org iburst
server 0.tr.pool.ntp.org iburst
server 1.tr.pool.ntp.org iburst
server 2.tr.pool.ntp.org iburst
pool 0.pool.ntp.org iburst
driftfile /var/lib/chrony/chrony.drift
makestep 1.0 3
rtcsync
leapsectz right/UTC
logdir /var/log/chrony
EOT
systemctl restart chronyd
echo "✓ NTP servers configured"
echo "✓ Timezone and NTP configuration completed!"
EOF

    cat <<'EOF' > "$WORK_DIR/scripts/proxmox-helpers/install_security.sh"
#!/bin/bash
set -e
if [ "$(id -u)" -ne 0 ]; then echo "ERROR: Must be run as root"; exit 1; fi
echo "Installing and configuring Fail2ban for Proxmox..."
apt update && apt install -y fail2ban
cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
cat > /etc/fail2ban/filter.d/proxmox.conf << EOT
[Definition]
failregex = pvedaemon\[.*authentication failure; rhost=<HOST> user=.* msg=.*
ignoreregex =
journalmatch = _SYSTEMD_UNIT=pvedaemon.service
EOT
# Remove existing proxmox section if exists
sed -i '/^\[proxmox\]/,/^\[/{ /^\[proxmox\]/d; /^\[/!d; }' /etc/fail2ban/jail.local
sed -i '/^\[proxmox\]/,/^$/d' /etc/fail2ban/jail.local
# Add new proxmox section
cat >> /etc/fail2ban/jail.local << EOT

[proxmox]
enabled = true
port = https,http,8006
filter = proxmox
backend = systemd
maxretry = 3
findtime = 2d
bantime = 1h
EOT
systemctl restart fail2ban
echo "✓ Fail2ban configured for Proxmox."
fail2ban-client status proxmox
EOF

    cat <<'EOF' > "$WORK_DIR/scripts/proxmox-helpers/install_storage.sh"
#!/bin/bash
set -e
if [ "$(id -u)" -ne 0 ]; then echo "ERROR: Must be run as root"; exit 1; fi
echo "Installing storage tools (Samba, Sanoid)..."
apt update && apt install -y samba sanoid
read -p "Enter Samba username: " samba_username
useradd -r -s /bin/false "$samba_username" 2>/dev/null || true
usermod -a -G root "$samba_username"
# Remove existing datapool section if exists
sed -i '/^\[datapool\]/,/^\[/{ /^\[datapool\]/d; /^\[/!d; }' /etc/samba/smb.conf
sed -i '/^\[datapool\]/,/^$/d' /etc/samba/smb.conf
# Add new datapool section
cat >> /etc/samba/smb.conf << EOT

[datapool]
   path = /datapool
   browseable = yes
   read only = no
   valid users = $samba_username
EOT
read -s -p "Enter Samba password for $samba_username: " samba_password
echo
(echo "$samba_password"; echo "$samba_password") | smbpasswd -a -s "$samba_username"
mkdir -p /etc/sanoid
cat > /etc/sanoid/sanoid.conf << EOT
[template_system]
daily = 7
monthly = 1
autosnap = yes
autoprune = yes
[template_data]
daily = 15
monthly = 2
autosnap = yes
autoprune = yes
[rpool/ROOT]
use_template = system
recursive = yes
[datapool]
use_template = data
recursive = yes
EOT
systemctl enable --now sanoid.timer
echo "✓ Samba and Sanoid configured."
EOF

    cat <<'EOF' > "$WORK_DIR/scripts/proxmox-helpers/optimize_zfs.sh"
#!/bin/bash
set -e
if [ "$(id -u)" -ne 0 ]; then echo "ERROR: Must be run as root"; exit 1; fi
if ! command -v zfs >/dev/null 2>&1; then echo "ERROR: ZFS not found. Aborting."; exit 1; fi
read -p "Do you want to apply ZFS optimizations? (atime=off, sync=disabled, ARC=50% RAM) (y/N): " confirm
if [[ ! $confirm =~ ^[Yy]$ ]]; then echo "Operation cancelled."; exit 0; fi
echo "Applying ZFS optimizations..."
zfs set atime=off rpool
zfs set sync=disabled datapool
arc_max_bytes=$(( $(free -g | awk 'NR==2{print $2}') / 2 * 1024 * 1024 * 1024 ))
echo "options zfs zfs_arc_max=${arc_max_bytes}" > /etc/modprobe.d/zfs.conf
update-initramfs -u -k all >/dev/null 2>&1
echo "✓ ZFS optimization applied. A reboot is required for ARC changes to take effect."
EOF

    cat <<'EOF' > "$WORK_DIR/scripts/proxmox-helpers/setup_bonding.sh"
#!/bin/bash
# Proxmox Network Bonding Setup Script
# Configures network bonding for maximum redundancy

set -e

# Configuration variables
BOND_NAME="bond0"
BRIDGE_NAME="vmbr0"
IP_ADDRESS=""
GATEWAY=""
NETWORK_MASK="24"

# Root check
if [ "$EUID" -ne 0 ]; then
    echo "ERROR: This script must be run as root"
    exit 1
fi

# Function to detect network interfaces
detect_interfaces() {
    echo "Detecting ethernet interfaces..."
    
    # Get all ethernet interfaces (excluding lo, docker, etc.)
    INTERFACES=($(ip link show | grep -E '^[0-9]+: enp|^[0-9]+: eth' | cut -d: -f2 | tr -d ' '))
    
    if [ ${#INTERFACES[@]} -eq 0 ]; then
        echo "ERROR: No ethernet interfaces found!"
        exit 1
    fi
    
    if [ ${#INTERFACES[@]} -eq 1 ]; then
        echo "WARNING: Only one interface found. Bonding requires multiple interfaces."
        echo "Found: ${INTERFACES[*]}"
        read -p "Continue anyway? (y/N): " confirm
        if [[ ! $confirm =~ ^[Yy]$ ]]; then
            exit 0
        fi
    fi
    
    echo "Found ${#INTERFACES[@]} interfaces: ${INTERFACES[*]}"
}

# Function to get network configuration
get_network_config() {
    echo "Network configuration required:"
    echo
    
    # Auto-detect current IP and gateway
    CURRENT_IP=$(ip route get 1 2>/dev/null | grep -Po '(?<=src )[0-9.]+' | head -1)
    CURRENT_GW=$(ip route | grep default | grep -Po '(?<=via )[0-9.]+' | head -1)
    
    # Get IP address
    if [ ! -z "$CURRENT_IP" ]; then
        read -p "IP Address [$CURRENT_IP]: " IP_ADDRESS
        IP_ADDRESS=${IP_ADDRESS:-$CURRENT_IP}
    else
        read -p "IP Address: " IP_ADDRESS
        while [[ ! $IP_ADDRESS =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; do
            echo "ERROR: Invalid IP address format"
            read -p "IP Address: " IP_ADDRESS
        done
    fi
    
    # Get gateway
    if [ ! -z "$CURRENT_GW" ]; then
        read -p "Gateway [$CURRENT_GW]: " GATEWAY
        GATEWAY=${GATEWAY:-$CURRENT_GW}
    else
        read -p "Gateway: " GATEWAY
        while [[ ! $GATEWAY =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; do
            echo "ERROR: Invalid gateway format"
            read -p "Gateway: " GATEWAY
        done
    fi
    
    # Get network mask
    read -p "Network Mask [24]: " NETWORK_MASK
    NETWORK_MASK=${NETWORK_MASK:-24}
    
    echo
    echo "Configuration summary:"
    echo "  IP: $IP_ADDRESS/$NETWORK_MASK"
    echo "  Gateway: $GATEWAY"
    echo "  Bond: ${INTERFACES[*]} → $BOND_NAME → $BRIDGE_NAME"
    echo
}

# Function to create backup
create_backup() {
    echo "Creating configuration backup..."
    
    BACKUP_DIR="/root/network-backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    
    # Backup essential files
    [ -f /etc/network/interfaces ] && cp /etc/network/interfaces "$BACKUP_DIR/"
    [ -f /etc/rc.local ] && cp /etc/rc.local "$BACKUP_DIR/"
    [ -f /etc/modules ] && cp /etc/modules "$BACKUP_DIR/"
    
    echo "Backup saved to: $BACKUP_DIR"
}

# Function to setup bonding module
setup_bonding_module() {
    echo "Configuring bonding module..."
    
    # Load bonding module
    modprobe bonding 2>/dev/null || true
    
    # Add to modules for persistent loading
    if ! grep -q "^bonding" /etc/modules 2>/dev/null; then
        echo 'bonding' >> /etc/modules
    fi
}

# Function to create network interfaces configuration
create_network_config() {
    echo "Creating network configuration..."
    
    cat > /etc/network/interfaces << EOF
# Network Interfaces Configuration
# Auto-generated by Proxmox Bonding Setup Script

auto lo
iface lo inet loopback

# Network Bond - Active-Backup Mode
auto $BOND_NAME
iface $BOND_NAME inet manual
    bond-slaves ${INTERFACES[*]}
    bond-mode active-backup
    bond-miimon 100
    bond-downdelay 200
    bond-updelay 200
    bond-primary ${INTERFACES[0]}

EOF

    # Add individual interface configurations
    for interface in "${INTERFACES[@]}"; do
        cat >> /etc/network/interfaces << EOF
# Interface $interface - Bond slave
auto $interface
iface $interface inet manual
    bond-master $BOND_NAME

EOF
    done

    # Add bridge configuration
    cat >> /etc/network/interfaces << EOF
# Bridge for VMs/CTs
auto $BRIDGE_NAME
iface $BRIDGE_NAME inet static
    address $IP_ADDRESS/$NETWORK_MASK
    gateway $GATEWAY
    bridge-ports $BOND_NAME
    bridge-stp off
    bridge-fd 0

source /etc/network/interfaces.d/*
EOF
}

# Function to create speed optimization
create_speed_optimization() {
    echo "Creating speed optimization..."
    
    cat > /etc/rc.local << 'EOF'
#!/bin/bash
# Network Speed Optimization

# Wait for interfaces to be ready
sleep 10

# Force 1Gbps on all ethernet interfaces
EOF

    for interface in "${INTERFACES[@]}"; do
        cat >> /etc/rc.local << EOF
ethtool -s $interface autoneg off speed 1000 duplex full 2>/dev/null || true
sleep 1
ethtool -s $interface autoneg on 2>/dev/null || true
EOF
    done

    cat >> /etc/rc.local << 'EOF'

exit 0
EOF

    chmod +x /etc/rc.local
    systemctl enable rc-local 2>/dev/null || true
}

# Function to apply configuration
apply_configuration() {
    echo "WARNING: Applying network configuration..."
    echo "Network connectivity will be briefly interrupted!"
    
    read -p "Press Enter to continue or Ctrl+C to abort..."
    
    # Restart networking
    systemctl restart networking
    
    # Wait for interfaces to stabilize
    sleep 5
}

# Function to verify configuration
verify_configuration() {
    echo "Verifying configuration..."
    
    # Test connectivity
    if ping -c 2 -W 3 "$GATEWAY" >/dev/null 2>&1; then
        echo "Network connectivity verified"
        return 0
    else
        echo "ERROR: Gateway connectivity failed"
        return 1
    fi
}

# Main function
main() {
    echo "Proxmox Network Bonding Setup"
    echo "============================="
    
    # Detect interfaces
    detect_interfaces
    
    # Get configuration
    get_network_config
    
    # Final confirmation
    echo "WARNING: This will modify your network configuration!"
    echo "Current active connections may be interrupted."
    echo
    read -p "Continue with bonding setup? (y/N): " confirm
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        echo "Setup cancelled"
        exit 0
    fi
    
    # Execute setup
    create_backup
    setup_bonding_module
    create_network_config
    create_speed_optimization
    apply_configuration
    
    # Verify and show results
    if verify_configuration; then
        echo
        echo "Network bonding setup completed successfully!"
        echo "Cable redundancy enabled - you can plug into any ethernet port"
    else
        echo "Configuration verification failed!"
        echo "Check network settings and consider restoring from backup."
        exit 1
    fi
}

# Handle interruption
trap 'echo; echo "Setup interrupted!"; exit 1' INT TERM

# Execute main function
main "$@"
EOF

    chmod +x "$WORK_DIR/scripts/proxmox-helpers/"*.sh
}

# --- Main Logic ---

# Unpack all helper scripts once when the menu starts.
unpack_helper_scripts

while true; do
    clear
    echo "======================================="
    echo " Proxmox Helper Scripts"
    echo "======================================="
    echo
    echo "1) Configure Timezone (Europe/Istanbul)"
    echo "2) Install Security Tools (Fail2ban)"
    echo "3) Configure Storage (Samba + Sanoid)"
    echo "4) Optimize ZFS Performance"
    echo "5) Setup Network Bonding (Interactive)"
    echo "---------------------------------------"
    echo "b) Back to Main Menu"
    echo "q) Quit"
    echo
    read -p "Enter your choice: " choice

    case $choice in
        1) bash "$WORK_DIR/scripts/proxmox-helpers/configure_timezone.sh" ;;
        2) bash "$WORK_DIR/scripts/proxmox-helpers/install_security.sh" ;;
        3) bash "$WORK_DIR/scripts/proxmox-helpers/install_storage.sh" ;;
        4) bash "$WORK_DIR/scripts/proxmox-helpers/optimize_zfs.sh" ;;
        5) bash "$WORK_DIR/scripts/proxmox-helpers/setup_bonding.sh" ;;
        b|B) break ;;
        q|Q) echo "Exiting."; exit 0 ;;
        *) echo "Invalid choice. Please try again." ;;
    esac
    echo
    read -p "Press Enter to continue..."
done