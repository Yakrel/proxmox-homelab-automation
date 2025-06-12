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

# Function to ensure proper datapool permissions
ensure_datapool_permissions() {
    local stack_type=$1
    
    print_step "Setting up datapool permissions for $stack_type stack..."
    
    # Create necessary directories based on stack type
    case $stack_type in
        "proxy")
            mkdir -p /datapool/config/{cloudflared,watchtower-proxy}
            ;;
        "media")
            mkdir -p /datapool/config/{sonarr,radarr,bazarr,jellyfin,jellyseerr,qbittorrent,prowlarr,flaresolverr,watchtower-media,recyclarr,cleanuperr,huntarr}
            mkdir -p /datapool/config/jellyseerr/logs
            mkdir -p /datapool/{torrents,media}/{tv,movies}
            mkdir -p /datapool/torrents/other
            ;;
        "downloads")
            mkdir -p /datapool/config/{jdownloader2,metube,watchtower-downloads}
            ;;
        "utility")
            mkdir -p /datapool/config/{firefox,watchtower-utility}
            ;;
        "monitoring")
            mkdir -p /datapool/config/{prometheus,grafana,alertmanager,watchtower-monitoring}
            mkdir -p /datapool/config/prometheus/rules
            mkdir -p /datapool/config/grafana/provisioning/{datasources,dashboards}
            ;;
    esac
    
    # Set ownership for all application directories in one command
    chown -R 101000:101000 /datapool/{config,torrents,media} 2>/dev/null || true
    
    print_info "✓ Datapool permissions configured for $stack_type"
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
    
    # Download additional config files for monitoring stack
    if [ "$stack_type" = "monitoring" ]; then
        print_info "Downloading monitoring configuration files..."
        wget -q -O "$target_dir/prometheus.yml" "$GITHUB_REPO/docker/monitoring/prometheus.yml"
        wget -q -O "$target_dir/alertmanager.yml" "$GITHUB_REPO/docker/monitoring/alertmanager.yml"
        
        if [ $? -ne 0 ]; then
            print_warning "Failed to download some monitoring config files"
        fi
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

