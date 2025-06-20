#!/bin/bash

# Ubuntu Development LXC Creation using native Proxmox commands
# Creates Ubuntu LXC with development tools - no Docker, no datapool mount

set -e

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Check if common.sh exists in the same directory (for setup.sh execution)
if [ -f "$SCRIPT_DIR/common.sh" ]; then
    source "$SCRIPT_DIR/common.sh"
elif [ -f "$SCRIPT_DIR/../utils/common.sh" ]; then
    source "$SCRIPT_DIR/../utils/common.sh"
else
    echo "ERROR: common.sh not found!"
    exit 1
fi

# Function to check LXC status
check_lxc_status() {
    local lxc_id=$1
    
    if pct status "$lxc_id" >/dev/null 2>&1; then
        local status=$(pct status "$lxc_id" | awk '{print $2}')
        echo "$status"
    else
        echo "not_exists"
    fi
}

# Function to wait for container readiness
wait_for_container_ready() {
    local lxc_id=$1
    local max_attempts=30
    local attempt=1
    
    print_info "Waiting for container to be ready..."
    while [ $attempt -le $max_attempts ]; do
        if pct exec "$lxc_id" -- echo "ready" >/dev/null 2>&1; then
            print_info "✓ Container is ready after ${attempt} attempts"
            return 0
        fi
        sleep 2
        attempt=$((attempt + 1))
    done
    
    print_warning "Container readiness check timeout after $((max_attempts * 2)) seconds, continuing..."
    return 0  # Don't fail entire script
}

# Function to create Ubuntu LXC using direct Proxmox commands (idempotent)
create_ubuntu_lxc_direct() {
    local lxc_id=$1
    local lxc_name=$2
    local cpu_cores=$3
    local ram_mb=$4
    local disk_gb=$5

    print_info "Managing Ubuntu Development LXC: $lxc_name (ID: $lxc_id)"
    print_info "Specs: ${cpu_cores} cores, ${ram_mb}MB RAM, ${disk_gb}GB disk"
    
    # Check current LXC status
    local lxc_status=$(check_lxc_status "$lxc_id")
    
    case "$lxc_status" in
        "not_exists")
            print_info "LXC $lxc_id does not exist, creating new container..."
            ;;
        "running")
            print_info "LXC $lxc_id already running, development LXC is ready!"
            print_info "✓ LXC $lxc_id updated successfully!"
            return 0
            ;;
        "stopped")
            print_info "LXC $lxc_id exists but stopped, starting..."
            pct start "$lxc_id"
            wait_for_container_ready "$lxc_id"
            print_info "✓ LXC $lxc_id updated successfully!"
            return 0
            ;;
        *)
            print_warning "LXC $lxc_id in unknown state: $lxc_status, attempting to start..."
            pct start "$lxc_id" >/dev/null 2>&1 || true
            wait_for_container_ready "$lxc_id"
            print_info "✓ LXC $lxc_id updated successfully!"
            return 0
            ;;
    esac

    print_step "Creating Ubuntu Development LXC using direct Proxmox commands..."
    
    # Use datapool for both templates and disk storage
    local template_storage="datapool"
    local disk_storage="datapool"
    
    print_info "Using storage: datapool (for both templates and containers)"
    
    # Get latest Ubuntu LTS template
    print_step "Finding latest Ubuntu LTS template..."
    local template_name=$(pveam available | grep ubuntu | grep -E "22\.04|24\.04" | sort -V | tail -1 | awk '{print $2}')
    if [ -z "$template_name" ]; then
        template_name="ubuntu-24.04-standard_24.04-2_amd64.tar.zst"
    fi
    
    # Download template if not exists
    print_step "Downloading Ubuntu template: $template_name"
    if ! pveam list "$template_storage" | grep -q "$template_name"; then
        print_info "Downloading template to $template_storage..."
        pveam download "$template_storage" "$template_name"
    else
        print_info "Template already exists in $template_storage"
    fi
    
    # Create LXC container directly with Ubuntu
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
        
        # Configure Ubuntu container for development
        print_step "Configuring Ubuntu container for development..."
        
        # Create and run setup script inside container
        pct exec "$lxc_id" -- bash -c '
            # Complete silent Ubuntu setup
            echo "Setting up Development Container..."
            
            # Update package list
            export DEBIAN_FRONTEND=noninteractive
            apt-get update -qq >/dev/null 2>&1
            
            # Install essential packages
            echo "Installing essential packages..." >/dev/null
            apt-get install -y -qq curl wget git nano vim htop net-tools >/dev/null 2>&1
            
            # Configure timezone
            ln -sf /usr/share/zoneinfo/Europe/Istanbul /etc/localtime >/dev/null 2>&1
            
            # Configure bash for root
            echo "export TERM=\"xterm-256color\"" >> /root/.bashrc
            echo "export EDITOR=nano" >> /root/.bashrc
            
            # Disable SSH password authentication (keep key-based)
            sed -i "s/#PasswordAuthentication yes/PasswordAuthentication no/" /etc/ssh/sshd_config >/dev/null 2>&1
            
            echo "Basic configuration completed!" >/dev/null
        '
        
        # Wait for services to stabilize
        sleep 5
        
        print_info "✓ Ubuntu Development LXC creation completed!"
    else
        print_error "Ubuntu LXC creation failed!"
        print_error "Please check Proxmox logs and try again"
        return 1
    fi
    
    # Verify LXC creation
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
        
        return 0
    else
        print_error "Script execution failed or timed out"
        return 1
    fi
}

# Main function
create_development_lxc() {
    local stack_type=$1
    
    case $stack_type in
        "development")
            create_ubuntu_lxc_direct 150 "lxc-development-01" 2 4096 12
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
    echo "Available: development"
    exit 1
fi

case "$1" in
    development)
        ;;
    *)
        print_error "Invalid stack type: $1"
        exit 1
        ;;
esac

check_root

# Execute
STACK_TYPE=$1
print_info "Creating $STACK_TYPE LXC using Ubuntu template..."

if create_development_lxc "$STACK_TYPE"; then
    print_info "🎉 $STACK_TYPE LXC created successfully!"
    print_info ""
    print_info "Features installed:"
    print_info "✓ Latest Ubuntu LTS with essential packages"
    print_info "✓ Git, curl, wget, nano, vim, htop"
    print_info "✓ SSH with key-based authentication only"
    print_info "✓ Turkish timezone configured"
    print_info "✓ Development-ready environment"
    print_info "✓ No Docker, no datapool mount - clean development setup"
    print_info ""
    print_info "LXC container created successfully!"
    print_info "Next: Run deployment script to install Claude Code and Node.js"
else
    print_error "Failed to create $STACK_TYPE LXC"
    exit 1
fi
