#!/bin/bash

# Proxmox Homelab Stack Configurations
# Single source of truth for all LXC specifications

# Stack resource specifications
get_stack_specs() {
    local stack_type="$1"
    
    case "$stack_type" in
        "proxy")
            echo "id=100 hostname=lxc-proxy-01 ip=192.168.1.100/24 cores=2 memory=2048 disk=20 template=alpine"
            ;;
        "media")
            echo "id=101 hostname=lxc-media-01 ip=192.168.1.101/24 cores=4 memory=10240 disk=20 template=alpine"
            ;;
        "files")
            echo "id=102 hostname=lxc-files-01 ip=192.168.1.102/24 cores=2 memory=3072 disk=20 template=alpine"
            ;;
        "webtools")
            echo "id=103 hostname=lxc-webtools-01 ip=192.168.1.103/24 cores=2 memory=6144 disk=20 template=alpine"
            ;;
        "monitoring")
            echo "id=104 hostname=lxc-monitoring-01 ip=192.168.1.104/24 cores=4 memory=6144 disk=20 template=alpine"
            ;;
        "content")
            echo "id=105 hostname=lxc-content-01 ip=192.168.1.105/24 cores=4 memory=8192 disk=20 template=alpine"
            ;;
        "development")
            echo "id=150 hostname=lxc-development-01 ip=192.168.1.150/24 cores=4 memory=8192 disk=20 template=ubuntu"
            ;;
        *)
            echo "ERROR: Unknown stack type: $stack_type" >&2
            return 1
            ;;
    esac
}

# Get all available stack types
get_available_stacks() {
    echo "proxy media files webtools monitoring content development"
}

# Parse stack specification into individual variables
parse_stack_specs() {
    local specs="$1"
    local -n result_ref="$2"
    
    # Clear the associative array
    for key in "${!result_ref[@]}"; do
        unset result_ref["$key"]
    done
    
    # Parse key=value pairs
    local IFS=' '
    for pair in $specs; do
        local key="${pair%%=*}"
        local value="${pair#*=}"
        result_ref["$key"]="$value"
    done
}

# Validate stack type
validate_stack_type() {
    local stack_type="$1"
    local available_stacks
    available_stacks=$(get_available_stacks)
    
    if [[ " $available_stacks " =~ " $stack_type " ]]; then
        return 0
    else
        echo "ERROR: Invalid stack type: $stack_type" >&2
        echo "Available stacks: $available_stacks" >&2
        return 1
    fi
}

# Display stack information
show_stack_info() {
    local stack_type="$1"
    
    if ! validate_stack_type "$stack_type"; then
        return 1
    fi
    
    local specs
    specs=$(get_stack_specs "$stack_type")
    
    declare -A config
    parse_stack_specs "$specs" config
    
    echo "Stack Type: $stack_type"
    echo "  LXC ID: ${config[id]}"
    echo "  Hostname: ${config[hostname]}"
    echo "  IP Address: ${config[ip]}"
    echo "  Resources: ${config[cores]} cores, $((${config[memory]}/1024))GB RAM, ${config[disk]}GB disk"
    echo "  Template: ${config[template]}"
}