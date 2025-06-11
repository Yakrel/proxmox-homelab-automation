#!/bin/bash

# Direct Alpine Docker LXC Creation - Optimized Version
# Creates Alpine LXC with Docker installed - no external dependencies

set -e

# Source common functions
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
source "$SCRIPT_DIR/../common/functions.sh"

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
    if lxc_exists "$lxc_id"; then
        print_error "LXC $lxc_id already exists!"
        return 1
    fi

    print_step "Creating Alpine Docker LXC..."
    
    # Get storage using simplified functions
    local template_storage=$(get_template_storage)
    local disk_storage=$(get_container_storage)
    
    if [ -z "$template_storage" ]; then
        print_error "No template storage found!"
        return 1
    fi
    
    if [ -z "$disk_storage" ]; then
        print_error "No container storage found!"
        return 1
    fi
    
    print_info "Using template storage: $template_storage"
    print_info "Using disk storage: $disk_storage"
    
    # Download Alpine template if not exists
    local template_name="alpine-3.18-default_20230607_amd64.tar.xz"
    local template_path="$template_storage:vztmpl/$template_name"
    
    if ! pvesm list "$template_storage" --content vztmpl 2>/dev/null | grep -q "$template_name"; then
        print_step "Downloading Alpine template..."
        pveam update 2>/dev/null || true
        if ! pveam download "$template_storage" "$template_name" 2>/dev/null; then
            print_warning "Template download failed, will use any available Alpine template"
            template_name=$(pvesm list "$template_storage" --content vztmpl 2>/dev/null | grep -i alpine | head -1 | awk '{print $2}' | cut -d'/' -f2)
            if [ -z "$template_name" ]; then
                print_error "No Alpine template found!"
                return 1
            fi
        fi
    fi
    
    # Create LXC container
    print_step "Creating LXC container $lxc_id..."
    local storage_spec="${disk_storage}:${disk_gb}"
    
    if ! pct create "$lxc_id" \
        "$template_storage:vztmpl/$template_name" \
        --hostname "$lxc_name" \
        --memory "$ram_mb" \
        --cores "$cpu_cores" \
        --storage "$disk_storage" \
        --rootfs "$storage_spec" \
        --net0 "name=eth0,bridge=vmbr0,ip=192.168.1.${lxc_id}/24,gw=192.168.1.1" \
        --features "nesting=1" \
        --unprivileged 1 \
        --onboot 1 \
        --start 1; then
        print_error "Failed to create LXC $lxc_id"
        return 1
    fi

    # Wait for container to be ready
    wait_for_lxc "$lxc_id"
    
    # Install Docker
    print_step "Installing Docker in LXC $lxc_id..."
    
    # Update and install Docker
    pct exec "$lxc_id" -- sh -c "
        apk update && 
        apk add docker docker-cli-compose &&
        rc-update add docker default &&
        service docker start &&
        addgroup root docker
    " || {
        print_error "Docker installation failed"
        return 1
    }
    
    # Verify Docker installation
    if pct exec "$lxc_id" -- docker --version >/dev/null 2>&1; then
        print_info "✓ Docker successfully installed in LXC $lxc_id"
    else
        print_error "Docker installation verification failed"
        return 1
    fi

    # Create datapool directory structure
    print_step "Setting up directory structure..."
    pct exec "$lxc_id" -- sh -c "
        mkdir -p /datapool/config
        mkdir -p /datapool/media/{movies,tv,youtube/{playlists,channels}}
        mkdir -p /datapool/torrents/{movies,tv,other}
        chown -R 1000:1000 /datapool
        chmod -R 755 /datapool
    "
    
    print_info "✅ Alpine Docker LXC $lxc_name (ID: $lxc_id) created successfully!"
    print_info "   Access: pct enter $lxc_id"
    print_info "   IP: 192.168.1.$lxc_id"
    
    return 0
}

# LXC configurations for different stack types
configure_stack_lxc() {
    local stack_type="$1"
    
    case "$stack_type" in
        "proxy")
            create_alpine_lxc_direct 100 "lxc-proxy-01" 1 2048 8
            ;;
        "media")
            create_alpine_lxc_direct 101 "lxc-media-01" 4 10240 16
            ;;
        "downloads")
            create_alpine_lxc_direct 102 "lxc-downloads-01" 2 3072 8
            ;;
        "utility")
            create_alpine_lxc_direct 103 "lxc-utility-01" 2 6144 8
            ;;
        "monitoring")
            create_alpine_lxc_direct 104 "lxc-monitoring-01" 2 4096 10
            ;;
        *)
            print_error "Unknown stack type: $stack_type"
            print_info "Available types: proxy, media, downloads, utility, monitoring"
            exit 1
            ;;
    esac
}

# Main execution
main() {
    check_root
    
    local stack_type="$1"
    
    if [ -z "$stack_type" ]; then
        print_error "Stack type required!"
        print_info "Usage: $0 <stack_type>"
        print_info "Available types: proxy, media, downloads, utility, monitoring"
        exit 1
    fi
    
    print_info "Starting Alpine Docker LXC creation for $stack_type stack..."
    configure_stack_lxc "$stack_type"
}

# Run main function with all arguments
main "$@"