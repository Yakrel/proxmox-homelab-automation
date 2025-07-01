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
            mkdir -p /datapool/config/{sonarr,radarr,bazarr,jellyfin,jellyseerr,qbittorrent,prowlarr,flaresolverr,recyclarr,cleanuperr}
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

# Export community script variables for Alpine Docker
export_alpine_docker_variables() {
    local lxc_id=$1
    local hostname=$2
    local ip_address=$3
    local cores=$4
    local memory=$5
    local disk=$6
    
    # Silent mode to skip interactive prompts
    export SILENT="1"
    
    # Resource configuration
    export var_cpu="$cores"
    export var_ram="$memory"
    export var_disk="$disk"
    export var_unprivileged="1"
    export var_tags="homelab-stack;alpine;docker"
    
    # Container identity
    export var_ctid="$lxc_id"
    export var_hostname="$hostname"
    
    # Network configuration
    export var_net="$ip_address"
    export var_gate="192.168.1.1"
    export var_bridge="vmbr0"
    
    # Alpine specific settings
    export var_os="alpine"
    export var_version="3.22"
    export var_ssh="no"
    export var_verbose="no"
    export var_timezone="$HOMELAB_TIMEZONE"
    
    print_long_operation "Alpine Docker variables exported for LXC $lxc_id ($hostname)"
}

# Export community script variables for Ubuntu
export_ubuntu_variables() {
    local lxc_id=$1
    local hostname=$2
    local ip_address=$3
    local cores=$4
    local memory=$5
    local disk=$6
    
    # Silent mode
    export SILENT="1"
    
    # Resource configuration
    export var_cpu="$cores"
    export var_ram="$memory"
    export var_disk="$disk"
    export var_unprivileged="1"
    export var_tags="homelab-stack;ubuntu;development"
    
    # Container identity
    export var_ctid="$lxc_id"
    export var_hostname="$hostname"
    
    # Network configuration
    export var_net="$ip_address"
    export var_gate="192.168.1.1"
    export var_bridge="vmbr0"
    
    # Ubuntu specific settings
    export var_os="ubuntu"
    export var_version="24.04"
    export var_ssh="yes"
    export var_verbose="no"
    export var_timezone="$HOMELAB_TIMEZONE"
    
    print_long_operation "Ubuntu variables exported for LXC $lxc_id ($hostname)"
}







