#!/bin/bash

# Automated Stack Deployment Script
# Downloads latest docker-compose files from GitHub and deploys them

set -e

# Color definitions for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
GITHUB_REPO="https://raw.githubusercontent.com/Yakrel/proxmox-homelab-automation/main"
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

# Docker Compose command (Alpine Docker template uses V2 syntax)
DOCKER_COMPOSE_CMD="docker compose"

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

print_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Function to download files from GitHub
download_stack_files() {
    local stack_type=$1
    local target_dir=$2
    
    print_step "Downloading $stack_type stack files from GitHub..."
    
    # Create target directory if it doesn't exist
    mkdir -p "$target_dir"
    
    # Download docker-compose.yml
    print_info "Downloading docker-compose.yml..."
    wget -q -O "$target_dir/docker-compose.yml" "$GITHUB_REPO/docker/$stack_type/docker-compose.yml"
    
    if [ $? -ne 0 ]; then
        print_error "Failed to download docker-compose.yml for $stack_type"
        return 1
    fi
    
    # Download .env.example
    print_info "Downloading .env.example..."
    wget -q -O "$target_dir/.env.example" "$GITHUB_REPO/docker/$stack_type/.env.example"
    
    if [ $? -ne 0 ]; then
        print_warning "Failed to download .env.example for $stack_type (may not exist)"
    fi
    
    print_info "✓ Stack files downloaded successfully"
    return 0
}

# Function to setup environment file with interactive setup
setup_env_file() {
    local stack_dir=$1
    local stack_type=$2
    
    print_step "Setting up environment file..."
    
    if [ ! -f "$stack_dir/.env" ]; then
        print_info "Running interactive configuration setup..."
        
        # Download and run interactive setup script
        local interactive_script="$TEMP_DIR/interactive_setup.sh"
        if [ ! -f "$interactive_script" ]; then
            wget -q -O "$interactive_script" "$GITHUB_REPO/scripts/automation/interactive_setup.sh"
            chmod +x "$interactive_script"
        fi
        
        # Run interactive setup for this stack type
        bash "$interactive_script" "$stack_type" "$(dirname $stack_dir)"
        
        if [ -f "$stack_dir/.env" ]; then
            print_info "✓ Environment configuration completed"
        else
            print_error "Failed to create .env file"
            return 1
        fi
    else
        print_info "✓ .env file already exists"
    fi
}

# Function to deploy stack with Docker Compose
deploy_with_compose() {
    local stack_dir=$1
    local stack_type=$2
    
    print_step "Deploying $stack_type stack with Docker Compose..."
    
    cd "$stack_dir"
    
    # Pull latest images
    print_info "Pulling latest Docker images..."
    $DOCKER_COMPOSE_CMD pull
    
    if [ $? -ne 0 ]; then
        print_warning "Some images failed to pull, continuing anyway..."
    fi
    
    # Start services
    print_info "Starting services..."
    $DOCKER_COMPOSE_CMD up -d
    
    if [ $? -eq 0 ]; then
        print_info "✓ $stack_type stack deployed successfully!"
        
        # Show running containers
        print_info "Running containers:"
        $DOCKER_COMPOSE_CMD ps
        
        return 0
    else
        print_error "Failed to deploy $stack_type stack"
        return 1
    fi
}

# Function to verify deployment
verify_deployment() {
    local stack_type=$1
    
    print_step "Verifying $stack_type stack deployment..."
    
    # Define container name patterns for each stack type
    local container_patterns=""
    case $stack_type in
        "media")
            container_patterns="sonarr|radarr|jellyfin|qbittorrent|prowlarr"
            ;;
        "proxy")
            container_patterns="cloudflared"
            ;;
        "downloads")
            container_patterns="jdownloader|metube"
            ;;
        "utility")
            container_patterns="firefox"
            ;;
        "monitoring")
            container_patterns="prometheus|grafana|alertmanager"
            ;;
        *)
            print_error "Unknown stack type: $stack_type"
            return 1
            ;;
    esac
    
    # Check if containers are running
    local running_containers=$(docker ps --format "table {{.Names}}\t{{.Status}}" | grep -E "(${container_patterns})" | wc -l)
    
    if [ "$running_containers" -gt 0 ]; then
        print_info "✓ Found $running_containers running containers"
        
        
        return 0
    else
        print_warning "No containers appear to be running"
        return 1
    fi
}

