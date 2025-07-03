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

print_info() {
    echo -e "\033[36m[INFO]\033[0m $1"
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


# Unified environment setup functions

# Interactive user input
get_user_input() {
    local prompt="$1"
    local variable_name="$2"
    local default_value="${3:-}"
    
    if [ -n "$default_value" ]; then
        read -p "$prompt [$default_value]: " "$variable_name"
        eval "$variable_name=\"\${$variable_name:-$default_value}\""
    else
        read -p "$prompt: " "$variable_name"
    fi
}

# Silent (password) input
get_user_password() {
    local prompt="$1"
    local variable_name="$2"
    
    read -sp "$prompt: " "$variable_name"
    echo
}

# Generate a random key
generate_random_key() {
    openssl rand -base64 32
}

# Unified .env file management for stacks (container-side execution)
# Preserves ALL existing values, creates backup, and merges .env.example template
create_stack_env_file() {
    local target_file=$1
    local stack_name=$2
    local env_example_content=$3

    # Create backup of existing .env file before modifying
    if [ -f "$target_file" ]; then
        local backup_file="${target_file}.backup"
        cp "$target_file" "$backup_file" 2>/dev/null || true
        echo "INFO: Backup created: $(basename "$backup_file")"
    fi

    local temp_env=$(mktemp)
    
    # If a .env file already exists, start with its content
    if [ -f "$target_file" ]; then
        cp "$target_file" "$temp_env"
    fi

    # Read the .env.example content line by line using process substitution to avoid subshell
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Skip comments and empty lines
        if [[ "$line" =~ ^[[:space:]]*# ]] || [[ -z "$line" ]]; then
            continue
        fi

        # Extract variable name
        var_name=$(echo "$line" | cut -d'=' -f1)

        # If the variable is not already in the .env file, add it
        if ! grep -q "^${var_name}=" "$temp_env"; then
            echo "$line" >> "$temp_env"
        fi
    done < <(echo "$env_example_content")

    # Overwrite the original .env file with the updated content
    mv "$temp_env" "$target_file"

    # Set proper permissions
    chmod 600 "$target_file"
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

# Disable MOTD in LXC container using .hushlogin
disable_motd() {
    local lxc_id=$1
    
    print_info "Disabling MOTD for LXC $lxc_id using .hushlogin"
    
    # Create .hushlogin file in the container's root directory
    pct exec "$lxc_id" -- touch /root/.hushlogin 2>/dev/null || true
    
    return 0
}







