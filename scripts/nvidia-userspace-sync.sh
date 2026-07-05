#!/bin/bash
# Sync NVIDIA User-Space Libraries with Host Driver Version
set -euo pipefail

# 1. Detect Host Driver Version
if [[ ! -f /proc/driver/nvidia/version ]]; then
    echo "[NVIDIA-SYNC] WARNING: NVIDIA kernel module is not loaded on host. Skipping sync."
    exit 0
fi

# Use grep directly on file (no pipe) to avoid broken pipe errors
target_version=$(grep -oP 'Kernel Module\s+\K[0-9.]+' /proc/driver/nvidia/version 2>/dev/null || true)
if [[ -z "$target_version" ]]; then
    # Fallback: awk parses the version without spawning extra processes
    target_version=$(awk '/Kernel Module/ {for(i=1;i<=NF;i++) if($i ~ /^[0-9]+\.[0-9]/) {print $i; exit}}' /proc/driver/nvidia/version || true)
fi

if [[ -z "$target_version" ]]; then
    echo "[NVIDIA-SYNC] ERROR: Could not parse host NVIDIA driver version. Skipping sync."
    exit 0
fi

# 2. Check Container's Current Installed Version
installed_version=""
if command -v nvidia-smi &>/dev/null; then
    raw=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader,nounits 2>/dev/null || true)
    # Only accept output that looks like a real version number (e.g. 580.173.02)
    # When NVML has a version mismatch, nvidia-smi writes an error message to stdout
    if [[ "$raw" =~ ^[0-9]+\.[0-9]+ ]]; then
        installed_version="$raw"
    fi
fi

lib_check=0
if ldconfig -p | grep -q libEGL_nvidia; then
    lib_check=1
fi

# 3. Perform Sync if versions mismatch or libraries are missing
if [[ "$installed_version" != "$target_version" ]] || [[ "$lib_check" -eq 0 ]]; then
    driver_file="/datapool/config/temp/NVIDIA-Linux-x86_64-${target_version}.run"
    if [[ -f "$driver_file" ]]; then
        echo "[NVIDIA-SYNC] Host driver version is ${target_version} (container is ${installed_version:-none}). Syncing..."
        "$driver_file" --silent --accept-license --no-kernel-module --no-x-check
        echo "[NVIDIA-SYNC] NVIDIA user-space libraries updated to ${target_version} successfully."
    else
        echo "[NVIDIA-SYNC] WARNING: Driver installer runfile not found at ${driver_file}. Bypassing sync so container can boot."
        exit 0
    fi
else
    echo "[NVIDIA-SYNC] NVIDIA user-space drivers are already up-to-date (version ${target_version})."
fi
