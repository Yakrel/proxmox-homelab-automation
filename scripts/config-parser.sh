#!/bin/bash

# =================================================================
#                     Configuration Parser Module
# =================================================================
# Stack specification parsing utilities extracted from helper-functions.sh
# Provides centralized configuration management for homelab automation
set -euo pipefail

# Ensure yq is available for YAML parsing
ensure_yq() {
    if ! command -v yq >/dev/null 2>&1; then
        apt-get update -q >/dev/null 2>&1 || { echo "ERROR: Failed to update package lists" >&2; exit 1; }
        apt-get install -y yq >/dev/null 2>&1 || { echo "ERROR: Failed to install yq" >&2; exit 1; }
    fi
}

# Parse stack configuration from stacks.yaml
parse_stack_config() {
    local stack="$1"
    local stacks_file="${2:-$WORK_DIR/stacks.yaml}"
    
    # Ensure required tools
    ensure_yq
    
    # Validate stacks file exists
    [[ ! -f "$stacks_file" ]] && { 
        echo "ERROR: Stacks file not found: $stacks_file" >&2
        exit 1
    }
    
    # Read configuration - all common fields in one place
    local ct_id ct_hostname ct_cpu_cores ct_memory_mb ct_disk_gb storage_pool
    
    ct_id=$(yq -r ".stacks.$stack.ct_id" "$stacks_file" 2>/dev/null)
    ct_hostname=$(yq -r ".stacks.$stack.hostname" "$stacks_file" 2>/dev/null)
    ct_cpu_cores=$(yq -r ".stacks.$stack.cpu_cores" "$stacks_file" 2>/dev/null)
    ct_memory_mb=$(yq -r ".stacks.$stack.memory_mb" "$stacks_file" 2>/dev/null)
    ct_disk_gb=$(yq -r ".stacks.$stack.disk_gb" "$stacks_file" 2>/dev/null)
    
    # Storage configuration (use datapool default)
    storage_pool=$(yq -r ".storage.pool" "$stacks_file" 2>/dev/null)
    
    # Validate required fields
    [[ -z "$ct_id" || "$ct_id" == "null" ]] && { 
        echo "ERROR: Stack '$stack' not found in $stacks_file" >&2
        exit 1
    }
    
    # Output configuration as key=value pairs for sourcing
    cat << EOF
CT_ID=$ct_id
CT_HOSTNAME=$ct_hostname
CT_CPU_CORES=$ct_cpu_cores
CT_MEMORY_MB=$ct_memory_mb
CT_DISK_GB=$ct_disk_gb
STORAGE_POOL=${storage_pool:-datapool}
EOF
}

# Get list of available stacks from configuration
get_available_stacks() {
    local stacks_file="${1:-$WORK_DIR/stacks.yaml}"
    
    ensure_yq
    
    [[ ! -f "$stacks_file" ]] && { 
        echo "ERROR: Stacks file not found: $stacks_file" >&2
        exit 1
    }
    
    # Extract stack names, sorted by CT ID
    yq -r '.stacks | to_entries | map(select(.value.ct_id != null)) | sort_by(.value.ct_id) | .[].key' "$stacks_file" 2>/dev/null || {
        echo "ERROR: Failed to parse stacks from $stacks_file" >&2
        exit 1
    }
}

# Validate stack configuration
validate_stack_config() {
    local stack="$1"
    local stacks_file="${2:-$WORK_DIR/stacks.yaml}"
    
    # Check if stack exists
    if ! parse_stack_config "$stack" "$stacks_file" >/dev/null 2>&1; then
        echo "ERROR: Invalid stack configuration for '$stack'" >&2
        return 1
    fi
    
    # Additional validation can be added here
    return 0
}

# Load configuration into environment variables 
load_stack_config() {
    local stack="$1"
    local stacks_file="${2:-$WORK_DIR/stacks.yaml}"
    
    # Parse and source configuration
    local config_output
    config_output=$(parse_stack_config "$stack" "$stacks_file")
    
    # Export variables to current shell
    eval "$config_output"
    
    # Compute derived values
    readonly LXC_IP_BASE="192.168.1"
    export CT_IP="${LXC_IP_BASE}.${CT_ID}"
    export NETWORK_GATEWAY="192.168.1.1"
    export NETWORK_BRIDGE="vmbr0"
    export DATAPOOL="/datapool"
}

# Main entry point for testing
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    WORK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)"
    
    case "${1:-}" in
        "list")
            get_available_stacks
            ;;
        "parse")
            [[ -z "${2:-}" ]] && { echo "ERROR: Stack name required" >&2; exit 1; }
            parse_stack_config "$2"
            ;;
        "validate")
            [[ -z "${2:-}" ]] && { echo "ERROR: Stack name required" >&2; exit 1; }
            validate_stack_config "$2" && echo "Valid configuration for stack: $2"
            ;;
        *)
            echo "Usage: $0 {list|parse|validate} [stack-name]"
            echo "Examples:"
            echo "  $0 list                    # List all available stacks"
            echo "  $0 parse monitoring        # Parse monitoring stack config"
            echo "  $0 validate proxy          # Validate proxy stack config"
            exit 1
            ;;
    esac
fi