#!/bin/bash

# =================================================================
#             Shared Helper Functions for Homelab Automation
# =================================================================
# This file contains all common utility functions to follow DRY principle.
# All scripts should source this file instead of duplicating functions.
#
# Usage: source "$WORK_DIR/scripts/helper-functions.sh"
#

# Strict error handling
set -euo pipefail

# === LOGGING FUNCTIONS ===
# Colored output functions used throughout all scripts

print_info() { 
    echo -e "\033[36m▸\033[0m $1" 
}

print_success() { 
    echo -e "\033[32m✓\033[0m $1" 
}

print_error() { 
    echo -e "\033[31m[ERROR]\033[0m $1" >&2
}

print_warning() { 
    echo -e "\033[33m[WARNING]\033[0m $1" 
}

# === USER INTERACTION FUNCTIONS ===
# Common user input and interaction patterns

press_enter_to_continue() {
    echo
    read -r -p "Press Enter to continue..."
}

prompt_env_passphrase() {
    local pass=""

    echo -n "Enter encryption passphrase: " >&2
    read -r -s pass
    echo >&2

    # Return the clean passphrase
    printf '%s' "$pass"
}

# Read one value from an env file without sourcing executable shell content.
get_env_value() {
    local key="$1"
    local env_file="${2:-${ENV_DECRYPTED_PATH:-}}"
    local value

    [[ -f "$env_file" ]] || return 1

    value=$(awk -v key="$key" '
        index($0, key "=") == 1 {
            print substr($0, length(key) + 2)
            exit
        }
    ' "$env_file")

    if [[ ${#value} -ge 2 ]]; then
        if [[ "${value:0:1}" == '"' && "${value: -1}" == '"' ]]; then
            value="${value:1:${#value}-2}"
        elif [[ "${value:0:1}" == "'" && "${value: -1}" == "'" ]]; then
            value="${value:1:${#value}-2}"
        fi
    fi

    printf '%s' "$value"
}

# === SYSTEM UTILITIES ===
# Common system-level utility functions

require_root() {
    if [[ "$(id -u)" -ne 0 ]]; then
        print_error "This script must be run as root!"
        exit 1
    fi
}

ensure_packages() {
    local missing_pkgs=()
    for pkg in "$@"; do
        if ! dpkg -s "$pkg" >/dev/null 2>&1; then
            missing_pkgs+=("$pkg")
        fi
    done

    if [[ ${#missing_pkgs[@]} -gt 0 ]]; then
        print_info "Installing missing host packages: ${missing_pkgs[*]}"
        apt-get update -qq
        apt-get install -y -qq "${missing_pkgs[@]}"
        print_success "Packages installed"
    fi
}

# === HOMELAB INFRASTRUCTURE CONSTANTS ===
# Fixed topology for homelab - no discovery needed

readonly LXC_IP_BASE="192.168.1"
# These constants are consumed by scripts that source this file.
# shellcheck disable=SC2034
readonly DATAPOOL="/datapool"
# shellcheck disable=SC2034
readonly FASTPOOL="/fastpool"
readonly NETWORK_BRIDGE="vmbr0"
readonly NETWORK_GATEWAY="192.168.1.1"

declare -ag RUNTIME_TEMP_FILES=()

register_runtime_temp_file() {
    RUNTIME_TEMP_FILES+=("$1")
}

cleanup_runtime_temp_files() {
    local temp_file
    for temp_file in "${RUNTIME_TEMP_FILES[@]}"; do
        rm -f -- "$temp_file"
    done
    RUNTIME_TEMP_FILES=()
}

# Compute LXC IP from container ID
get_lxc_ip() {
    local ct_id="$1"
    echo "${LXC_IP_BASE}.${ct_id}"
}

# === CONFIGURATION MANAGEMENT ===
# Unified configuration parsing and validation

get_nvidia_driver_version() {
    local stacks_file="${1:-$WORK_DIR/stacks.yaml}"
    [[ -f "$stacks_file" ]] || { print_error "Stacks file not found: $stacks_file"; exit 1; }
    yq -r '.nvidia.driver_version // empty' "$stacks_file"
}

get_loaded_nvidia_driver_version() {
    [[ -r /proc/driver/nvidia/version ]] || return 1

    awk '
        /Kernel Module/ {
            for (i = 1; i <= NF; i++) {
                if ($i ~ /^[0-9]+\.[0-9.]+$/) {
                    print $i
                    exit
                }
            }
        }
    ' /proc/driver/nvidia/version
}

ensure_nvidia_driver_runfile() {
    local version="$1"
    local driver_dir="/fastpool/config/temp"
    local driver_file="$driver_dir/NVIDIA-Linux-x86_64-${version}.run"

    mkdir -p "$driver_dir"
    if [[ ! -f "$driver_file" ]]; then
        local driver_url="https://us.download.nvidia.com/XFree86/Linux-x86_64/${version}/NVIDIA-Linux-x86_64-${version}.run"
        local download_file
        download_file=$(mktemp "$driver_dir/.nvidia-driver.XXXXXX")
        register_runtime_temp_file "$download_file"
        print_info "Downloading NVIDIA ${version} driver runfile"
        wget -q --show-progress "$driver_url" -O "$download_file"
        chmod 0755 "$download_file"
        mv "$download_file" "$driver_file"
    fi
    chmod 0755 "$driver_file"
}

configure_nvidia_host_runtime() {
    local expected_version="$1"
    local start_now="${2:-true}"

    cat > /etc/modules-load.d/proxmox-lxc-nvidia.conf << 'EOF'
nvidia
nvidia_modeset
nvidia_uvm
nvidia_drm
EOF

    cat > /etc/udev/rules.d/70-proxmox-lxc-nvidia.rules << 'EOF'
KERNEL=="nvidia", RUN+="/usr/bin/nvidia-modprobe -u -c0"
KERNEL=="nvidia*", MODE="0666"
SUBSYSTEM=="drm", KERNEL=="card[0-9]*", MODE="0666"
SUBSYSTEM=="drm", KERNEL=="renderD[0-9]*", MODE="0666"
EOF

    cat > /etc/systemd/system/proxmox-lxc-nvidia-devices.service << 'EOF'
[Unit]
Description=Prepare NVIDIA devices for unprivileged LXC containers
After=systemd-modules-load.service local-fs.target

[Service]
Type=oneshot
ExecStart=/sbin/modprobe nvidia-uvm
ExecStart=/usr/bin/nvidia-modprobe -c0
ExecStart=/usr/bin/nvidia-modprobe -m
ExecStart=/usr/bin/nvidia-modprobe -u -c0
# Initialize the user-space driver before validating nodes. On headless hosts,
# /dev/nvidiactl can otherwise remain absent until the first NVIDIA client runs.
ExecStart=/usr/bin/nvidia-smi --query-gpu=name,driver_version --format=csv,noheader
ExecStart=/bin/chmod 0666 /dev/nvidia0 /dev/nvidiactl /dev/nvidia-modeset /dev/nvidia-uvm /dev/nvidia-uvm-tools
ExecStart=/usr/bin/find /dev/dri -maxdepth 1 -type c -exec /bin/chmod 0666 {} +
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable proxmox-lxc-nvidia-devices.service

    [[ "$start_now" == "true" ]] || return 0

    local loaded_version
    loaded_version=$(get_loaded_nvidia_driver_version) || {
        print_error "NVIDIA kernel module is not loaded"
        return 1
    }
    if [[ "$loaded_version" != "$expected_version" ]]; then
        print_error "Loaded NVIDIA driver ${loaded_version} does not match configured version ${expected_version}"
        return 1
    fi

    systemctl restart proxmox-lxc-nvidia-devices.service

    local device
    for device in \
        /dev/nvidia0 \
        /dev/nvidiactl \
        /dev/nvidia-modeset \
        /dev/nvidia-uvm \
        /dev/nvidia-uvm-tools \
        /dev/dri; do
        if [[ ! -e "$device" ]]; then
            print_error "Required NVIDIA device is missing: $device"
            return 1
        fi
    done

    nvidia-smi --query-gpu=name,driver_version --format=csv,noheader
}

# Get list of available stacks from stacks.yaml, sorted by CT ID
get_available_stacks() {
    local stacks_file="${1:-$WORK_DIR/stacks.yaml}"

    [[ ! -f "$stacks_file" ]] && { print_error "Stacks file not found: $stacks_file"; exit 1; }

    # Get stacks with their CT IDs, sort by CT ID, then return stack names only
    yq -r '.stacks | to_entries | map(select(.value.ct_id != null)) | sort_by(.value.ct_id) | .[].key' "$stacks_file"
}

# Generate dynamic stack menu options
generate_stack_menu_options() {
    local stacks_file="${1:-$WORK_DIR/stacks.yaml}"

    [[ ! -f "$stacks_file" ]] && { print_error "Stacks file not found: $stacks_file"; exit 1; }

    yq -r '
        .stacks
        | to_entries
        | map(select(.value.ct_id != null))
        | sort_by(.value.ct_id)
        | .[]
        | "Deploy [\(.key)] Stack -> LXC \(.value.ct_id) (\(.value.hostname))"
    ' "$stacks_file"
}

# Get stack name from menu selection index  
get_stack_from_menu_index() {
    local index="$1"
    local stacks_file="${2:-$WORK_DIR/stacks.yaml}"
    local -a stacks=()
    
    while IFS= read -r stack; do
        stacks+=("$stack")
    done < <(get_available_stacks "$stacks_file")
    
    if [[ $index -ge 0 && $index -lt ${#stacks[@]} ]]; then
        echo "${stacks[$index]}"
    else
        return 1
    fi
}

get_stack_config() {
    local stack="$1"
    local stacks_file="${2:-$WORK_DIR/stacks.yaml}"

    # Validate stacks file exists
    [[ ! -f "$stacks_file" ]] && { print_error "Stacks file not found: $stacks_file"; exit 1; }

    # Read all common fields in a single yq call (5x faster)
    IFS=$'\t' read -r CT_ID CT_HOSTNAME CT_CPU_CORES CT_MEMORY_MB CT_DISK_GB STORAGE_POOL TEMPLATE_POOL < <(
        yq -r "[.stacks.$stack.ct_id, .stacks.$stack.hostname, .stacks.$stack.cpu_cores, .stacks.$stack.memory_mb, .stacks.$stack.disk_gb, .storage.pool, .storage.template_pool] | @tsv" "$stacks_file"
    )

    # Validate required fields
    [[ -z "$CT_ID" || "$CT_ID" == "null" ]] && { print_error "Stack '$stack' not found in $stacks_file"; exit 1; }

    # Use fixed homelab infrastructure values
    CT_IP=$(get_lxc_ip "$CT_ID")

    # Export all variables for use in calling scripts
    export CT_ID CT_HOSTNAME CT_CPU_CORES CT_MEMORY_MB CT_DISK_GB
    export NETWORK_GATEWAY NETWORK_BRIDGE STORAGE_POOL TEMPLATE_POOL CT_IP
}

# === CONTAINER MANAGEMENT ===
# Common LXC container operations

check_container_exists() {
    local ct_id="$1"
    pct status "$ct_id" &>/dev/null
}

check_container_running() {
    local ct_id="$1"
    local status
    status=$(pct status "$ct_id" 2>&1 | awk '{print $2}')
    [[ "$status" == "running" ]]
}



# === MENU UTILITIES ===
# Common menu display patterns

show_menu_header() {
    local title="$1"
    echo
    echo "======================================="
    echo "      $title"
    echo "======================================="
    echo
}

show_menu_footer() {
    echo "---------------------------------------"
    echo "   b) Back to Main Menu"
    echo "   q) Quit"
    echo
}

# Interactive menu system with options and handlers
show_interactive_menu() {
    local title="$1"
    local -n options_ref="$2"
    local -n handlers_ref="$3"
    local back_handler="${4:-}"
    local quit_handler="${5:-}"
    
    while true; do
        show_menu_header "$title"
        
        # Show numbered options
        for i in "${!options_ref[@]}"; do
            echo "   $((i+1))) ${options_ref[$i]}"
        done
        
        show_menu_footer
        read -r -p "   Enter your choice: " choice
        
        case $choice in
            [1-9]|[1-9][0-9])
                local index=$((choice - 1))
                if [[ $index -ge 0 && $index -lt ${#options_ref[@]} ]]; then
                    ${handlers_ref[$index]} $index
                else
                    print_error "Invalid choice. Please try again."
                fi
                ;;
            b|B)
                if [[ -n "$back_handler" ]]; then
                    $back_handler
                    return 0
                else
                    return 0
                fi
                ;;
            q|Q)
                if [[ -n "$quit_handler" ]]; then
                    $quit_handler
                else
                    print_info "Exiting..."
                    exit 0
                fi
                ;;
            *)
                print_error "Invalid choice. Please try again."
                ;;
        esac
    done
}

# Create one bind-mount directory with the ownership expected by UID/GID 1000
# inside every unprivileged LXC. Existing contents are never scanned or changed.
prepare_host_directory() {
    local path="$1"
    local mode="${2:-0755}"

    install -d -o 101000 -g 101000 -m "$mode" "$path"
}

# === SHARED PROVISIONING UTILITIES ===

setup_homepage_proxmox_token() {
    local env_file="${1:-$ENV_DECRYPTED_PATH}"

    grep -q "placeholder_will_be_set_on_deploy" "$env_file" || return 0

    print_info "Setting up Homepage API token"

    local pve_user="homepage@pve"
    local token_name="homepage-token"
    local token_id="${pve_user}!${token_name}"
    local credential_dir="/root/.config/proxmox-homelab"
    local secret_file="$credential_dir/homepage-token.secret"

    if ! pveum user list | grep -qw "$pve_user"; then
        pveum user add "$pve_user" --comment "Homepage dashboard monitoring"
    fi

    pveum acl modify / --user "$pve_user" --role PVEAuditor

    local token_exists token_output token_secret
    token_exists=$(pveum user token list "$pve_user" --output-format=json | PVE_TOKEN_NAME="$token_name" python3 -c '
import json
import os
import sys

tokens = json.load(sys.stdin)
print("true" if any(token.get("tokenid") == os.environ["PVE_TOKEN_NAME"] for token in tokens) else "false")
')

    if [[ "$token_exists" == "true" && -s "$secret_file" ]]; then
        token_secret=$(<"$secret_file")
    else
        if [[ "$token_exists" == "true" ]]; then
            pveum user token remove "$pve_user" "$token_name"
        fi

        token_output=$(pveum user token add "$pve_user" "$token_name" --privsep 1 --output-format=json)
        token_secret=$(PVE_TOKEN_OUTPUT="$token_output" python3 - <<'PYEOF'
import json
import os

print(json.loads(os.environ["PVE_TOKEN_OUTPUT"])["value"])
PYEOF
        )

        [[ -n "$token_secret" ]] || {
            print_error "Failed to extract token secret"
            return 1
        }

        install -d -m 0700 "$credential_dir"
        (
            umask 077
            printf '%s\n' "$token_secret" > "$secret_file"
        )
    fi

    pveum acl modify / --token "$token_id" --role PVEAuditor

    HOMEPAGE_RENDER_TOKEN="$token_secret" python3 - "$env_file" <<'PYEOF'
import os
import stat
import sys
import tempfile

path = sys.argv[1]
with open(path, encoding="utf-8") as env_file:
    content = env_file.read()

content = content.replace("placeholder_will_be_set_on_deploy", os.environ["HOMEPAGE_RENDER_TOKEN"])

fd, temp_path = tempfile.mkstemp(prefix=".homepage-env.", dir=os.path.dirname(path))
try:
    with os.fdopen(fd, "w", encoding="utf-8") as temp_file:
        temp_file.write(content)
    os.chmod(temp_path, stat.S_IMODE(os.stat(path).st_mode))
    os.replace(temp_path, path)
except Exception:
    if os.path.exists(temp_path):
        os.unlink(temp_path)
    raise
PYEOF
    print_success "API token configured"
}
