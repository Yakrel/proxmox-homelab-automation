#!/bin/bash

# =================================================================
#             Shared Helper Functions for Homelab Automation
# =================================================================
# This file contains all common utility functions to follow DRY principle.
# All scripts should source this file instead of duplicating functions.
#
# Usage: source "$WORK_DIR/scripts/helper-functions.sh"
#

# Strict error handling
set -euo pipefail

# === LOGGING FUNCTIONS ===
# Colored output functions used throughout all scripts

print_info() { 
    echo -e "\033[36m▸\033[0m $1" 
}

print_success() { 
    echo -e "\033[32m✓\033[0m $1" 
}

print_error() { 
    echo -e "\033[31m[ERROR]\033[0m $1" >&2
}

print_warning() { 
    echo -e "\033[33m[WARNING]\033[0m $1" 
}

# === USER INTERACTION FUNCTIONS ===
# Common user input and interaction patterns

press_enter_to_continue() {
    echo
    read -r -p "Press Enter to continue..."
}

prompt_env_passphrase() {
    local pass=""

    echo -n "Enter encryption passphrase: " >&2
    read -r -s pass
    echo >&2

    # Return the clean passphrase
    printf '%s' "$pass"
}

# === SYSTEM UTILITIES ===
# Common system-level utility functions

require_root() {
    if [[ "$(id -u)" -ne 0 ]]; then
        print_error "This script must be run as root!"
        exit 1
    fi
}

