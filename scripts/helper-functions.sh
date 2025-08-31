#!/bin/bash

# =================================================================
#             Shared Helper Functions for Homelab Automation
# =================================================================
# This file contains all common utility functions to follow DRY principle.
# All scripts should source this file instead of duplicating functions.
#
# Usage: source "$WORK_DIR/scripts/helper-functions.sh"
#

# === LOGGING FUNCTIONS ===
# Colored output functions used throughout all scripts

print_info() { 
    echo -e "\033[36m[INFO]\033[0m $1" 
}

print_success() { 
    echo -e "\033[32m[SUCCESS]\033[0m $1" 
}

print_error() { 
    echo -e "\033[31m[ERROR]\033[0m $1" 
}

print_warning() { 
    echo -e "\033[33m[WARNING]\033[0m $1" 
}

# === USER INTERACTION FUNCTIONS ===
# Common user input and interaction patterns

press_enter_to_continue() {
    echo
    read -p "Press Enter to continue..."
}

prompt_password() {
    local prompt="${1:-Enter password: }"
    local min_length="${2:-8}"
    local pass
    local confirm_pass
    
    while true; do
        echo -n "$prompt" >&2
        read -s pass
        echo >&2
        
        if [[ -z "$pass" ]]; then
            print_warning "Password cannot be empty."
            continue
        fi
        
        if [[ ${#pass} -lt $min_length ]]; then
            print_warning "Password must be at least $min_length characters long."
            continue
        fi
        
        echo -n "Confirm password: " >&2
        read -s confirm_pass
        echo >&2
        
        if [[ "$pass" != "$confirm_pass" ]]; then
            print_warning "Passwords do not match. Please try again."
            continue
        fi
        
        break
    done
    
    printf '%s' "$pass"
}

prompt_env_passphrase() {
    local pass
    while true; do
        echo -n "Enter encryption passphrase: " >&2
        read -s pass
        echo >&2
        
        if [[ -z "$pass" ]]; then
            print_warning "Passphrase cannot be empty."
            continue
        fi
        
        break
    done
    
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
    print_info "Ensuring packages '$*' are installed..."
    apt-get update -q >/dev/null 2>&1 || true
    apt-get install -y "$@" >/dev/null 2>&1
}

ensure_yq() {
    if ! command -v yq >/dev/null 2>&1; then
        print_info "Installing yq (YAML processor)..."
        apt-get update -q >/dev/null 2>&1 || true
        apt-get install -y yq >/dev/null 2>&1 || true
    fi
}

# === CONFIGURATION MANAGEMENT ===
# Unified configuration parsing and validation

# Get list of available stacks from stacks.yaml
get_available_stacks() {
    local stacks_file="${1:-$WORK_DIR/stacks.yaml}"
    ensure_yq
    
    if [[ ! -f "$stacks_file" ]]; then
        print_error "Stacks file not found: $stacks_file"
        return 1
    fi
    
    yq -r '.stacks | keys | .[]' "$stacks_file" 2>/dev/null || {
        print_error "Failed to parse stacks from $stacks_file"
        return 1
    }
}

# Generate dynamic stack menu options
generate_stack_menu_options() {
    local stacks_file="${1:-$WORK_DIR/stacks.yaml}"
    local -a options=()
    
    ensure_yq
    
    if [[ ! -f "$stacks_file" ]]; then
        print_error "Stacks file not found: $stacks_file"
        return 1
    fi
    
    while IFS= read -r stack; do
        local ct_id=$(yq -r ".stacks.$stack.ct_id" "$stacks_file" 2>/dev/null)
        local hostname=$(yq -r ".stacks.$stack.hostname" "$stacks_file" 2>/dev/null)
        
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
    
    # Ensure required tools
    ensure_yq
    
    # Validate stacks file exists
    if [[ ! -f "$stacks_file" ]]; then
        print_error "Stacks file not found: $stacks_file"
        exit 1
    fi
    
    # Read configuration - all common fields in one place
    CT_ID=$(yq -r ".stacks.$stack.ct_id" "$stacks_file" 2>/dev/null)
    CT_HOSTNAME=$(yq -r ".stacks.$stack.hostname" "$stacks_file" 2>/dev/null)
    CT_IP_OCTET=$(yq -r ".stacks.$stack.ip_octet" "$stacks_file" 2>/dev/null)
    CT_CPU_CORES=$(yq -r ".stacks.$stack.cpu_cores" "$stacks_file" 2>/dev/null)
    CT_MEMORY_MB=$(yq -r ".stacks.$stack.memory_mb" "$stacks_file" 2>/dev/null)
    CT_DISK_GB=$(yq -r ".stacks.$stack.disk_gb" "$stacks_file" 2>/dev/null)
    
    # Network configuration
    NETWORK_GATEWAY=$(yq -r ".network.gateway" "$stacks_file" 2>/dev/null)
    NETWORK_BRIDGE=$(yq -r ".network.bridge" "$stacks_file" 2>/dev/null)
    NETWORK_IP_BASE=$(yq -r ".network.ip_base" "$stacks_file" 2>/dev/null)
    
    # Storage configuration
    STORAGE_POOL=$(yq -r ".storage.pool" "$stacks_file" 2>/dev/null)
    
    # Backup-specific configuration (if needed)
    if [[ "$stack" == "backup" ]]; then
        PBS_DATASTORE_NAME=$(yq -r ".stacks.$stack.pbs_datastore_name" "$stacks_file" 2>/dev/null)
        PBS_REPO_SUITE=$(yq -r ".stacks.$stack.pbs_repo_suite" "$stacks_file" 2>/dev/null)
        PBS_PRUNE_SCHEDULE=$(yq -r ".stacks.$stack.pbs_prune_schedule" "$stacks_file" 2>/dev/null)
        PBS_GC_SCHEDULE=$(yq -r ".stacks.$stack.pbs_gc_schedule" "$stacks_file" 2>/dev/null)
        PBS_VERIFY_SCHEDULE=$(yq -r ".stacks.$stack.pbs_verify_schedule" "$stacks_file" 2>/dev/null)
    fi
    
    # Validate required fields
    if [[ -z "$CT_ID" || "$CT_ID" == "null" ]]; then
        print_error "Stack '$stack' not found or incomplete in $stacks_file"
        exit 1
    fi
    
    # Construct derived values
    CT_IP="$NETWORK_IP_BASE.$CT_IP_OCTET"
    
    # Export all variables for use in calling scripts
    export CT_ID CT_HOSTNAME CT_IP_OCTET CT_CPU_CORES CT_MEMORY_MB CT_DISK_GB
    export NETWORK_GATEWAY NETWORK_BRIDGE NETWORK_IP_BASE STORAGE_POOL CT_IP
    export PBS_DATASTORE_NAME PBS_REPO_SUITE PBS_PRUNE_SCHEDULE PBS_GC_SCHEDULE PBS_VERIFY_SCHEDULE
}

# === CONTAINER MANAGEMENT ===
# Common LXC container operations

check_container_exists() {
    local ct_id="$1"
    pct status "$ct_id" >/dev/null 2>&1
}

check_container_running() {
    local ct_id="$1"
    [[ "$(pct status "$ct_id" 2>/dev/null)" == "status: running" ]]
}

wait_for_container() {
    local ct_id="$1"
    local max_wait="${2:-30}"
    local count=0
    
    print_info "Waiting for container $ct_id to be ready..."
    
    while ! check_container_running "$ct_id" && [[ $count -lt $max_wait ]]; do
        sleep 2
        count=$((count + 2))
        echo -n "."
    done
    echo
    
    if [[ $count -ge $max_wait ]]; then
        print_error "Container $ct_id failed to start within ${max_wait} seconds"
        return 1
    fi
    
    print_success "Container $ct_id is ready"
    return 0
}

exec_in_container() {
    local ct_id="$1"
    shift
    pct exec "$ct_id" -- "$@"
}

# === MENU UTILITIES ===
# Common menu display patterns

show_menu_header() {
    local title="$1"
    clear
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
        read -p "   Enter your choice: " choice
        
        case $choice in
            [1-9]|[1-9][0-9])
                local index=$((choice - 1))
                if [[ $index -ge 0 && $index -lt ${#options_ref[@]} ]]; then
                    ${handlers_ref[$index]} $index
                else
                    print_error "Invalid choice. Please try again."
                    sleep 2
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
                sleep 2
                ;;
        esac
    done
}

# === FILE AND DIRECTORY UTILITIES ===
# Common file operations and validations

ensure_directory() {
    local dir_path="$1"
    local owner="${2:-}"
    
    if [[ ! -d "$dir_path" ]]; then
        mkdir -p "$dir_path"
        print_info "Created directory: $dir_path"
    fi
    
    if [[ -n "$owner" ]]; then
        chown "$owner" "$dir_path" 2>/dev/null || print_warning "Could not set ownership for $dir_path"
    fi
}

backup_file() {
    local file_path="$1"
    
    if [[ -f "$file_path" ]]; then
        cp "$file_path" "$file_path.backup.$(date +%Y%m%d_%H%M%S)"
        print_info "Backup created: $file_path.backup.$(date +%Y%m%d_%H%M%S)"
    fi
}

# Download file and push to LXC container
download_and_push_config() {
    local ct_id="$1"
    local remote_url="$2"
    local target_path="$3"
    local temp_file="${4:-$WORK_DIR/$(basename "$remote_url")}"
    
    print_info "    -> Downloading $(basename "$remote_url")"
    if ! curl -sSL "$remote_url" -o "$temp_file"; then
        print_error "Failed to download $(basename "$remote_url")"
        return 1
    fi
    
    print_info "    -> Pushing to LXC $ct_id ($target_path)"
    if ! pct push "$ct_id" "$temp_file" "$target_path"; then
        print_error "Failed to push file to container"
        rm -f "$temp_file"
        return 1
    fi
    
    rm -f "$temp_file"
    return 0
}

# Environment file encryption/decryption helpers
encrypt_env_file() {
    local input_file="$1"
    local output_file="$2"
    local passphrase="$3"
    
    if printf '%s' "$passphrase" | openssl enc -aes-256-cbc -pbkdf2 -salt -pass stdin -in "$input_file" -out "$output_file" 2>/dev/null; then
        return 0
    else
        rm -f "$output_file"
        return 1
    fi
}

decrypt_env_file() {
    local input_file="$1"
    local output_file="$2"
    local passphrase="$3"
    
    if printf '%s' "$passphrase" | openssl enc -aes-256-cbc -pbkdf2 -d -salt -pass stdin -in "$input_file" -out "$output_file" 2>/dev/null; then
        return 0
    else
        rm -f "$output_file"
        return 1
    fi
}

# Download, customize template, and push to LXC container
download_customize_and_push() {
    local ct_id="$1"
    local remote_url="$2"
    local target_path="$3"
    local hostname="$4"
    local temp_file="${5:-$WORK_DIR/$(basename "$remote_url")}"
    
    print_info "  -> Downloading $(basename "$remote_url") template"
    if ! curl -sSL "$remote_url" -o "$temp_file"; then
        print_error "Failed to download $(basename "$remote_url")"
        return 1
    fi
    
    # Replace hostname placeholder
    sed -i "s/REPLACE_HOST_LABEL/$hostname/g" "$temp_file"
    
    print_info "  -> Pushing customized $(basename "$remote_url") to LXC $ct_id ($target_path)"
    if ! pct push "$ct_id" "$temp_file" "$target_path"; then
        print_error "Failed to push file to container"
        rm -f "$temp_file"
        return 1
    fi
    
    rm -f "$temp_file"
    return 0
}

# === VALIDATION FUNCTIONS ===
# Common validation patterns

validate_ip() {
    local ip="$1"
    local regex="^([0-9]{1,3}\.){3}[0-9]{1,3}$"
    
    if [[ $ip =~ $regex ]]; then
        for octet in $(echo "$ip" | tr '.' ' '); do
            if [[ $octet -gt 255 ]]; then
                return 1
            fi
        done
        return 0
    else
        return 1
    fi
}

validate_container_id() {
    local ct_id="$1"
    
    if [[ "$ct_id" =~ ^[0-9]+$ ]] && [[ $ct_id -ge 100 ]] && [[ $ct_id -le 999 ]]; then
        return 0
    else
        return 1
    fi
}