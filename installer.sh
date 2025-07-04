#!/bin/bash

# =================================================================
#         Proxmox Homelab Automation - Bootstrapper
# =================================================================
# This script is a lightweight bootstrapper. It sets up a temporary
# environment and downloads the latest version of the main scripts
# from the GitHub repository to execute them.
#
# To run:
# bash -c "$(curl -fsSL https://raw.githubusercontent.com/Yakrel/proxmox-homelab-automation/main/installer.sh)"
#

set -e

# --- Global Variables ---

WORK_DIR=""
REPO_BASE_URL="https://raw.githubusercontent.com/Yakrel/proxmox-homelab-automation/main"

# --- Helper Functions ---

print_info() { echo -e "\033[36m[INFO]\033[0m $1"; }
print_success() { echo -e "\033[32m[SUCCESS]\033[0m $1"; }
print_error() { echo -e "\033[31m[ERROR]\033[0m $1"; }

# --- Cleanup Function ---

cleanup() {
    if [ -n "$WORK_DIR" ] && [ -d "$WORK_DIR" ]; then
        print_info "Cleaning up temporary files..."
        rm -rf "$WORK_DIR"
    fi
}

# --- Main Logic ---

# 1. Setup Temporary Environment
WORK_DIR=$(mktemp -d /tmp/proxmox-automation.XXXXXX)
trap cleanup EXIT

print_info "Created temporary directory: $WORK_DIR"
cd "$WORK_DIR"
mkdir -p scripts

# 2. Download Core Scripts
print_info "Downloading the latest scripts from the repository..."

# List of scripts to download
SCRIPTS_TO_DOWNLOAD=(
    "scripts/main-menu.sh"
    "scripts/lxc-manager.sh"
    "scripts/deploy-stack.sh"
    "scripts/stack-config.sh"
    "scripts/helper-menu.sh"
)

for script_path in "${SCRIPTS_TO_DOWNLOAD[@]}"; do
    print_info " -> Downloading $script_path"
    curl -sSL "$REPO_BASE_URL/$script_path" -o "$script_path"
    if [ ! -s "$script_path" ]; then
        print_error "Failed to download $script_path. Please check the URL and repository structure."
        exit 1
    fi
    chmod +x "$script_path"
done

print_success "All scripts downloaded successfully."

# 3. Execute the Main Menu
print_info "Starting the main application..."
echo "-------------------------------------------------"

bash "$WORK_DIR/scripts/main-menu.sh"

# The 'trap' will handle cleanup automatically on exit