# Function to setup stack environment interactively
setup_stack_env() {
    local stack_type=$1
    local lxc_id=$2
    local target_dir=$3
    
    print_step "Interactive configuration for $stack_type stack..."
    
    case $stack_type in
        "proxy")
            setup_proxy_env "$lxc_id" "$target_dir"
            ;;
        "media")
            setup_media_env "$lxc_id" "$target_dir"
            ;;
        "downloads")
            setup_downloads_env "$lxc_id" "$target_dir"
            ;;
        "utility")
            setup_utility_env "$lxc_id" "$target_dir"
            ;;
        "monitoring")
            setup_monitoring_env "$lxc_id" "$target_dir"
            ;;
        *)
            # Default: just copy .env.example to .env
            pct exec "$lxc_id" -- sh -c "cd $target_dir && if [ -f .env.example ]; then cp .env.example .env; fi"
            ;;
    esac
}

# Function to setup proxy stack environment
setup_proxy_env() {
    local lxc_id=$1
    local target_dir=$2
    
    echo
    print_info "🔧 Cloudflare Tunnel Configuration"
    echo "You need to create a Cloudflare tunnel first:"
    echo "1. Go to https://one.dash.cloudflare.com/"
    echo "2. Navigate to 'Networks' > 'Tunnels'"
    echo "3. Create a new tunnel"
    echo "4. Copy the tunnel token"
    echo
    
    read -p "Enter your Cloudflare tunnel token: " tunnel_token
    while [ -z "$tunnel_token" ]; do
        print_error "Tunnel token is required!"
        read -p "Enter your Cloudflare tunnel token: " tunnel_token
    done
    
    read -p "Enter timezone [Europe/Istanbul]: " timezone
    timezone=${timezone:-Europe/Istanbul}
    
    # Create .env file in LXC
    pct exec "$lxc_id" -- sh -c "cat > $target_dir/.env << EOF
# Proxy Stack Environment Variables
CLOUDFLARED_TOKEN=$tunnel_token
TZ=$timezone
PUID=1000
PGID=1000
EOF"
    
    print_info "✓ Proxy environment configured"
}

# Function to setup media stack environment  
setup_media_env() {
    local lxc_id=$1
    local target_dir=$2
    
    echo
    print_info "🎬 Media Stack Configuration"
    
    read -p "Enter timezone [Europe/Istanbul]: " timezone
    timezone=${timezone:-Europe/Istanbul}
    
    # Create .env file in LXC
    pct exec "$lxc_id" -- sh -c "cat > $target_dir/.env << EOF
# Media Stack Environment Variables
TZ=$timezone
PUID=1000
PGID=1000
EOF"
    
    print_info "✓ Media environment configured"
}

# Function to setup downloads stack environment
setup_downloads_env() {
    local lxc_id=$1
    local target_dir=$2
    
    echo
    print_info "⬇️ Downloads Stack Configuration"
    
    read -p "Enter JDownloader VNC password: " jdownloader_password
    while [ -z "$jdownloader_password" ]; do
        print_error "JDownloader VNC password is required!"
        read -p "Enter JDownloader VNC password: " jdownloader_password
    done
    
    read -p "Enter timezone [Europe/Istanbul]: " timezone
    timezone=${timezone:-Europe/Istanbul}
    
    # Create .env file in LXC
    pct exec "$lxc_id" -- sh -c "cat > $target_dir/.env << EOF
# Downloads Stack Environment Variables
JDOWNLOADER_VNC_PASSWORD=$jdownloader_password
TZ=$timezone
PUID=1000
PGID=1000
EOF"
    
    print_info "✓ Downloads environment configured"
}

# Function to setup utility stack environment
setup_utility_env() {
    local lxc_id=$1
    local target_dir=$2
    
    echo
    print_info "🛠️ Utility Stack Configuration"
    
    read -p "Enter Firefox VNC password: " vnc_password
    while [ -z "$vnc_password" ]; do
        print_error "VNC password is required!"
        read -p "Enter Firefox VNC password: " vnc_password
    done
    
    read -p "Enter timezone [Europe/Istanbul]: " timezone
    timezone=${timezone:-Europe/Istanbul}
    
    # Create .env file in LXC
    pct exec "$lxc_id" -- sh -c "cat > $target_dir/.env << EOF
# Utility Stack Environment Variables
FIREFOX_VNC_PASSWORD=$vnc_password
TZ=$timezone
PUID=1000
PGID=1000
EOF"
    
    print_info "✓ Utility environment configured"
}

