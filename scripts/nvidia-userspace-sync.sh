#!/bin/bash
# Host modules and device permissions belong to PVE; this only installs guest libraries.
set -euo pipefail

mode="${1:-sync}"
case "$mode:$#" in
    sync:0|--check:1|--check-installation:1) ;;
    *) echo "Usage: $0 [--check|--check-installation]" >&2; exit 1 ;;
esac

report() { echo "[NVIDIA-SYNC] $*" >&2; }
fail() { report "$*"; exit 1; }

manifest=/etc/homelab-nvidia/driver
[[ -r "$manifest" ]] || fail "Missing driver manifest: $manifest"
read -r target_version expected_sha256 extra < "$manifest"
[[ "$target_version" =~ ^580\.[0-9]+\.[0-9]+$ && -z "$extra" ]] ||
    fail "Invalid pinned 580-series driver manifest"
[[ "$expected_sha256" =~ ^[a-f0-9]{64}$ ]] || fail "Invalid driver manifest checksum"

check_device_ownership() {
    local device
    for device in /dev/nvidia0 /dev/nvidiactl /dev/nvidia-uvm; do
        if [[ ! -c "$device" ]]; then
            report "Missing NVIDIA character device: $device"
            return 1
        fi
    done
    return 0
}

check_helpers() {
    return 0
}

check_libraries() {
    local cache library path resolved bad=0
    cache=$(ldconfig -p) || { report "Cannot read the guest dynamic linker cache"; return 1; }
    # NVML reports the running host driver, not the version of every installed library.
    # Require actual 64-bit files, not dangling symlinks with a matching version suffix.
    for library in libnvidia-ml.so.1 libcuda.so.1 libnvidia-encode.so.1 libnvcuvid.so.1 \
        libEGL_nvidia.so.0 libGLX_nvidia.so.0 libnvidia-eglcore.so."$target_version" \
        libnvidia-glcore.so."$target_version" libnvidia-ptxjitcompiler.so.1; do
        path=$(awk -v library="$library" '$1 == library && /x86-64/ && !found {print $NF; found=1}' <<< "$cache")
        resolved=""
        if [[ -n "$path" ]]; then
            resolved=$(readlink -e -- "$path") || resolved=""
        fi
        if [[ -z "$resolved" || ! -f "$resolved" || ! -s "$resolved" || ! -r "$resolved" ||
            "${resolved##*/}" != "${library%%.so*}.so.${target_version}" ]]; then
            report "Userspace drift: $library resolves to ${resolved:-no existing file}; expected ${library%%.so*}.so.${target_version}"
            bad=1
        fi
    done
    if ! command -v nvidia-smi &>/dev/null; then
        report "Userspace drift: nvidia-smi is missing"
        bad=1
    fi
    (( bad == 0 ))
}

check_runtime() {
    local versions version
    if ! versions=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader,nounits); then
        report "nvidia-smi cannot communicate with the host driver; Docker must remain stopped"
        return 1
    fi
    [[ -n "$versions" ]] || { report "nvidia-smi returned no GPUs"; return 1; }
    while IFS= read -r version; do
        [[ "$version" == "$target_version" ]] || {
            report "GPU reports driver $version instead of $target_version"
            return 1
        }
    done <<< "$versions"
    check_device_ownership
}

# Offline chroot inspection must not read the host's proc/dev or call NVML.
if [[ "$mode" == --check-installation ]]; then
    check_helpers && check_libraries || exit 1
    report "Installed guest userspace matches $target_version"
    exit 0
fi
[[ -r /proc/driver/nvidia/version ]] ||
    fail "Host NVIDIA module is not visible; restore host modules and LXC devices before starting Docker"
loaded_version=$(awk '/Kernel Module/ {for(i=1;i<=NF;i++) if($i ~ /^[0-9]+\.[0-9.]+$/) {print $i; exit}}' /proc/driver/nvidia/version)
[[ "$loaded_version" == "$target_version" ]] ||
    fail "Loaded host driver ${loaded_version:-none} differs from pinned $target_version; complete the host upgrade/reboot first"


# Check these before executing NVIDIA binaries: neither a probe nor installation may
# invoke a guest helper that changes PVE's device ownership.
safe=true
check_helpers || safe=false
check_device_ownership || safe=false
$safe || exit 1

if check_libraries; then
    check_runtime || exit 1
    report "Guest userspace and devices already match $target_version; no changes needed"
    exit 0
fi
[[ "$mode" == --check ]] && exit 1

# Never replace libraries underneath running containers or an activatable daemon.
# At boot the service ordering must keep BOTH docker.service and docker.socket behind sync.
for unit in docker.service docker.socket; do
    state=$(systemctl show --property=ActiveState --value "$unit") ||
        fail "Cannot establish whether $unit is stopped; refusing userspace repair"
    case "$state" in
        inactive|failed) ;;
        *) fail "Userspace repair needed, but $unit is ${state:-unknown}; use approved NVIDIA maintenance to stop Docker and its socket first" ;;
    esac
done

driver_file="/etc/homelab-nvidia/NVIDIA-Linux-x86_64-${target_version}.run"
[[ -f "$driver_file" && -r "$driver_file" ]] || fail "Verified installer artifact is missing: $driver_file"
printf '%s  %s\n' "$expected_sha256" "$driver_file" | sha256sum --check --status ||
    fail "Installer checksum does not match the host manifest"
bash "$driver_file" --check || fail "NVIDIA runfile integrity check failed"

# These flags are supported by NVIDIA's 580.178.04 option_table.h. There is no
# separate --no-device flag. Omitting modules, helper, distro hooks and systemd
# units leaves module/device management to PVE. Keep graphics libraries for EGL.
# https://github.com/NVIDIA/nvidia-installer/blob/580.178.04/option_table.h
report "Installing guest NVIDIA userspace $target_version with Docker stopped"
bash "$driver_file" --silent --no-kernel-modules --no-kernel-module-source \
    --no-nvidia-modprobe --no-distro-scripts --no-systemd --no-x-check \
    --no-install-compat32-libs || fail "NVIDIA userspace installation failed; Docker must remain stopped"

check_helpers && check_device_ownership && check_libraries && check_runtime ||
    fail "Post-install validation failed; Docker must remain stopped"
report "Guest NVIDIA userspace successfully synchronized to $target_version"
