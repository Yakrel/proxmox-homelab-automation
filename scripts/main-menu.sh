#!/bin/bash

# This script is downloaded and executed by the main installer.
# It provides the main user interface for the automation tool.

# --- Global Variables ---

WORK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)"

# Source helper functions and other scripts
source "$WORK_DIR/scripts/stack-config.sh"

# --- Main Menu Loop ---

while true; do
    clear
    echo "==============================================="
    echo "      Proxmox Homelab - Stack Deployment"
    echo "==============================================="
    echo
    echo "   1) Deploy [proxy]      Stack (LXC 100)"
    echo "   2) Deploy [media]      Stack (LXC 101)"
    echo "   3) Deploy [files]      Stack (LXC 102)"
    echo "   4) Deploy [webtools]   Stack (LXC 103)"
    echo "   5) Deploy [monitoring] Stack (LXC 104)"
    echo "   6) Deploy [development]Stack (LXC 150)"
    echo
    echo "-----------------------------------------------"
    echo "   h) Run Proxmox Helper Scripts..."
    echo "-----------------------------------------------"
    echo "   q) Quit"
    echo
    read -p "   Enter your choice: " choice

    case $choice in
        1) bash "$WORK_DIR/scripts/deploy-stack.sh" "proxy" ; break ;;
        2) bash "$WORK_DIR/scripts/deploy-stack.sh" "media" ; break ;;
        3) bash "$WORK_DIR/scripts/deploy-stack.sh" "files" ; break ;;
        4) bash "$WORK_DIR/scripts/deploy-stack.sh" "webtools" ; break ;;
        5) bash "$WORK_DIR/scripts/deploy-stack.sh" "monitoring" ; break ;;
        6) bash "$WORK_DIR/scripts/deploy-stack.sh" "development" ; break ;;
        h) bash "$WORK_DIR/scripts/helper-menu.sh" ; break ;;
        q|Q) echo "Exiting."; exit 0 ;;
        *) echo "Invalid choice. Please try again." ; sleep 2 ;;
    esac
    echo
    read -p "Press Enter to return to the menu..."
done
