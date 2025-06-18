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

# Repository URL - configurable branch
BRANCH="${HOMELAB_BRANCH:-main}"
REPO_URL="https://raw.githubusercontent.com/Yakrel/proxmox-homelab-automation/$BRANCH"
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

echo "Setting up temporary directory at $TEMP_DIR"

# Function to download script file (always fresh)
download_script() {
    script_path=$1
    script_name=$(basename "$script_path")
    echo "Downloading latest $script_name..."
    
    # Remove existing file to ensure fresh download
    [ -f "$TEMP_DIR/$script_name" ] && rm -f "$TEMP_DIR/$script_name"
    
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
    while true; do
        echo ""
        echo "Please select the operation you want to perform:"
        echo "1) Deploy Proxy Stack (LXC 100 - Cloudflare Tunnels)"
        echo "2) Deploy Media Stack (LXC 101 - Sonarr, Radarr, Jellyfin)"
        echo "3) Deploy Downloads Stack (LXC 102 - JDownloader, MeTube)"
        echo "4) Deploy Utility Stack (LXC 103 - Firefox Browser)"
        echo "5) Deploy Monitoring Stack (LXC 104 - Grafana, Prometheus)"
        echo "6) Post-Install Setup (Recommended after fresh Proxmox install)"
        echo "7) System Maintenance (Security Status)"
        echo "8) Exit"
        echo ""
        
        read -p "Your choice (1-8): " auto_choice
        
        case $auto_choice in
            1)
                echo "Starting automated Proxy stack deployment..."
                if download_script "scripts/automation/create_alpine_lxc.sh" && download_script "scripts/automation/deploy_stack.sh"; then
                    bash "$TEMP_DIR/create_alpine_lxc.sh" proxy
                    bash "$TEMP_DIR/deploy_stack.sh" proxy
                fi
                ;;
            2)
                echo "Starting automated Media stack deployment..."
                if download_script "scripts/automation/create_alpine_lxc.sh" && download_script "scripts/automation/deploy_stack.sh"; then
                    bash "$TEMP_DIR/create_alpine_lxc.sh" media
                    bash "$TEMP_DIR/deploy_stack.sh" media
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
                # Post-Install Setup submenu
                post_install_menu
                ;;
            7)
                # System Maintenance submenu
                system_maintenance_menu
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
    done
}

# Function for Post-Install Setup submenu
post_install_menu() {
    while true; do
        echo ""
        echo "======================================================"
        echo "Post-Install Setup Menu"
        echo "======================================================"
        echo "⚠️  Run these once after fresh Proxmox installation"
        echo ""
        echo "1) Helper Scripts Post-Install (PVE optimization)"
        echo "2) Microcode Update (CPU microcode)"
        echo "3) ZFS Performance Optimization"
        echo "4) Security Setup (Fail2Ban)"
        echo "5) Storage Setup (Samba, Sanoid)"
        echo "6) Network Bonding Setup"
        echo "7) Timezone Configuration (Turkey)"
        echo "8) Auto-Update Setup (Cron for LXCs)"
        echo "9) Development Environment (LXC + Claude Code)"
        echo "10) Back to Main Menu"
        echo ""
        
        read -p "Your choice (1-10): " post_choice
        
        case $post_choice in
            1)
                echo "Running Helper Scripts Post-Install..."
                bash -c "$(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/tools/pve/post-pve-install.sh)"
                ;;
            2)
                echo "Running Microcode Update..."
                bash -c "$(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/tools/pve/microcode.sh)"
                ;;
            3)
                if download_script "scripts/core/optimize_zfs.sh"; then
                    echo "Starting ZFS performance optimization..."
                    bash "$TEMP_DIR/optimize_zfs.sh"
                fi
                ;;
            4)
                if download_script "scripts/core/install_security.sh"; then
                    echo "Starting security installation..."
                    bash "$TEMP_DIR/install_security.sh"
                fi
                ;;
            5)
                if download_script "scripts/core/install_storage.sh"; then
                    echo "Starting storage installation..."
                    bash "$TEMP_DIR/install_storage.sh"
                fi
                ;;
            6)
                if download_script "scripts/network/setup_bonding.sh"; then
                    echo "Starting network bonding setup..."
                    bash "$TEMP_DIR/setup_bonding.sh"
                fi
                ;;
            7)
                if download_script "scripts/core/configure_timezone.sh"; then
                    echo "Starting timezone configuration..."
                    bash "$TEMP_DIR/configure_timezone.sh"
                fi
                ;;
            8)
                echo "Setting up Auto-Update for LXCs..."
                bash -c "$(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/tools/pve/cron-update-lxcs.sh)"
                ;;
            9)
                if download_script "scripts/lxc/setup_dev_lxc.sh"; then
                    echo "Setting up Development Environment..."
                    bash "$TEMP_DIR/setup_dev_lxc.sh"
                fi
                ;;
            10)
                return 0
                ;;
            *)
                echo "Invalid choice!"
                ;;
        esac
    done
}

# Function for System Maintenance submenu
system_maintenance_menu() {
    while true; do
        echo ""
        echo "======================================================"
        echo "System Maintenance Menu"
        echo "======================================================"
        echo "1) Security Status Check (Fail2ban)"
        echo "2) Back to Main Menu"
        echo ""
        
        read -p "Your choice (1-2): " maint_choice
        
        case $maint_choice in
            1)
                if download_script "scripts/maintenance/security_monitor.sh"; then
                    echo "Checking security status..."
                    bash "$TEMP_DIR/security_monitor.sh"
                fi
                ;;
            2)
                return 0
                ;;
            *)
                echo "Invalid choice!"
                ;;
        esac
    done
}

# Execute main menu
main_deployment_menu

echo "======================================================"
echo "Operation completed!"
echo "======================================================"
exit 0
