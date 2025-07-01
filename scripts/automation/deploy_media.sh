#!/bin/bash

# Media Stack Deployment with Community Alpine Docker Script
# This script deploys the media stack (Sonarr, Radarr, Jellyfin, etc.) to LXC 101

set -e

# Media Stack Configuration
STACK_TYPE="media"
LXC_ID=101
HOSTNAME="lxc-media-01"
IP_ADDRESS="192.168.1.101/24"
GATEWAY="192.168.1.1"
CPU_CORES=2
RAM_SIZE=2048
DISK_SIZE=16

# Export variables for community script
export CT_ID="$LXC_ID"
export HN="$HOSTNAME" 
export NET="$IP_ADDRESS"
export GATE="$GATEWAY"
export CORE_COUNT="$CPU_CORES"
export RAM_SIZE="$RAM_SIZE"
export DISK_SIZE="$DISK_SIZE"
export CT_TYPE="1"  # Unprivileged
export BRG="vmbr0"

# GitHub Repository
GITHUB_REPO="https://raw.githubusercontent.com/Yakrel/proxmox-homelab-automation/main"
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    print_error "This script must be run as root"
    exit 1
fi

print_info "======================================================"
print_info "Media Stack Deployment"
print_info "======================================================"
print_info "LXC ID: $LXC_ID"
print_info "Hostname: $HOSTNAME"
print_info "IP Address: $IP_ADDRESS"
print_info "CPU Cores: $CPU_CORES"
print_info "RAM: ${RAM_SIZE}MB"
print_info "Disk: ${DISK_SIZE}GB"
print_info "======================================================"

# Check if LXC already exists
if pct status "$LXC_ID" &>/dev/null; then
    print_warning "LXC $LXC_ID already exists. Updating existing deployment..."
    
    # Ensure LXC is running
    if ! pct status "$LXC_ID" | grep -q "running"; then
        print_info "Starting LXC $LXC_ID..."
        pct start "$LXC_ID"
        sleep 5
    fi
    
    # Skip to Docker deployment
    LXC_EXISTS=true
else
    LXC_EXISTS=false
fi

# Create LXC with community script if it doesn't exist
if [ "$LXC_EXISTS" = false ]; then
    print_info "Creating LXC container with community script..."
    print_warning "When prompted, please select option 1 (Advanced) and then 1 (Default) for automatic configuration"
    
    # Download and run community script
    bash -c "$(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/ct/alpine-docker.sh)"
    
    if ! pct status "$LXC_ID" &>/dev/null; then
        print_error "LXC creation failed!"
        exit 1
    fi
    
    print_success "LXC $LXC_ID created successfully"
    
    # Wait for container to be ready
    print_info "Waiting for container to be ready..."
    sleep 10
    
    # Ensure container is running
    if ! pct status "$LXC_ID" | grep -q "running"; then
        pct start "$LXC_ID"
        sleep 5
    fi
fi

# Setup datapool mount
print_info "Setting up datapool mount..."
if ! pct config "$LXC_ID" | grep -q "mp=/datapool"; then
    pct set "$LXC_ID" -mp0 /datapool,mp=/datapool,acl=1
    print_success "Datapool mount added"
fi

# Setup datapool permissions and directories
print_info "Setting up datapool directories..."
if [ -d "/datapool" ]; then
    # Create media stack directories
    mkdir -p /datapool/config/{sonarr,radarr,bazarr,jellyfin,jellyseerr,qbittorrent,prowlarr,flaresolverr,recyclarr,cleanuperr}
    mkdir -p /datapool/config/jellyseerr/logs
    mkdir -p /datapool/{torrents,media}/{tv,movies}
    mkdir -p /datapool/torrents/other
    
    # Set permissions (unprivileged LXC mapping: 1000 -> 101000)
    chown -R 101000:101000 /datapool/config/{sonarr,radarr,bazarr,jellyfin,jellyseerr,qbittorrent,prowlarr,flaresolverr,recyclarr,cleanuperr} 2>/dev/null || true
    chown -R 101000:101000 /datapool/{torrents,media} 2>/dev/null || true
    
    print_success "Datapool directories created"
