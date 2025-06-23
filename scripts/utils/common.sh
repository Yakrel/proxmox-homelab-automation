#!/bin/bash

# Common utility functions for Proxmox Homelab Automation
# This file contains shared functions used across multiple scripts

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

# Function to check LXC status (unified implementation)
check_lxc_status() {
    local lxc_id=$1
    
    if pct status "$lxc_id" >/dev/null 2>&1; then
        local status=$(pct status "$lxc_id" | awk '{print $2}')
        echo "$status"
    else
        echo "not_exists"
    fi
}

# Function to wait for container readiness (unified implementation)
wait_for_container_ready() {
    local lxc_id=$1
    local max_attempts=${2:-30}  # Default 30 attempts
    local quiet=${3:-false}  # Add quiet mode option
    local attempt=1
    
    [ "$quiet" != "true" ] && print_info "Waiting for container to be ready..."
    while [ $attempt -le $max_attempts ]; do
        if pct exec "$lxc_id" -- echo "ready" >/dev/null 2>&1; then
            if [ "$quiet" != "true" ] && [ $attempt -gt 1 ]; then
                print_info "✓ Container is ready after ${attempt} attempts"
            elif [ "$quiet" != "true" ]; then
                print_info "✓ Container is ready"
            fi
            return 0
        fi
        sleep 2
        attempt=$((attempt + 1))
    done
    
    print_warning "Container readiness check timeout after $((max_attempts * 2)) seconds, continuing..."
    return 0  # Don't fail entire script
}