# Function to check if datapool mount exists
validate_datapool_mount() {
    local lxc_id=$1
    
    if ! pct exec "$lxc_id" -- test -d /datapool; then
        print_error "/datapool mount not found in LXC $lxc_id"
        print_info "Adding datapool mount..."
        
        # Try to add datapool mount
        if pct status "$lxc_id" | grep -q "running"; then
            pct shutdown "$lxc_id"
            sleep 5
        fi
        
        # Add mount point
        local next_mp_index=$(pct config "$lxc_id" | grep -o 'mp[0-9]\+' | sort -V | tail -n 1 | grep -o '[0-9]\+' | awk '{print $1+1}')
        next_mp_index=${next_mp_index:-0}
        
        if pct set "$lxc_id" -mp${next_mp_index} /datapool,mp=/datapool,acl=1; then
            pct start "$lxc_id"
            sleep 5
            print_info "✓ Datapool mount added successfully"
            return 0
        else
            print_error "Failed to add datapool mount"
            return 1
        fi
    fi
    
    return 0
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

# Function to validate Cloudflare token format
validate_cloudflare_token() {
    local token=$1
    # Basic validation: should be long enough and contain expected characters
    if [ ${#token} -lt 80 ]; then
        return 1
    fi
    # Check if it looks like a Cloudflare token (contains letters, numbers, and some special chars)
    if [[ ! "$token" =~ ^[A-Za-z0-9_-]{80,}$ ]]; then
        return 1
    fi
    return 0
}

# Function to validate timezone format
validate_timezone() {
    local tz=$1
    # Check if timezone file exists
    if [ ! -f "/usr/share/zoneinfo/$tz" ]; then
        return 1
    fi
    return 0
}

# Function to setup proxy stack environment
setup_proxy_env() {
    local lxc_id=$1
    local target_dir=$2
    
    echo
    print_info "🔧 Cloudflare Tunnel Configuration"
    echo "Please provide your Cloudflare tunnel token:"
    echo
    
    read -p "Enter your Cloudflare tunnel token: " tunnel_token
    while [ -z "$tunnel_token" ] || ! validate_cloudflare_token "$tunnel_token"; do
        if [ -z "$tunnel_token" ]; then
            print_error "Tunnel token is required!"
        else
            print_error "Invalid token format! Token should be 80+ characters long."
        fi
        read -p "Enter your Cloudflare tunnel token: " tunnel_token
    done
    
    read -p "Enter timezone [Europe/Istanbul]: " timezone
    timezone=${timezone:-Europe/Istanbul}
    
    # Validate timezone
    if ! validate_timezone "$timezone"; then
        print_warning "Invalid timezone '$timezone', using default Europe/Istanbul"
        timezone="Europe/Istanbul"
    fi
    
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
    
    # Validate timezone
    if ! validate_timezone "$timezone"; then
        print_warning "Invalid timezone '$timezone', using default Europe/Istanbul"
        timezone="Europe/Istanbul"
    fi
    
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
    
    # Validate timezone
    if ! validate_timezone "$timezone"; then
        print_warning "Invalid timezone '$timezone', using default Europe/Istanbul"
        timezone="Europe/Istanbul"
    fi
    
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
    
    # Validate timezone
    if ! validate_timezone "$timezone"; then
        print_warning "Invalid timezone '$timezone', using default Europe/Istanbul"
        timezone="Europe/Istanbul"
    fi
    
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

# Function to setup PVE monitoring user
setup_pve_monitoring_user() {
    local pve_user=$1
    local pve_password=$2
    
    print_info "Setting up Proxmox monitoring user..."
    
    # Check if user already exists
    if pveum user list | grep -q "^$pve_user:"; then
        print_info "✓ User $pve_user already exists"
    else
        print_info "Creating Proxmox monitoring user: $pve_user"
        if pveum user add "$pve_user" --password "$pve_password" --comment "Monitoring user for Prometheus PVE exporter"; then
            print_info "✓ User $pve_user created successfully"
        else
            print_warning "Failed to create user $pve_user"
            return 1
        fi
    fi
    
    # Assign PVEAuditor role if not already assigned
    if pveum acl list | grep -q "$pve_user.*PVEAuditor"; then
        print_info "✓ User $pve_user already has PVEAuditor role"
    else
        print_info "Assigning PVEAuditor role to $pve_user"
        if pveum acl modify / --users "$pve_user" --roles PVEAuditor; then
            print_info "✓ PVEAuditor role assigned successfully"
        else
            print_warning "Failed to assign PVEAuditor role"
            return 1
        fi
    fi
    
    print_info "✓ PVE monitoring user setup completed"
}

# Function to auto-detect LXC IP addresses for Prometheus targets
auto_detect_lxc_ips() {
    local prometheus_config="/datapool/config/prometheus/prometheus.yml"
    
    print_info "Auto-detecting LXC IP addresses for Prometheus targets..."
    
    # Array of LXC IDs and their corresponding service names
    local lxc_services=("100:proxy" "101:media" "102:downloads" "103:utility")
    
    for entry in "${lxc_services[@]}"; do
        local lxc_id="${entry%:*}"
        local service_name="${entry#*:}"
        
        # Check if LXC exists and is running
        if pct status "$lxc_id" &>/dev/null; then
            if pct status "$lxc_id" | grep -q "running"; then
                # Get the IP address of the LXC
                local lxc_ip=$(pct exec "$lxc_id" -- ip -4 addr show eth0 2>/dev/null | grep inet | awk '{print $2}' | cut -d/ -f1 | head -n1)
                
                if [ -n "$lxc_ip" ]; then
                    print_info "Found $service_name LXC ($lxc_id) at IP: $lxc_ip"
                    
                    # Update prometheus.yml with the detected IP
                    case $service_name in
                        "proxy")
                            sed -i "s/192\.168\.1\.100:9104/$lxc_ip:9104/g" "$prometheus_config"
                            ;;
                        "media")
                            sed -i "s/192\.168\.1\.101:9101/$lxc_ip:9101/g" "$prometheus_config"
                            ;;
                        "downloads")
                            sed -i "s/192\.168\.1\.102:9102/$lxc_ip:9102/g" "$prometheus_config"
                            ;;
                        "utility")
                            sed -i "s/192\.168\.1\.103:9103/$lxc_ip:9103/g" "$prometheus_config"
                            ;;
                    esac
                else
                    print_warning "Could not detect IP for $service_name LXC ($lxc_id)"
                fi
            else
                print_warning "$service_name LXC ($lxc_id) is not running, skipping IP detection"
            fi
        else
            print_warning "$service_name LXC ($lxc_id) does not exist, skipping IP detection"
        fi
    done
    
    print_info "✓ IP detection completed"
}

