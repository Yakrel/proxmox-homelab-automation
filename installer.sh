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
# DEPENDENCIES:
# - yq: YAML parser used to read stacks.yaml configuration
#   (python3-argcomplete, python3-tomlkit, python3-xmltodict are auto-installed as yq dependencies)
#
# To remove these packages from your Proxmox host if needed:
# apt-get remove --purge -y yq python3-argcomplete python3-tomlkit python3-xmltodict
# apt-get autoremove -y
#

# Strict error handling
set -euo pipefail

# --- Global Variables ---

WORK_DIR=""

# --- Helper Functions ---

print_info() { echo -e "\033[36m[INFO]\033[0m $1"; }
print_success() { echo -e "\033[32m[SUCCESS]\033[0m $1"; }
print_error() { echo -e "\033[31m[ERROR]\033[0m $1"; }

# --- Cleanup Function ---

cleanup() {
    if [ -n "$WORK_DIR" ] && [ -d "$WORK_DIR" ]; then
        print_info "Cleaning up temporary files..."
        rm -rf "${WORK_DIR:?}"
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

# Download and extract the repository archive (tarball)
# This ensures we get all files without maintaining a manual list
curl -sSL "https://github.com/Yakrel/proxmox-homelab-automation/archive/refs/heads/main.tar.gz" | \
    tar xz -C "$WORK_DIR" --strip-components=1 || {
    print_error "Failed to download or extract repository archive"
    exit 1
}

# Post-processing: Fix line endings and permissions for all scripts
print_info "Setting up permissions..."
find "$WORK_DIR" -name "*.sh" -type f -exec sed -i 's/\r$//' {} +
find "$WORK_DIR" -name "*.sh" -type f -exec chmod +x {} +

print_success "Environment setup complete"

print_success "All scripts downloaded successfully."

# Ensure yq is available before running menus
if ! command -v yq &>/dev/null; then
    apt-get update -q || { print_error "Failed to update package lists"; exit 1; }
    apt-get install -y yq || { print_error "Failed to install yq"; exit 1; }
fi

# 3. Execute the Main Menu
print_info "Starting main application"
echo "-------------------------------------------------"

bash "$WORK_DIR/scripts/main-menu.sh"
main_menu_exit_code=$?

# Only report error if it's a real failure
if [[ $main_menu_exit_code -ne 0 && $main_menu_exit_code -ne 124 && $main_menu_exit_code -ne 130 ]]; then
    echo
    print_error "Main menu failed with exit code $main_menu_exit_code"
    print_error "Possible causes: missing packages, permission issues, configuration problems"
    print_info "Ensure you are running as root on Proxmox"
    exit $main_menu_exit_code
fi

# The 'trap' will handle cleanup automatically on exit