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

# Cleanup function
cleanup_and_exit() {
    local exit_code=${1:-0}
    echo ""
    echo "======================================================"
    if [ $exit_code -eq 0 ]; then
        echo "Operation completed!"
    else
        echo "Operation interrupted or failed!"
    fi
    echo "Cleaning up temporary files..."
    rm -rf "$TEMP_DIR" 2>/dev/null || true
    echo "======================================================"
    exit $exit_code
}

# Set up signal handlers for graceful exit
trap 'cleanup_and_exit 1' INT TERM
trap 'cleanup_and_exit 0' EXIT

echo "Setting up temporary directory at $TEMP_DIR"

# Create proper directory structure to match GitHub repo
mkdir -p "$TEMP_DIR/scripts/automation"
mkdir -p "$TEMP_DIR/scripts/utils"
mkdir -p "$TEMP_DIR/scripts/core"
mkdir -p "$TEMP_DIR/scripts/network"
mkdir -p "$TEMP_DIR/scripts/maintenance"

# Function to download script file (always fresh)
download_script() {
    script_path=$1
    script_name=$(basename "$script_path")
    echo "Downloading latest $script_name..."
    
    # Create full path in temp directory to match repo structure
    local target_path="$TEMP_DIR/$script_path"
    local target_dir=$(dirname "$target_path")
    
    # Ensure target directory exists
    mkdir -p "$target_dir"
    
    # Remove existing file to ensure fresh download
    [ -f "$target_path" ] && rm -f "$target_path"
    
    wget -q -O "$target_path" "$REPO_URL/$script_path"
    
    if [ $? -ne 0 ]; then
        echo "ERROR: Failed to download $script_name from $REPO_URL/$script_path"
        return 1
    fi
    
    chmod +x "$target_path"
    return 0
}

# Main deployment menu
main_deployment_menu() {
    while true; do
        echo ""
        echo "Please select the operation you want to perform:"
        echo "1) Deploy Proxy Stack (LXC 100 - Cloudflare Tunnels)"
        echo "2) Deploy Media Stack (LXC 101 - Sonarr, Radarr, Jellyfin)"
        echo "3) Deploy Files Stack (LXC 102 - JDownloader, MeTube, Palmr)"
        echo "4) Deploy Webtools Stack (LXC 103 - Homepage, Firefox)"
        echo "5) Deploy Monitoring Stack (LXC 104 - Grafana, Prometheus)"
        echo "6) Deploy Development Stack (LXC 150 - Ubuntu + Claude Code)"
        echo "7) Post-Install Setup (Recommended after fresh Proxmox install)"
        echo "8) System Maintenance (Security Status)"
        echo "9) Exit"
        echo ""
        
        read -p "Your choice (1-9): " auto_choice
        
        case $auto_choice in
            1)
                echo "Starting automated Proxy stack deployment..."
                if download_script "scripts/automation/create_alpine_lxc.sh" && download_script "scripts/automation/deploy_stack.sh" && download_script "scripts/utils/common.sh"; then
                    bash "$TEMP_DIR/scripts/automation/create_alpine_lxc.sh" proxy
                    bash "$TEMP_DIR/scripts/automation/deploy_stack.sh" proxy
                fi
                ;;
            2)
                echo "Starting automated Media stack deployment..."
                if download_script "scripts/automation/create_alpine_lxc.sh" && download_script "scripts/automation/deploy_stack.sh" && download_script "scripts/utils/common.sh"; then
                    bash "$TEMP_DIR/scripts/automation/create_alpine_lxc.sh" media
                    bash "$TEMP_DIR/scripts/automation/deploy_stack.sh" media
                fi
                ;;
            3)
                echo "Starting automated Files stack deployment..."
                if download_script "scripts/automation/create_alpine_lxc.sh" && download_script "scripts/automation/deploy_stack.sh" && download_script "scripts/utils/common.sh"; then
                    bash "$TEMP_DIR/scripts/automation/create_alpine_lxc.sh" files
                    bash "$TEMP_DIR/scripts/automation/deploy_stack.sh" files
                fi
                ;;
            4)
                echo "Starting automated Webtools stack deployment..."
                if ! download_script "scripts/automation/create_alpine_lxc.sh"; then
                    echo "ERROR: Failed to download create_alpine_lxc.sh"
                elif ! download_script "scripts/automation/deploy_stack.sh"; then
                    echo "ERROR: Failed to download deploy_stack.sh"
                elif ! download_script "scripts/utils/common.sh"; then
                    echo "ERROR: Failed to download common.sh"
                else
                    bash "$TEMP_DIR/scripts/automation/create_alpine_lxc.sh" webtools
                    bash "$TEMP_DIR/scripts/automation/deploy_stack.sh" webtools
                fi
                ;;
            5)
                echo "Starting automated Monitoring stack deployment..."
                if download_script "scripts/automation/create_alpine_lxc.sh" && download_script "scripts/automation/deploy_stack.sh" && download_script "scripts/utils/common.sh"; then
                    bash "$TEMP_DIR/scripts/automation/create_alpine_lxc.sh" monitoring
                    bash "$TEMP_DIR/scripts/automation/deploy_stack.sh" monitoring
                fi
                ;;
            6)
                echo "Starting automated Development stack deployment..."
                if download_script "scripts/automation/create_ubuntu_lxc.sh" && download_script "scripts/utils/common.sh"; then
                    bash "$TEMP_DIR/scripts/automation/create_ubuntu_lxc.sh" development
                fi
                ;;
            7)
                # Post-Install Setup submenu
                post_install_menu
                ;;
            8)
                # System Maintenance submenu
                system_maintenance_menu
                ;;
            9)
                # Exit
                echo "Exiting..."
                return 0
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
        echo "9) Back to Main Menu"
        echo ""
        
        read -p "Your choice (1-9): " post_choice
        
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
                    bash "$TEMP_DIR/scripts/core/optimize_zfs.sh"
                fi
                ;;
            4)
                if download_script "scripts/core/install_security.sh"; then
                    echo "Starting security installation..."
                    bash "$TEMP_DIR/scripts/core/install_security.sh"
                fi
                ;;
            5)
                if download_script "scripts/core/install_storage.sh"; then
                    echo "Starting storage installation..."
                    bash "$TEMP_DIR/scripts/core/install_storage.sh"
                fi
                ;;
            6)
                if download_script "scripts/network/setup_bonding.sh"; then
                    echo "Starting network bonding setup..."
                    bash "$TEMP_DIR/scripts/network/setup_bonding.sh"
                fi
                ;;
            7)
                if download_script "scripts/core/configure_timezone.sh"; then
                    echo "Starting timezone configuration..."
                    bash "$TEMP_DIR/scripts/core/configure_timezone.sh"
                fi
                ;;
            8)
                echo "Setting up Auto-Update for LXCs..."
                bash -c "$(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/tools/pve/cron-update-lxcs.sh)"
                ;;
            9)
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
                    bash "$TEMP_DIR/scripts/maintenance/security_monitor.sh"
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

# Normal exit - cleanup will be handled by EXIT trap
exit 0
