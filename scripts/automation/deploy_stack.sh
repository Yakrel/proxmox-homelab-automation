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

# Docker Compose command (use V2 syntax if available)
if command -v "docker" &> /dev/null && docker compose version &> /dev/null; then
    DOCKER_COMPOSE_CMD="docker compose"
else
    DOCKER_COMPOSE_CMD="docker-compose"
fi

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
        
        # Show service URLs
        print_info "Service access URLs:"
        case $stack_type in
            "media")
                print_info "- Sonarr: http://$(hostname -I | awk '{print $1}'):8989"
                print_info "- Radarr: http://$(hostname -I | awk '{print $1}'):7878"
                print_info "- Jellyfin: http://$(hostname -I | awk '{print $1}'):8096"
                print_info "- qBittorrent: http://$(hostname -I | awk '{print $1}'):8080"
                print_info "- Prowlarr: http://$(hostname -I | awk '{print $1}'):9696"
                ;;
            "proxy")
                print_info "- Cloudflared: Check Cloudflare dashboard for tunnel status"
                ;;
            "downloads")
                print_info "- JDownloader2: http://$(hostname -I | awk '{print $1}'):5801"
                print_info "- MeTube: http://$(hostname -I | awk '{print $1}'):8081"
                ;;
            "utility")
                print_info "- Firefox: http://$(hostname -I | awk '{print $1}'):5800"
                ;;
        esac
        
        return 0
    else
        print_warning "No containers appear to be running"
        return 1
    fi
}

# Function to deploy complete stack
deploy_complete_stack() {
    local stack_type=$1
    local lxc_id=$2
    
    print_info "🚀 Starting complete deployment for $stack_type stack (LXC $lxc_id)"
    
    # Determine LXC ID based on stack type if not provided
    if [ -z "$lxc_id" ]; then
        case $stack_type in
            "media") lxc_id=101 ;;
            "proxy") lxc_id=100 ;;
            "downloads") lxc_id=102 ;;
            "utility") lxc_id=103 ;;
            *) 
                print_error "Unknown stack type: $stack_type"
                return 1
                ;;
        esac
    fi
    
    # Check if LXC exists and is running
    if ! pct status "$lxc_id" >/dev/null 2>&1; then
        print_error "LXC $lxc_id does not exist!"
        print_info "Run: ./create_alpine_lxc.sh $stack_type"
        return 1
    fi
    
    # Start LXC if not running
    if [ "$(pct status $lxc_id)" != "status: running" ]; then
        print_info "Starting LXC $lxc_id..."
        pct start "$lxc_id"
        sleep 10
    fi
    
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
    
    # Setup environment inside LXC
    print_info "Setting up environment in LXC..."
    
    # Create .env file if it doesn't exist
    pct exec "$lxc_id" -- sh -c "cd $target_dir && if [ -f .env.example ] && [ ! -f .env ]; then cp .env.example .env; fi"
    
    # Deploy stack inside LXC
    print_info "Deploying stack inside LXC..."
    pct exec "$lxc_id" -- sh -c "cd $target_dir && docker-compose pull && docker-compose up -d"
    
    if [ $? -eq 0 ]; then
        print_info "🎉 $stack_type stack deployed successfully in LXC $lxc_id!"
        
        # Show status
        print_info "Container status:"
        pct exec "$lxc_id" -- sh -c "cd $target_dir && docker-compose ps"
        
        # Show important notes
        print_warning "⚠️  IMPORTANT NOTES:"
        print_info "1. Configure passwords in: $target_dir/.env"
        print_info "2. Access LXC: pct enter $lxc_id"
        print_info "3. Stack location: $target_dir"
        print_info "4. Restart services: cd $target_dir && docker-compose restart"
        
        return 0
    else
        print_error "Failed to deploy $stack_type stack"
        return 1
    fi
}

# Main script execution
if [ $# -eq 0 ]; then
    echo "Usage: $0 <stack_type> [lxc_id]"
    echo "Available stack types: media, proxy, downloads, utility"
    echo "Examples:"
    echo "  $0 media      # Deploy to LXC 101"
    echo "  $0 proxy      # Deploy to LXC 100"
    echo "  $0 downloads  # Deploy to LXC 102"
    echo "  $0 utility    # Deploy to LXC 103"
    exit 1
fi

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    print_error "This script must be run as root"
    exit 1
fi

STACK_TYPE=$1
LXC_ID=$2

print_info "Starting deployment process for $STACK_TYPE stack..."

deploy_complete_stack "$STACK_TYPE" "$LXC_ID"

if [ $? -eq 0 ]; then
    print_info "✅ Deployment completed successfully!"
else
    print_error "❌ Deployment failed!"
    exit 1
fi