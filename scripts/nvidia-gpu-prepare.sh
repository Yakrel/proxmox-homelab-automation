#!/bin/bash
# Prepare NVIDIA devices before Proxmox inspects dev[n] passthrough paths.
set -euo pipefail

# This short lock protects preparation only. The menu also holds Proxmox
# configuration locks across the complete shutdown/install/start transaction.
exec 9>/run/lock/homelab-nvidia.lock
flock -w 30 9 || { echo "NVIDIA device preparation or maintenance is busy" >&2; exit 1; }

manifest=/etc/homelab-nvidia/driver
[[ -r "$manifest" ]] || { echo "NVIDIA driver manifest is missing" >&2; exit 1; }
read -r expected_version expected_sha256 < "$manifest"
[[ "$expected_version" =~ ^580\.[0-9]+\.[0-9]+$ ]] || exit 1
[[ "$expected_sha256" =~ ^[a-f0-9]{64}$ ]] || exit 1
disk_version=$(modinfo -k "$(uname -r)" -F version nvidia)
[[ "$disk_version" == "$expected_version" ]] || {
    echo "NVIDIA module on disk is $disk_version; expected $expected_version" >&2
    exit 1
}

modprobe nvidia
modprobe nvidia_modeset
modprobe nvidia_uvm
modprobe nvidia_drm
nvidia-modprobe -c0
nvidia-modprobe -m
nvidia-modprobe -u -c0

loaded_version=$(awk '/Kernel Module/ {for (i=1; i<=NF; i++) if ($i ~ /^[0-9]+\.[0-9.]+$/) {print $i; exit}}' /proc/driver/nvidia/version)
[[ "$loaded_version" == "$expected_version" ]] || {
    echo "NVIDIA driver $loaded_version is loaded; expected $expected_version" >&2
    exit 1
}
nvidia-smi --query-gpu=name,driver_version --format=csv,noheader

for node in nvidia0 nvidiactl nvidia-modeset nvidia-uvm nvidia-uvm-tools; do
    [[ -c "/dev/$node" ]] || { echo "Missing GPU device: /dev/$node" >&2; exit 1; }
    # Host ownership is authoritative; never repair these nodes in a guest.
    chown 101000:101000 "/dev/$node"
    chmod 0660 "/dev/$node"
done

# /dev/dri is bind-mounted as a directory so changing card/render numbers do
# not break boot. Grant access only to this unprivileged LXC's mapped UID 1000.
drm_found=false
for node in /dev/dri/card[0-9]* /dev/dri/renderD[0-9]*; do
    [[ -c "$node" ]] || continue
    vendor_file="/sys/class/drm/${node##*/}/device/vendor"
    [[ -r "$vendor_file" ]] || continue
    [[ $(< "$vendor_file") == 0x10de ]] || continue
    setfacl -m u:101000:rw "$node"
    drm_found=true
done
[[ "$drm_found" == true ]] || { echo "No NVIDIA DRM device found" >&2; exit 1; }
