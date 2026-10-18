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
    
    if bash "$WORK_DIR/scripts/deploy-stack.sh" "$stack"; then
        return 0
    else
        local exit_code=$?
        echo
        print_error "Stack deployment failed with exit code $exit_code"
        press_enter_to_continue
    fi
}

fast_redeploy_handler() {
    if bash "$WORK_DIR/scripts/fast-redeploy.sh"; then
        return 0
    else
        local exit_code=$?
        echo
        print_error "Fast redeploy failed with exit code $exit_code"
        press_enter_to_continue
    fi
}

helper_menu_handler() {
    if bash "$WORK_DIR/scripts/helper-menu.sh"; then
        return 0
    else
        local exit_code=$?
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

    local stack_count=${#stack_options[@]}

    # Add additional options
    stack_options+=("Fast redeploy running Docker stacks...")
    stack_options+=("Run Proxmox Helper Scripts...")
    
    # Create handlers array
    local -a handlers=()

    # Add stack deployment handlers
    local index
    for ((index = 0; index < stack_count; index++)); do
        handlers+=("deploy_stack_handler")
    done
    
    # Add additional handlers
    handlers+=("fast_redeploy_handler")
    handlers+=("helper_menu_handler")
    
    # Show interactive menu
    show_interactive_menu "Proxmox Homelab - Stack Deployment" stack_options handlers "" ""
}

# Run main menu
main_menu
