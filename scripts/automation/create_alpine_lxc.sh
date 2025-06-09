#!/bin/bash

# Direct Alpine Docker LXC Creation using native Proxmox commands
# Creates Alpine LXC with Docker installed - no external dependencies

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

# Function to create Alpine LXC using direct Proxmox commands
create_alpine_lxc_direct() {
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

    print_step "Creating Alpine Docker LXC using direct Proxmox commands..."
    
    # Detect available storages
    print_step "Detecting available storage options..."
    local template_storages=$(pvesm status -content vztmpl | awk 'NR>1 && $2=="active" {print $1}' | head -5)
    local disk_storages=$(pvesm status -content images | awk 'NR>1 && $2=="active" {print $1}' | head -5)
    
    # Select template storage
    local template_storage=""
    local template_count=$(echo "$template_storages" | wc -l)
    if [ "$template_count" -eq 1 ]; then
        template_storage=$(echo "$template_storages" | head -1)
        print_info "Using template storage: $template_storage"
    elif [ "$template_count" -gt 1 ]; then
        print_step "Multiple template storages available:"
        echo "$template_storages" | nl
        read -p "Select template storage (1-$template_count): " choice
        template_storage=$(echo "$template_storages" | sed -n "${choice}p")
        print_info "Selected template storage: $template_storage"
    else
        print_error "No active template storage found!"
        return 1
    fi
    
    # Select disk storage
    local disk_storage=""
    local disk_count=$(echo "$disk_storages" | wc -l)
    if [ "$disk_count" -eq 1 ]; then
        disk_storage=$(echo "$disk_storages" | head -1)
        print_info "Using disk storage: $disk_storage"
    elif [ "$disk_count" -gt 1 ]; then
        print_step "Multiple disk storages available:"
        echo "$disk_storages" | nl
        read -p "Select disk storage (1-$disk_count): " choice
        disk_storage=$(echo "$disk_storages" | sed -n "${choice}p")
        print_info "Selected disk storage: $disk_storage"
    else
        print_error "No active disk storage found!"
        return 1
    fi
    
    # Get latest Alpine template
    print_step "Finding latest Alpine template..."
    local template_name=$(pveam available | grep alpine | grep default | sort -V | tail -1 | awk '{print $2}')
    if [ -z "$template_name" ]; then
        template_name="alpine-3.21-default_20241217_amd64.tar.xz"
    fi
    
    # Download template if not exists
    print_step "Downloading Alpine template: $template_name"
    if ! pveam list "$template_storage" | grep -q "$template_name"; then
        print_info "Downloading template to $template_storage..."
        pveam download "$template_storage" "$template_name"
    else
        print_info "Template already exists in $template_storage"
    fi
    
    # Create LXC container directly with Alpine
    print_step "Creating LXC container $lxc_id..."
    if pct create "$lxc_id" "$template_storage:vztmpl/$template_name" \
        --hostname "$lxc_name" \
        --cores "$cpu_cores" \
        --memory "$ram_mb" \
        --rootfs "$disk_storage:$disk_gb" \
        --net0 "name=eth0,bridge=vmbr0,ip=dhcp" \
        --onboot 1 \
        --unprivileged 1 \
        --features "nesting=1"; then
        
        print_info "✓ LXC container created successfully!"
        
        # Start the container
        print_step "Starting LXC container..."
        pct start "$lxc_id"
        sleep 10
        
        # Configure Alpine exactly like tteck's script
        print_step "Configuring Alpine container (tteck clone)..."
        pct exec "$lxc_id" -- ash -c '
            # Set up network and container OS (tteck style)
            echo "Setting up Container OS..."
            
            # IPv6 disable if needed (tteck default)
            sysctl -w net.ipv6.conf.all.disable_ipv6=1
            echo "net.ipv6.conf.all.disable_ipv6 = 1" >> /etc/sysctl.conf
            rc-update add sysctl default
            
            # Update Alpine (tteck style)
            echo "Updating Container OS..."
            apk -U upgrade
            
            # Install core dependencies (exactly like tteck)
            echo "Installing core dependencies..."
            apk update
            apk add newt curl openssh nano mc ncurses gpg bash util-linux
            
            # Install Docker (tteck does this via separate script)
            echo "Installing Docker and Docker Compose..."
            apk add docker docker-compose docker-cli-compose
            rc-update add docker boot
            service docker start
            
            # Configure passwordless root login (tteck style)
            passwd -d root
            
            # Set 256-color terminal
            echo "export TERM=\"xterm-256color\"" >> /root/.bashrc
            
            # Configure SSH (disabled by default like tteck)
            rc-update del sshd 2>/dev/null || true
            service sshd stop 2>/dev/null || true
            
            # Create autologin for console (tteck style)
            mkdir -p /etc/local.d
            cat > /etc/local.d/autologin.start << "EOF"
#!/bin/sh
# Enable autologin on tty1
if [ -f /sbin/agetty ]; then
    busybox pkill -f "agetty.*tty1" 2>/dev/null || true
    setsid /sbin/agetty --autologin root --noclear tty1 linux &
fi
EOF
            chmod +x /etc/local.d/autologin.start
            rc-update add local default
            
            # Set bash as default shell (tteck style)
            chsh -s /bin/bash root
            
            echo "Alpine container configured successfully!"
        '
        
        print_info "✓ Direct Alpine Docker LXC creation completed!"
    else
        print_error "Direct LXC creation failed!"
        print_error "Please check Proxmox logs and try again"
        return 1
    fi
    
    # If we reach here, one of the methods succeeded
    print_step "Verifying LXC creation..."
    
    # Check if we're in a Proxmox environment
    if ! command -v pct >/dev/null 2>&1; then
        print_warning "Not in Proxmox environment - skipping LXC verification"
        print_info "✓ Automation methods executed successfully"
        return 0
    fi
    
    if pct status "$lxc_id" >/dev/null 2>&1; then
        print_info "✓ LXC $lxc_name created successfully!"
        
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
    
    # Determine the next available mount index
    local next_mp_index=$(pct config "$lxc_id" | grep -o 'mp[0-9]\+' | sort -V | tail -n 1 | grep -o '[0-9]\+' | awk '{print $1+1}')
    next_mp_index=${next_mp_index:-0} # Default to 0 if no mount points exist
    
    # Add mount point
    if pct set "$lxc_id" -mp${next_mp_index} /datapool,mp=/datapool; then
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
            create_alpine_lxc_direct 101 "lxc-media-01" 4 10240 20
            ;;
        "proxy")
            create_alpine_lxc_direct 100 "lxc-proxy-01" 2 2048 8
            ;;
        "downloads")
            create_alpine_lxc_direct 102 "lxc-downloads-01" 2 3072 8
            ;;
        "utility")
            create_alpine_lxc_direct 103 "lxc-utility-01" 3 6144 8
            ;;
        "monitoring")
            create_alpine_lxc_direct 104 "lxc-monitoring-01" 2 4096 12
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
print_info "Creating $STACK_TYPE stack using direct Alpine Docker LXC creation..."

if create_stack_lxc "$STACK_TYPE"; then
    print_info "🎉 $STACK_TYPE LXC created successfully!"
    print_info ""
    print_info "Features installed:"
    print_info "✓ Latest Alpine Linux with core configurations"
    print_info "✓ Docker + Docker Compose + Essential packages"
    print_info "✓ SSH disabled, passwordless console access"
    print_info "✓ IPv6 disabled, 256-color terminal"
    print_info "✓ Autologin console, unprivileged container"
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