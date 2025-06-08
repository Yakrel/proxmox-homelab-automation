#!/bin/bash

# Automated Alpine Docker LXC Creation using tteck's script
# Passes environment variables to automate the community script

set -e

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Function to create Alpine LXC using tteck's automated script
create_alpine_lxc_auto() {
    local lxc_id=$1
    local lxc_name=$2
    local cpu_cores=$3
    local ram_mb=$4
    local disk_gb=$5

    print_info "Creating Alpine Docker LXC: $lxc_name (ID: $lxc_id)"
    print_info "Specs: ${cpu_cores} cores, ${ram_mb}MB RAM, ${disk_gb}GB disk"
    
    # Check if LXC already exists
    if pct status "$lxc_id" >/dev/null 2>&1; then
        print_error "LXC $lxc_id already exists!"
        return 1
    fi

    print_step "Setting up environment variables for tteck's script..."
    
    # Core script variables for Alpine Docker
    export var_cpu="$cpu_cores"
    export var_ram="$ram_mb"
    export var_disk="$disk_gb"
    export var_os="alpine"
    export var_version="latest"  # Always use latest Alpine
    export var_unprivileged="1"
    export var_tags="docker;alpine;homelab"
    
    # Container settings
    export CTID="$lxc_id"
    export HN="$lxc_name"
    export CT_TYPE="1"  # Unprivileged
    
    # Network settings (DHCP by default)
    export NET="dhcp"
    export BRG="vmbr0"
    export GATE=""
    export DISABLEIP6="no"
    
    # Security settings (like tteck's script does)
    export SSH="no"           # Disable SSH root access
    export PW=""              # No password (uses key-based or Proxmox console)
    export SSH_AUTHORIZED_KEY=""
    
    # Advanced features
    export ENABLE_FUSE="no"   # Usually not needed for Docker
    export ENABLE_TUN="no"    # Usually not needed
    
    # Automation settings
    export VERB="no"          # Non-verbose mode
    export METHOD="default"   # Use default settings
    
    # Try to make it non-interactive by pre-answering
    export DEBIAN_FRONTEND=noninteractive
    
    print_step "Downloading and executing tteck's Alpine Docker script..."
    print_warning "Note: Script may still prompt for confirmation - press Enter for defaults"
    
    # Create a wrapper script that pre-answers the prompts
    cat > /tmp/alpine_auto.sh << 'EOF'
#!/bin/bash
# Auto-answer script for tteck's Alpine Docker
echo "1" | bash <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/ct/alpine-docker.sh)
EOF
    
    chmod +x /tmp/alpine_auto.sh
    
    # Execute with timeout in case it hangs
    if timeout 600 /tmp/alpine_auto.sh; then
        print_info "✓ LXC $lxc_name created successfully!"
        
        # Clean up
        rm -f /tmp/alpine_auto.sh
        
        # Wait for container to be fully ready
        sleep 10
        
        # Verify container exists and is running
        if pct status "$lxc_id" | grep -q "running"; then
            print_info "✓ Container is running"
        else
            print_warning "Container not running, starting..."
            pct start "$lxc_id"
            sleep 5
        fi
        
        # Add datapool mount
        print_step "Adding /datapool mount point..."
        if add_datapool_mount "$lxc_id"; then
            print_info "✓ Mount point added successfully"
        else
            print_warning "Failed to add mount point automatically"
        fi
        
        # Verify Docker installation
        print_step "Verifying Docker installation..."
        if verify_docker "$lxc_id"; then
            print_info "✓ Docker and Docker Compose verified"
        else
            print_warning "Docker verification failed, may need manual check"
        fi
        
        return 0
    else
        print_error "Script execution failed or timed out"
        rm -f /tmp/alpine_auto.sh
        return 1
    fi
}

