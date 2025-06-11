#!/bin/bash

# Interactive Password and Configuration Setup Script - Optimized Version
# Prompts user for passwords and creates .env files automatically

set -e

# Source common functions
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
source "$SCRIPT_DIR/../common/functions.sh"

# Simple password validation
validate_password() {
    local password=$1
    
    if [ ${#password} -lt 8 ]; then
        print_error "Password must be at least 8 characters long"
        return 1
    fi
    
    if ! [[ "$password" =~ [0-9] ]] || ! [[ "$password" =~ [a-zA-Z] ]]; then
        print_error "Password must contain both letters and numbers"
        return 1
    fi
    
    return 0
}

# Get secure password input
get_password() {
    local prompt="$1"
    local password=""
    
    while true; do
        print_step "$prompt"
        read -s -p "Password: " password
        echo
        
        if validate_password "$password"; then
            read -s -p "Confirm password: " confirm_password
            echo
            
            if [ "$password" = "$confirm_password" ]; then
                echo "$password"
                return 0
            else
                print_error "Passwords do not match!"
            fi
        fi
    done
}

# Generate random password
generate_password() {
    openssl rand -base64 12 | tr -d "=+/" | cut -c1-12
}

# Setup environment for specific stack
setup_stack_env() {
    local stack_type="$1"
    local stack_dir="$2"
    
    print_step "Setting up $stack_type stack configuration..."
    
    # Create base .env file
    cat > "$stack_dir/.env" << EOF
# Environment file for $stack_type stack
TZ=Europe/Istanbul
PUID=1000
PGID=1000
UMASK=002

EOF
    
    case "$stack_type" in
        "proxy")
            print_info "Cloudflare tunnel setup required:"
            print_info "1. Go to https://dash.cloudflare.com/"
            print_info "2. Create a tunnel and get the token"
            read -p "Enter Cloudflare tunnel token: " cf_token
            echo "CLOUDFLARED_TOKEN=$cf_token" >> "$stack_dir/.env"
            ;;
            
        "downloads")
            local jd_pass=$(get_password "Set JDownloader VNC password")
            echo "JDOWNLOADER_VNC_PASSWORD=$jd_pass" >> "$stack_dir/.env"
            ;;
            
        "utility")
            local ff_pass=$(get_password "Set Firefox VNC password")
            echo "FIREFOX_VNC_PASSWORD=$ff_pass" >> "$stack_dir/.env"
            ;;
            
        "monitoring")
            local grafana_pass=$(get_password "Set Grafana admin password")
            echo "GRAFANA_ADMIN_PASSWORD=$grafana_pass" >> "$stack_dir/.env"
            
            print_info "Proxmox monitoring user setup:"
            read -p "Proxmox username (default: monitoring@pve): " pve_user
            pve_user=${pve_user:-monitoring@pve}
            
            local pve_pass=$(get_password "Set Proxmox monitoring user password")
            
            read -p "Proxmox URL (e.g., https://192.168.1.10:8006): " pve_url
            
            echo "PVE_USER=$pve_user" >> "$stack_dir/.env"
            echo "PVE_PASSWORD=$pve_pass" >> "$stack_dir/.env"
            echo "PVE_URL=$pve_url" >> "$stack_dir/.env"
            ;;
            
        "media")
            print_info "Media stack uses default configuration"
            print_info "Configure services through their web interfaces after deployment"
            ;;
    esac
    
    print_info "✓ Configuration saved to $stack_dir/.env"
}

# Main interactive setup
main() {
    local stack_type="$1"
    local stack_dir="$2"
    
    if [ -z "$stack_type" ] || [ -z "$stack_dir" ]; then
        print_error "Usage: $0 <stack_type> <stack_dir>"
        print_info "Available types: proxy, media, downloads, utility, monitoring"
        exit 1
    fi
    
    # Validate stack type
    case "$stack_type" in
        proxy|media|downloads|utility|monitoring)
            ;;
        *)
            print_error "Invalid stack type: $stack_type"
            exit 1
            ;;
    esac
    
    print_info "🔧 Interactive setup for $stack_type stack"
    echo "================================="
    
    # Create directory if not exists
    mkdir -p "$stack_dir"
    
    # Check if .env already exists
    if [ -f "$stack_dir/.env" ]; then
        read -p ".env file exists. Overwrite? [y/N]: " overwrite
        if [[ ! "$overwrite" =~ ^[Yy]$ ]]; then
            print_info "Keeping existing configuration"
            exit 0
        fi
    fi
    
    setup_stack_env "$stack_type" "$stack_dir"
    
    print_info "✅ Interactive setup completed for $stack_type stack"
    print_info "   Configuration: $stack_dir/.env"
    print_warning "Review the configuration before deploying the stack"
}

# Run main function
main "$@"