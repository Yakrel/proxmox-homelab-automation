#!/bin/bash

# Proxmox Homelab Automation - Bootstrapper
# This script downloads and runs the latest version of the automation suite.

set -e # Exit immediately if a command exits with a non-zero status.

# --- Configuration ---
REPO_URL="https://github.com/Yakrel/proxmox-homelab-automation"
TMP_DIR=$(mktemp -d /tmp/proxmox-automation.XXXXXX)

# --- Cleanup Function ---
# Ensures the temporary directory is removed on exit, interrupt, or termination.
cleanup() {
    echo "Cleaning up temporary files..."
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT INT TERM

# --- Main Logic ---
echo "======================================================"
echo "Proxmox Homelab Automation - Setup Tool"
echo "======================================================"
echo "Downloading the latest version from GitHub..."

# Download the latest version of the repository as a tarball and extract it
# -f: Fail silently on server errors
# -s: Silent mode
# -S: Show error message if it fails
# -L: Follow redirects
# -C "$TMP_DIR": Change directory to the temp dir before extracting
# --strip-components=1: Remove the top-level directory from the tarball
if ! curl -fsSL "${REPO_URL}/archive/main.tar.gz" | tar -xz -C "$TMP_DIR" --strip-components=1; then
    echo "ERROR: Failed to download or extract the repository." >&2
    exit 1
fi

echo "Download complete. Launching the main script..."
echo ""

# Change to the temporary directory and execute the main script
cd "$TMP_DIR"
bash "scripts/main.sh"

# The cleanup trap will handle directory removal automatically on exit.
exit 0
