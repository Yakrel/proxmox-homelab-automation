#!/bin/bash

# This script is downloaded and executed by the main installer.
# It provides the main user interface for the automation tool.

# Strict error handling
set -euo pipefail

# --- Global Variables ---
WORK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)"

# Source helper functions
source "$WORK_DIR/scripts/helper-functions.sh"

# --- Handler Functions ---
deploy_stack_handler() {
    local index="$1"
    local stack
    
    stack=$(get_stack_from_menu_index "$index") || { print_error "Failed to get stack for index $index"; return; }
    
    bash "$WORK_DIR/scripts/deploy-stack.sh" "$stack"
    local exit_code=$?
    
    # If deployment failed, pause to let user see the error
    if [[ $exit_code -ne 0 ]]; then
        echo
        print_error "Stack deployment failed with exit code $exit_code"
        press_enter_to_continue
    fi
}

encrypt_env_handler() {
    bash "$WORK_DIR/scripts/encrypt-env.sh"
    local exit_code=$?
    
    # If encryption failed, pause to let user see the error
    if [[ $exit_code -ne 0 ]]; then
        echo
        print_error "Environment encryption failed with exit code $exit_code"
        print_info "Review the error message above before continuing"
        press_enter_to_continue
    fi
}

helper_menu_handler() {
    bash "$WORK_DIR/scripts/helper-menu.sh"
    local exit_code=$?
    
    # If helper menu failed, pause to let user see the error
    if [[ $exit_code -ne 0 ]]; then
        echo
        print_error "Helper menu failed with exit code $exit_code"
        press_enter_to_continue
    fi
}

# --- Main Menu ---
main_menu() {
    # Generate dynamic stack options
    local -a stack_options=()
    while IFS= read -r option; do
        stack_options+=("$option")
    done < <(generate_stack_menu_options "$WORK_DIR/stacks.yaml")
    
    # Add additional options
    stack_options+=("Encrypt .env files from containers...")
    stack_options+=("Run Proxmox Helper Scripts...")
    
    # Create handlers array
    local -a handlers=()
    local stack_count=0
    
    # Add stack deployment handlers
    while IFS= read -r stack; do
        handlers+=("deploy_stack_handler")
        stack_count=$((stack_count + 1))
    done < <(get_available_stacks "$WORK_DIR/stacks.yaml")
    
    # Add additional handlers
    handlers+=("encrypt_env_handler")
    handlers+=("helper_menu_handler")
    
    # Show interactive menu
    show_interactive_menu "Proxmox Homelab - Stack Deployment" stack_options handlers "" ""
}

# Run main menu
main_menu