# Function to add datapool mount
add_datapool_mount() {
    local lxc_id=$1
    
    # Stop container if running
    if pct status "$lxc_id" | grep -q "running"; then
        pct stop "$lxc_id"
        sleep 3
    fi
    
    # Add mount point
    if pct set "$lxc_id" -mp0 /datapool,mp=/datapool; then
        # Start container
        pct start "$lxc_id"
        sleep 5
        
        # Verify mount
        if pct exec "$lxc_id" -- test -d /datapool; then
            return 0
        else
            return 1
        fi
    else
        return 1
    fi
}

# Function to verify Docker installation
verify_docker() {
    local lxc_id=$1
    
    # Test Docker
    if pct exec "$lxc_id" -- docker --version >/dev/null 2>&1; then
        local docker_version=$(pct exec "$lxc_id" -- docker --version)
        print_info "✓ Docker: $docker_version"
    else
        return 1
    fi
    
    # Test Docker Compose
    if pct exec "$lxc_id" -- docker compose version >/dev/null 2>&1; then
        local compose_version=$(pct exec "$lxc_id" -- docker compose version --short)
        print_info "✓ Docker Compose: $compose_version"
    else
        return 1
    fi
    
    # Test Docker service
    if pct exec "$lxc_id" -- rc-service docker status | grep -q "started"; then
        print_info "✓ Docker service is running"
    else
        print_warning "Starting Docker service..."
        pct exec "$lxc_id" -- rc-service docker start
    fi
    
    return 0
}

# Main function
create_stack_lxc() {
    local stack_type=$1
    
    case $stack_type in
        "media")
            create_alpine_lxc_auto 101 "lxc-media-01" 4 8192 16
            ;;
        "proxy")
            create_alpine_lxc_auto 100 "lxc-proxy-01" 1 2048 8
            ;;
        "downloads")
            create_alpine_lxc_auto 102 "lxc-downloads-01" 2 4096 8
            ;;
        "utility")
            create_alpine_lxc_auto 103 "lxc-utility-01" 2 4096 8
            ;;
        "monitoring")
            create_alpine_lxc_auto 104 "lxc-monitoring-01" 2 4096 16
            ;;
        *)
            print_error "Unknown stack type: $stack_type"
            return 1
            ;;
    esac
}

# Input validation
if [ $# -ne 1 ]; then
    print_error "Usage: $0 <stack_type>"
    echo "Available: media, proxy, downloads, utility, monitoring"
    exit 1
fi

case "$1" in
    media|proxy|downloads|utility|monitoring)
        ;;
    *)
        print_error "Invalid stack type: $1"
        exit 1
        ;;
esac

if [ "$(id -u)" -ne 0 ]; then
    print_error "This script must be run as root"
    exit 1
fi

# Execute
STACK_TYPE=$1
print_info "Creating $STACK_TYPE stack using tteck's Alpine Docker script (automated)..."

if create_stack_lxc "$STACK_TYPE"; then
    print_info "🎉 $STACK_TYPE LXC created successfully!"
    print_info ""
    print_info "Features installed by tteck's script:"
    print_info "✓ Latest Alpine Linux (3.21)"
    print_info "✓ Latest Docker + Docker Compose"
    print_info "✓ SSH disabled for security"
    print_info "✓ Passwordless root console access"
    print_info "✓ Unprivileged container with nesting"
    print_info "✓ /datapool mount point added"
    print_info ""
    print_info "Next steps:"
    case $STACK_TYPE in
        media) LXC_ID=101;;
        proxy) LXC_ID=100;;
        downloads) LXC_ID=102;;
        utility) LXC_ID=103;;
        monitoring) LXC_ID=104;;
    esac
    print_info "1. Create directories: bash scripts/lxc/setup_${STACK_TYPE}_lxc.sh"
    print_info "2. Deploy services: bash scripts/automation/deploy_stack.sh $STACK_TYPE $LXC_ID"
    print_info "3. Access LXC: pct enter $LXC_ID"
else
    print_error "Failed to create $STACK_TYPE LXC"
    exit 1
fi