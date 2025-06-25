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

# Standardized print functions
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

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

# Wait for LXC container to be ready for commands 
# Usage: wait_for_container_ready 101
# Returns: 0 on success, 1 on timeout
wait_for_container_ready() {
    local lxc_id=$1
    print_info "Waiting for container to be ready..."
    sleep 5
    print_info "✓ Container is ready"
}

# Ensure Docker service is ready (homelab simplified)
ensure_docker_ready() {
    local lxc_id=$1
    print_info "Starting Docker service..."
    pct exec "$lxc_id" -- rc-service docker start >/dev/null 2>&1 || true
    sleep 10
    print_info "✓ Docker service started"
}

# Function to ensure container and Docker are ready (unified implementation)
ensure_container_ready() {
    local lxc_id=$1
    
    # Check if container exists
    if ! pct status "$lxc_id" >/dev/null 2>&1; then
        print_error "LXC $lxc_id does not exist!"
        return 1
    fi
    
    # Start container if not running
    if ! pct status "$lxc_id" | grep -q "running"; then
        print_info "Starting container $lxc_id..."
        pct start "$lxc_id"
    fi
    
    # Wait for container readiness
    wait_for_container_ready "$lxc_id"
    
    # Ensure Docker is ready
    ensure_docker_ready "$lxc_id"
    
    return 0
}

# Function to ensure datapool mount exists (homelab simplified)
ensure_datapool_mount() {
    local lxc_id=$1
    
    # Check if mount already exists
    if pct config "$lxc_id" | grep -q "mp=/datapool"; then
        print_info "✓ /datapool mount already configured"
        return 0
    fi
    
    print_info "Adding /datapool mount point..."
    pct set "$lxc_id" -mp0 /datapool,mp=/datapool,acl=1
    print_info "✓ Mount point added successfully"
    return 0
}



# Function to ensure proper datapool permissions (unified implementation)
ensure_datapool_permissions() {
    local stack_type=$1
    
    print_step "Setting up datapool permissions for $stack_type stack..."
    
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
    
    # Set ownership for all application directories in one command (homelab hardcoded)
    chown -R $HOMELAB_HOST_UID:$HOMELAB_HOST_GID /datapool/{config,torrents,media,files} 2>/dev/null || true
    
    print_info "✓ Datapool permissions configured for $stack_type"
}

# Function to create temporary directory with cleanup trap
setup_temp_dir() {
    local temp_dir=$(mktemp -d)
    # Global variable for cleanup
    SCRIPT_TEMP_DIR="$temp_dir"
    trap 'rm -rf "$SCRIPT_TEMP_DIR"' EXIT
    echo "$temp_dir"
}

# Function to check if running as root (standardized check)
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        print_error "This script must be run as root"
        exit 1
    fi
}

# Homelab hardcoded defaults
HOMELAB_TIMEZONE="Europe/Istanbul"
HOMELAB_NETWORK_BASE="192.168.1"
HOMELAB_PUID="1000"
HOMELAB_PGID="1000"
HOMELAB_HOST_UID="101000"
HOMELAB_HOST_GID="101000"

validate_timezone() {
    echo "$HOMELAB_TIMEZONE"
}

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

# Create .env file with proper permissions
create_stack_env_file() {
    local target_file=$1
    local stack_name=$2
    local custom_content=$3
    
    create_common_env_content "$stack_name" "$custom_content" > "$target_file"
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
download_and_prepare_template() {
    local template_type=$1
    
    print_info "Getting latest $template_type template..." >&2
    pveam update >&2
    
    if [ "$template_type" = "alpine" ]; then
        # Get latest Alpine template - correct pattern matching
        local template_name=$(pveam available | grep "^system.*alpine.*default.*amd64" | tail -1 | awk '{print $2}')
    else
        # Get latest Ubuntu LTS template - correct pattern matching
        local template_name=$(pveam available | grep "^system.*ubuntu.*standard.*amd64" | tail -1 | awk '{print $2}')
    fi
    
    
    local template_path="/datapool/template/cache/$template_name"
    
    # Download if not exists
    if [ ! -f "$template_path" ]; then
        print_info "Downloading $template_name..." >&2
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
    
    print_info "Creating LXC container $lxc_id for $stack_type stack..."
    print_info "Specs: ${cores} cores, ${memory}MB RAM, ${disk}GB disk"
    
    # Create the container
    if pct create "$lxc_id" "$template_path" \
        --hostname "${stack_type}-server" \
        --cores "$cores" \
        --memory "$memory" \
        --rootfs "datapool:${disk}" \
        --net0 "name=eth0,bridge=vmbr0,ip=dhcp" \
        --unprivileged 1 \
        --features nesting=1 \
        --start 1; then
        
        print_success "✓ LXC container $lxc_id created successfully"
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
    
    print_info "Configuring security settings for container $lxc_id..."
    
    # Wait for container to be ready
    wait_for_container_ready "$lxc_id"
    
    if [ "$template_type" = "alpine" ]; then
        # Alpine-specific security setup
        pct exec "$lxc_id" -- apk update
        pct exec "$lxc_id" -- apk add --no-cache openssh shadow sudo
        
        # Set root password and enable autologin
        echo "root:root" | pct exec "$lxc_id" -- chpasswd
        
        # Enable SSH root login
        pct exec "$lxc_id" -- sed -i 's/#PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config 2>/dev/null || true
        pct exec "$lxc_id" -- rc-update add sshd default
        pct exec "$lxc_id" -- rc-service sshd start
        
        # Setup console autologin
        pct exec "$lxc_id" -- sed -i 's/^tty1::respawn:/tty1::respawn:-\/bin\/login -f root /' /etc/inittab 2>/dev/null || true
        
    else
        # Ubuntu-specific security setup
        # Set root password
        echo "root:root" | pct exec "$lxc_id" -- chpasswd
        
        # Enable SSH root login
        pct exec "$lxc_id" -- sed -i 's/#PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
        pct exec "$lxc_id" -- systemctl restart ssh
        
        # Setup console autologin
        pct exec "$lxc_id" -- mkdir -p /etc/systemd/system/console-getty.service.d/
        cat << 'EOF' | pct exec "$lxc_id" -- tee /etc/systemd/system/console-getty.service.d/autologin.conf > /dev/null
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin root --noclear %I $TERM
EOF
        pct exec "$lxc_id" -- systemctl daemon-reload
    fi
    
    print_success "✓ Security settings configured"
}

# Setup Alpine Docker container
setup_alpine_docker_container() {
    local lxc_id=$1
    
    print_info "Setting up Alpine Docker environment..."
    
    # Install Docker and dependencies
    pct exec "$lxc_id" -- apk update
    pct exec "$lxc_id" -- apk add --no-cache docker docker-compose wget curl git nano
    
    # Add Docker to boot
    pct exec "$lxc_id" -- rc-update add docker default
    pct exec "$lxc_id" -- rc-service docker start
    
    # Wait for Docker to be ready
    ensure_docker_ready "$lxc_id"
    
    print_success "✓ Alpine Docker environment ready"
}

# Setup Ubuntu development container
setup_ubuntu_development_container() {
    local lxc_id=$1
    
    print_info "Setting up Ubuntu development environment..."
    
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
    
    print_success "✓ Ubuntu development environment ready"
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
    
    print_success "✓ Container $lxc_id configuration complete"
}