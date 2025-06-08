#!/bin/bash

# Alpine Docker LXC Creation Script
# Uses community-scripts/ProxmoxVE Alpine Docker template
# Source: https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/ct/alpine-docker.sh

set -e

# Color definitions for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to create Alpine LXC with custom parameters
create_alpine_lxc() {
    local lxc_id=$1
    local lxc_name=$2
    local cpu_cores=$3
    local ram_mb=$4
    local disk_gb=$5
    local ip_address=$6

    print_info "Creating Alpine Docker LXC: $lxc_name (ID: $lxc_id)"
    print_info "Specs: ${cpu_cores} cores, ${ram_mb}MB RAM, ${disk_gb}GB disk"
    print_info "IP: $ip_address"

    # Download and execute the Alpine Docker script with custom parameters
    # Override default variables before sourcing the script
    export CT_ID="$lxc_id"
    export CT_NAME="$lxc_name"
    export CPU_CORES="$cpu_cores"
    export RAM_SIZE="$ram_mb"
    export DISK_SIZE="$disk_gb"
    export NET_IP="$ip_address"
    
    # Set non-interactive mode
    export DEBIAN_FRONTEND=noninteractive
    
    print_info "Downloading Alpine Docker LXC creation script..."
    
    # Create temporary script file
    TEMP_SCRIPT=$(mktemp)
    trap 'rm -f "$TEMP_SCRIPT"' EXIT
    
    # Download the script
    wget -q -O "$TEMP_SCRIPT" "https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/ct/alpine-docker.sh"
    
    if [ $? -ne 0 ]; then
        print_error "Failed to download Alpine Docker script"
        return 1
    fi
    
    # Make it executable
    chmod +x "$TEMP_SCRIPT"
    
    print_info "Executing LXC creation script..."
    
    # Execute the script
    bash "$TEMP_SCRIPT"
    
    if [ $? -eq 0 ]; then
        print_info "✓ LXC $lxc_name created successfully!"
        
        # Wait a moment for container to be ready
        sleep 5
        
        return 0
    else
        print_error "Failed to create LXC $lxc_name"
        return 1
    fi
}

# Function to setup mount points
setup_mount_points() {
    local lxc_id=$1
    local mount_source=$2
    local mount_target=$3
    
    print_info "Setting up mount point: $mount_source -> $mount_target"
    
    # Add mount point to LXC config
    pct set "$lxc_id" -mp0 "$mount_source,mp=$mount_target"
    
    if [ $? -eq 0 ]; then
        print_info "✓ Mount point configured successfully"
        return 0
    else
        print_error "Failed to configure mount point"
        return 1
    fi
}

# Function to prepare directory structure with proper permissions
prepare_directories() {
    local stack_type=$1
    local lxc_id=$2
    
    case $stack_type in
        "media")
            prepare_media_directories "$lxc_id"
            ;;
        "proxy")
            prepare_proxy_directories "$lxc_id"
            ;;
        "downloads")
            prepare_downloads_directories "$lxc_id"
            ;;
        "utility")
            prepare_utility_directories "$lxc_id"
            ;;
        "monitoring")
            prepare_monitoring_directories "$lxc_id"
            ;;
        *)
            print_error "Unknown stack type: $stack_type"
            return 1
            ;;
    esac
}

prepare_media_directories() {
    local lxc_id=$1
    print_info "Preparing media stack directories..."
    
    # Configuration variables
    local PUID=1000
    local PGID=1000
    
    # Directory arrays for bulk operations
    local CONFIG_DIRS=("sonarr" "radarr" "bazarr" "jellyfin" "jellyseerr" "qbittorrent" "prowlarr" "flaresolverr" "watchtower-media" "recyclarr" "cleanuperr" "huntarr")
    
    # Create config directories
    for dir in "${CONFIG_DIRS[@]}"; do
        mkdir -p "/datapool/config/$dir"
        chown -R "${PUID}:${PGID}" "/datapool/config/$dir"
    done
    
    # Create media and torrent directories
    mkdir -p /datapool/media/{tv,movies}
    mkdir -p /datapool/media/youtube/{playlists,channels}
    mkdir -p /datapool/torrents/{tv,movies,other}
    
    # Set unified ownership
    chown -R "${PUID}:${PGID}" /datapool/media
    chown -R "${PUID}:${PGID}" /datapool/torrents
}

