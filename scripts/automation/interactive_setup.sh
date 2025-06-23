#!/bin/bash

# Interactive Password and Configuration Setup Script
# Prompts user for passwords and creates .env files automatically

set -e

# Cleanup temporary files on exit
TEMP_FILES=()
cleanup_temp_files() {
    for temp_file in "${TEMP_FILES[@]}"; do
        [ -f "$temp_file" ] && rm -f "$temp_file"
    done
}
trap cleanup_temp_files EXIT

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Try different locations for common.sh based on execution context
if [ -f "$SCRIPT_DIR/common.sh" ]; then
    source "$SCRIPT_DIR/common.sh"
elif [ -f "$SCRIPT_DIR/../utils/common.sh" ]; then
    source "$SCRIPT_DIR/../utils/common.sh"
elif [ -f "scripts/utils/common.sh" ]; then
    source "scripts/utils/common.sh"
elif [ -f "/tmp/common.sh" ]; then
    source "/tmp/common.sh"
else
    # Define basic print functions if common.sh is not found
    print_info() { echo "[INFO] $1"; }
    print_error() { echo "[ERROR] $1"; }
    print_warning() { echo "[WARNING] $1"; }
    print_step() { echo "[STEP] $1"; }
fi

# Minimal password validation function
validate_password_strength() {
    local password=$1
    
    # Only check for completely empty passwords
    if [ -z "$password" ]; then
        print_error "Password cannot be empty"
        return 1
    fi
    
    return 0
}

# Generate random string for encryption keys
generate_random_string() {
    local length=${1:-32}
    openssl rand -base64 48 | tr -d "=+/" | cut -c1-${length}
}

# Simple validation helper
check_empty() {
    [ -z "$1" ] && { print_error "$2 required"; return 1; }
    return 0
}

# Function to get secure password input with enhanced validation
get_password() {
    local prompt=$1
    local password
    local password_confirm
    
    while true; do
        read -sp "$prompt: " password
        echo ""
        
        if ! validate_password_strength "$password"; then
            print_warning "Please enter a non-empty password"
            continue
        fi
        
        read -sp "Confirm password: " password_confirm
        echo ""
        
        if [ "$password" = "$password_confirm" ]; then
            printf "%s" "$password"
            return 0
        else
            print_error "Passwords do not match. Please try again."
        fi
    done
}

# Helper function to create common environment settings
create_common_env_content() {
    local stack_name=$1
    local custom_content=$2
    
    cat << EOF
# ${stack_name} Stack Environment Variables - Generated $(date)

# Timezone setting
TZ=Europe/Istanbul

# PUID/PGID for file permissions (currently testing unified 1000)
# FALLBACK: Use stack-specific values if issues occur
PUID=1000
PGID=1000

${custom_content}
EOF
}

# Simple .env file creation
create_env_file() {
    local target_file=$1
    local stack_name=$2
    local custom_content=$3
    
    create_common_env_content "$stack_name" "$custom_content" > "$target_file"
    chmod 600 "$target_file"
}

# Function to setup proxy stack environment with smart merging
setup_proxy_env() {
    local stack_dir=$1
    local env_file="$stack_dir/.env"
    
    print_step "Setting up Proxy stack environment..."
    
    # Read existing values if file exists
    local existing_token=$(get_existing_env_value "$env_file" "CLOUDFLARED_TOKEN")
    
    # Show what we're preserving
    if [ -n "$existing_token" ]; then
        print_info "✓ Preserving existing Cloudflare tunnel token: ${existing_token:0:8}..."
    fi
    
    local cloudflare_token="$existing_token"
    if [ -z "$cloudflare_token" ]; then
        # Get Cloudflare tunnel token with validation
        while true; do
            echo -n "Enter your Cloudflare tunnel token: "
            read cloudflare_token
            
            if check_empty "$cloudflare_token" "Cloudflare token"; then
                break
            fi
            print_warning "Please enter a valid Cloudflare tunnel token"
        done
    fi
    
    # Create .env file with common settings and proxy-specific content
    local proxy_content="# Cloudflare tunnel token for secure connections
CLOUDFLARED_TOKEN=$cloudflare_token"
    
    create_env_file "$env_file" "Proxy" "$proxy_content"
    return $?
}