# Function to ensure Docker service is ready (unified implementation)
ensure_docker_ready() {
    local lxc_id=$1
    local max_attempts=${2:-15}  # Default 15 attempts
    local quiet=${3:-false}  # Add quiet mode option
    local attempt=1
    
    # Quick check first - if Docker is already ready, don't show messages
    if pct exec "$lxc_id" -- docker info >/dev/null 2>&1; then
        [ "$quiet" != "true" ] && print_info "✓ Docker is already working"
        return 0
    fi
    
    [ "$quiet" != "true" ] && print_info "Ensuring Docker service is ready..."
    while [ $attempt -le $max_attempts ]; do
        if pct exec "$lxc_id" -- docker info >/dev/null 2>&1; then
            [ "$quiet" != "true" ] && print_info "✓ Docker service is ready"
            return 0
        fi
        
        if [ $attempt -eq 5 ]; then
            [ "$quiet" != "true" ] && print_info "Docker not ready, restarting service..."
            pct exec "$lxc_id" -- rc-service docker restart >/dev/null 2>&1 || true
        fi
        
        sleep 3
        attempt=$((attempt + 1))
    done
    
    print_warning "Docker readiness check timeout, continuing anyway..."
    return 0
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

# Function to ensure datapool mount exists (unified implementation)
ensure_datapool_mount() {
    local lxc_id=$1
    
    print_info "Checking /datapool mount for LXC $lxc_id..."
    
    # Check if mount already exists with more precise regex
    local existing_mount=$(pct config "$lxc_id" | grep -E "^mp[0-9]+=.*,mp=/datapool" 2>/dev/null)
    if [ -n "$existing_mount" ]; then
        print_info "✓ Found existing datapool mount configuration: $(echo "$existing_mount" | cut -d'=' -f1)"
        
        # Verify mount is accessible if container is running
        if pct status "$lxc_id" | grep -q "running"; then
            if pct exec "$lxc_id" -- test -d /datapool 2>/dev/null; then
                print_info "✓ /datapool mount is accessible and working"
                return 0
            else
                print_warning "Mount exists in config but not accessible - attempting remount"
                # Try to remount without full restart
                pct exec "$lxc_id" -- mount -a 2>/dev/null || true
                sleep 2
                if pct exec "$lxc_id" -- test -d /datapool 2>/dev/null; then
                    print_info "✓ /datapool mount remounted successfully"
                    return 0
                else
                    print_warning "Remount failed - container may need manual restart"
                    print_info "You can restart the container with: pct restart $lxc_id"
                    return 0
                fi
            fi
        else
            print_info "✓ Mount configured, container not running (mount will be available on startup)"
            return 0
        fi
    fi
    
    print_info "Adding /datapool mount point..."
    
    # Stop container if running (needed for mount changes)
    local was_running=false
    if pct status "$lxc_id" | grep -q "running"; then
        was_running=true
        pct shutdown "$lxc_id" 2>/dev/null || pct stop "$lxc_id"
        
        # Wait for shutdown
        local attempts=10
        while [ $attempts -gt 0 ] && pct status "$lxc_id" | grep -q "running"; do
            sleep 2
            attempts=$((attempts - 1))
        done
    fi
    
    # Determine the next available mount index
    local next_mp_index=$(pct config "$lxc_id" | grep -o 'mp[0-9]\+' | sort -V | tail -n 1 | grep -o '[0-9]\+' | awk '{print $1+1}' 2>/dev/null)
    next_mp_index=${next_mp_index:-0}
    
    # Add mount point with ACL support
    if pct set "$lxc_id" -mp${next_mp_index} /datapool,mp=/datapool,acl=1; then
        print_info "✓ Mount point added successfully"
        
        # Restart container if it was running
        if [ "$was_running" = true ]; then
            pct start "$lxc_id"
            wait_for_container_ready "$lxc_id"
        fi
        
        return 0
    else
        print_error "Failed to add mount point"
        # Restart container if it was running
        if [ "$was_running" = true ]; then
            pct start "$lxc_id"
        fi
        return 1
    fi
}

# Function to extract API keys from running services
extract_service_api_key() {
    local lxc_id=$1
    local service_name=$2
    local api_endpoint=$3
    local config_path=$4
    
    print_info "Extracting $service_name API key..."
    
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        # Check if service is responding
        if pct exec "$lxc_id" -- wget -q --spider "$api_endpoint" 2>/dev/null; then
            # Try to extract API key from config file
            local api_key=$(pct exec "$lxc_id" -- cat "$config_path" 2>/dev/null | grep -i apikey | sed 's/.*<ApiKey>\(.*\)<\/ApiKey>.*/\1/' | head -n1)
            
            if [ -n "$api_key" ] && [ "$api_key" != "" ]; then
                echo "$api_key"
                return 0
            fi
        fi
        
        print_info "Waiting for $service_name to initialize... ($attempt/$max_attempts)"
        sleep 10
        attempt=$((attempt + 1))
    done
    
    print_warning "Could not extract $service_name API key automatically"
    return 1
}

# Function to update env file with extracted API keys
update_env_with_api_keys() {
    local lxc_id=$1
    local stack_dir=$2
    
    print_info "Attempting to extract API keys for Media stack..."
    
    # Wait for services to be ready
    sleep 30
    
    # Extract Sonarr API key
    local sonarr_key=$(extract_service_api_key "$lxc_id" "Sonarr" "http://localhost:8989" "/datapool/config/sonarr/config.xml")
    if [ $? -eq 0 ] && [ -n "$sonarr_key" ]; then
        pct exec "$lxc_id" -- sed -i "s/^SONARR_API_KEY=.*/SONARR_API_KEY=$sonarr_key/" "$stack_dir/.env"
        print_info "✓ Updated Sonarr API key"
    fi
    
    # Extract Radarr API key
    local radarr_key=$(extract_service_api_key "$lxc_id" "Radarr" "http://localhost:7878" "/datapool/config/radarr/config.xml")
    if [ $? -eq 0 ] && [ -n "$radarr_key" ]; then
        pct exec "$lxc_id" -- sed -i "s/^RADARR_API_KEY=.*/RADARR_API_KEY=$radarr_key/" "$stack_dir/.env"
        print_info "✓ Updated Radarr API key"
    fi
    
    return 0
}

# Function to generate secure password
generate_secure_password() {
    local length=${1:-16}
    openssl rand -base64 $((length * 3 / 4)) | tr -d "=+/" | cut -c1-$length
}

# Function to validate input (not empty)
validate_not_empty() {
    local input=$1
    local field_name=$2
    
    if [ -z "$input" ]; then
        print_error "$field_name cannot be empty"
        return 1
    fi
    return 0
}

# Function to validate URL format
validate_url() {
    local url=$1
    
    if [[ ! "$url" =~ ^https?://[a-zA-Z0-9.-]+(:[0-9]+)?(/.*)?$ ]]; then
        print_error "Invalid URL format. Expected format: http(s)://hostname[:port][/path]"
        return 1
    fi
    return 0
}

# Function to get validated input with retry
get_validated_input() {
    local prompt=$1
    local min_val=$2
    local max_val=$3
    local input
    
    while true; do
        read -p "$prompt" input
        if [[ "$input" =~ ^[0-9]+$ ]] && [ "$input" -ge "$min_val" ] && [ "$input" -le "$max_val" ]; then
            echo "$input"
            return 0
        else
            print_error "Please enter a valid number between $min_val and $max_val"
        fi
    done
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
            mkdir -p /datapool/config/{prometheus,grafana,alertmanager}
            mkdir -p /datapool/config/prometheus/{rules,data}
            mkdir -p /datapool/config/grafana/provisioning/{datasources,dashboards}
            ;;
    esac
    
    # Set ownership for all application directories in one command
    chown -R 101000:101000 /datapool/{config,torrents,media} 2>/dev/null || true
    
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

# Function to validate timezone
validate_timezone() {
    local timezone=$1
    local default_tz=${2:-"Europe/Istanbul"}
    
    if [ -z "$timezone" ] || [ ! -f "/usr/share/zoneinfo/$timezone" ]; then
        print_warning "Invalid or empty timezone '$timezone', using default $default_tz"
        echo "$default_tz"
    else
        echo "$timezone"
    fi
}

# Unified environment setup functions

# Simple password input function (no complex validation or retry)
get_simple_password() {
    local prompt=$1
    local password
    
    # Ensure we have a proper terminal for password input
    if [ ! -t 0 ]; then
        print_error "No terminal available for password input"
        return 1
    fi
    
    printf "%s: " "$prompt" >&2
    read -s password < /dev/tty
    echo "" >&2
    
    if [ -z "$password" ]; then
        print_error "Password cannot be empty"
        return 1
    fi
    
    printf "%s" "$password"
    return 0
}

# Generate random encryption key
generate_encryption_key() {
    local length=${1:-32}
    openssl rand -base64 48 | tr -d "=+/" | cut -c1-${length}
}

# Create common environment content for all stacks
create_common_env_content() {
    local stack_name=$1
    local custom_content=$2
    
    cat << EOF
# ${stack_name} Stack Environment Variables - Generated $(date)

# Timezone setting
TZ=Europe/Istanbul

# PUID/PGID for file permissions
PUID=1000
PGID=1000

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