prepare_proxy_directories() {
    local lxc_id=$1
    print_info "Preparing proxy stack directories..."
    
    # Configuration variables
    local PUID=1000
    local PGID=1000
    
    # Directory arrays for bulk operations
    local CONFIG_DIRS=("cloudflared" "watchtower-proxy")
    
    # Create config directories
    for dir in "${CONFIG_DIRS[@]}"; do
        mkdir -p "/datapool/config/$dir"
        chown -R "${PUID}:${PGID}" "/datapool/config/$dir"
    done
}

prepare_downloads_directories() {
    local lxc_id=$1
    print_info "Preparing downloads stack directories..."
    
    # Configuration variables
    local PUID=1000
    local PGID=1000
    
    # Directory arrays for bulk operations
    local CONFIG_DIRS=("jdownloader2" "metube" "watchtower-downloads")
    
    # Create config directories
    for dir in "${CONFIG_DIRS[@]}"; do
        mkdir -p "/datapool/config/$dir"
        chown -R "${PUID}:${PGID}" "/datapool/config/$dir"
    done
}

prepare_utility_directories() {
    local lxc_id=$1
    print_info "Preparing utility stack directories..."
    
    # Configuration variables
    local PUID=1000
    local PGID=1000
    
    # Directory arrays for bulk operations
    local CONFIG_DIRS=("firefox" "watchtower-utility")
    
    # Create config directories
    for dir in "${CONFIG_DIRS[@]}"; do
        mkdir -p "/datapool/config/$dir"
        chown -R "${PUID}:${PGID}" "/datapool/config/$dir"
    done
}

prepare_monitoring_directories() {
    local lxc_id=$1
    print_info "Preparing monitoring stack directories..."
    
    # Configuration variables
    local PUID=1000
    local PGID=1000
    
    # Directory arrays for bulk operations
    local CONFIG_DIRS=("prometheus" "grafana" "alertmanager" "watchtower-monitoring")
    
    # Create config directories
    for dir in "${CONFIG_DIRS[@]}"; do
        mkdir -p "/datapool/config/$dir"
        chown -R "${PUID}:${PGID}" "/datapool/config/$dir"
    done
    
    # Create monitoring specific directories
    mkdir -p /datapool/config/monitoring/{prometheus,grafana/provisioning,alertmanager}
    chown -R "${PUID}:${PGID}" /datapool/config/monitoring
}

# Main function to create complete LXC setup
create_complete_lxc() {
    local stack_type=$1
    
    case $stack_type in
        "media")
            create_alpine_lxc 101 "lxc-media-01" 4 8192 16 "192.168.1.101/24"
            setup_mount_points 101 "/datapool" "/datapool"
            prepare_directories "media" 101
            ;;
        "proxy")
            create_alpine_lxc 100 "lxc-proxy-01" 1 2048 8 "192.168.1.100/24"
            setup_mount_points 100 "/datapool" "/datapool"
            prepare_directories "proxy" 100
            ;;
        "downloads")
            create_alpine_lxc 102 "lxc-downloads-01" 2 4096 8 "192.168.1.102/24"
            setup_mount_points 102 "/datapool" "/datapool"
            prepare_directories "downloads" 102
            ;;
        "utility")
            create_alpine_lxc 103 "lxc-utility-01" 2 4096 8 "192.168.1.103/24"
            setup_mount_points 103 "/datapool" "/datapool"
            prepare_directories "utility" 103
            ;;
        "monitoring")
            create_alpine_lxc 104 "lxc-monitoring-01" 2 4096 16 "192.168.1.104/24"
            setup_mount_points 104 "/datapool" "/datapool"
            prepare_directories "monitoring" 104
            ;;
        *)
            print_error "Unknown stack type: $stack_type"
            print_info "Available types: media, proxy, downloads, utility, monitoring"
            return 1
            ;;
    esac
}

# Script execution
if [ $# -eq 0 ]; then
    echo "Usage: $0 <stack_type>"
    echo "Available stack types: media, proxy, downloads, utility, monitoring"
    exit 1
fi

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    print_error "This script must be run as root"
    exit 1
fi

STACK_TYPE=$1
print_info "Starting LXC creation for $STACK_TYPE stack..."

create_complete_lxc "$STACK_TYPE"

if [ $? -eq 0 ]; then
    print_info "🎉 $STACK_TYPE stack LXC created successfully!"
    print_info "Next steps:"
    case $STACK_TYPE in
        media) LXC_ID=101;;
        proxy) LXC_ID=100;;
        downloads) LXC_ID=102;;
        utility) LXC_ID=103;;
        monitoring) LXC_ID=104;;
    esac
    print_info "1. Enter the LXC: pct enter $LXC_ID"
    print_info "2. Deploy the stack using the deployment script"
else
    print_error "Failed to create $STACK_TYPE stack LXC"
    exit 1
fi