# Function to read existing env value
get_existing_env_value() {
    local env_file=$1
    local var_name=$2
    
    if [ -f "$env_file" ]; then
        grep "^${var_name}=" "$env_file" 2>/dev/null | cut -d'=' -f2- | tr -d '"'
    fi
}

# Function to setup media stack environment with smart merging
setup_media_env() {
    local stack_dir=$1
    local env_file="$stack_dir/.env"
    
    print_step "Setting up Media stack environment..."
    
    # Read existing values if file exists
    local existing_sonarr_key=$(get_existing_env_value "$env_file" "SONARR_API_KEY")
    local existing_radarr_key=$(get_existing_env_value "$env_file" "RADARR_API_KEY")
    local existing_qb_username=$(get_existing_env_value "$env_file" "QB_USERNAME")
    local existing_qb_password=$(get_existing_env_value "$env_file" "QB_PASSWORD")
    
    # Show what we're preserving
    if [ -n "$existing_sonarr_key" ]; then
        print_info "✓ Preserving existing Sonarr API key: ${existing_sonarr_key:0:8}..."
    fi
    if [ -n "$existing_radarr_key" ]; then
        print_info "✓ Preserving existing Radarr API key: ${existing_radarr_key:0:8}..."
    fi
    if [ -n "$existing_qb_username" ]; then
        print_info "✓ Preserving existing qBittorrent username: $existing_qb_username"
    fi
    if [ -n "$existing_qb_password" ]; then
        print_info "✓ Preserving existing qBittorrent password: [hidden]"
    fi
    
    # Use existing values or defaults
    local sonarr_key=${existing_sonarr_key:-""}
    local radarr_key=${existing_radarr_key:-""}
    local qb_username=${existing_qb_username:-"admin"}
    local qb_password=${existing_qb_password:-""}
    
    # Media stack content with preserved/default values
    local media_content="# API Keys for service integration (get from web UIs after deployment)
# Sonarr API Key (get from: Settings > General > API Key)
SONARR_API_KEY=$sonarr_key

# Radarr API Key (get from: Settings > General > API Key)  
RADARR_API_KEY=$radarr_key

# qBittorrent Credentials
QB_USERNAME=$qb_username
QB_PASSWORD=$qb_password"
    
    create_env_file "$env_file" "Media" "$media_content"
    
    # Show guidance for empty API keys
    if [ -z "$existing_sonarr_key" ] || [ -z "$existing_radarr_key" ]; then
        echo
        print_info "📝 API Key Setup Guidance:"
        if [ -z "$sonarr_key" ]; then
            print_info "  • Sonarr API Key: http://192.168.1.101:8989 → Settings → General → API Key"
        fi
        if [ -z "$radarr_key" ]; then
            print_info "  • Radarr API Key: http://192.168.1.101:7878 → Settings → General → API Key"
        fi
        print_info "  • Update .env file manually after getting API keys from web interfaces"
    fi
    
    return $?
}

# Function to setup files stack environment with smart merging
setup_files_env() {
    local stack_dir=$1
    local env_file="$stack_dir/.env"
    
    print_step "Setting up Files stack environment..."
    
    # Read existing values if file exists
    local existing_password=$(get_existing_env_value "$env_file" "JDOWNLOADER_VNC_PASSWORD")
    local existing_encryption_key=$(get_existing_env_value "$env_file" "PALMR_ENCRYPTION_KEY")
    
    # Show what we're preserving
    if [ -n "$existing_password" ]; then
        print_info "✓ Preserving existing JDownloader VNC password"
    fi
    if [ -n "$existing_encryption_key" ]; then
        print_info "✓ Preserving existing Palmr encryption key"
    fi
    
    local jdownloader_password="$existing_password"
    if [ -z "$jdownloader_password" ]; then
        jdownloader_password=$(get_password "Enter JDownloader VNC password (min 8 chars)")
    fi
    
    local palmr_encryption_key="$existing_encryption_key"
    if [ -z "$palmr_encryption_key" ]; then
        palmr_encryption_key=$(generate_random_string 32)
        print_info "Generated Palmr encryption key (32 chars)"
    fi
    
    # Create .env file with common settings and files-specific content
    local files_content="# JDownloader2 VNC password for web interface access
JDOWNLOADER_VNC_PASSWORD=$jdownloader_password

# Palmr encryption key for secure file sharing (32 chars minimum)
PALMR_ENCRYPTION_KEY=$palmr_encryption_key"
    
    create_env_file "$env_file" "Files" "$files_content"
    return $?
}

