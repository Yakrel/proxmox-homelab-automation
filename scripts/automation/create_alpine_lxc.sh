#!/bin/bash

# Direct Alpine Docker LXC Creation using native Proxmox commands
# Creates Alpine LXC with Docker installed - no external dependencies
# Adapted from: https://raw.githubusercontent.com/community-scripts/ProxmoxVE/9140fd52acd532b263f100f7ef0a6139000d8376/ct/alpine-docker.sh

set -e

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -f "$SCRIPT_DIR/../utils/common.sh" ]; then
    source "$SCRIPT_DIR/../utils/common.sh"
else
    echo "ERROR: common.sh not found!" >&2
    exit 1
fi

# Function to create Alpine LXC using direct Proxmox commands (idempotent)
create_alpine_lxc_direct() {
    local lxc_id=$1
    local lxc_name=$2
    local cpu_cores=$3
    local ram_mb=$4
    local disk_gb=$5

    print_info "Managing Alpine Docker LXC: $lxc_name (ID: $lxc_id)"
    print_info "Specs: ${cpu_cores} cores, ${ram_mb}MB RAM, ${disk_gb}GB disk"
    
    # Check current LXC status
    local lxc_status=$(check_lxc_status "$lxc_id")
    
    case "$lxc_status" in
        "not_exists")
            print_info "LXC $lxc_id does not exist, creating new container..."
            ;;
        "running")
            print_info "LXC $lxc_id already running, verifying configuration..."
            ensure_docker_ready "$lxc_id"
            ensure_datapool_mount "$lxc_id"
            print_info "✓ LXC $lxc_id updated successfully!"
            return 0
            ;;
        "stopped")
            print_info "LXC $lxc_id exists but stopped, starting and updating..."
            pct start "$lxc_id"
            wait_for_container_ready "$lxc_id"
            ensure_docker_ready "$lxc_id"
            ensure_datapool_mount "$lxc_id"
            print_info "✓ LXC $lxc_id updated successfully!"
            return 0
            ;;
        *)
            print_warning "LXC $lxc_id in unknown state: $lxc_status, attempting to start..."
            pct start "$lxc_id" >/dev/null 2>&1 || true
            wait_for_container_ready "$lxc_id"
            ensure_docker_ready "$lxc_id"
            ensure_datapool_mount "$lxc_id"
            print_info "✓ LXC $lxc_id updated successfully!"
            return 0
            ;;
    esac

    print_step "Creating Alpine Docker LXC using direct Proxmox commands..."
    
    # Detect available storages
    print_step "Using datapool storage for LXC deployment..."
    
    # Use datapool for both templates and disk storage
    local template_storage="datapool"
    local disk_storage="datapool"
    
    print_info "Using storage: datapool (for both templates and containers)"
    
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
        --net0 "name=eth0,bridge=vmbr0,ip=192.168.1.${lxc_id}/24,gw=192.168.1.1" \
        --nameserver "192.168.1.1" \
        --onboot 1 \
        --unprivileged 1 \
        --features "nesting=1"; then
        
        print_info "✓ LXC container created successfully!"
        
        # Start the container
        print_step "Starting LXC container..."
        pct start "$lxc_id"
        wait_for_container_ready "$lxc_id"
        
        # Configure Alpine container using tteck approach
        print_step "Configuring Alpine container (this may take 5-10 minutes)..."
        
        # Create and run setup script inside container
        pct exec "$lxc_id" -- ash -c '
            # Complete silent Alpine setup
            echo "Setting up Container OS..."
            
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
        ensure_datapool_mount "$lxc_id"
        
        # Verify Docker installation
        print_step "Verifying Docker installation..."
        verify_docker "$lxc_id"
        
        return 0
    else
        print_error "Script execution failed or timed out"
        return 1
    fi
}


# Function to verify and ensure Docker installation (idempotent)
verify_docker() {
    local lxc_id=$1
    
    # Check if Docker is already working
    if pct exec "$lxc_id" -- docker --version >/dev/null 2>&1; then
        print_info "✓ Docker is already working"
        return 0
    fi
    
    # Try to start Docker service
    print_info "Starting Docker service..."
    pct exec "$lxc_id" -- rc-service docker start >/dev/null 2>&1 || true
    
    # Use our improved Docker readiness check with quiet mode
    if ensure_docker_ready "$lxc_id" 15 true; then
        print_info "✓ Docker and Docker Compose verified"
        return 0
    else
        print_warning "Docker verification completed with warnings"
        return 0  # Don't fail entire script
    fi
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
        "files")
            create_alpine_lxc_direct 102 "lxc-files-01" 2 3072 8
            ;;
        "webtools")
            create_alpine_lxc_direct 103 "lxc-webtools-01" 3 6144 8
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
    echo "Available: media, proxy, files, webtools, monitoring"
    exit 1
fi

case "$1" in
    media|proxy|files|webtools|monitoring)
        ;;
    *)
        print_error "Invalid stack type: $1"
        exit 1
        ;;
esac

check_root

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
    print_info "LXC container created successfully!"
else
    print_error "Failed to create $STACK_TYPE LXC"
    exit 1
fi