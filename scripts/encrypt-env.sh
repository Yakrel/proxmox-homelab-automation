#!/bin/bash

# Encrypt .env files from LXC containers
# Usage: encrypt-env.sh [stack-name]

# Strict error handling
set -euo pipefail

WORK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)"

# --- Load Shared Functions ---
source "$WORK_DIR/scripts/helper-functions.sh"

# --- Encrypt function ---
encrypt_container_env() {
    local stack="$1"
    get_stack_config "$stack"
    
    print_info "Encrypting .env file from container [$CT_HOSTNAME] (ID: $ct_id)..."
    
    # Check if container is running
    if ! pct status "$CT_ID" | grep -q "running"; then
        print_error "Container $CT_ID is not running"
        exit 1
    fi
    
    # Check if .env exists in container
    if ! pct exec "$CT_ID" -- test -f "/root/.env"; then
        print_error "No .env file found in container $CT_ID"
        exit 1
    fi
    
    # Create output directory
    local output_dir="$WORK_DIR/docker/$stack"
    mkdir -p "$output_dir"
    
    # Get .env from container
    local temp_env="/tmp/.env.temp"
    pct exec "$CT_ID" -- cat "/root/.env" > "$temp_env"
    
    # Get passphrase (user's chosen password - same as used for deployment)
    local pass
    pass=$(prompt_env_passphrase)
    
    # Encrypt using helper function
    local encrypted_file="$output_dir/.env.enc"
    if encrypt_env_file "$temp_env" "$encrypted_file" "$pass"; then
        print_success "Environment file encrypted successfully: docker/$stack/.env.enc"
        print_info "Next steps:"
        print_info "1. Copy docker/$stack/.env.enc to your development environment"
        print_info "2. git add docker/$stack/.env.enc"
        print_info "3. git commit -m 'Update $stack environment'"
        print_info "4. git push"
    else
        print_error "Encryption failed"
        exit 1
    fi
    
    # Clean up temp file
    rm -f "$temp_env"
}

# --- Menu handlers ---
encrypt_stack_handler() {
    local index="$1"
    local stack
    
    if stack=$(get_stack_from_menu_index "$index"); then
        encrypt_container_env "$stack"
        press_enter_to_continue
    else
        print_error "Failed to get stack for index $index"
    fi
}

back_to_main() {
    print_info "Returning to main menu..."
    exit 0
}

# --- Interactive menu ---
show_encrypt_menu() {
    # Generate dynamic encryption options
    local -a encrypt_options=()
    while IFS= read -r stack; do
        local ct_id
        ct_id=$(yq -r ".stacks.$stack.ct_id" "$WORK_DIR/stacks.yaml" 2>/dev/null)
        if [[ "$ct_id" != "null" && -n "$ct_id" ]]; then
            # Only show stacks that would have Docker compose (skip backup which is native)
            if [[ "$stack" != "backup" ]]; then
                encrypt_options+=("Encrypt [$stack] .env (LXC $ct_id)")
            fi
        fi
    done < <(get_available_stacks)
    
    # Create handlers array
    local -a handlers=()
    local stack_count=0
    
    while IFS= read -r stack; do
        if [[ "$stack" != "backup" ]]; then
            handlers+=("encrypt_stack_handler")
            stack_count=$((stack_count + 1))
        fi
    done < <(get_available_stacks)
    
    # Show interactive menu
    show_interactive_menu "Environment File Encryption Menu" encrypt_options handlers "back_to_main" "back_to_main"
}

# --- Main execution ---
if [ -n "$1" ]; then
    # Direct stack name provided
    encrypt_container_env "$1"
else
    # Show interactive menu
    show_encrypt_menu
fi