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
source "$SCRIPT_DIR/../utils/common.sh"

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
            echo "$password"
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
    print_info "✓ ${stack_name} .env file created"
}

# Function to setup proxy stack environment
setup_proxy_env() {
    local stack_dir=$1
    
    print_step "Setting up Proxy stack environment..."
    
    # Get Cloudflare tunnel token with validation
    while true; do
        echo -n "Enter your Cloudflare tunnel token: "
        read cloudflare_token
        
        if check_empty "$cloudflare_token" "Cloudflare token"; then
            break
        fi
        print_warning "Please enter a valid Cloudflare tunnel token"
    done
    
    # Create .env file with common settings and proxy-specific content
    local proxy_content="# Cloudflare tunnel token for secure connections
CLOUDFLARED_TOKEN=$cloudflare_token"
    
    create_env_file "$stack_dir/.env" "Proxy" "$proxy_content"
    return $?
}

# Function to setup media stack environment
setup_media_env() {
    local stack_dir=$1
    
    print_step "Setting up Media stack environment..."
    
    # Media stack includes API key placeholders for services
    local media_content="# API Keys for service integration (get from web UIs after deployment)
# Sonarr API Key (get from: Settings > General > API Key)
SONARR_API_KEY=

# Radarr API Key (get from: Settings > General > API Key)  
RADARR_API_KEY=

# qBittorrent Credentials (default username is usually 'admin')
QB_USERNAME=admin
QB_PASSWORD="
    
    create_env_file "$stack_dir/.env" "Media" "$media_content"
    return $?
}

# Function to setup downloads stack environment
setup_downloads_env() {
    local stack_dir=$1
    
    print_step "Setting up Downloads stack environment..."
    
    # Get JDownloader VNC password
    local jdownloader_password=$(get_password "Enter JDownloader VNC password (min 8 chars)")
    
    # Create .env file with common settings and downloads-specific content
    local downloads_content="# JDownloader2 VNC password for web interface access
JDOWNLOADER_VNC_PASSWORD=$jdownloader_password"
    
    create_env_file "$stack_dir/.env" "Downloads" "$downloads_content"
    return $?
}

# Function to setup utility stack environment
setup_utility_env() {
    local stack_dir=$1
    
    print_step "Setting up Utility stack environment..."
    
    # Get Firefox VNC password
    local firefox_password=$(get_password "Enter Firefox VNC password (min 8 chars)")
    
    # Create .env file with common settings and utility-specific content
    local utility_content="# Firefox VNC password for web interface access
FIREFOX_VNC_PASSWORD=$firefox_password"
    
    create_env_file "$stack_dir/.env" "Utility" "$utility_content"
    return $?
}

# Function to setup monitoring stack environment
setup_monitoring_env() {
    local stack_dir=$1
    
    print_step "Setting up Monitoring stack environment..."
    
    # Get Grafana admin password
    local grafana_password=$(get_password "Enter Grafana admin password (min 8 chars)")
    
    # Get Proxmox monitoring user password
    local pve_password=$(get_password "Enter Proxmox monitoring user password (min 8 chars)")
    
    # Get email configuration for alerts
    print_step "Configuring email notifications..."
    echo
    print_info "Email configuration is required for system alerts from Alertmanager"
    print_info "For Gmail, you need to generate an App Password (not your regular password)"
    print_info "Gmail App Password instructions: https://myaccount.google.com/apppasswords"
    print_info "For other providers, use your regular email credentials or app-specific passwords"
    echo
    
    local email_address
    while true; do
        read -p "Enter your email address: " email_address
        if [[ "$email_address" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
            break
        else
            print_error "Please enter a valid email address (e.g., user@example.com)"
        fi
    done
    
    local email_password
    while true; do
        read -s -p "Enter email password: " email_password
        echo
        if [ -n "$email_password" ]; then
            break
        else
            print_error "Email password cannot be empty"
        fi
    done
    
    # Network Configuration
    print_step "Configuring network settings..."
    echo
    print_info "Network configuration for monitoring targets:"
    print_info "This determines which IPs Prometheus will monitor"
    echo
    
    # Auto-detect Proxmox local IP and construct URL
    # Simple network detection
    local detected_ip=$(hostname -I | cut -d' ' -f1)
    local default_base="192.168.1"
    
    # Extract network base if IP detected
    if [ -n "$detected_ip" ]; then
        default_base=$(echo "$detected_ip" | cut -d'.' -f1-3)
    fi
    
    print_info "Detected network base: $default_base"
    print_info "LXC monitoring targets will be:"
    print_info "  • Proxy LXC (100): ${default_base}.100:9104"
    print_info "  • Media LXC (101): ${default_base}.101:9101" 
    print_info "  • Downloads LXC (102): ${default_base}.102:9102"
    print_info "  • Utility LXC (103): ${default_base}.103:9103"
    echo
    
    local network_base
    while true; do
        read -p "Network base [${default_base}]: " network_base
        network_base=${network_base:-$default_base}
        
        # Validate network base format (should be X.X.X format)
        if [[ "$network_base" =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$ ]]; then
            # Check if each octet is valid (0-255)
            local octet1=${BASH_REMATCH[1]}
            local octet2=${BASH_REMATCH[2]}
            local octet3=${BASH_REMATCH[3]}
            
            if [ "$octet1" -ge 0 ] && [ "$octet1" -le 255 ] && \
               [ "$octet2" -ge 0 ] && [ "$octet2" -le 255 ] && \
               [ "$octet3" -ge 0 ] && [ "$octet3" -le 255 ]; then
                break
            else
                print_error "Invalid network base: octets must be between 0-255"
            fi
        else
            print_error "Invalid network base format. Expected format: X.X.X (e.g., 192.168.1)"
        fi
    done
    
    # Grafana dashboard URL for email notifications
    local default_grafana_url="http://${network_base}.104:3000"
    local grafana_url
    read -p "Grafana dashboard URL [${default_grafana_url}]: " grafana_url
    grafana_url=${grafana_url:-$default_grafana_url}
    
    local default_pve_url="https://${detected_ip}:8006"
    
    # Use auto-detected Proxmox URL
    local pve_url="$default_pve_url"
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
        "downloads")
            setup_downloads_env "$stack_dir"
            ;;
        "utility")
            setup_utility_env "$stack_dir"
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
        "proxy"|"media"|"downloads"|"utility"|"monitoring")
            print_info "Setting up $stack_type stack configuration..."
            setup_stack_environment "$stack_type" "$base_dir/$stack_type-stack"
            ;;
        "all")
            print_info "Setting up all stack configurations..."
            
            # Setup each stack
            for stack in proxy media downloads utility monitoring; do
                echo ""
                print_info "Setting up $stack stack..."
                setup_stack_environment "$stack" "$base_dir/$stack-stack"
            done
            ;;
        *)
            echo "Usage: $0 <stack_type> [base_dir]"
            echo "Stack types: proxy, media, downloads, utility, monitoring, all"
            echo "Base dir: Directory where stack folders are located (default: /opt)"
            echo ""
            echo "Examples:"
            echo "  $0 downloads /opt     # Setup downloads stack only"
            echo "  $0 monitoring /opt    # Setup monitoring stack only"
            echo "  $0 all /opt           # Setup all stacks"
            exit 1
            ;;
    esac
    
    echo ""
    print_info "✅ Configuration setup completed!"
    
    if [ "$stack_type" = "all" ]; then
        print_warning "REMINDER: Configure services through their web UIs and update credentials as needed"
    fi
}

# Execute main function
main "$@"