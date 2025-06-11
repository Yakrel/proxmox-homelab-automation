#!/bin/bash

# Common Functions Library for Proxmox Homelab Automation
# Safe to source from any script without breaking existing functionality

# Color definitions
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[1;33m'
export BLUE='\033[0;34m'
export NC='\033[0m'

# Print functions
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

# Root check function
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        print_error "This script must be run as root"
        exit 1
    fi
}

# Safe command execution with error handling
run_cmd() {
    local cmd="$*"
    if ! $cmd; then
        print_error "Command failed: $cmd"
        return 1
    fi
}

# Download with retry
safe_download() {
    local url="$1"
    local output="$2"
    local retries=3
    
    for i in $(seq 1 $retries); do
        if wget -q -O "$output" "$url"; then
            return 0
        fi
        print_warning "Download attempt $i failed, retrying..."
        sleep 2
    done
    
    print_error "Failed to download $url after $retries attempts"
    return 1
}

# Get first available storage for templates
get_template_storage() {
    pvesm status -content vztmpl 2>/dev/null | awk 'NR>1 && $3=="active" {print $1; exit}'
}

# Get first available storage for containers
get_container_storage() {
    pvesm status -content rootdir 2>/dev/null | awk 'NR>1 && $3=="active" {print $1; exit}'
}

# Check if LXC exists
lxc_exists() {
    local lxc_id="$1"
    pct status "$lxc_id" >/dev/null 2>&1
}

# Wait for LXC to be ready
wait_for_lxc() {
    local lxc_id="$1"
    local timeout=60
    local count=0
    
    print_info "Waiting for LXC $lxc_id to be ready..."
    
    while [ $count -lt $timeout ]; do
        if pct exec "$lxc_id" -- echo "ready" >/dev/null 2>&1; then
            print_info "LXC $lxc_id is ready"
            return 0
        fi
        sleep 2
        count=$((count + 2))
    done
    
    print_error "LXC $lxc_id not ready after ${timeout}s"
    return 1
}