# Function to setup monitoring stack environment
setup_monitoring_env() {
    local lxc_id=$1
    local target_dir=$2
    
    echo
    print_info "📊 Monitoring Stack Configuration"
    echo "You'll need Proxmox credentials for monitoring..."
    echo
    
    read -p "Enter Grafana admin password: " grafana_password
    while [ -z "$grafana_password" ]; do
        print_error "Grafana password is required!"
        read -p "Enter Grafana admin password: " grafana_password
    done
    
    read -p "Enter Proxmox server IP [$(ip route get 1 | sed -n 's/.*src \([0-9.]*\).*/\1/p')]: " proxmox_ip
    proxmox_ip=${proxmox_ip:-$(ip route get 1 | sed -n 's/.*src \([0-9.]*\).*/\1/p')}
    
    read -p "Enter Proxmox monitoring user [monitoring@pve]: " pve_user
    pve_user=${pve_user:-monitoring@pve}
    
    read -s -p "Enter Proxmox monitoring password: " pve_password
    echo
    while [ -z "$pve_password" ]; do
        print_error "Proxmox password is required!"
        read -s -p "Enter Proxmox monitoring password: " pve_password
        echo
    done
    
    read -p "Enter timezone [Europe/Istanbul]: " timezone
    timezone=${timezone:-Europe/Istanbul}
    
    # Create .env file in LXC
    pct exec "$lxc_id" -- sh -c "cat > $target_dir/.env << EOF
# Monitoring Stack Environment Variables
GRAFANA_ADMIN_PASSWORD=$grafana_password
PVE_USER=$pve_user
PVE_PASSWORD=$pve_password
PVE_URL=https://$proxmox_ip:8006
TZ=$timezone
PUID=1000
PGID=1000
EOF"
    
    print_info "✓ Monitoring environment configured"
}

# Function to update existing stack
update_existing_stack() {
    local stack_type=$1
    local lxc_id=$2
    local target_dir="/opt/$stack_type-stack"
    
    print_info "🔄 Updating existing $stack_type stack in LXC $lxc_id"
    
    # Check if LXC exists and is running
    if ! pct status "$lxc_id" &>/dev/null; then
        print_error "LXC $lxc_id does not exist!"
        return 1
    fi
    
    # Start LXC if not running
    if pct status "$lxc_id" | grep -q "stopped"; then
        print_info "Starting LXC $lxc_id..."
        pct start "$lxc_id"
        sleep 10
    fi
    
    # Check if stack directory exists
    if ! pct exec "$lxc_id" -- test -d "$target_dir"; then
        print_warning "Stack directory $target_dir doesn't exist, creating new deployment..."
        deploy_complete_stack "$stack_type" "$lxc_id"
        return $?
    fi
    
    # Backup existing .env file
    print_info "Backing up existing environment file..."
    pct exec "$lxc_id" -- sh -c "cd $target_dir && if [ -f .env ]; then cp .env .env.backup; fi"
    
    # Download latest stack files
    download_stack_files "$stack_type" "$TEMP_DIR/$stack_type"
    
    # Copy updated docker-compose.yml to LXC
    print_info "Updating docker-compose.yml..."
    pct push "$lxc_id" "$TEMP_DIR/$stack_type/docker-compose.yml" "$target_dir/docker-compose.yml"
    
    # Restore .env file if backup exists
    pct exec "$lxc_id" -- sh -c "cd $target_dir && if [ -f .env.backup ]; then mv .env.backup .env; fi"
    
    # Update stack with latest compose file
    print_info "Updating services with latest configuration..."
    pct exec "$lxc_id" -- sh -c "cd $target_dir && docker compose pull && docker compose up -d"
    
    if [ $? -eq 0 ]; then
        print_info "✅ $stack_type stack updated successfully!"
        
        # Show status
        print_info "Container status:"
        pct exec "$lxc_id" -- sh -c "cd $target_dir && docker compose ps"
        
        return 0
    else
        print_error "Failed to update $stack_type stack"
        return 1
    fi
}

