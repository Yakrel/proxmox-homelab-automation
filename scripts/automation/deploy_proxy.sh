#!/bin/bash

# Proxy Stack Deployment with Community Alpine Docker Script
# This script deploys Cloudflare tunnels to LXC 100

set -e

# Proxy Stack Configuration
STACK_TYPE="proxy"
LXC_ID=100
HOSTNAME="lxc-proxy-00"
IP_ADDRESS="192.168.1.100/24"
GATEWAY="192.168.1.1"
CPU_CORES=1
RAM_SIZE=512
DISK_SIZE=8

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
print_info "Proxy Stack Deployment"
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
    # Create proxy stack directories
    mkdir -p /datapool/config/cloudflared
    
    # Set permissions (unprivileged LXC mapping: 1000 -> 101000)
    chown -R 101000:101000 /datapool/config/cloudflared 2>/dev/null || true
    
    print_success "Datapool directories created"
else
    print_error "Datapool not accessible"
    exit 1
fi

# Download and deploy Docker Compose files
print_info "Downloading Docker Compose files..."
STACK_DIR="/opt/proxy"

# Create stack directory in LXC
pct exec "$LXC_ID" -- mkdir -p "$STACK_DIR"

# Download compose files to temp directory
wget -q -O "$TEMP_DIR/docker-compose.yml" "$GITHUB_REPO/docker/proxy/docker-compose.yml"
wget -q -O "$TEMP_DIR/.env.example" "$GITHUB_REPO/docker/proxy/.env.example" 2>/dev/null || true

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

# Interactive setup for Cloudflare token
echo ""
print_info "Cloudflare Tunnel Configuration"
print_info "You need a Cloudflare tunnel token to proceed."
print_info "Get your token from: https://one.dash.cloudflare.com/"
echo ""

# Check if we have an existing token
EXISTING_TOKEN=""
if pct exec "$LXC_ID" -- test -f "$STACK_DIR/.env" 2>/dev/null; then
    EXISTING_TOKEN=$(pct exec "$LXC_ID" -- grep "CLOUDFLARED_TOKEN=" "$STACK_DIR/.env" 2>/dev/null | cut -d'=' -f2 || true)
fi

if [ -n "$EXISTING_TOKEN" ] && [ "$EXISTING_TOKEN" != "" ]; then
    print_info "Existing Cloudflare token found (keeping existing)"
    CLOUDFLARED_TOKEN="$EXISTING_TOKEN"
else
    read -p "Enter your Cloudflare tunnel token: " CLOUDFLARED_TOKEN
    if [ -z "$CLOUDFLARED_TOKEN" ]; then
        print_error "Cloudflare tunnel token is required"
        exit 1
    fi
fi

# Create .env file
pct exec "$LXC_ID" -- bash -c "cat > $STACK_DIR/.env << 'EOF'
# Proxy Stack Environment Configuration
# Generated by Proxmox Homelab Automation

# User and Group IDs (for unprivileged LXC)
PUID=1000
PGID=1000

# Timezone
TZ=Europe/Istanbul

# Cloudflare Tunnel Token
CLOUDFLARED_TOKEN=$CLOUDFLARED_TOKEN

# Configuration
CONFIG_ROOT=/datapool/config

# Setup Instructions:
# 1. Configure your tunnel at https://one.dash.cloudflare.com/
# 2. Point your domains to the appropriate internal services
# 3. Tunnel will automatically start and maintain connections
EOF"

print_success "Environment file created"

# Deploy services
print_info "Deploying proxy services..."
pct exec "$LXC_ID" -- bash -c "cd $STACK_DIR && docker compose pull"
pct exec "$LXC_ID" -- bash -c "cd $STACK_DIR && docker compose up -d"

if [ $? -eq 0 ]; then
    print_success "Proxy stack deployed successfully!"
    
    print_info "======================================================"
    print_info "Service Status:"
    pct exec "$LXC_ID" -- bash -c "cd $STACK_DIR && docker compose ps"
    
    print_info "======================================================"
    print_info "Cloudflare Tunnel Information:"
    print_info "- Tunnel is running and connected to Cloudflare"
    print_info "- Configure your domains at: https://one.dash.cloudflare.com/"
    print_info "- Point domains to internal services (e.g., 192.168.1.101:8096 for Jellyfin)"
    print_info "======================================================"
    
    # Clean up
    pct exec "$LXC_ID" -- rm -f "$STACK_DIR/.env.example" 2>/dev/null || true
    
    exit 0
else
    print_error "Failed to deploy proxy stack"
    exit 1
fi