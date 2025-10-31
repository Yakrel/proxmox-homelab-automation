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
get_repo_base_url() { echo "https://raw.githubusercontent.com/Yakrel/proxmox-homelab-automation/main"; }
REPO_BASE_URL=$(get_repo_base_url)

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

# List of files to download
FILES_TO_DOWNLOAD=(
    "scripts/helper-functions.sh"
    "scripts/main-menu.sh"
    "scripts/lxc-manager.sh"
    "scripts/deploy-stack.sh"
    "scripts/helper-menu.sh"
    "scripts/gaming-menu.sh"
    "scripts/game-manager.sh"
    "scripts/fail2ban-manager.sh"
    "scripts/encrypt-env.sh"
    "scripts/modules/docker-deployment.sh"
    "scripts/modules/monitoring-deployment.sh"
    "scripts/modules/backup-deployment.sh"
    "config/promtail/promtail.yml"
    "stacks.yaml"
    "config/backrest/config.json.template"
)

# Create all directory structures first
for file_path in "${FILES_TO_DOWNLOAD[@]}"; do
    mkdir -p "$(dirname "$file_path")"
done

# Download all files in parallel for better performance
pids=()
for file_path in "${FILES_TO_DOWNLOAD[@]}"; do
    (
        curl -sSL "$REPO_BASE_URL/$file_path" -o "$file_path" || exit 1
        [[ ! -s "$file_path" ]] && exit 1
        # Convert line endings to Unix format (LF) for scripts
        if [[ "$file_path" == *.sh ]]; then
            sed -i 's/\r$//' "$file_path"
            chmod +x "$file_path"
        fi
    ) &
    pids+=($!)
done

# Wait for all downloads and check for failures
failed_downloads=()
for i in "${!pids[@]}"; do
    if ! wait "${pids[$i]}"; then
        failed_downloads+=("${FILES_TO_DOWNLOAD[$i]}")
    fi
done

# Report any failures
if [[ ${#failed_downloads[@]} -gt 0 ]]; then
    print_error "Failed to download the following files:"
    for file in "${failed_downloads[@]}"; do
        print_error "  - $file"
    done
    exit 1
fi


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