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

# Function to get secure password input
get_password() {
    local prompt=$1
    local password
    local password_confirm
    
    while true; do
        echo -n "$prompt: "
        read -s password
        echo ""
        
        if [ ${#password} -lt 8 ]; then
            print_error "Password must be at least 8 characters long"
            continue
        fi
        
        echo -n "Confirm password: "
        read -s password_confirm
        echo ""
        
        if [ "$password" = "$password_confirm" ]; then
            echo "$password"
            return 0
        else
            print_error "Passwords do not match. Please try again."
        fi
    done
}

# Function to setup proxy stack environment
setup_proxy_env() {
    local stack_dir=$1
    
    print_step "Setting up Proxy stack environment..."
    
    # Get Cloudflare tunnel token
    echo -n "Enter your Cloudflare tunnel token: "
    read cloudflare_token
    
    if [ -z "$cloudflare_token" ]; then
        print_error "Cloudflare tunnel token is required for proxy stack"
        return 1
    fi
    
    # Create .env file
    cat > "$stack_dir/.env" << EOF
# Proxy Stack Environment Variables - Generated $(date)

# Cloudflare tunnel token for secure connections
CLOUDFLARED_TOKEN=$cloudflare_token

# Timezone setting
TZ=Europe/Istanbul

# PUID/PGID for file permissions (proxy stack uses 100000)
PUID=100000
PGID=100000
EOF
    
    print_info "✓ Proxy stack .env file created successfully"
    return 0
}

# Function to setup media stack environment
setup_media_env() {
    local stack_dir=$1
    
    print_step "Setting up Media stack environment..."
    
    # Media stack doesn't require passwords, just create basic .env
    cat > "$stack_dir/.env" << EOF
# Media Stack Environment Variables - Generated $(date)

# Timezone setting
TZ=Europe/Istanbul

# PUID/PGID for file permissions
PUID=1000
PGID=1000

# No additional passwords required for media stack
# All services use web-based configuration interfaces
EOF
    
    print_info "✓ Media stack .env file created successfully"
    print_info "Configure services through their web UIs after deployment"
    return 0
}

# Function to setup downloads stack environment
setup_downloads_env() {
    local stack_dir=$1
    
    print_step "Setting up Downloads stack environment..."
    
    # Get JDownloader VNC password
    local jdownloader_password=$(get_password "Enter JDownloader VNC password (min 8 chars)")
    
    # Create .env file
    cat > "$stack_dir/.env" << EOF
# Downloads Stack Environment Variables - Generated $(date)

# JDownloader2 VNC password for web interface access
JDOWNLOADER_VNC_PASSWORD=$jdownloader_password

# Timezone setting
TZ=Europe/Istanbul

# PUID/PGID for file permissions  
PUID=1000
PGID=1000
EOF
    
    print_info "✓ Downloads stack .env file created successfully"
    return 0
}

# Function to setup utility stack environment
setup_utility_env() {
    local stack_dir=$1
    
    print_step "Setting up Utility stack environment..."
    
    # Get Firefox VNC password
    local firefox_password=$(get_password "Enter Firefox VNC password (min 8 chars)")
    
    # Create .env file
    cat > "$stack_dir/.env" << EOF
# Utility Stack Environment Variables - Generated $(date)

# Firefox VNC password for web interface access
FIREFOX_VNC_PASSWORD=$firefox_password

# Timezone setting
TZ=Europe/Istanbul

# PUID/PGID for file permissions
PUID=1000
PGID=1000
EOF
    
    print_info "✓ Utility stack .env file created successfully"
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
        "proxy"|"media"|"downloads"|"utility")
            print_info "Setting up $stack_type stack configuration..."
            setup_stack_environment "$stack_type" "$base_dir/$stack_type-stack"
            ;;
        "all")
            print_info "Setting up all stack configurations..."
            
            # Setup each stack
            for stack in proxy media downloads utility; do
                echo ""
                print_info "Setting up $stack stack..."
                setup_stack_environment "$stack" "$base_dir/$stack-stack"
            done
            ;;
        *)
            echo "Usage: $0 <stack_type> [base_dir]"
            echo "Stack types: proxy, media, downloads, utility, all"
            echo "Base dir: Directory where stack folders are located (default: /opt)"
            echo ""
            echo "Examples:"
            echo "  $0 downloads /opt    # Setup downloads stack only"
            echo "  $0 all /opt          # Setup all stacks"
            exit 1
            ;;
    esac
    
    echo ""
    print_info "✅ Configuration setup completed!"
    
    if [ "$stack_type" = "all" ]; then
        print_warning "Remember to:"
        print_info "1. Keep your passwords secure"
        print_info "2. Deploy stacks: docker-compose up -d"
        print_info "3. Configure individual services through their web UIs"
    fi
}

# Execute main function
main "$@"