# Function to deploy complete stack
deploy_complete_stack() {
    local stack_type=$1
    local lxc_id=$2
    
    print_info "🚀 Starting complete deployment for $stack_type stack (LXC $lxc_id)"
    
    
    # Wait a moment for LXC to be fully ready
    sleep 5
    
    # Set target directory inside LXC
    local target_dir="/opt/$stack_type-stack"
    
    # Create directory structure inside LXC
    print_info "Creating directory structure in LXC..."
    pct exec "$lxc_id" -- mkdir -p "$target_dir"
    
    # Download stack files to temp directory
    download_stack_files "$stack_type" "$TEMP_DIR/$stack_type"
    
    # Copy files to LXC
    print_info "Copying files to LXC..."
    pct push "$lxc_id" "$TEMP_DIR/$stack_type/docker-compose.yml" "$target_dir/docker-compose.yml"
    
    if [ -f "$TEMP_DIR/$stack_type/.env.example" ]; then
        pct push "$lxc_id" "$TEMP_DIR/$stack_type/.env.example" "$target_dir/.env.example"
    fi
    
    # Setup environment inside LXC with interactive configuration
    print_info "Setting up environment in LXC..."
    
    # Interactive configuration for the stack
    setup_stack_env "$stack_type" "$lxc_id" "$target_dir"
    
    # Deploy stack inside LXC
    print_info "Deploying stack inside LXC..."
    
    # Deploy with docker compose (Alpine Docker template uses V2 syntax)
    pct exec "$lxc_id" -- sh -c "cd $target_dir && docker compose pull && docker compose up -d"
    
    if [ $? -eq 0 ]; then
        print_info "🎉 $stack_type stack deployed successfully in LXC $lxc_id!"
        
        # Show status
        print_info "Container status:"
        pct exec "$lxc_id" -- sh -c "cd $target_dir && docker compose ps"
        
        # Show important notes
        print_warning "⚠️  IMPORTANT NOTES:"
        print_info "1. Access LXC: pct enter $lxc_id"
        print_info "2. Stack location: $target_dir"
        print_info "3. Restart services: cd $target_dir && docker compose restart"
        
        return 0
    else
        print_error "Failed to deploy $stack_type stack"
        return 1
    fi
}

# Enhanced input validation
if [ $# -eq 0 ] || [ $# -gt 2 ]; then
    print_info "Usage: $0 <stack_type> [lxc_id]"
    echo "Available stack types: media, proxy, downloads, utility, monitoring"
    echo "Examples:"
    echo "  $0 media      # Deploy to LXC 101"
    echo "  $0 proxy      # Deploy to LXC 100"
    echo "  $0 downloads  # Deploy to LXC 102"
    echo "  $0 utility    # Deploy to LXC 103"
    echo "  $0 monitoring # Deploy to LXC 104"
    exit 1
fi

# Validate stack type
case "$1" in
    media|proxy|downloads|utility|monitoring)
        # Valid stack type
        ;;
    *)
        print_error "Invalid stack type: $1"
        print_error "Available stack types: media, proxy, downloads, utility, monitoring"
        exit 1
        ;;
esac

# Validate LXC ID if provided
if [ $# -eq 2 ]; then
    if ! [[ "$2" =~ ^[0-9]+$ ]] || [ "$2" -lt 100 ] || [ "$2" -gt 999 ]; then
        print_error "Invalid LXC ID: $2 (must be a number between 100-999)"
        exit 1
    fi
fi

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    print_error "This script must be run as root"
    exit 1
fi

STACK_TYPE=$1
LXC_ID=$2

print_info "Starting deployment process for $STACK_TYPE stack..."

# Determine LXC ID if not provided
if [ -z "$LXC_ID" ]; then
    case $STACK_TYPE in
        "media") LXC_ID=101 ;;
        "proxy") LXC_ID=100 ;;
        "downloads") LXC_ID=102 ;;
        "utility") LXC_ID=103 ;;
        "monitoring") LXC_ID=104 ;;
        *) 
            print_error "Unknown stack type: $STACK_TYPE"
            exit 1
            ;;
    esac
fi

# Check if LXC exists and has existing stack
if pct status "$LXC_ID" &>/dev/null && pct exec "$LXC_ID" -- test -d "/opt/$STACK_TYPE-stack"; then
    print_info "🔍 Found existing $STACK_TYPE stack in LXC $LXC_ID - updating compose files..."
    update_existing_stack "$STACK_TYPE" "$LXC_ID"
else
    deploy_complete_stack "$STACK_TYPE" "$LXC_ID"
fi

if [ $? -eq 0 ]; then
    print_info "✅ Deployment completed successfully!"
else
    print_error "❌ Deployment failed!"
    exit 1
fi