#!/bin/bash

# Interactive Password and Configuration Setup Script
# Prompts user for passwords and creates .env files automatically

set -e

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

# Enhanced password validation function
validate_password_strength() {
    local password=$1
    local errors=()
    
    # Check minimum length
    if [ ${#password} -lt 8 ]; then
        errors+=("Password must be at least 8 characters long")
    fi
    
    # Check for at least one number
    if ! [[ "$password" =~ [0-9] ]]; then
        errors+=("Password must contain at least one number")
    fi
    
    # Check for at least one letter
    if ! [[ "$password" =~ [a-zA-Z] ]]; then
        errors+=("Password must contain at least one letter")
    fi
    
    # Check for weak patterns
    if [[ "$password" =~ ^[0-9]+$ ]] || [[ "$password" =~ ^[a-zA-Z]+$ ]]; then
        errors+=("Password should contain a mix of letters and numbers")
    fi
    
    if [ ${#errors[@]} -gt 0 ]; then
        for error in "${errors[@]}"; do
            print_error "$error"
        done
        return 1
    fi
    
    return 0
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
        print_error "Invalid URL format. Expected format: http(s)://hostname[:port][/path][?query][#fragment]"
        return 1
    fi
    return 0
}

# Function to validate Cloudflare token format
validate_cloudflare_token() {
    local token=$1
    
    # Cloudflare tunnel tokens are typically 40+ character alphanumeric strings
    if [ ${#token} -lt 40 ]; then
        print_error "Cloudflare token appears too short (expected 40+ characters)"
        return 1
    fi
    
    if ! [[ "$token" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        print_error "Cloudflare token contains invalid characters"
        return 1
    fi
    
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
            print_warning "Please choose a stronger password"
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

# Function to setup proxy stack environment
setup_proxy_env() {
    local stack_dir=$1
    
    print_step "Setting up Proxy stack environment..."
    
    # Get Cloudflare tunnel token with validation
    while true; do
        echo -n "Enter your Cloudflare tunnel token: "
        read cloudflare_token
        
        if validate_not_empty "$cloudflare_token" "Cloudflare tunnel token" && validate_cloudflare_token "$cloudflare_token"; then
            break
        fi
        print_warning "Please enter a valid Cloudflare tunnel token"
    done
    
    # Create .env file with common settings and proxy-specific content
    local proxy_content="# Cloudflare tunnel token for secure connections
CLOUDFLARED_TOKEN=$cloudflare_token"
    
    create_common_env_content "Proxy" "$proxy_content" > "$stack_dir/.env"
    chmod 600 "$stack_dir/.env"
    
    print_info "✓ Proxy stack .env file created successfully with secure permissions"
    return 0
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
    
    create_common_env_content "Media" "$media_content" > "$stack_dir/.env"
    chmod 600 "$stack_dir/.env"
    
    print_info "✓ Media stack .env file created successfully with secure permissions"
    return 0
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
    
    create_common_env_content "Downloads" "$downloads_content" > "$stack_dir/.env"
    chmod 600 "$stack_dir/.env"
    
    print_info "✓ Downloads stack .env file created successfully with secure permissions"
    return 0
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
    
    create_common_env_content "Utility" "$utility_content" > "$stack_dir/.env"
    chmod 600 "$stack_dir/.env"
    
    print_info "✓ Utility stack .env file created successfully with secure permissions"
    return 0
}

# Function to setup monitoring stack environment
setup_monitoring_env() {
    local stack_dir=$1
    
    print_step "Setting up Monitoring stack environment..."
    
    # Get Grafana admin password
    local grafana_password=$(get_password "Enter Grafana admin password (min 8 chars)")
    
    # Get Proxmox monitoring user password
    local pve_password=$(get_password "Enter Proxmox monitoring user password (min 8 chars)")
    
    # Auto-detect Proxmox local IP and construct URL
    # Try multiple methods to get the primary local network IP
    local detected_ip
    
    # Method 1: Get IP from default route interface
    detected_ip=$(ip route show default | head -1 | awk '{print $5}' | xargs -I {} ip addr show {} | grep 'inet ' | grep -v '127.0.0.1' | head -1 | awk '{print $2}' | cut -d'/' -f1 2>/dev/null)
    
    # Method 2: Fallback to first non-loopback IP
    if [ -z "$detected_ip" ]; then
        detected_ip=$(ip addr show | grep 'inet ' | grep -v '127.0.0.1' | head -1 | awk '{print $2}' | cut -d'/' -f1 2>/dev/null)
    fi
    
    # Method 3: Final fallback
    if [ -z "$detected_ip" ]; then
        detected_ip=$(hostname -I | awk '{print $1}' 2>/dev/null)
    fi
    
    # If still no IP found, use placeholder
    if [ -z "$detected_ip" ]; then
        detected_ip="YOUR_PROXMOX_IP"
    fi
    
    local default_pve_url="https://${detected_ip}:8006"
    
    # Use auto-detected Proxmox URL
    local pve_url="$default_pve_url"
    print_info "Using auto-detected Proxmox URL: $pve_url"
    
    
    # Create .env file with common settings and monitoring-specific content
    local monitoring_content="# Grafana admin credentials for dashboard access
GRAFANA_ADMIN_USER=admin
GRAFANA_ADMIN_PASSWORD=$grafana_password

# Proxmox monitoring credentials
PVE_USER=monitoring@pve
PVE_PASSWORD=$pve_password
PVE_URL=$pve_url
PVE_VERIFY_SSL=false"
    
    create_common_env_content "Monitoring" "$monitoring_content" > "$stack_dir/.env"
    chmod 600 "$stack_dir/.env"
    
    print_info "✓ Monitoring stack .env file created successfully with secure permissions"
    return 0
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