#!/bin/bash

# Common utility functions for Proxmox Homelab Automation
# This file contains shared functions used across multiple scripts
#
# Error Handling Standard:
# - Functions return 0 for success, 1 for failure
# - Use print_error/print_info for consistent messaging
# - Commands should be checked with proper error handling
# - Use set -e in calling scripts for automatic error exit

# Color definitions (standardized across all scripts)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Global quiet mode variable (set by scripts if needed)
QUIET_MODE=${QUIET_MODE:-false}

# Minimized print functions - only for errors and long operations
print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Only show messages for long operations to prevent terminal hang confusion
print_long_operation() {
    echo "$1"
}

# Legacy function stubs for compatibility - now silent
print_info() { :; }
print_info_quiet() { :; }
print_step() { :; }
print_success() { :; }
print_progress() { :; }

# Check LXC container status
# Returns: running, stopped, or not_exists
# Usage: status=$(check_lxc_status 101)
check_lxc_status() {
    local lxc_id=$1
    
    if pct status "$lxc_id" >/dev/null 2>&1; then
        local status=$(pct status "$lxc_id" | awk '{print $2}')
        echo "$status"
        return 0
    else
        echo "not_exists"
        return 1
    fi
}



# Function to ensure datapool mount exists (homelab simplified)
ensure_datapool_mount() {
    local lxc_id=$1
    
    # Check if mount already exists
    if pct config "$lxc_id" | grep -q "mp=/datapool"; then
        return 0
    fi
    
    pct set "$lxc_id" -mp0 /datapool,mp=/datapool,acl=1
    return 0
}



# Function to ensure proper datapool permissions (unified implementation)
ensure_datapool_permissions() {
    local stack_type=$1
    
    # Check if /datapool is accessible before attempting operations
    if [ ! -d "/datapool" ]; then
        print_warning "Datapool directory not accessible - skipping permission setup"
        return 1
    fi
    
    # Create necessary directories based on stack type
    case $stack_type in
        "proxy")
            mkdir -p /datapool/config/cloudflared
            ;;
        "media")
            mkdir -p /datapool/config/{sonarr,radarr,bazarr,jellyfin,jellyseerr,qbittorrent,prowlarr,flaresolverr,recyclarr,cleanuperr,huntarr}
            mkdir -p /datapool/config/jellyseerr/logs
            mkdir -p /datapool/{torrents,media}/{tv,movies}
            mkdir -p /datapool/torrents/other
            ;;
        "files")
            mkdir -p /datapool/config/{jdownloader2,metube,palmr}
            mkdir -p /datapool/files
            ;;
        "webtools")
            mkdir -p /datapool/config/{homepage,firefox}
            ;;
        "monitoring")
            mkdir -p /datapool/config/monitoring/{prometheus/rules,prometheus/data,grafana,alertmanager}
            mkdir -p /datapool/config/monitoring/grafana/provisioning/{datasources,dashboards}
            ;;
    esac
    
    # Set ownership for all application directories
    if ! chown -R $HOMELAB_HOST_UID:$HOMELAB_HOST_GID /datapool/{config,torrents,media,files} 2>/dev/null; then
        if [ ! -w "/datapool" ]; then
            print_warning "Cannot set datapool permissions - ensure /datapool is properly mounted"
        fi
    fi
}


# Function to check if running as root (standardized check)
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        print_error "This script must be run as root"
        exit 1
    fi
}

# Homelab hardcoded defaults (network configuration is intentionally fixed)
# Network hardcoded for simplicity - all IPs follow 192.168.1.x pattern
# LXC IDs are fixed: proxy=100, media=101, files=102, webtools=103, monitoring=104
HOMELAB_TIMEZONE="Europe/Istanbul"
HOMELAB_NETWORK_BASE="192.168.1"
HOMELAB_PUID="1000"
HOMELAB_PGID="1000"
HOMELAB_HOST_UID="101000"
HOMELAB_HOST_GID="101000"


# Unified environment setup functions

# Simple password input function (homelab optimized)
get_simple_password() {
    local prompt=$1
    local password
    
    printf "%s: " "$prompt" >&2
    read -s password
    echo "" >&2
    
    printf "%s" "$password"
    return 0
}

