#!/bin/bash

# Automated Stack Deployment Script - Optimized Version
# Downloads latest docker-compose files from GitHub and deploys them

set -e

# Source common functions
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
source "$SCRIPT_DIR/../common/functions.sh"

# Configuration
GITHUB_REPO="https://raw.githubusercontent.com/Yakrel/proxmox-homelab-automation/main"
DOCKER_COMPOSE_CMD="docker compose"

# Function to download stack files from GitHub
download_stack_files() {
    local stack_type=$1
    local target_dir=$2
    
    print_step "Downloading $stack_type stack files..."
    
    mkdir -p "$target_dir"
    
    # Download docker-compose.yml
    if ! safe_download "$GITHUB_REPO/docker/$stack_type/docker-compose.yml" "$target_dir/docker-compose.yml"; then
        print_error "Failed to download docker-compose.yml for $stack_type"
        return 1
    fi
    
    # Download .env.example (optional)
    safe_download "$GITHUB_REPO/docker/$stack_type/.env.example" "$target_dir/.env.example" || \
        print_warning ".env.example not found for $stack_type (optional)"
    
    print_info "✓ Stack files downloaded successfully"
    return 0
}

# Function to setup environment file with minimal interaction
setup_env_file() {
    local stack_dir=$1
    local stack_type=$2
    
    print_step "Setting up environment file..."
    
    # Create basic .env if not exists
    if [ ! -f "$stack_dir/.env" ]; then
        cat > "$stack_dir/.env" << EOF
# Environment file for $stack_type stack
# Generated automatically - edit as needed

# Common settings
TZ=Europe/Istanbul
PUID=1000
PGID=1000
UMASK=002

EOF
        
        # Stack-specific environment variables
        case "$stack_type" in
            "proxy")
                echo "CLOUDFLARED_TOKEN=your_cloudflare_tunnel_token_here" >> "$stack_dir/.env"
                ;;
            "downloads")
                echo "JDOWNLOADER_VNC_PASSWORD=changeme123" >> "$stack_dir/.env"
                ;;
            "utility")
                echo "FIREFOX_VNC_PASSWORD=changeme123" >> "$stack_dir/.env"
                ;;
            "monitoring")
                echo "GRAFANA_ADMIN_PASSWORD=changeme123" >> "$stack_dir/.env"
                echo "PVE_USER=monitoring@pve" >> "$stack_dir/.env"
                echo "PVE_PASSWORD=your_proxmox_password" >> "$stack_dir/.env"
                echo "PVE_URL=https://your_proxmox_ip:8006" >> "$stack_dir/.env"
                ;;
        esac
        
        print_info "✓ Environment file created at $stack_dir/.env"
        print_warning "Please edit $stack_dir/.env with your actual values before starting services"
    else
        print_info "Environment file already exists at $stack_dir/.env"
    fi
}

# Function to create directory structure
create_directories() {
    local stack_type=$1
    
    print_step "Creating directory structure..."
    
    # Common directories
    mkdir -p "/datapool/config/$stack_type"
    
    # Stack-specific directories
    case "$stack_type" in
        "media")
            mkdir -p /datapool/config/{sonarr,radarr,bazarr,jellyfin,jellyseerr,qbittorrent,prowlarr,flaresolverr,recyclarr,cleanuperr,huntarr}
            mkdir -p /datapool/media/{movies,tv,youtube/{playlists,channels}}
            mkdir -p /datapool/torrents/{movies,tv,other}
            ;;
        "monitoring")
            mkdir -p /datapool/config/monitoring/{prometheus,grafana/{provisioning/{datasources,dashboards}},alertmanager}
            ;;
        "downloads")
            mkdir -p /datapool/config/{jdownloader2,metube}
            ;;
        "utility")
            mkdir -p /datapool/config/firefox
            ;;
        "proxy")
            mkdir -p /datapool/config/cloudflared
            ;;
    esac
    
    # Set ownership
    chown -R 1000:1000 /datapool/config 2>/dev/null || true
    chmod -R 755 /datapool/config 2>/dev/null || true
    
    print_info "✓ Directory structure created"
}