# Function to setup monitoring stack environment
setup_monitoring_env() {
    local lxc_id=$1
    local target_dir=$2
    
    echo
    print_info "📊 Monitoring Stack Configuration"
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
    
    # Validate timezone
    if ! validate_timezone "$timezone"; then
        print_warning "Invalid timezone '$timezone', using default Europe/Istanbul"
        timezone="Europe/Istanbul"
    fi
    
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
    
    # Create PVE monitoring user if it doesn't exist
    setup_pve_monitoring_user "$pve_user" "$pve_password"
    
    # Auto-detect and update LXC IPs in prometheus config
    auto_detect_lxc_ips
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
    
    # Validate datapool mount
    validate_datapool_mount "$lxc_id"
    
    # Check if stack directory exists
    if ! pct exec "$lxc_id" -- test -d "$target_dir"; then
        print_warning "Stack directory $target_dir doesn't exist, creating new deployment..."
        deploy_complete_stack "$stack_type" "$lxc_id"
        return $?
    fi
    
    # Check if .env exists (skip configuration if it does)
    if pct exec "$lxc_id" -- test -f "$target_dir/.env"; then
        print_info "✓ Environment file exists, skipping configuration prompts"
        skip_env_setup=true
    else
        print_warning "No .env file found, will need configuration setup"
        skip_env_setup=false
    fi
    
    # Download latest stack files
    download_stack_files "$stack_type" "$TEMP_DIR/$stack_type"
    
    # Copy updated docker-compose.yml to LXC
    print_info "Updating docker-compose.yml..."
    pct push "$lxc_id" "$TEMP_DIR/$stack_type/docker-compose.yml" "$target_dir/docker-compose.yml"
    
    # Update monitoring config files if needed (permissions already set by ensure_datapool_permissions)
    if [ "$stack_type" = "monitoring" ]; then
        if [ -f "$TEMP_DIR/$stack_type/prometheus.yml" ]; then
            cp "$TEMP_DIR/$stack_type/prometheus.yml" "/datapool/config/prometheus/prometheus.yml"
        fi
        if [ -f "$TEMP_DIR/$stack_type/alertmanager.yml" ]; then
            cp "$TEMP_DIR/$stack_type/alertmanager.yml" "/datapool/config/alertmanager/alertmanager.yml"
        fi
    fi
    
    # Setup environment if .env doesn't exist
    if [ "$skip_env_setup" = false ]; then
        print_info "Setting up environment configuration..."
        setup_stack_env "$stack_type" "$lxc_id" "$target_dir"
    fi
    
    # Ensure proper datapool permissions (always run for existing stacks)
    ensure_datapool_permissions "$stack_type"
    
    # Copy additional monitoring configuration files if needed
    if [ "$stack_type" = "monitoring" ]; then
        # Copy monitoring configuration files (permissions already set by ensure_datapool_permissions)
        cp "$GITHUB_REPO/docker/monitoring/grafana-datasource.yml" "/datapool/config/grafana/provisioning/datasources/prometheus.yml" 2>/dev/null || true
        cp "$GITHUB_REPO/docker/monitoring/alerts.yml" "/datapool/config/prometheus/rules/alerts.yml" 2>/dev/null || true
    fi
    
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
    
    # Ensure proper datapool permissions for new deployment
    ensure_datapool_permissions "$stack_type"
    
    # Copy monitoring config files to host directory (permissions already set by ensure_datapool_permissions)
    if [ "$stack_type" = "monitoring" ]; then
        if [ -f "$TEMP_DIR/$stack_type/prometheus.yml" ]; then
            cp "$TEMP_DIR/$stack_type/prometheus.yml" "/datapool/config/prometheus/prometheus.yml"
        fi
        if [ -f "$TEMP_DIR/$stack_type/alertmanager.yml" ]; then
            cp "$TEMP_DIR/$stack_type/alertmanager.yml" "/datapool/config/alertmanager/alertmanager.yml"
        fi
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
        
        # Clean up .env.example file
        print_info "Cleaning up temporary files..."
        pct exec "$lxc_id" -- sh -c "cd $target_dir && rm -f .env.example"
        
        # Show important notes
        print_info "Stack deployed successfully to $target_dir"
        
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