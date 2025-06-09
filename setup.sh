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
    script_path=$1
    script_name=$(basename "$script_path")
    echo "Downloading $script_name..."
    wget -q -O "$TEMP_DIR/$script_name" "$REPO_URL/$script_path"
    
    if [ $? -ne 0 ]; then
        echo "ERROR: Failed to download $script_name from $REPO_URL/$script_path"
        return 1
    fi
    
    chmod +x "$TEMP_DIR/$script_name"
    return 0
}

# Main deployment menu
main_deployment_menu() {
    echo ""
    echo "Please select the operation you want to perform:"
    echo "1) Deploy Media Stack (Auto LXC + Services)"
    echo "2) Deploy Proxy Stack (Auto LXC + Services)"
    echo "3) Deploy Downloads Stack (Auto LXC + Services)"
    echo "4) Deploy Utility Stack (Auto LXC + Services)"
    echo "5) Deploy Monitoring Stack (Auto LXC + Services)"
    echo "6) Deploy All Stacks (Complete Homelab)"
    echo "7) Other Utilities (Security, Storage, Network)"
    echo "8) Exit"
    echo ""
    
    read -p "Your choice (1-8): " auto_choice
    
    case $auto_choice in
        1)
            echo "Starting automated Media stack deployment..."
            if download_script "scripts/automation/create_alpine_lxc.sh" && download_script "scripts/automation/deploy_stack.sh"; then
                bash "$TEMP_DIR/create_alpine_lxc.sh" media
                bash "$TEMP_DIR/deploy_stack.sh" media
            fi
            ;;
        2)
            echo "Starting automated Proxy stack deployment..."
            if download_script "scripts/automation/create_alpine_lxc.sh" && download_script "scripts/automation/deploy_stack.sh"; then
                bash "$TEMP_DIR/create_alpine_lxc.sh" proxy
                bash "$TEMP_DIR/deploy_stack.sh" proxy
            fi
            ;;
        3)
            echo "Starting automated Downloads stack deployment..."
            if download_script "scripts/automation/create_alpine_lxc.sh" && download_script "scripts/automation/deploy_stack.sh"; then
                bash "$TEMP_DIR/create_alpine_lxc.sh" downloads
                bash "$TEMP_DIR/deploy_stack.sh" downloads
            fi
            ;;
        4)
            echo "Starting automated Utility stack deployment..."
            if download_script "scripts/automation/create_alpine_lxc.sh" && download_script "scripts/automation/deploy_stack.sh"; then
                bash "$TEMP_DIR/create_alpine_lxc.sh" utility
                bash "$TEMP_DIR/deploy_stack.sh" utility
            fi
            ;;
        5)
            echo "Starting automated Monitoring stack deployment..."
            if download_script "scripts/automation/create_alpine_lxc.sh" && download_script "scripts/automation/deploy_stack.sh"; then
                bash "$TEMP_DIR/create_alpine_lxc.sh" monitoring
                bash "$TEMP_DIR/deploy_stack.sh" monitoring
            fi
            ;;
        6)
            echo "Starting complete homelab deployment..."
            if download_script "scripts/automation/create_alpine_lxc.sh" && download_script "scripts/automation/deploy_stack.sh"; then
                echo "Deploying Proxy stack..."
                bash "$TEMP_DIR/create_alpine_lxc.sh" proxy
                bash "$TEMP_DIR/deploy_stack.sh" proxy
                
                echo "Deploying Media stack..."
                bash "$TEMP_DIR/create_alpine_lxc.sh" media
                bash "$TEMP_DIR/deploy_stack.sh" media
                
                echo "Deploying Downloads stack..."
                bash "$TEMP_DIR/create_alpine_lxc.sh" downloads
                bash "$TEMP_DIR/deploy_stack.sh" downloads
                
                echo "Deploying Utility stack..."
                bash "$TEMP_DIR/create_alpine_lxc.sh" utility
                bash "$TEMP_DIR/deploy_stack.sh" utility
                
                echo "Deploying Monitoring stack..."
                bash "$TEMP_DIR/create_alpine_lxc.sh" monitoring
                bash "$TEMP_DIR/deploy_stack.sh" monitoring
                
                echo "Complete homelab deployment finished!"
            fi
            ;;
        7)
            # Other utilities submenu
            other_utilities_menu
            ;;
        8)
            # Exit
            echo "Exiting..."
            exit 0
            ;;
        *)
            echo "Invalid choice!"
            ;;
    esac
}

# Function for Other Utilities submenu
other_utilities_menu() {
    echo ""
    echo "======================================================"
    echo "Other Utilities Menu"
    echo "======================================================"
    echo "1) Security Setup (Fail2Ban)"
    echo "2) Storage Setup (Samba, Sanoid)"
    echo "3) Network Bonding Setup"
    echo "4) Back to Main Menu"
    echo ""
    
    read -p "Your choice (1-4): " util_choice
    
    case $util_choice in
        1)
            # Security installation
            if download_script "scripts/core/install_security.sh"; then
                echo "Starting security installation..."
                bash "$TEMP_DIR/install_security.sh"
            fi
            ;;
        2)
            # Storage installation
            if download_script "scripts/core/install_storage.sh"; then
                echo "Starting storage installation..."
                bash "$TEMP_DIR/install_storage.sh"
            fi
            ;;
        3)
            # Network bonding setup
            if download_script "scripts/network/setup_bonding.sh"; then
                echo "Starting network bonding setup..."
                bash "$TEMP_DIR/setup_bonding.sh"
            fi
            ;;
        4)
            return 0
            ;;
        *)
            echo "Invalid choice!"
            ;;
    esac
}

# Execute main menu
main_deployment_menu

echo "======================================================"
echo "Operation completed!"
echo "======================================================"
exit 0
