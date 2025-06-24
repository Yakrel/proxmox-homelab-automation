#!/bin/bash

# Interactive Password and Configuration Setup Script
# Simplified version using unified functions from common.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common utilities
if [ -f "$SCRIPT_DIR/../utils/common.sh" ]; then
    source "$SCRIPT_DIR/../utils/common.sh"
elif [ -f "/tmp/common.sh" ]; then
    source "/tmp/common.sh"
else
    echo "[ERROR] common.sh not found!" >&2
    exit 1
fi

# Function to setup proxy stack environment
setup_proxy_env() {
    local stack_dir=$1
    local env_file="$stack_dir/.env"
    
    print_step "Setting up Proxy stack environment..."
    
    # Check for existing token
    local existing_token=$(get_existing_env_value "$env_file" "CLOUDFLARED_TOKEN")
    
    if [ -n "$existing_token" ]; then
        print_info "✓ Preserving existing Cloudflare tunnel token: ${existing_token:0:8}..."
    fi
    
    local cloudflare_token="$existing_token"
    if [ -z "$cloudflare_token" ]; then
        while true; do
            echo -n "Enter your Cloudflare tunnel token: "
            read cloudflare_token
            
            if [ -n "$cloudflare_token" ]; then
                break
            fi
            print_warning "Please enter a valid Cloudflare tunnel token"
        done
    fi
    
    # Create .env file
    local proxy_content="# Cloudflare tunnel token for secure connections
CLOUDFLARED_TOKEN=$cloudflare_token"
    
    create_stack_env_file "$env_file" "Proxy" "$proxy_content"
    return $?
}

# Function to setup media stack environment
setup_media_env() {
    local stack_dir=$1
    local env_file="$stack_dir/.env"
    
    print_step "Setting up Media stack environment..."
    
    # Check for existing values
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
        print_info "✓ Preserving existing qBittorrent password"
    fi
    
    # Use existing values or hardcoded homelab defaults
    local sonarr_key=${existing_sonarr_key:-""}
    local radarr_key=${existing_radarr_key:-""}
    local qb_username=${existing_qb_username:-"admin"}  # Hardcoded for homelab
    local qb_password=${existing_qb_password:-""}
    
    # Create .env file
    local media_content="# API Keys for service integration (get from web UIs after deployment)
# Sonarr API Key (get from: Settings > General > API Key)
SONARR_API_KEY=$sonarr_key

# Radarr API Key (get from: Settings > General > API Key)  
RADARR_API_KEY=$radarr_key

# qBittorrent Credentials
QB_USERNAME=$qb_username
QB_PASSWORD=$qb_password"
    
    create_stack_env_file "$env_file" "Media" "$media_content"
    
    # Show guidance for empty API keys (hardcoded homelab IPs)
    if [ -z "$existing_sonarr_key" ] || [ -z "$existing_radarr_key" ]; then
        echo
        print_info "📝 API Key Setup Guidance (homelab URLs):"
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

# Function to setup files stack environment
setup_files_env() {
    local stack_dir=$1
    local env_file="$stack_dir/.env"
    
    print_step "Setting up Files stack environment..."
    
    # Check for existing values
    local existing_password=$(get_existing_env_value "$env_file" "JDOWNLOADER_VNC_PASSWORD")
    local existing_encryption_key=$(get_existing_env_value "$env_file" "PALMR_ENCRYPTION_KEY")
    
    if [ -n "$existing_password" ]; then
        print_info "✓ Preserving existing JDownloader VNC password"
    fi
    if [ -n "$existing_encryption_key" ]; then
        print_info "✓ Preserving existing Palmr encryption key"
    fi
    
    local jdownloader_password="$existing_password"
    if [ -z "$jdownloader_password" ]; then
        jdownloader_password=$(get_simple_password "Enter JDownloader VNC password")
        if [ $? -ne 0 ] || [ -z "$jdownloader_password" ]; then
            print_error "Failed to get JDownloader VNC password"
            return 1
        fi
    fi
    
    local palmr_encryption_key="$existing_encryption_key"
    if [ -z "$palmr_encryption_key" ]; then
        palmr_encryption_key=$(generate_encryption_key 32)
        print_info "Generated Palmr encryption key (32 chars)"
    fi
    
    # Create .env file
    local files_content="# JDownloader2 VNC password for web interface access
JDOWNLOADER_VNC_PASSWORD=$jdownloader_password

# Palmr encryption key for secure file sharing (32 chars minimum)
PALMR_ENCRYPTION_KEY=$palmr_encryption_key"
    
    create_stack_env_file "$env_file" "Files" "$files_content"
    return $?
}

# Function to setup webtools stack environment
setup_webtools_env() {
    local stack_dir=$1
    local env_file="$stack_dir/.env"
    
    print_step "Setting up Webtools stack environment..."
    
    # Check for existing password
    local existing_password=$(get_existing_env_value "$env_file" "FIREFOX_VNC_PASSWORD")
    
    if [ -n "$existing_password" ]; then
        print_info "✓ Preserving existing Firefox VNC password"
    fi
    
    local firefox_password="$existing_password"
    if [ -z "$firefox_password" ]; then
        firefox_password=$(get_simple_password "Enter Firefox VNC password")
        if [ $? -ne 0 ] || [ -z "$firefox_password" ]; then
            print_error "Failed to get Firefox VNC password"
            return 1
        fi
    fi
    
    # Create .env file
    local webtools_content="# Firefox VNC password for web interface access
FIREFOX_VNC_PASSWORD=$firefox_password"
    
    create_stack_env_file "$env_file" "Webtools" "$webtools_content"
    return $?
}

# Function to setup monitoring stack environment
setup_monitoring_env() {
    local stack_dir=$1
    local env_file="$stack_dir/.env"
    
    print_step "Setting up Monitoring stack environment..."
    
    # Check for existing values
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
        grafana_password=$(get_simple_password "Enter Grafana admin password")
        if [ $? -ne 0 ] || [ -z "$grafana_password" ]; then
            print_error "Failed to get Grafana admin password"
            return 1
        fi
    fi
    
    local pve_password="$existing_pve_pwd"
    if [ -z "$pve_password" ]; then
        pve_password=$(get_simple_password "Enter Proxmox monitoring user password")
        if [ $? -ne 0 ] || [ -z "$pve_password" ]; then
            print_error "Failed to get Proxmox monitoring password"
            return 1
        fi
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
    
    # Hardcoded network configuration for homelab (simplified)
    local grafana_url="http://192.168.1.104:3000"
    local pve_url="https://192.168.1.10:8006"
    
    # Create .env file
    local monitoring_content="# Email notification settings for Alertmanager
GMAIL_ADDRESS=$email_address
GMAIL_APP_PASSWORD=$email_password

# Network Configuration (hardcoded for homelab)
GRAFANA_URL=$grafana_url

# Grafana admin credentials for dashboard access
GRAFANA_ADMIN_USER=admin
GRAFANA_ADMIN_PASSWORD=$grafana_password

# Proxmox monitoring credentials (hardcoded for homelab)
PVE_USER=monitoring@pve
PVE_PASSWORD=$pve_password
PVE_URL=$pve_url
PVE_VERIFY_SSL=false"
    
    create_stack_env_file "$env_file" "Monitoring" "$monitoring_content"
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
    
    exit 0
}

# Execute main function
main "$@"