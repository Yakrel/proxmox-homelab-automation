#!/bin/bash

# Strict error handling
set -euo pipefail

# --- Global Variables ---

WORK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)"

# Load shared functions to get container ID from config
source "$WORK_DIR/scripts/helper-functions.sh"

# Get gameservers container ID from configuration
get_stack_config "gameservers"
CONTAINER_ID="$CT_ID"

deploy_gaming_stack() {
    print_info "Deploying Gaming Stack (LXC $CONTAINER_ID)..."
    bash "$WORK_DIR/scripts/deploy-stack.sh" "gameservers"
    local exit_code=$?
    
    # Always pause for gaming stack to let user see the results
    if [[ $exit_code -ne 0 ]]; then
        echo
        print_error "Gaming stack deployment failed with exit code $exit_code"
        print_info "Please review the error message above before continuing."
    fi
    press_enter_to_continue
}

manage_games() {
    # Check if container exists and is running
    if ! check_container_exists "$CONTAINER_ID"; then
        print_error "Gaming stack container ($CONTAINER_ID) does not exist!"
        echo "Please deploy the gaming stack first."
        press_enter_to_continue
        return 1
    fi
    
    if ! check_container_running "$CONTAINER_ID"; then
        print_warning "Container $CONTAINER_ID is not running. Starting it..."
        pct start "$CONTAINER_ID" || { print_error "Failed to start container"; return 1; }
    fi
    
    # Copy game manager to container
    print_info "Installing game manager in container..."
    pct push "$CONTAINER_ID" "$WORK_DIR/scripts/game-manager.sh" "/root/game-manager.sh"
    pct exec "$CONTAINER_ID" -- chmod +x /root/game-manager.sh
    
    # Run interactive game manager inside container
    print_info "Starting Game Manager (inside LXC $CONTAINER_ID)..."
    echo "Use this menu to start/stop individual game servers."
    echo "Only one game can run at a time to save resources."
    echo
    pct exec "$CONTAINER_ID" -- /root/game-manager.sh
}

show_gaming_status() {
    if ! check_container_exists "$CONTAINER_ID"; then
        echo "Gaming Stack: NOT DEPLOYED"
        return
    fi
    
    echo "Gaming Stack Status:"
    echo "  Container: $(pct status "$CONTAINER_ID")"
    
    if check_container_running "$CONTAINER_ID"; then
        echo "  Current Game:"
        exec_in_container "$CONTAINER_ID" /root/game-manager.sh status || echo "    Game manager not installed"
    fi
    
    press_enter_to_continue
}

# --- Main Menu ---

while true; do
    show_menu_header "Gaming Stack Manager"
    echo "   1) Deploy Gaming Stack (LXC $CONTAINER_ID)"
    echo "   2) Manage Game Servers"
    echo "   3) Show Gaming Status"
    show_menu_footer
    read -r -p "   Enter your choice: " choice

    case $choice in
        1) deploy_gaming_stack ;;
        2) manage_games ;;
        3) show_gaming_status ;;
        b|B) exec bash "$WORK_DIR/scripts/main-menu.sh" ;;
        q|Q) echo "Exiting."; exit 0 ;;
        *) print_error "Invalid choice. Please try again." ;;
    esac
done