# Function to deploy stack
deploy_stack() {
    local stack_type=$1
    local stack_dir="/opt/${stack_type}-stack"
    
    print_info "Starting deployment of $stack_type stack..."
    
    # Get LXC ID for stack type
    local lxc_id
    case "$stack_type" in
        "proxy") lxc_id=100 ;;
        "media") lxc_id=101 ;;
        "downloads") lxc_id=102 ;;
        "utility") lxc_id=103 ;;
        "monitoring") lxc_id=104 ;;
        *)
            print_error "Unknown stack type: $stack_type"
            return 1
            ;;
    esac
    
    # Check if LXC exists and is running
    if ! lxc_exists "$lxc_id"; then
        print_error "LXC $lxc_id does not exist! Please create it first."
        return 1
    fi
    
    if ! pct status "$lxc_id" | grep -q "running"; then
        print_info "Starting LXC $lxc_id..."
        pct start "$lxc_id"
        wait_for_lxc "$lxc_id"
    fi
    
    # Copy files to LXC
    print_step "Copying stack files to LXC $lxc_id..."
    
    # Create stack directory in LXC
    pct exec "$lxc_id" -- mkdir -p "$stack_dir"
    
    # Copy docker-compose and env files
    pct push "$lxc_id" "/tmp/docker-compose-${stack_type}.yml" "$stack_dir/docker-compose.yml"
    [ -f "/tmp/.env-${stack_type}" ] && pct push "$lxc_id" "/tmp/.env-${stack_type}" "$stack_dir/.env"
    
    # Create directories in LXC
    pct exec "$lxc_id" -- bash -c "$(declare -f create_directories); create_directories $stack_type"
    
    # Deploy stack
    print_step "Deploying $stack_type stack in LXC $lxc_id..."
    
    pct exec "$lxc_id" -- bash -c "
        cd '$stack_dir' &&
        docker compose pull &&
        docker compose up -d
    "
    
    if [ $? -eq 0 ]; then
        print_info "✅ $stack_type stack deployed successfully!"
        print_info "   LXC ID: $lxc_id"
        print_info "   IP: 192.168.1.$lxc_id"
        print_info "   Stack directory: $stack_dir"
    else
        print_error "Failed to deploy $stack_type stack"
        return 1
    fi
}

# Main execution
main() {
    check_root
    
    local stack_type="$1"
    
    if [ -z "$stack_type" ]; then
        print_error "Stack type required!"
        print_info "Usage: $0 <stack_type>"
        print_info "Available types: proxy, media, downloads, utility, monitoring"
        exit 1
    fi
    
    # Validate stack type
    case "$stack_type" in
        proxy|media|downloads|utility|monitoring)
            ;;
        *)
            print_error "Invalid stack type: $stack_type"
            print_info "Available types: proxy, media, downloads, utility, monitoring"
            exit 1
            ;;
    esac
    
    print_info "Starting deployment of $stack_type stack..."
    
    # Download files to temp directory first
    local temp_stack_dir="$TEMP_DIR/$stack_type"
    
    if ! download_stack_files "$stack_type" "$temp_stack_dir"; then
        print_error "Failed to download stack files"
        exit 1
    fi
    
    # Setup environment
    setup_env_file "$temp_stack_dir" "$stack_type"
    
    # Copy files to temp locations for LXC transfer
    cp "$temp_stack_dir/docker-compose.yml" "/tmp/docker-compose-${stack_type}.yml"
    [ -f "$temp_stack_dir/.env" ] && cp "$temp_stack_dir/.env" "/tmp/.env-${stack_type}"
    
    # Deploy the stack
    deploy_stack "$stack_type"
    
    # Cleanup temp files
    rm -f "/tmp/docker-compose-${stack_type}.yml" "/tmp/.env-${stack_type}"
    
    print_info "✅ $stack_type stack deployment completed!"
}

# Setup cleanup trap
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

# Run main function with all arguments
main "$@"