# Generate random encryption key
generate_encryption_key() {
    local length=${1:-32}
    openssl rand -base64 48 | tr -d "=+/" | cut -c1-${length}
}

# Create common environment content for all stacks (homelab hardcoded)
create_common_env_content() {
    local stack_name=$1
    local custom_content=$2
    
    cat << EOF
# ${stack_name} Stack Environment Variables - Generated $(date)
# Homelab Configuration - Hardcoded for consistency

# Timezone setting
TZ=$HOMELAB_TIMEZONE

# PUID/PGID for file permissions (Docker containers)
PUID=$HOMELAB_PUID
PGID=$HOMELAB_PGID

${custom_content}
EOF
}

# Unified .env file management for stacks (container-side execution)
# Preserves ALL existing values, creates backup, and merges .env.example template
create_stack_env_file() {
    local target_file=$1
    local stack_name=$2
    local custom_content=$3
    
    # Create backup of existing .env file before modifying
    if [ -f "$target_file" ]; then
        local backup_file="${target_file}.backup"
        cp "$target_file" "$backup_file" 2>/dev/null || true
        echo "INFO: Backup created: $(basename "$backup_file")"
        
        # Merge existing values with new template
        local temp_merged=$(mktemp)
        create_common_env_content "$stack_name" "$custom_content" > "$temp_merged"
        
        # Add variables from .env.example template if available
        if [ -f "/tmp/.env.example" ]; then
            # Extract variables from .env.example (skip comments and empty lines)
            while IFS= read -r line; do
                # Skip comments and empty lines
                if [[ "$line" =~ ^[[:space:]]*# ]] || [[ "$line" =~ ^[[:space:]]*$ ]]; then
                    continue
                fi
                
                # Extract variable definitions
                if [[ "$line" =~ ^([^=]+)= ]]; then
                    local var_name="${BASH_REMATCH[1]}"
                    # Add variable to merged file if not already present
                    if ! grep -q "^${var_name}=" "$temp_merged" 2>/dev/null; then
                        echo "$line" >> "$temp_merged"
                    fi
                fi
            done < "/tmp/.env.example"
        fi
        
        # Preserve ALL existing values from old .env
        if [ -f "$target_file" ] && [ -s "$target_file" ]; then
            # Read each line from existing file and preserve values
            while IFS= read -r line; do
                # Skip comments and empty lines
                if [[ "$line" =~ ^[[:space:]]*# ]] || [[ "$line" =~ ^[[:space:]]*$ ]]; then
                    continue
                fi
                
                # Extract variable name
                if [[ "$line" =~ ^([^=]+)= ]]; then
                    local var_name="${BASH_REMATCH[1]}"
                    # Replace the variable in merged file with existing value
                    sed -i "s|^${var_name}=.*|${line}|" "$temp_merged" 2>/dev/null || true
                fi
            done < "$target_file"
        fi
        
        # Move merged content to target
        mv "$temp_merged" "$target_file"
    else
        # No existing file, create new one
        local temp_new=$(mktemp)
        create_common_env_content "$stack_name" "$custom_content" > "$temp_new"
        
        # Add variables from .env.example template if available
        if [ -f "/tmp/.env.example" ]; then
            # Extract variables from .env.example (skip comments and empty lines)
            while IFS= read -r line; do
                # Skip comments and empty lines
                if [[ "$line" =~ ^[[:space:]]*# ]] || [[ "$line" =~ ^[[:space:]]*$ ]]; then
                    continue
                fi
                
                # Extract variable definitions
                if [[ "$line" =~ ^([^=]+)= ]]; then
                    local var_name="${BASH_REMATCH[1]}"
                    # Add variable to new file if not already present
                    if ! grep -q "^${var_name}=" "$temp_new" 2>/dev/null; then
                        echo "$line" >> "$temp_new"
                    fi
                fi
            done < "/tmp/.env.example"
        fi
        
        # Move new content to target
        mv "$temp_new" "$target_file"
    fi
    
    # Set proper permissions
    chmod 600 "$target_file"
}

# Get existing environment variable value
get_existing_env_value() {
    local env_file=$1
    local var_name=$2
    
    if [ -f "$env_file" ]; then
        grep "^${var_name}=" "$env_file" 2>/dev/null | cut -d'=' -f2- | sed "s/^['\"]//; s/['\"]$//"
    fi
}

# ========== UNIFIED LXC CREATION FUNCTIONS ==========

# Stack type to LXC ID mapping
get_stack_lxc_id() {
    local stack_type=$1
    
    case $stack_type in
        "proxy") echo "100" ;;
        "media") echo "101" ;;
        "files") echo "102" ;;
        "webtools") echo "103" ;;
        "monitoring") echo "104" ;;
        "content") echo "105" ;;
        "development") echo "150" ;;
        *) 
            print_error "Unknown stack type: $stack_type"
            return 1
            ;;
    esac
}

