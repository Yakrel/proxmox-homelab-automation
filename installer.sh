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
if [[ $EUID -ne 0 ]]; then
    print_error "Run this installer as root on the Proxmox host"
    exit 1
fi

WORK_DIR=$(mktemp -d /tmp/proxmox-automation.XXXXXX)
trap cleanup EXIT

print_info "Created temporary directory: $WORK_DIR"
cd "$WORK_DIR"

# 2. Download Core Scripts
print_info "Downloading the latest scripts from the repository..."

# Download through GitHub's archive host so a transient github.com HTML error
# cannot be piped into tar and mistaken for a repository archive.
archive_file="$WORK_DIR/repository.tar.gz"
curl -fsSL \
    "https://codeload.github.com/Yakrel/proxmox-homelab-automation/tar.gz/refs/heads/main" \
    -o "$archive_file" || {
    print_error "Failed to download repository archive"
    exit 1
}

tar -xzf "$archive_file" -C "$WORK_DIR" --strip-components=1 || {
    print_error "Failed to extract repository archive"
    exit 1
}
rm -f "$archive_file"

print_success "Environment setup complete"

# Ensure yq and age are available before running menus. age unwraps the SOPS
# identity from the master passphrase.
missing_tools=()
for tool in yq age; do
    command -v "$tool" &>/dev/null || missing_tools+=("$tool")
done
if [[ ${#missing_tools[@]} -gt 0 ]]; then
    apt-get update -q || { print_error "Failed to update package lists"; exit 1; }
    apt-get install -y "${missing_tools[@]}" || { print_error "Failed to install ${missing_tools[*]}"; exit 1; }
fi

# SOPS is not packaged for Debian. Install the latest release once, verified
# against the SHA-256 checksums published with it; later runs reuse the binary.
# To upgrade, delete /usr/local/bin/sops and run the installer again.
if ! command -v sops &>/dev/null; then
    print_info "Installing sops..."
    sops_tag=$(curl -fsSLI -o /dev/null -w '%{url_effective}' https://github.com/getsops/sops/releases/latest)
    sops_tag="${sops_tag##*/}"
    sops_url="https://github.com/getsops/sops/releases/download/${sops_tag}"
    curl -fsSL "$sops_url/sops-${sops_tag}.linux.amd64" -o "$WORK_DIR/sops"
    curl -fsSL "$sops_url/sops-${sops_tag}.checksums.txt" -o "$WORK_DIR/sops.checksums"
    sops_sha256=$(awk -v name="sops-${sops_tag}.linux.amd64" '$2 == name { print $1 }' "$WORK_DIR/sops.checksums")
    echo "$sops_sha256  $WORK_DIR/sops" | sha256sum -c --quiet -
    install -m 0755 "$WORK_DIR/sops" /usr/local/bin/sops
fi

# 3. Parse CLI arguments or launch interactive menu
raw_0="${0:-}"
args=("$@")

if [[ ! "$raw_0" =~ (^-?(bash|sh|zsh)$|\.sh$|/) ]]; then
    target_args=("$raw_0" "${args[@]}")
else
    target_args=("${args[@]}")
fi

if [[ "${target_args[0]:-}" =~ ^(_|--)$ ]]; then
    target_args=("${target_args[@]:1}")
fi

if [[ ${#target_args[@]} -eq 0 ]]; then
    print_info "Starting main application"
    echo "-------------------------------------------------"
    bash "$WORK_DIR/scripts/main-menu.sh"
else
    action="${target_args[0]}"
    case "$action" in
        redeploy|fast-redeploy)
            target="${target_args[1]:-all}"
            if [[ "$target" != "all" && -f "$WORK_DIR/stacks.yaml" ]] && ! yq -e ".stacks[\"$target\"]" "$WORK_DIR/stacks.yaml" &>/dev/null; then
                print_error "Unknown stack for redeploy: '$target'"
                print_info "Available stacks: all, $(yq -r '.stacks | keys | join(", ")' "$WORK_DIR/stacks.yaml")"
                exit 1
            fi
            echo "-------------------------------------------------"
            if [[ "$target" == "all" ]]; then
                print_info "Starting fast redeploy for all running stacks..."
                bash "$WORK_DIR/scripts/fast-redeploy.sh"
            else
                print_info "Starting fast redeploy for stack: $target..."
                bash "$WORK_DIR/scripts/fast-redeploy.sh" "$target"
            fi
            ;;
        helper|helpers)
            echo "-------------------------------------------------"
            bash "$WORK_DIR/scripts/helper-menu.sh" "${target_args[@]:1}"
            ;;
        *)
            if [[ -f "$WORK_DIR/stacks.yaml" ]] && ! yq -e ".stacks[\"$action\"]" "$WORK_DIR/stacks.yaml" &>/dev/null; then
                print_error "Unknown stack or command: '$action'"
                print_info "Available stacks: $(yq -r '.stacks | keys | join(", ")' "$WORK_DIR/stacks.yaml")"
                print_info "Commands: redeploy [stack|all], helper"
                exit 1
            fi
            echo "-------------------------------------------------"
            print_info "Starting deployment for stack: $action..."
            bash "$WORK_DIR/scripts/deploy-stack.sh" "$action"
            ;;
    esac
fi

# The 'trap' will handle cleanup automatically on exit
