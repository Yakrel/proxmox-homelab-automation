#!/bin/bash

# Network Bonding Setup Script for Proxmox
# Configures network interface bonding for homelab setup

set -e

# Simple utility functions
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "ERROR: This script must be run as root"
        exit 1
    fi
}

# Function to backup existing network configuration
backup_network_config() {
    local backup_dir="/etc/network/backup-$(date +%Y%m%d-%H%M%S)"
    echo "Backing up current network configuration..."
    
    mkdir -p "$backup_dir"
    cp /etc/network/interfaces "$backup_dir/"
    
    if [ -d /etc/network/interfaces.d ]; then
        cp -r /etc/network/interfaces.d "$backup_dir/"
    fi
    
    echo "✓ Network configuration backed up to $backup_dir"
}

# Function to check if interfaces exist
check_interfaces() {
    local interfaces=("enp0s25" "enp2s0f0" "enp2s0f1" "enp2s0f2" "enp2s0f3")
    local missing_interfaces=()
    
    echo "Checking network interfaces..."
    
    for iface in "${interfaces[@]}"; do
        if ! ip link show "$iface" >/dev/null 2>&1; then
            missing_interfaces+=("$iface")
        fi
    done
    
    if [ ${#missing_interfaces[@]} -gt 0 ]; then
        echo "WARNING: The following interfaces are not available:"
        printf '  %s\n' "${missing_interfaces[@]}"
        echo
        read -p "Continue anyway? (y/N): " confirm
        if [[ ! $confirm =~ ^[Yy]$ ]]; then
            echo "Bonding setup cancelled"
            exit 0
        fi
    else
        echo "✓ All interfaces are available"
    fi
}

# Function to create bonding configuration
create_bond_config() {
    local bond_name="bond0"
    local primary_iface="enp2s0f0"
    local slave_ifaces=("enp0s25" "enp2s0f0" "enp2s0f1" "enp2s0f2" "enp2s0f3")
    
    echo "Creating bonding configuration..."
    
    # Create new interfaces file
    cat > /etc/network/interfaces << 'EOF'
# This file describes the network interfaces available on your system
# and how to activate them. For more information, see interfaces(5).

source /etc/network/interfaces.d/*

# The loopback network interface
auto lo
iface lo inet loopback

# Bond interface
auto bond0
iface bond0 inet dhcp
    bond-slaves none
    bond-mode active-backup
    bond-miimon 100
    bond-downdelay 200
    bond-updelay 200
    bond-primary enp2s0f0
    bond-primary-reselect always

EOF

    # Create slave interface configurations
    for iface in "${slave_ifaces[@]}"; do
        cat > "/etc/network/interfaces.d/${iface}" << EOF
# Slave interface for bond0
auto ${iface}
iface ${iface} inet manual
    bond-master bond0
    bond-primary ${primary_iface}

EOF
    done
    
    echo "✓ Bonding configuration created"
    echo "  Bond name: $bond_name"
    echo "  Mode: active-backup"
    echo "  Primary interface: $primary_iface"
    echo "  Slave interfaces: ${slave_ifaces[*]}"
}

# Function to load bonding module
load_bonding_module() {
    echo "Loading bonding kernel module..."
    
    # Load module
    modprobe bonding
    
    # Ensure module loads at boot
    echo "bonding" >> /etc/modules
    
    echo "✓ Bonding module loaded and configured for boot"
}

# Function to restart networking
restart_networking() {
    echo "Restarting network services..."
    
    # Restart networking
    systemctl restart networking
    
    if [ $? -eq 0 ]; then
        echo "✓ Network services restarted successfully"
        
        # Show bond status
        echo
        echo "Bond interface status:"
        if ip link show bond0 >/dev/null 2>&1; then
            ip addr show bond0 | grep -E "(inet|bond0:|state)"
            
            # Show bonding info if available
            if [ -f /proc/net/bonding/bond0 ]; then
                echo
                echo "Bonding details:"
                cat /proc/net/bonding/bond0 | grep -E "(Bonding Mode|Primary Slave|Currently Active Slave|MII Status)"
            fi
        else
            echo "WARNING: bond0 interface not found"
        fi
    else
        echo "ERROR: Failed to restart networking"
        echo "You may need to reboot or manually configure networking"
        return 1
    fi
}

# Function to show current network configuration
show_current_config() {
    echo "Current network configuration:"
    echo
    
    # Show active interfaces
    echo "Active interfaces:"
    ip link show | grep -E "^[0-9]+:" | awk '{print "  " $2}' | sed 's/://'
    echo
    
    # Show IP addresses
    echo "IP addresses:"
    ip addr show | grep -E "(inet )" | grep -v "127.0.0.1" | awk '{print "  " $2 " on " $NF}'
}

# Main bonding setup function
setup_bonding() {
    echo "Network Bonding Setup"
    echo "====================="
    echo
    
    # Show current configuration
    show_current_config
    echo
    
    # Confirm setup
    echo "This will configure network bonding with the following settings:"
    echo "  Bond name: bond0"
    echo "  Bond mode: active-backup (failover)"
    echo "  Primary interface: enp2s0f0"
    echo "  Slave interfaces: enp0s25, enp2s0f0, enp2s0f1, enp2s0f2, enp2s0f3"
    echo
    echo "WARNING: This will modify your network configuration."
    echo "Make sure you have console access in case of issues."
    echo
    read -p "Continue with bonding setup? (y/N): " confirm
    
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        echo "Bonding setup cancelled"
        exit 0
    fi
    
    echo
    
    # Perform setup steps
    backup_network_config
    check_interfaces
    load_bonding_module
    create_bond_config
    restart_networking
    
    echo
    echo "Network bonding setup completed successfully!"
    echo "Your network interfaces are now bonded for redundancy."
    echo
    echo "To verify bonding status, run:"
    echo "  cat /proc/net/bonding/bond0"
}

# Check root privileges
check_root

# Run bonding setup
setup_bonding