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

# Repository URL
REPO_URL="https://raw.githubusercontent.com/Yakrel/proxmox-homelab-automation/main"
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

echo "Setting up temporary directory at $TEMP_DIR"

# Function to download script file
download_script() {
    script_name=$1
    echo "Downloading $script_name..."
    wget -q -O "$TEMP_DIR/$script_name" "$REPO_URL/scripts/$script_name"
    
    if [ $? -ne 0 ]; then
        echo "ERROR: Failed to download $script_name from $REPO_URL/scripts/$script_name"
        return 1
    fi
    
    chmod +x "$TEMP_DIR/$script_name"
    return 0
}

# Menu
echo ""
echo "Please select the operation you want to perform:"
echo "1) Security Installation (Fail2Ban)"
echo "2) Storage Installation (Samba, Sanoid)"
echo "3) Proxy LXC (lxc-proxy-01, ID: 100) Preparation"
echo "4) Media LXC (lxc-media-01, ID: 101) Preparation"
echo "5) Exit"
echo ""

read -p "Your choice (1-5): " choice

case $choice in
    1)
        # Security installation
        if download_script "install_security.sh"; then
            echo "Starting security installation..."
            bash "$TEMP_DIR/install_security.sh"
        fi
        ;;
    2)
        # Storage installation
        if download_script "install_storage.sh"; then
            echo "Starting storage installation..."
            bash "$TEMP_DIR/install_storage.sh"
        fi
        ;;
    3)
        # Proxy LXC preparation
        if download_script "setup_proxy_lxc.sh"; then
            echo "Starting Proxy LXC preparation..."
            bash "$TEMP_DIR/setup_proxy_lxc.sh"
        fi
        ;;
    4)
        # Media LXC preparation
        if download_script "setup_media_lxc.sh"; then
            echo "Starting Media LXC preparation..."
            bash "$TEMP_DIR/setup_media_lxc.sh"
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
