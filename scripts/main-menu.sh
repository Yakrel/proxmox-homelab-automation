#!/bin/bash

# This script provides the main user interface for the Ansible-driven automation tool.

set -e

# --- Global Variables ---
REPO_DIR="/root/proxmox-homelab-automation" # Assuming the repo is cloned here by installer.sh

# --- Helper Functions ---
print_info() { echo -e "\033[36m[INFO]\033[0m $1"; }
print_success() { echo -e "\033[32m[SUCCESS]\033[0m $1"; }
print_error() { echo -e "\033[31m[ERROR]\033[0m $1"; }
press_enter_to_continue() {
    echo
    read -p "Press Enter to continue..."
}

# --- Main Menu Loop ---

while true; do
    clear
    echo "==============================================="
    echo "      Proxmox Homelab - Ansible Automation"
    echo "==============================================="
    echo
    echo "   Deploy Stacks:"
    echo "   1) Deploy [proxy]      Stack (LXC 100)"
    echo "   2) Deploy [media]      Stack (LXC 101)"
    echo "   3) Deploy [files]      Stack (LXC 102)"
    echo "   4) Deploy [webtools]   Stack (LXC 103)"
    echo "   5) Deploy [monitoring] Stack (LXC 104)"
    echo "   6) Deploy [backup]     Stack (LXC 150)"
    echo "   7) Deploy [development]Stack (LXC 151)"
    echo
    echo "   Host Configuration:"
    echo "   8) Configure Proxmox Host (Timezone, Security, Storage, ZFS, Network)"
    echo
    echo "-----------------------------------------------"
    echo "   q) Quit"
    echo
    read -p "   Enter your choice: " choice

    case $choice in
        1) ansible-playbook "$REPO_DIR/deploy.yml" --extra-vars "stack_name=proxy" ; press_enter_to_continue ;;
        2) ansible-playbook "$REPO_DIR/deploy.yml" --extra-vars "stack_name=media" ; press_enter_to_continue ;;
        3) ansible-playbook "$REPO_DIR/deploy.yml" --extra-vars "stack_name=files" ; press_enter_to_continue ;;
        4) ansible-playbook "$REPO_DIR/deploy.yml" --extra-vars "stack_name=webtools" ; press_enter_to_continue ;;
        5) ansible-playbook "$REPO_DIR/deploy.yml" --extra-vars "stack_name=monitoring" ; press_enter_to_continue ;;
        6) ansible-playbook "$REPO_DIR/deploy.yml" --extra-vars "stack_name=backup" ; press_enter_to_continue ;;
        7) ansible-playbook "$REPO_DIR/deploy.yml" --extra-vars "stack_name=development" ; press_enter_to_continue ;;
        8) ansible-playbook "$REPO_DIR/deploy.yml" --extra-vars "stack_name=proxmox_host_setup" ; press_enter_to_continue ;;
        q|Q) echo "Exiting."; exit 0 ;;
        *) echo "Invalid choice. Please try again." ; sleep 2 ;;
    esac
done