# Function to setup webtools stack environment with smart merging
setup_webtools_env() {
    local stack_dir=$1
    local env_file="$stack_dir/.env"
    
    print_step "Setting up Webtools stack environment..."
    
    # Read existing values if file exists
    local existing_password=$(get_existing_env_value "$env_file" "FIREFOX_VNC_PASSWORD")
    
    # Show what we're preserving
    if [ -n "$existing_password" ]; then
        print_info "✓ Preserving existing Firefox VNC password"
    fi
    
    local firefox_password="$existing_password"
    if [ -z "$firefox_password" ]; then
        firefox_password=$(get_password "Enter Firefox VNC password (min 8 chars)")
    fi
    
    # Create .env file with common settings and webtools-specific content
    local webtools_content="# Firefox VNC password for web interface access
FIREFOX_VNC_PASSWORD=$firefox_password"
    
    create_env_file "$env_file" "Webtools" "$webtools_content"
    return $?
}

# Function to setup monitoring stack environment with smart merging
setup_monitoring_env() {
    local stack_dir=$1
    local env_file="$stack_dir/.env"
    
    print_step "Setting up Monitoring stack environment..."
    
    # Read existing values if file exists
    local existing_grafana_pwd=$(get_existing_env_value "$env_file" "GRAFANA_ADMIN_PASSWORD")
    local existing_pve_pwd=$(get_existing_env_value "$env_file" "PVE_PASSWORD")
    local existing_email=$(get_existing_env_value "$env_file" "GMAIL_ADDRESS")
    local existing_email_pwd=$(get_existing_env_value "$env_file" "GMAIL_APP_PASSWORD")
    
    # Show what we're preserving
    if [ -n "$existing_grafana_pwd" ]; then
        print_info "✓ Preserving existing Grafana admin password"
    fi
    if [ -n "$existing_pve_pwd" ]; then
        print_info "✓ Preserving existing Proxmox monitoring password"
    fi
    if [ -n "$existing_email" ]; then
        print_info "✓ Preserving existing email: $existing_email"
    fi
    if [ -n "$existing_email_pwd" ]; then
        print_info "✓ Preserving existing email password"
    fi
    
    # Get missing values only
    local grafana_password="$existing_grafana_pwd"
    if [ -z "$grafana_password" ]; then
        grafana_password=$(get_password "Enter Grafana admin password (min 8 chars)")
    fi
    
    local pve_password="$existing_pve_pwd"
    if [ -z "$pve_password" ]; then
        pve_password=$(get_password "Enter Proxmox monitoring user password (min 8 chars)")
    fi
    
    local email_address="$existing_email"
    local email_password="$existing_email_pwd"
    
    if [ -z "$email_address" ] || [ -z "$email_password" ]; then
        print_step "Configuring email notifications..."
        echo
        print_info "Email configuration is required for system alerts from Alertmanager"
        print_info "For Gmail, you need to generate an App Password (not your regular password)"
        print_info "Gmail App Password instructions: https://myaccount.google.com/apppasswords"
        print_info "For other providers, use your regular email credentials or app-specific passwords"
        echo
        
        if [ -z "$email_address" ]; then
            while true; do
                read -p "Enter your email address: " email_address
                if [[ "$email_address" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
                    break
                else
                    print_error "Please enter a valid email address (e.g., user@example.com)"
                fi
            done
        fi
        
        if [ -z "$email_password" ]; then
            while true; do
                read -s -p "Enter email password: " email_password
                echo
                if [ -n "$email_password" ]; then
                    break
                else
                    print_error "Email password cannot be empty"
                fi
            done
        fi
    fi
    
    # Network Configuration - Hardcoded values
    print_step "Configuring network settings..."
    echo
    print_info "Using hardcoded network configuration:"
    print_info "LXC monitoring targets:"
    print_info "  • Proxy LXC (100): 192.168.1.100:9104"
    print_info "  • Media LXC (101): 192.168.1.101:9101" 
    print_info "  • Downloads LXC (102): 192.168.1.102:9102"
    print_info "  • Utility LXC (103): 192.168.1.103:9103"
    echo
    
    # Hardcoded network configuration
    local network_base="192.168.1"
    
    # Grafana dashboard URL for email notifications
    local grafana_url="http://192.168.1.104:3000"
    
    # Auto-detect Proxmox host IP for PVE URL
    local detected_ip=$(hostname -I | cut -d' ' -f1)
    local pve_url="https://${detected_ip}:8006"
    print_info "Using auto-detected Proxmox URL: $pve_url"
    
    
    # Create .env file with common settings and monitoring-specific content
    local monitoring_content="# Email notification settings for Alertmanager
GMAIL_ADDRESS=$email_address
GMAIL_APP_PASSWORD=$email_password

# Network Configuration
NETWORK_BASE=$network_base
GRAFANA_URL=$grafana_url

# Grafana admin credentials for dashboard access
GRAFANA_ADMIN_USER=admin
GRAFANA_ADMIN_PASSWORD=$grafana_password

# Proxmox monitoring credentials
PVE_USER=monitoring@pve
PVE_PASSWORD=$pve_password
PVE_URL=$pve_url
PVE_VERIFY_SSL=false"
    
    create_env_file "$stack_dir/.env" "Monitoring" "$monitoring_content"
    return $?
}

# Function to setup environment for specific stack
setup_stack_environment() {
    local stack_type=$1
    local stack_dir=$2
    
    # Ensure directory exists
    mkdir -p "$stack_dir"
    
    case $stack_type in
        "proxy")
            setup_proxy_env "$stack_dir"
            ;;
        "media")
            setup_media_env "$stack_dir"
            ;;
        "files")
            setup_files_env "$stack_dir"
            ;;
        "webtools")
            setup_webtools_env "$stack_dir"
            ;;
        "monitoring")
            setup_monitoring_env "$stack_dir"
            ;;
        *)
            print_error "Unknown stack type: $stack_type"
            return 1
            ;;
    esac
}

