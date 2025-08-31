#!/bin/bash

# This script is downloaded and executed by the main installer.
# It provides the main user interface for the automation tool.

# --- Global Variables ---
WORK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)"

# Source helper functions
source "$WORK_DIR/scripts/helper-functions.sh"

# --- Handler Functions ---
deploy_stack_handler() {
    local index="$1"
    local stack
    
    if stack=$(get_stack_from_menu_index "$index"); then
        if [[ "$stack" == "gameservers" ]]; then
            bash "$WORK_DIR/scripts/gaming-menu.sh"
        else
            bash "$WORK_DIR/scripts/deploy-stack.sh" "$stack"
        fi
    else
        print_error "Failed to get stack for index $index"
        sleep 2
    fi
}

encrypt_env_handler() {
    bash "$WORK_DIR/scripts/encrypt-env.sh"
}

helper_menu_handler() {
    bash "$WORK_DIR/scripts/helper-menu.sh"
}

# --- Main Menu ---
main_menu() {
    # Generate dynamic stack options
    local -a stack_options=()
    while IFS= read -r option; do
        stack_options+=("$option")
    done < <(generate_stack_menu_options)
    
    # Add additional options
    stack_options+=("Encrypt .env files from containers...")
    stack_options+=("Run Proxmox Helper Scripts...")
    
    # Create handlers array
    local -a handlers=()
    local stack_count=0
    
    # Add stack deployment handlers
    while IFS= read -r stack; do
        handlers+=("deploy_stack_handler")
        ((stack_count++))
    done < <(get_available_stacks)
    
    # Add additional handlers
    handlers+=("encrypt_env_handler")
    handlers+=("helper_menu_handler")
    
    # Show interactive menu
    show_interactive_menu "Proxmox Homelab - Stack Deployment" stack_options handlers "" ""
}

# Run main menu
main_menu