# Get stack specifications (CPU, RAM, disk, template) - Homelab optimized and simplified
get_stack_specifications() {
    local stack_type=$1
    
    case $stack_type in
        "proxy")
            echo "cores=1 memory=512 disk=8 template=alpine"
            ;;
        "media")
            echo "cores=2 memory=2048 disk=16 template=alpine"
            ;;
        "files")
            echo "cores=1 memory=1024 disk=10 template=alpine"
            ;;
        "webtools")
            echo "cores=1 memory=1024 disk=10 template=alpine"
            ;;
        "monitoring")
            echo "cores=2 memory=2048 disk=12 template=alpine"
            ;;
        "content")
            echo "cores=2 memory=2048 disk=16 template=alpine"
            ;;
        "development")
            echo "cores=2 memory=2048 disk=16 template=ubuntu"
            ;;
        *)
            print_error "Unknown stack type: $stack_type"
            return 1
            ;;
    esac
}

# Download latest LXC templates (get latest LTS versions dynamically)
# Alpine: Uses latest stable version (e.g., 3.22)
# Ubuntu: Uses latest LTS version only (20.04, 22.04, 24.04, etc.) for long-term support
download_and_prepare_template() {
    local template_type=$1
    
    print_long_operation "Getting latest $template_type template..."
    pveam update >&2
    
    if [ "$template_type" = "alpine" ]; then
        # Get latest Alpine template - always use latest stable
        local template_name=$(pveam available | grep "^system.*alpine.*default.*amd64" | tail -1 | awk '{print $2}')
    else
        # Get latest Ubuntu LTS template - hardcoded LTS versions for reliability
        # Ubuntu LTS releases: every 2 years in April (XX.04 format)
        local UBUNTU_LTS_VERSIONS=("20.04" "22.04" "24.04" "26.04" "28.04")
        local latest_lts=""
        
        # Find the latest available LTS version
        for version in "${UBUNTU_LTS_VERSIONS[@]}"; do
            local template_candidate=$(pveam available | grep "ubuntu-${version}-standard.*amd64" | tail -1 | awk '{print $2}')
            if [ -n "$template_candidate" ]; then
                latest_lts="$template_candidate"
            fi
        done
        
        local template_name="$latest_lts"
        
        if [ -z "$template_name" ]; then
            print_error "No Ubuntu LTS template found! Available templates:" >&2
            pveam available | grep "ubuntu.*standard.*amd64" >&2
            return 1
        fi
    fi
    
    
    local template_path="/datapool/template/cache/$template_name"
    
    # Download if not exists
    if [ ! -f "$template_path" ]; then
        print_long_operation "Downloading $template_name..."
        pveam download datapool "$template_name" >&2
    fi
    
    echo "$template_path"
    return 0
}

# Universal LXC container creation
create_lxc_container() {
    local stack_type=$1
    local lxc_id=$2
    local specs_string=$3
    local template_path=$4
    
    # Parse specifications string
    local cores=$(echo "$specs_string" | grep -o 'cores=[0-9]*' | cut -d'=' -f2)
    local memory=$(echo "$specs_string" | grep -o 'memory=[0-9]*' | cut -d'=' -f2)
    local disk=$(echo "$specs_string" | grep -o 'disk=[0-9]*' | cut -d'=' -f2)
    
    print_long_operation "Creating LXC container $lxc_id..."
    
    # Create the container
    if pct create "$lxc_id" "$template_path" \
        --hostname "${stack_type}" \
        --cores "$cores" \
        --memory "$memory" \
        --rootfs "datapool:${disk}" \
        --net0 "name=eth0,bridge=vmbr0,ip=dhcp" \
        --unprivileged 1 \
        --features nesting=1 \
        --start 1; then
        
        return 0
    else
        print_error "Failed to create LXC container"
        return 1
    fi
}