else
    print_error "Datapool not accessible"
    exit 1
fi

# Download and deploy Docker Compose files
print_info "Downloading Docker Compose files..."
STACK_DIR="/opt/media"

# Create stack directory in LXC
pct exec "$LXC_ID" -- mkdir -p "$STACK_DIR"

# Download compose files to temp directory
wget -q -O "$TEMP_DIR/docker-compose.yml" "$GITHUB_REPO/docker/media/docker-compose.yml"
wget -q -O "$TEMP_DIR/.env.example" "$GITHUB_REPO/docker/media/.env.example" 2>/dev/null || true

if [ ! -f "$TEMP_DIR/docker-compose.yml" ]; then
    print_error "Failed to download docker-compose.yml"
    exit 1
fi

# Copy files to LXC
pct push "$LXC_ID" "$TEMP_DIR/docker-compose.yml" "$STACK_DIR/docker-compose.yml"
if [ -f "$TEMP_DIR/.env.example" ]; then
    pct push "$LXC_ID" "$TEMP_DIR/.env.example" "$STACK_DIR/.env.example"
fi

print_success "Docker Compose files deployed"

# Setup environment file
print_info "Setting up environment configuration..."
if pct exec "$LXC_ID" -- test -f "$STACK_DIR/.env"; then
    print_info "Backing up existing .env file..."
    pct exec "$LXC_ID" -- cp "$STACK_DIR/.env" "$STACK_DIR/.env.backup"
fi

# Create basic .env file
pct exec "$LXC_ID" -- bash -c "cat > $STACK_DIR/.env << 'EOF'
# Media Stack Environment Configuration
# Generated by Proxmox Homelab Automation

# User and Group IDs (for unprivileged LXC)
PUID=1000
PGID=1000

# Timezone
TZ=Europe/Istanbul

# Paths
CONFIG_ROOT=/datapool/config
MEDIA_ROOT=/datapool/media
TORRENTS_ROOT=/datapool/torrents

# Service URLs
SONARR_URL=http://192.168.1.101:8989
RADARR_URL=http://192.168.1.101:7878
JELLYFIN_URL=http://192.168.1.101:8096
QBITTORRENT_URL=http://192.168.1.101:8080
JELLYSEERR_URL=http://192.168.1.101:5055
PROWLARR_URL=http://192.168.1.101:9696

# API Keys (configure after deployment)
SONARR_API_KEY=
RADARR_API_KEY=
PROWLARR_API_KEY=

# Setup Instructions:
# 1. Services will be available at the URLs above after deployment
# 2. Configure API keys in each service's settings
# 3. Update the API keys in this file for integration between services
# 4. Restart containers: docker compose down && docker compose up -d
EOF"

print_success "Environment file created"

# Deploy services
print_info "Deploying media services..."
pct exec "$LXC_ID" -- bash -c "cd $STACK_DIR && docker compose pull"
pct exec "$LXC_ID" -- bash -c "cd $STACK_DIR && docker compose up -d"

if [ $? -eq 0 ]; then
    print_success "Media stack deployed successfully!"
    
    print_info "======================================================"
    print_info "Service Status:"
    pct exec "$LXC_ID" -- bash -c "cd $STACK_DIR && docker compose ps"
    
    print_info "======================================================"
    print_info "Service URLs:"
    print_info "Sonarr:      http://192.168.1.101:8989"
    print_info "Radarr:      http://192.168.1.101:7878" 
    print_info "Jellyfin:    http://192.168.1.101:8096"
    print_info "qBittorrent: http://192.168.1.101:8080"
    print_info "Jellyseerr:  http://192.168.1.101:5055"
    print_info "Prowlarr:    http://192.168.1.101:9696"
    print_info "======================================================"
    print_info "Next Steps:"
    print_info "1. Configure each service through their web interfaces"
    print_info "2. Set up API keys and inter-service connections"
    print_info "3. Configure download clients and indexers"
    print_info "======================================================"
    
    # Clean up
    pct exec "$LXC_ID" -- rm -f "$STACK_DIR/.env.example" 2>/dev/null || true
    
    exit 0
else
    print_error "Failed to deploy media stack"
    exit 1
fi