ensure_packages() {
    local missing_pkgs=()
    for pkg in "$@"; do
        if ! dpkg -s "$pkg" >/dev/null 2>&1; then
            missing_pkgs+=("$pkg")
        fi
    done

    if [[ ${#missing_pkgs[@]} -gt 0 ]]; then
        print_info "Installing missing host packages: ${missing_pkgs[*]}"
        apt-get update -qq
        apt-get install -y -qq "${missing_pkgs[@]}"
        print_success "Packages installed"
    fi
}

# === HOMELAB INFRASTRUCTURE CONSTANTS ===
# Fixed topology for homelab - no discovery needed

readonly LXC_IP_BASE="192.168.1"
readonly DATAPOOL="/datapool"
readonly NETWORK_BRIDGE="vmbr0"
readonly NETWORK_GATEWAY="192.168.1.1"

# Compute LXC IP from container ID
get_lxc_ip() {
    local ct_id="$1"
    echo "${LXC_IP_BASE}.${ct_id}"
}

# === CONFIGURATION MANAGEMENT ===
# Unified configuration parsing and validation

get_nvidia_driver_version() {
    local stacks_file="${1:-$WORK_DIR/stacks.yaml}"
    [[ -f "$stacks_file" ]] || { print_error "Stacks file not found: $stacks_file"; exit 1; }
    yq -r '.nvidia.driver_version // empty' "$stacks_file"
}

# Get list of available stacks from stacks.yaml, sorted by CT ID
get_available_stacks() {
    local stacks_file="${1:-$WORK_DIR/stacks.yaml}"

    [[ ! -f "$stacks_file" ]] && { print_error "Stacks file not found: $stacks_file"; exit 1; }

    # Get stacks with their CT IDs, sort by CT ID, then return stack names only
    yq -r '.stacks | to_entries | map(select(.value.ct_id != null)) | sort_by(.value.ct_id) | .[].key' "$stacks_file"
}

# Generate dynamic stack menu options
generate_stack_menu_options() {
    local stacks_file="${1:-$WORK_DIR/stacks.yaml}"
    local -a options=()
    
    [[ ! -f "$stacks_file" ]] && { print_error "Stacks file not found: $stacks_file"; exit 1; }
    
    while IFS= read -r stack; do
        local ct_id
        local hostname
        ct_id=$(yq -r ".stacks.$stack.ct_id" "$stacks_file")
        hostname=$(yq -r ".stacks.$stack.hostname" "$stacks_file")
        
        if [[ "$ct_id" != "null" && -n "$ct_id" ]]; then
            options+=("Deploy [$stack] Stack -> LXC $ct_id ($hostname)")
        fi
    done < <(get_available_stacks "$stacks_file")
    
    printf '%s\n' "${options[@]}"
}

# Get stack name from menu selection index  
get_stack_from_menu_index() {
    local index="$1"
    local stacks_file="${2:-$WORK_DIR/stacks.yaml}"
    local -a stacks=()
    
    while IFS= read -r stack; do
        stacks+=("$stack")
    done < <(get_available_stacks "$stacks_file")
    
    if [[ $index -ge 0 && $index -lt ${#stacks[@]} ]]; then
        echo "${stacks[$index]}"
    else
        return 1
    fi
}

get_stack_config() {
    local stack="$1"
    local stacks_file="${2:-$WORK_DIR/stacks.yaml}"

    # Validate stacks file exists
    [[ ! -f "$stacks_file" ]] && { print_error "Stacks file not found: $stacks_file"; exit 1; }

    # Read all common fields in a single yq call (5x faster)
    read -r CT_ID CT_HOSTNAME CT_CPU_CORES CT_MEMORY_MB CT_DISK_GB STORAGE_POOL TEMPLATE_POOL <<< \
        $(yq -r "[.stacks.$stack.ct_id, .stacks.$stack.hostname, .stacks.$stack.cpu_cores, .stacks.$stack.memory_mb, .stacks.$stack.disk_gb, .storage.pool, .storage.template_pool] | @tsv" "$stacks_file")

    # Validate required fields
    [[ -z "$CT_ID" || "$CT_ID" == "null" ]] && { print_error "Stack '$stack' not found in $stacks_file"; exit 1; }

    # Use fixed homelab infrastructure values
    CT_IP=$(get_lxc_ip "$CT_ID")

    # Export all variables for use in calling scripts
    export CT_ID CT_HOSTNAME CT_CPU_CORES CT_MEMORY_MB CT_DISK_GB
    export NETWORK_GATEWAY NETWORK_BRIDGE STORAGE_POOL TEMPLATE_POOL CT_IP
}

# === CONTAINER MANAGEMENT ===
# Common LXC container operations

check_container_exists() {
    local ct_id="$1"
    pct status "$ct_id" &>/dev/null
}

check_container_running() {
    local ct_id="$1"
    local status
    status=$(pct status "$ct_id" 2>&1 | awk '{print $2}')
    [[ "$status" == "running" ]]
}



# === MENU UTILITIES ===
# Common menu display patterns

show_menu_header() {
    local title="$1"
    echo
    echo "======================================="
    echo "      $title"
    echo "======================================="
    echo
}

show_menu_footer() {
    echo "---------------------------------------"
    echo "   b) Back to Main Menu"
    echo "   q) Quit"
    echo
}

# Interactive menu system with options and handlers
show_interactive_menu() {
    local title="$1"
    local -n options_ref="$2"
    local -n handlers_ref="$3"
    local back_handler="${4:-}"
    local quit_handler="${5:-}"
    
    while true; do
        show_menu_header "$title"
        
        # Show numbered options
        for i in "${!options_ref[@]}"; do
            echo "   $((i+1))) ${options_ref[$i]}"
        done
        
        show_menu_footer
        read -r -p "   Enter your choice: " choice
        
        case $choice in
            [1-9]|[1-9][0-9])
                local index=$((choice - 1))
                if [[ $index -ge 0 && $index -lt ${#options_ref[@]} ]]; then
                    ${handlers_ref[$index]} $index
                else
                    print_error "Invalid choice. Please try again."
                fi
                ;;
            b|B)
                if [[ -n "$back_handler" ]]; then
                    $back_handler
                    return 0
                else
                    return 0
                fi
                ;;
            q|Q)
                if [[ -n "$quit_handler" ]]; then
                    $quit_handler
                else
                    print_info "Exiting..."
                    exit 0
                fi
                ;;
            *)
                print_error "Invalid choice. Please try again."
                ;;
        esac
    done
}

# Fix LXC container permissions globally
fix_all_permissions() {
    print_info "Ensuring shared permissions on /datapool (config, backup, media, torrents)"
    
    # Create base directories if they don't exist
    mkdir -p /datapool/config /datapool/backup /datapool/media /datapool/torrents

    # Performance Optimization: Shallow fix only (Top-level folder permissions)
    # Recursive scanning 60k+ files (especially in config/media) caused massive delays.
    # Containers usually inherit correct permissions or manage their own files.
    local dirs=("/datapool/config" "/datapool/backup" "/datapool/media" "/datapool/torrents")
    
    for dir in "${dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            # Only fix the root folder permissions, skip recursive scan
            chown 101000:101000 "$dir"
        fi
    done
    
    print_success "Permissions updated for /datapool"
}

fix_path_owner() {
    local path="$1"

    [[ -e "$path" ]] || return 0
    
    # Optimize ZFS I/O: Only change if it does not match
    local current_uid current_gid
    current_uid=$(stat -c "%u" "$path" 2>/dev/null || echo "")
    current_gid=$(stat -c "%g" "$path" 2>/dev/null || echo "")
    if [[ "$current_uid" != "101000" ]] || [[ "$current_gid" != "101000" ]]; then
        chown 101000:101000 "$path"
    fi
}

fix_path_owner_recursive() {
    local path="$1"

    [[ -e "$path" ]] || return 0
    
    # Optimize ZFS I/O: Only chown files/dirs that don't match the target UID/GID
    # This prevents rewriting metadata for unchanged files (read-only scan via ZFS ARC)
    find "$path" \
        \( ! -user 101000 -o ! -group 101000 \) \
        -exec chown 101000:101000 {} +
}

fix_path_chmod() {
    local path="$1"
    local mode="$2"

    [[ -e "$path" ]] || return 0

    # Only chmod if the current permission doesn't match — avoids rewriting metadata
    local current_mode
    current_mode=$(stat -c "%a" "$path" 2>/dev/null || echo "")
    if [[ "$current_mode" != "$mode" ]]; then
        chmod "$mode" "$path"
    fi
}

fix_path_chmod_recursive() {
    local path="$1"
    local mode="$2"

    [[ -e "$path" ]] || return 0

    # Only chmod files/dirs that don't already have the target permission
    find "$path" ! -perm "$mode" -exec chmod "$mode" {} +
}

# === SHARED PROVISIONING UTILITIES ===

setup_homepage_proxmox_token() {
    local env_file="${1:-$ENV_DECRYPTED_PATH}"

    grep -q "placeholder_will_be_set_on_deploy" "$env_file" || return 0

    print_info "Setting up Homepage API token"

    local pve_user="homepage@pve"
    local token_name="homepage-token"

    if ! pveum user list | grep -qw "$pve_user"; then
        pveum user add "$pve_user" --comment "Homepage dashboard monitoring"
    fi

    pveum acl modify / --user "$pve_user" --role PVEAuditor
    pveum user token remove "$pve_user" "$token_name" 2>/dev/null || true

    local token_output token_secret
    token_output=$(pveum user token add "$pve_user" "$token_name" --privsep 0 --output-format=json)
    token_secret=$(echo "$token_output" | grep -o '"value":"[^"]*"' | cut -d'"' -f4)

    if [[ -z "$token_secret" ]]; then
        print_error "Failed to extract token secret"
        return 1
    fi

    sed -i "s/placeholder_will_be_set_on_deploy/$token_secret/g" "$env_file"
    print_success "API token configured"
}
