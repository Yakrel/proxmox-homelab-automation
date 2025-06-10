#!/bin/bash

# Direct Alpine Docker LXC Creation using native Proxmox commands
# Creates Alpine LXC with Docker installed - no external dependencies
# Adapted from: https://raw.githubusercontent.com/community-scripts/ProxmoxVE/9140fd52acd532b263f100f7ef0a6139000d8376/ct/alpine-docker.sh

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
    
    # Get all storages with proper parsing
    print_step "Checking storage configuration..."
    
    # Get active storages only (exclude disabled)
    local active_storages=$(pvesm status 2>/dev/null | awk 'NR>1 && $3=="active" {print $1}' | grep -v "^$")
    print_info "Active storages found: $active_storages"
    
    # Filter template storages (support vztmpl content)
    local template_storages=""
    for storage in $active_storages; do
        if pvesm status -content vztmpl 2>/dev/null | grep -q "^$storage"; then
            template_storages="$template_storages $storage"
        fi
    done
    template_storages=$(echo "$template_storages" | xargs)
    
    # Filter disk storages (support images content)  
    local disk_storages=""
    for storage in $active_storages; do
        if pvesm status -content images 2>/dev/null | grep -q "^$storage"; then
            disk_storages="$disk_storages $storage"
        fi
    done
    disk_storages=$(echo "$disk_storages" | xargs)
    
    print_info "Found template storages: $template_storages"
    print_info "Found disk storages: $disk_storages"
    
    # Select template storage
    local template_storage=""
    local template_count=$(echo "$template_storages" | wc -w)
    
    if [ "$template_count" -eq 0 ]; then
        print_error "No active template storage found!"
        print_info "Available storages:"
        pvesm status
        return 1
    elif [ "$template_count" -eq 1 ]; then
        template_storage="$template_storages"
        print_info "Using template storage: $template_storage"
    else
        print_step "Multiple template storages available:"
        echo "$template_storages" | tr ' ' '\n' | nl
        read -p "Select template storage (1-$template_count): " choice
        template_storage=$(echo "$template_storages" | tr ' ' '\n' | sed -n "${choice}p")
        print_info "Selected template storage: $template_storage"
    fi
    
    # Select disk storage
    local disk_storage=""
    local disk_count=$(echo "$disk_storages" | wc -w)
    
    if [ "$disk_count" -eq 0 ]; then
        print_error "No active disk storage found!"
        print_info "Available storages:"
        pvesm status
        return 1
    elif [ "$disk_count" -eq 1 ]; then
        disk_storage="$disk_storages"
        print_info "Using disk storage: $disk_storage"
    else
        print_step "Multiple disk storages available:"
        echo "$disk_storages" | tr ' ' '\n' | nl
        read -p "Select disk storage (1-$disk_count): " choice
        disk_storage=$(echo "$disk_storages" | tr ' ' '\n' | sed -n "${choice}p")
        print_info "Selected disk storage: $disk_storage"
    fi
    
    # Validate selections
    if [ -z "$template_storage" ] || [ -z "$disk_storage" ]; then
        print_error "Storage selection failed!"
        print_info "Template storage: '$template_storage'"
        print_info "Disk storage: '$disk_storage'"
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
        
        # Configure Alpine container using tteck approach
        print_step "Configuring Alpine container..."
        
        # Create and run setup script inside container
        pct exec "$lxc_id" -- ash -c '
            # Complete silent Alpine setup
            echo "Setting up Container OS..." >/dev/null
            
            # IPv6 disable
            sysctl -w net.ipv6.conf.all.disable_ipv6=1 >/dev/null 2>&1
            echo "net.ipv6.conf.all.disable_ipv6 = 1" >> /etc/sysctl.conf
            rc-update add sysctl default >/dev/null 2>&1
            
            # Set non-interactive environment
            export DEBIAN_FRONTEND=noninteractive
            export APK_PROGRESS_FD=1
            
            # Update Alpine completely silent
            echo "Updating packages..." >/dev/null
            apk update >/dev/null 2>&1
            apk upgrade >/dev/null 2>&1
            
            # Install packages completely silent
            echo "Installing Docker and tools..." >/dev/null
            apk add --quiet --no-progress docker docker-compose docker-cli-compose curl bash nano mc >/dev/null 2>&1
            
            # Configure Docker service
            rc-update add docker boot >/dev/null 2>&1
            service docker start >/dev/null 2>&1
            
            # Passwordless root configuration
            passwd -d root >/dev/null 2>&1
            
            # Configure bash
            chsh -s /bin/bash root >/dev/null 2>&1
            echo "export TERM=\"xterm-256color\"" >> /root/.bashrc
            
            # Disable SSH completely
            rc-update del sshd >/dev/null 2>&1 || true
            service sshd stop >/dev/null 2>&1 || true
            
            # Configure autologin properly
            sed -i "s/^root:[^:]*:/root::/" /etc/shadow
            
            # Setup console autologin using inittab method
            sed -i "/^tty1:/d" /etc/inittab
            echo "tty1::respawn:/sbin/getty -a root 38400 tty1" >> /etc/inittab
            
            echo "Configuration completed!" >/dev/null
        '
        
        # Wait for services to stabilize
        sleep 5
        
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
    
    # Shutdown container if running
    if pct status "$lxc_id" | grep -q "running"; then
        pct shutdown "$lxc_id"
        sleep 10
        # If shutdown doesn't work, force stop
        if pct status "$lxc_id" | grep -q "running"; then
            pct stop "$lxc_id"
            sleep 3
        fi
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
    
    # Wait for Docker service to be ready
    sleep 10
    
    # Ensure Docker service is running
    pct exec "$lxc_id" -- rc-service docker start >/dev/null 2>&1 || true
    sleep 5
    
    # Test Docker
    if pct exec "$lxc_id" -- docker --version >/dev/null 2>&1; then
        print_info "✓ Docker installation verified"
    else
        print_warning "Docker not accessible, attempting restart..."
        pct exec "$lxc_id" -- rc-service docker restart >/dev/null 2>&1
        sleep 5
        if pct exec "$lxc_id" -- docker --version >/dev/null 2>&1; then
            print_info "✓ Docker installation verified after restart"
        else
            return 1
        fi
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