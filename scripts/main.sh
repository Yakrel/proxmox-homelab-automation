#!/bin/bash

# Enable exit on error for consistent error handling
set -e

# Title
echo "======================================================"
echo "Proxmox Homelab Automation - Setup Tool"
echo "======================================================"

# Root check
if [ "$(id -u)" -ne 0 ]; then
   echo "ERROR: This script must be run as root"
   exit 1
fi

# Cleanup function (simplified as no repo to clean)
cleanup_and_exit() {
    local exit_code=${1:-0}
    echo ""
    echo "======================================================"
    if [ $exit_code -eq 0 ]; then
        echo "Operation completed!"
    else
        echo "Operation interrupted or failed!"
    fi
    echo "Setup tool finished."
    echo "======================================================"
    exit $exit_code
}

# Set up signal handlers for graceful exit
trap 'cleanup_and_exit 1' INT TERM
trap 'cleanup_and_exit 0' EXIT

# --- Main Menu ---
# Main deployment menu
main_deployment_menu() {
    source "config.sh"

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
            1) bash "scripts/lxc-manager.sh" full proxy ;;
            2) bash "scripts/lxc-manager.sh" full media ;;
            3) bash "scripts/lxc-manager.sh" full files ;;
            4) bash "scripts/lxc-manager.sh" full webtools ;;
            5) bash "scripts/lxc-manager.sh" full monitoring ;;
            6) bash "scripts/lxc-manager.sh" full development ;;
            7) post_install_menu ;;
            8) system_maintenance_menu ;;
            9) echo "Exiting..."; return 0 ;;
            *) echo "Invalid choice!" ;;
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
            1) bash -c "$(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/tools/pve/post-pve-install.sh)" ;;
            2) bash -c "$(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/tools/pve/microcode.sh)" ;;
            3) bash "proxmox-helpers/optimize_zfs.sh" ;;
            4) bash "proxmox-helpers/install_security.sh" ;;
            5) bash "proxmox-helpers/install_storage.sh" ;;
            6) bash "proxmox-helpers/setup_bonding.sh" ;;
            7) bash "proxmox-helpers/configure_timezone.sh" ;;
            8) bash -c "$(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/tools/pve/cron-update-lxcs.sh)" ;;
            9) return 0 ;;
            *) echo "Invalid choice!" ;;
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
            1) bash "scripts/maintenance/security_monitor.sh" ;;
            2) return 0 ;;
            *) echo "Invalid choice!" ;;
        esac
    done
}

# Execute main menu
main_deployment_menu

# Normal exit - cleanup will be handled by EXIT trap
exit 0