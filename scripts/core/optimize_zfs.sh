#!/bin/bash

# ZFS Performance Optimization Script
# Optimizes ZFS pools for better performance in homelab environments

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if ZFS pools exist
check_zfs_pools() {
    if ! command -v zfs >/dev/null 2>&1; then
        print_error "ZFS not found on this system"
        exit 1
    fi
    
    if ! zpool list >/dev/null 2>&1; then
        print_error "No ZFS pools found"
        exit 1
    fi
}

# Function to optimize rpool (disable atime)
optimize_rpool() {
    if zpool list rpool >/dev/null 2>&1; then
        print_info "Optimizing rpool (disabling atime)..."
        zfs set atime=off rpool
        print_info "✓ rpool atime disabled"
    else
        print_warning "rpool not found, skipping atime optimization"
    fi
}

# Function to optimize datapool (disable sync)
optimize_datapool() {
    if zpool list datapool >/dev/null 2>&1; then
        print_info "Optimizing datapool (disabling sync)..."
        zfs set sync=disabled datapool
        print_info "✓ datapool sync disabled"
    else
        print_warning "datapool not found, skipping sync optimization"
    fi
}

# Function to configure ZFS ARC memory
configure_arc_memory() {
    local total_ram_gb=$(free -g | awk 'NR==2{print $2}')
    local arc_max_gb=$((total_ram_gb / 2))
    local arc_max_bytes=$((arc_max_gb * 1024 * 1024 * 1024))
    
    print_info "Configuring ZFS ARC memory (${arc_max_gb}GB max)..."
    
    # Create modprobe configuration
    echo "options zfs zfs_arc_max=${arc_max_bytes}" > /etc/modprobe.d/zfs.conf
    
    # Update initramfs
    update-initramfs -u -k all >/dev/null 2>&1
    
    print_info "✓ ZFS ARC configured for ${arc_max_gb}GB"
    print_warning "Reboot required for ARC settings to take effect"
}

# Function to show current ZFS settings
show_current_settings() {
    print_info "Current ZFS settings:"
    
    if zpool list rpool >/dev/null 2>&1; then
        local atime=$(zfs get -H -o value atime rpool)
        echo "  rpool atime: $atime"
    fi
    
    if zpool list datapool >/dev/null 2>&1; then
        local sync=$(zfs get -H -o value sync datapool)
        echo "  datapool sync: $sync"
    fi
    
    if [ -f /etc/modprobe.d/zfs.conf ]; then
        local arc_setting=$(grep zfs_arc_max /etc/modprobe.d/zfs.conf 2>/dev/null || echo "not configured")
        echo "  ZFS ARC: $arc_setting"
    else
        echo "  ZFS ARC: not configured"
    fi
}

# Main optimization function
optimize_all() {
    print_info "Starting ZFS performance optimization..."
    echo
    
    # Show current settings
    show_current_settings
    echo
    
    # Confirm optimization
    print_warning "This will apply the following optimizations:"
    echo "1. Disable atime on rpool (reduces SSD wear)"
    echo "2. Disable sync on datapool (improves VM performance)"
    echo "3. Configure ZFS ARC to use 50% of RAM"
    echo
    read -p "Continue with optimization? (y/N): " confirm
    
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        print_info "Optimization cancelled"
        exit 0
    fi
    
    echo
    
    # Apply optimizations
    optimize_rpool
    optimize_datapool
    configure_arc_memory
    
    echo
    print_info "ZFS optimization completed successfully!"
    print_warning "Reboot recommended to fully apply all changes"
}

# Check root privileges
if [ "$EUID" -ne 0 ]; then
    print_error "This script must be run as root"
    exit 1
fi

# Check ZFS availability
check_zfs_pools

# Run optimization
optimize_all