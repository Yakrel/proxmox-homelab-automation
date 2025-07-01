#!/bin/bash

# Webtools Stack Deployment with Community Alpine Docker Script
# This script deploys Homepage dashboard and Firefox to LXC 103

set -e

# Webtools Stack Configuration
STACK_TYPE="webtools"
LXC_ID=103
HOSTNAME="lxc-webtools-03"
IP_ADDRESS="192.168.1.103/24"
GATEWAY="192.168.1.1"
CPU_CORES=1
RAM_SIZE=1024
DISK_SIZE=10

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
print_info "Webtools Stack Deployment"
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
    # Create webtools stack directories
    mkdir -p /datapool/config/{homepage,firefox}
    
    # Set permissions (unprivileged LXC mapping: 1000 -> 101000)
    chown -R 101000:101000 /datapool/config/{homepage,firefox} 2>/dev/null || true
    
    print_success "Datapool directories created"
else
    print_error "Datapool not accessible"
    exit 1
fi

# Download and deploy Docker Compose files
print_info "Downloading Docker Compose files..."
STACK_DIR="/opt/webtools"

# Create stack directory in LXC
pct exec "$LXC_ID" -- mkdir -p "$STACK_DIR"

# Download compose files to temp directory
wget -q -O "$TEMP_DIR/docker-compose.yml" "$GITHUB_REPO/docker/webtools/docker-compose.yml"
wget -q -O "$TEMP_DIR/.env.example" "$GITHUB_REPO/docker/webtools/.env.example" 2>/dev/null || true

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

# Deploy Homepage configuration files
print_info "Deploying Homepage configurations..."
pct exec "$LXC_ID" -- mkdir -p /datapool/config/homepage

# Download and deploy each config file
config_files=("bookmarks.yaml" "docker.yaml" "services.yaml" "settings.yaml" "widgets.yaml")
success_count=0

for config_file in "${config_files[@]}"; do
    temp_file="$TEMP_DIR/$config_file"
    target_path="/datapool/config/homepage/$config_file"
    
    if wget -q -O "$temp_file" "$GITHUB_REPO/config/homepage/$config_file" 2>/dev/null; then
        if pct push "$LXC_ID" "$temp_file" "$target_path" 2>/dev/null; then
            success_count=$((success_count + 1))
        else
            print_warning "Failed to deploy $config_file"
        fi
    else
        print_warning "Failed to download $config_file"
    fi
done

# Set proper permissions for homepage configs
if [ -w "/datapool/config" ]; then
    chown -R 101000:101000 /datapool/config/homepage 2>/dev/null || true
    chmod -R 644 /datapool/config/homepage/*.yaml 2>/dev/null || true
fi

if [ $success_count -eq ${#config_files[@]} ]; then
    print_success "Homepage configurations deployed successfully"
elif [ $success_count -gt 0 ]; then
    print_warning "Partially deployed Homepage configs ($success_count/${#config_files[@]} files)"
else
    print_error "Failed to deploy Homepage configuration files"
fi

# Setup environment file
print_info "Setting up environment configuration..."
if pct exec "$LXC_ID" -- test -f "$STACK_DIR/.env"; then
    print_info "Backing up existing .env file..."
    pct exec "$LXC_ID" -- cp "$STACK_DIR/.env" "$STACK_DIR/.env.backup"
fi

# Interactive setup for VNC password
echo ""
print_info "VNC Password Configuration"
print_info "Setting up VNC password for Firefox remote access"
echo ""

FIREFOX_VNC_PASSWORD=""
if pct exec "$LXC_ID" -- test -f "$STACK_DIR/.env" 2>/dev/null; then
    FIREFOX_VNC_PASSWORD=$(pct exec "$LXC_ID" -- grep "FIREFOX_VNC_PASSWORD=" "$STACK_DIR/.env" 2>/dev/null | cut -d'=' -f2 || true)
fi

if [ -z "$FIREFOX_VNC_PASSWORD" ]; then
    read -s -p "Enter VNC password for Firefox remote access: " FIREFOX_VNC_PASSWORD
    echo ""
    if [ -z "$FIREFOX_VNC_PASSWORD" ]; then
        print_error "VNC password is required"
        exit 1
    fi
fi

# Create .env file
pct exec "$LXC_ID" -- bash -c "cat > $STACK_DIR/.env << 'EOF'
# Webtools Stack Environment Configuration
# Generated by Proxmox Homelab Automation

# User and Group IDs (for unprivileged LXC)
PUID=1000
PGID=1000

# Timezone
TZ=Europe/Istanbul

# Paths
CONFIG_ROOT=/datapool/config

# VNC Configuration
FIREFOX_VNC_PASSWORD=$FIREFOX_VNC_PASSWORD

# Service URLs
HOMEPAGE_URL=http://192.168.1.103:3000
FIREFOX_URL=http://192.168.1.103:5800

# Setup Instructions:
# 1. Homepage Dashboard: http://192.168.1.103:3000
# 2. Firefox VNC: http://192.168.1.103:5800
# 3. Homepage automatically shows all your homelab services
# 4. Use Firefox for secure web browsing through VNC
EOF"

print_success "Environment file created"

# Deploy services
print_info "Deploying webtools services..."
pct exec "$LXC_ID" -- bash -c "cd $STACK_DIR && docker compose pull"
pct exec "$LXC_ID" -- bash -c "cd $STACK_DIR && docker compose up -d"

if [ $? -eq 0 ]; then
    print_success "Webtools stack deployed successfully!"
    
    print_info "======================================================"
    print_info "Service Status:"
    pct exec "$LXC_ID" -- bash -c "cd $STACK_DIR && docker compose ps"
    
    print_info "======================================================"
    print_info "Service URLs:"
    print_info "Homepage Dashboard: http://192.168.1.103:3000"
    print_info "Firefox VNC:        http://192.168.1.103:5800"
    print_info "======================================================"
    print_info "Next Steps:"
    print_info "1. Access the Homepage dashboard for an overview of all services"
    print_info "2. Use Firefox VNC for secure web browsing"
    print_info "3. Homepage will automatically display your homelab services"
    print_info "4. Customize Homepage configuration files in /datapool/config/homepage/"
    print_info "======================================================"
    
    # Clean up
    pct exec "$LXC_ID" -- rm -f "$STACK_DIR/.env.example" 2>/dev/null || true
    
    exit 0
else
    print_error "Failed to deploy webtools stack"
    exit 1
fi