# Main function
main() {
    local stack_type=${1:-"all"}
    local base_dir=${2:-"/opt"}
    
    print_info "🔧 Interactive Stack Configuration Setup"
    echo ""
    
    case $stack_type in
        "proxy"|"media"|"files"|"webtools"|"monitoring")
            print_info "Setting up $stack_type stack configuration..."
            setup_stack_environment "$stack_type" "$base_dir/$stack_type-stack"
            ;;
        "all")
            print_info "Setting up all stack configurations..."
            
            # Setup each stack
            for stack in proxy media files webtools monitoring; do
                echo ""
                print_info "Setting up $stack stack..."
                setup_stack_environment "$stack" "$base_dir/$stack-stack"
            done
            ;;
        *)
            echo "Usage: $0 <stack_type> [base_dir]"
            echo "Stack types: proxy, media, files, webtools, monitoring, all"
            echo "Base dir: Directory where stack folders are located (default: /opt)"
            echo ""
            echo "Examples:"
            echo "  $0 files /opt         # Setup files stack only"
            echo "  $0 monitoring /opt    # Setup monitoring stack only"
            echo "  $0 all /opt           # Setup all stacks"
            exit 1
            ;;
    esac
    
    print_info "✅ Configuration setup completed!"
    
    if [ "$stack_type" = "all" ]; then
        print_warning "REMINDER: Configure services through their web UIs and update credentials as needed"
    fi
}

# Execute main function
main "$@"