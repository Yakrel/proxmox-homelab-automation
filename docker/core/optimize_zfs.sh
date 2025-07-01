#!/bin/bash

# ZFS Performance Optimization Script
# Optimizes ZFS pools for better performance in homelab environments

set -e

# Simple utility functions
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "ERROR: This script must be run as root"
        exit 1
    fi
}

# Function to check if ZFS pools exist
check_zfs_pools() {
    if ! command -v zfs >/dev/null 2>&1; then
        echo "ERROR: ZFS not found on this system"
        exit 1
    fi
    
    if ! zpool list >/dev/null 2>&1; then
        echo "ERROR: No ZFS pools found"
        exit 1
    fi
}

# Function to optimize rpool (disable atime)
optimize_rpool() {
    if zpool list rpool >/dev/null 2>&1; then
        echo "Optimizing rpool (disabling atime)..."
        zfs set atime=off rpool
        echo "✓ rpool atime disabled"
    else
        echo "WARNING: rpool not found, skipping atime optimization"
    fi
}

# Function to optimize datapool (disable sync)
optimize_datapool() {
    if zpool list datapool >/dev/null 2>&1; then
        echo "Optimizing datapool (disabling sync)..."
        zfs set sync=disabled datapool
        echo "✓ datapool sync disabled"
    else
        echo "WARNING: datapool not found, skipping sync optimization"
    fi
}

# Function to configure ZFS ARC memory
configure_arc_memory() {
    local total_ram_gb=$(free -g | awk 'NR==2{print $2}')
    local arc_max_gb=$((total_ram_gb / 2))
    local arc_max_bytes=$((arc_max_gb * 1024 * 1024 * 1024))
    
    echo "Configuring ZFS ARC memory (${arc_max_gb}GB max)..."
    
    # Create modprobe configuration
    echo "options zfs zfs_arc_max=${arc_max_bytes}" > /etc/modprobe.d/zfs.conf
    
    # Update initramfs
    update-initramfs -u -k all >/dev/null 2>&1
    
    echo "✓ ZFS ARC configured for ${arc_max_gb}GB"
    echo "WARNING: Reboot required for ARC settings to take effect"
}

# Function to show current ZFS settings
show_current_settings() {
    echo "Current ZFS settings:"
    
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
    echo "Starting ZFS performance optimization..."
    echo
    
    # Show current settings
    show_current_settings
    echo
    
    # Confirm optimization
    echo "This will apply the following optimizations:"
    echo "1. Disable atime on rpool (reduces SSD wear)"
    echo "2. Disable sync on datapool (improves VM performance)"
    echo "3. Configure ZFS ARC to use 50% of RAM"
    echo
    read -p "Continue with optimization? (y/N): " confirm
    
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        echo "Optimization cancelled"
        exit 0
    fi
    
    echo
    
    # Apply optimizations
    optimize_rpool
    optimize_datapool
    configure_arc_memory
    
    echo
    echo "ZFS optimization completed successfully!"
    echo "WARNING: Reboot recommended to fully apply all changes"
}

# Check root privileges
check_root

# Check ZFS availability
check_zfs_pools

# Run optimization
optimize_all