# Configure container security settings
configure_container_security() {
    local lxc_id=$1
    local template_type=$2
    
    if [ "$template_type" = "alpine" ]; then
        # Alpine-specific security setup
        pct exec "$lxc_id" -- apk update
        pct exec "$lxc_id" -- apk add --no-cache shadow sudo
        
        # Set root password and enable autologin
        echo "root:root" | pct exec "$lxc_id" -- chpasswd
        
        # Disable SSH service completely for security (access via Proxmox web console only)
        # SSH disabled for homelab security - access through Proxmox GUI console with root autologin
        pct exec "$lxc_id" -- rc-update del sshd default 2>/dev/null || true
        pct exec "$lxc_id" -- rc-service sshd stop 2>/dev/null || true
        
        # Setup console autologin for Proxmox console access (no password prompt)
        # Root autologin enables direct access via Proxmox web console
        pct exec "$lxc_id" -- sed -i 's/^tty1::respawn:/tty1::respawn:-\/bin\/login -f root /' /etc/inittab 2>/dev/null || true
        
    else
        # Ubuntu-specific security setup
        # Set root password
        echo "root:root" | pct exec "$lxc_id" -- chpasswd
        
        # Disable SSH service completely for security (access via Proxmox web console only)
        # SSH disabled for homelab security - access through Proxmox GUI console with root autologin
        pct exec "$lxc_id" -- systemctl stop ssh 2>/dev/null || true
        pct exec "$lxc_id" -- systemctl disable ssh 2>/dev/null || true
        
        # Setup console autologin for Proxmox console access (no password prompt)
        # Root autologin enables direct access via Proxmox web console
        pct exec "$lxc_id" -- mkdir -p /etc/systemd/system/console-getty.service.d/
        cat << 'EOF' | pct exec "$lxc_id" -- tee /etc/systemd/system/console-getty.service.d/autologin.conf > /dev/null
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin root --noclear %I $TERM
EOF
        pct exec "$lxc_id" -- systemctl daemon-reload
    fi
    
}

# Setup Alpine Docker container
setup_alpine_docker_container() {
    local lxc_id=$1
    
    print_long_operation "Setting up Docker environment..."
    
    # Install Docker and dependencies
    pct exec "$lxc_id" -- apk update
    pct exec "$lxc_id" -- apk add --no-cache docker docker-compose wget curl git nano
    
    # Add Docker to boot
    pct exec "$lxc_id" -- rc-update add docker default
    pct exec "$lxc_id" -- rc-service docker start
}

# Setup Ubuntu development container
setup_ubuntu_development_container() {
    local lxc_id=$1
    
    print_long_operation "Setting up development environment..."
    
    # Update package list
    pct exec "$lxc_id" -- apt update
    
    # Install basic development tools
    pct exec "$lxc_id" -- apt install -y \
        curl wget git nano vim htop tree \
        build-essential software-properties-common \
        apt-transport-https ca-certificates gnupg lsb-release
    
    # Install Node.js LTS
    pct exec "$lxc_id" -- curl -fsSL https://deb.nodesource.com/setup_lts.x | bash -
    pct exec "$lxc_id" -- apt install -y nodejs
    
    # Create projects directory
    pct exec "$lxc_id" -- mkdir -p /root/projects
    
    # Install Claude Code CLI
    pct exec "$lxc_id" -- npm install -g @anthropic/claude-code
}

# Main container post-creation configuration dispatcher
configure_container_post_creation() {
    local lxc_id=$1
    local stack_type=$2
    local template_type=$3
    
    # Configure security settings
    configure_container_security "$lxc_id" "$template_type"
    
    # Setup environment based on template type
    if [ "$template_type" = "alpine" ]; then
        setup_alpine_docker_container "$lxc_id"
    elif [ "$template_type" = "ubuntu" ]; then
        setup_ubuntu_development_container "$lxc_id"
    fi
    
    # Ensure datapool mount
    ensure_datapool_mount "$lxc_id"
    
    # Set datapool permissions
    ensure_datapool_permissions "$stack_type"
    
}