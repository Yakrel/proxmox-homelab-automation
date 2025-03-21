#!/bin/bash

# Title
echo "======================================================"
echo "Proxmox Homelab Automation - Setup Tool"
echo "======================================================"

# Root check
if [ "$(id -u)" -ne 0 ]; then
   echo "This script must be run as root" 
   exit 1
fi

# Temporary working directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "Fetching script files from $SCRIPT_DIR/scripts/."

# Menu
echo ""
echo "Please select the operation you want to perform:"
echo "1) Security Installation (Fail2Ban)"
echo "2) Storage Installation (Samba, Sanoid)"
echo "3) Proxy LXC (ID: 100) Preparation"
echo "4) Media LXC (ID: 101) Preparation"
echo "5) Exit"
echo ""

read -p "Your choice (1-5): " choice

case $choice in
    1)
        # Security installation
        if [ -f "$SCRIPT_DIR/scripts/install_security.sh" ]; then
            echo "Starting security installation..."
            bash "$SCRIPT_DIR/scripts/install_security.sh"
        else
            echo "ERROR: $SCRIPT_DIR/scripts/install_security.sh file not found!"
        fi
        ;;
    2)
        # Storage installation
        if [ -f "$SCRIPT_DIR/scripts/install_storage.sh" ]; then
            echo "Starting storage installation..."
            bash "$SCRIPT_DIR/scripts/install_storage.sh"
        else
            echo "ERROR: $SCRIPT_DIR/scripts/install_storage.sh file not found!"
        fi
        ;;
    3)
        # Proxy LXC preparation
        if [ -f "$SCRIPT_DIR/scripts/setup_proxy_lxc.sh" ]; then
            echo "Starting Proxy LXC preparation..."
            bash "$SCRIPT_DIR/scripts/setup_proxy_lxc.sh"
        else
            echo "ERROR: $SCRIPT_DIR/scripts/setup_proxy_lxc.sh file not found!"
        fi
        ;;
    4)
        # Media LXC preparation
        if [ -f "$SCRIPT_DIR/scripts/setup_media_lxc.sh" ]; then
            echo "Starting Media LXC preparation..."
            bash "$SCRIPT_DIR/scripts/setup_media_lxc.sh"
        else
            echo "ERROR: $SCRIPT_DIR/scripts/setup_media_lxc.sh file not found!"
        fi
        ;;
    5)
        # Exit
        echo "Exiting..."
        exit 0
        ;;
    *)
        echo "Invalid choice!"
        exit 1
        ;;
esac

echo "======================================================"
echo "Operation completed!"
echo "======================================================"
exit 0
