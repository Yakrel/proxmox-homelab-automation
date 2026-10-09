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

get_or_prompt_env_passphrase() {
    if [[ -n "${ENV_ENC_KEY:-}" ]]; then
        printf '%s' "$ENV_ENC_KEY"
    elif [[ -n "${KEY:-}" ]]; then
        printf '%s' "$KEY"
    else
        prompt_env_passphrase
    fi
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

# Validate that a decrypted environment has exactly the same variable schema as
# its committed example without exposing any values.
validate_env_file_schema() {
    local env_file="$1"
    local example_file="$2"

    python3 - "$env_file" "$example_file" <<'PYEOF'
import pathlib
import re
import sys

key_pattern = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")


def read_keys(path):
    keys = []
    for line_number, raw_line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            raise SystemExit(f"Invalid environment line in {path}:{line_number}")
        # Same exact "KEY=" form that get_env_value reads.
        key = raw_line.split("=", 1)[0]
        if not key_pattern.fullmatch(key):
            raise SystemExit(f"Invalid environment key in {path}:{line_number}: {key}")
        if key in keys:
            raise SystemExit(f"Duplicate environment key in {path}: {key}")
        keys.append(key)
    return set(keys)


env_path = pathlib.Path(sys.argv[1])
example_path = pathlib.Path(sys.argv[2])
actual = read_keys(env_path)
expected = read_keys(example_path)
missing = sorted(expected - actual)
extra = sorted(actual - expected)
if missing or extra:
    if missing:
        print("Missing encrypted environment keys: " + ", ".join(missing), file=sys.stderr)
    if extra:
        print("Unexpected encrypted environment keys: " + ", ".join(extra), file=sys.stderr)
    raise SystemExit(1)
PYEOF
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

# All repository-managed encrypted files use the same explicit KDF parameters.
# Keep this value centralized: OpenSSL's salted enc format does not store the
# PBKDF2 iteration count, so encryption and decryption must always agree.
readonly OPENSSL_PBKDF2_ITERATIONS=600000

decrypt_openssl_file() {
    local input_file="$1"
    local output_file="$2"
    local passphrase="$3"

    KEY="$passphrase" openssl enc \
        -d -aes-256-cbc \
        -pbkdf2 -iter "$OPENSSL_PBKDF2_ITERATIONS" -md sha256 \
        -pass env:KEY \
        -in "$input_file" \
        -out "$output_file"
}

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

get_nvidia_driver_sha256() {
    local stacks_file="${1:-$WORK_DIR/stacks.yaml}"
    [[ -f "$stacks_file" ]] || { print_error "Stacks file not found: $stacks_file"; exit 1; }
    yq -r '.nvidia.driver_sha256 // empty' "$stacks_file"
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
    local expected_sha256="$2"
    local driver_dir="/etc/homelab-nvidia"
    local driver_file="$driver_dir/NVIDIA-Linux-x86_64-${version}.run"
    local actual_sha256

    if [[ ! "$expected_sha256" =~ ^[a-f0-9]{64}$ ]]; then
        print_error "NVIDIA driver SHA-256 is missing or invalid"
        return 1
    fi

    mkdir -p "$driver_dir"
    if [[ ! -f "$driver_file" ]]; then
        local driver_url="https://us.download.nvidia.com/XFree86/Linux-x86_64/${version}/NVIDIA-Linux-x86_64-${version}.run"
        local download_file
        download_file=$(mktemp "$driver_dir/.nvidia-driver.XXXXXX")
        register_runtime_temp_file "$download_file"
        print_info "Downloading NVIDIA ${version} driver runfile"
        wget -q --show-progress "$driver_url" -O "$download_file"
        actual_sha256=$(sha256sum "$download_file" | awk '{print $1}')
        if [[ "$actual_sha256" != "$expected_sha256" ]]; then
            rm -f "$download_file"
            print_error "Downloaded NVIDIA driver checksum does not match stacks.yaml"
            return 1
        fi
        chmod 0755 "$download_file"
        mv "$download_file" "$driver_file"
    fi

    actual_sha256=$(sha256sum "$driver_file" | awk '{print $1}')
    if [[ "$actual_sha256" != "$expected_sha256" ]]; then
        print_error "Cached NVIDIA driver checksum does not match stacks.yaml"
        return 1
    fi

    chmod 0755 "$driver_file"
    "$driver_file" --check
}

# The host owns a single manifest. Guests read it through a read-only bind
# mount; no SHA or driver version is embedded in their systemd units.
readonly NVIDIA_DRIVER_MANIFEST=/etc/homelab-nvidia/driver
readonly NVIDIA_HOOK_STORAGE=datapool
readonly NVIDIA_HOOK_STORAGE_PATH=/datapool
readonly NVIDIA_HOOK_VOLUME=datapool:snippets/homelab-nvidia-prestart.sh


publish_nvidia_driver_manifest() {
    local version="$1" sha256="$2" staged
    install -d -m 0755 /etc/homelab-nvidia
    staged=$(mktemp /etc/homelab-nvidia/.driver.XXXXXX)
    register_runtime_temp_file "$staged"
    printf '%s %s\n' "$version" "$sha256" > "$staged"
    chmod 0644 "$staged"
    if [[ ! -f "$NVIDIA_DRIVER_MANIFEST" ]] || ! cmp -s "$staged" "$NVIDIA_DRIVER_MANIFEST"; then
        mv -f "$staged" "$NVIDIA_DRIVER_MANIFEST"
    fi
}

install_nvidia_host_prepare() {
    local script_path=/usr/local/sbin/homelab-nvidia-prepare
    local unit_path=/etc/systemd/system/homelab-nvidia-prepare.service

    if [[ ! -f "$script_path" ]] || ! cmp -s "$WORK_DIR/scripts/nvidia-gpu-prepare.sh" "$script_path"; then
        install -D -m 0755 "$WORK_DIR/scripts/nvidia-gpu-prepare.sh" "$script_path"
    fi
    chmod 0755 "$script_path"

    if [[ ! -f "$unit_path" ]] || ! cmp -s "$WORK_DIR/scripts/homelab-nvidia-prepare.service" "$unit_path"; then
        install -D -m 0644 "$WORK_DIR/scripts/homelab-nvidia-prepare.service" "$unit_path"
        systemctl daemon-reload
    fi
    chmod 0644 "$unit_path"
    systemctl --quiet enable homelab-nvidia-prepare.service
}

install_nvidia_prestart_hook() {
    local storage_entry storage_type storage_path content disabled nodes local_node path
    local_node=$(hostname -s)
    storage_entry=$(awk -v id="$NVIDIA_HOOK_STORAGE" '
        $1 ~ /:$/ && $2 == id { in_storage = 1; print; next }
        in_storage && /^[^[:space:]]/ { exit }
        in_storage { print }
    ' /etc/pve/storage.cfg)

    if [[ -z "$storage_entry" ]]; then
        print_error "datapool storage is not configured for GPU snippets"
        return 1
    fi
    storage_type=$(awk 'NR == 1 {sub(/:$/, "", $1); print $1}' <<< "$storage_entry")
    storage_path=$(awk '$1 == "path" {print $2; exit}' <<< "$storage_entry")
    content=$(awk '$1 == "content" {print $2; exit}' <<< "$storage_entry")
    disabled=$(awk '$1 == "disable" {print ($2 == "" ? "1" : $2); exit}' <<< "$storage_entry")
    nodes=$(awk '$1 == "nodes" {print $2; exit}' <<< "$storage_entry")
    if [[ "$storage_type" != dir || "$storage_path" != "$NVIDIA_HOOK_STORAGE_PATH" ||
          ",$content," != *,snippets,* || ( -n "$disabled" && "$disabled" != 0 ) ||
          ( -n "$nodes" && ",$nodes," != *,"$local_node",* ) ]]; then
        print_error "datapool must be an enabled directory at /datapool with snippets content"
        return 1
    fi
    if ! mountpoint -q "$NVIDIA_HOOK_STORAGE_PATH"; then
        print_error "GPU snippet storage path is not mounted: $NVIDIA_HOOK_STORAGE_PATH"
        return 1
    fi

    path=$(pvesm path "$NVIDIA_HOOK_VOLUME")
    if [[ ! -f "$path" ]] || ! cmp -s "$WORK_DIR/scripts/nvidia-gpu-prestart.sh" "$path"; then
        install -D -m 0755 "$WORK_DIR/scripts/nvidia-gpu-prestart.sh" "$path"
    fi
    chmod 0755 "$path"
}


# The change flag is read by the helper-menu and lxc-manager callers.
# shellcheck disable=SC2034
reconcile_nvidia_lxc_config() {
    local ct_id="$1" dry_run="${2:-false}" result
    # Use the same config lock/parser as Proxmox: preserve snapshots and never
    # rewrite a running guest's raw device configuration.
    result=$(perl - "$ct_id" "$dry_run" "${NVIDIA_MAINTENANCE_LOCK:-}" <<'PERL'
use strict;
use warnings;
use PVE::LXC;
use PVE::LXC::Config;
my ($vmid, $dry, $owned_lock) = @ARGV;
sub normalized {
    my ($value) = @_;
    my @parts = split /,/, ($value // '');
    for (@parts) { s/^mode=0+([0-7]+)$/mode=$1/; }
    return join ',', sort @parts;
}
PVE::LXC::Config->lock_config($vmid, sub {
    my $conf = PVE::LXC::Config->load_config($vmid);
    die "GPU LXC $vmid must be unprivileged\n" unless $conf->{unprivileged};
    if ($conf->{lock} && !($owned_lock eq 'create' && $conf->{lock} eq $owned_lock)) {
        die "GPU LXC $vmid is locked ($conf->{lock})\n";
    }
    die "Apply or discard pending LXC $vmid changes before GPU maintenance\n"
        if keys %{ $conf->{pending} // {} };
    my @raw = @{ $conf->{lxc} // [] };
    for my $entry (@raw) {
        my ($key, $value) = @$entry;
        die "Custom UID mapping is not supported for GPU LXC $vmid\n" if $key eq 'lxc.idmap';
        die "Conflicting raw GPU rule in LXC $vmid: $key: $value\n"
            if ($key eq 'lxc.mount.entry' && $value =~ m{^/dev/nvidia})
            || ($key eq 'lxc.cgroup2.devices.allow' && $value =~ /^c \d+:\* rwm$/);
    }
    my %desired = (
        mp2 => '/etc/homelab-nvidia,mp=/etc/homelab-nvidia,ro=1',
        hookscript => 'datapool:snippets/homelab-nvidia-prestart.sh',
    );
    my @devices = qw(nvidia0 nvidiactl nvidia-modeset nvidia-uvm nvidia-uvm-tools);
    for my $i (0 .. $#devices) {
        $desired{"dev$i"} = "/dev/$devices[$i],uid=1000,gid=1000,mode=0660";
        my $current = $conf->{"dev$i"};
        die "LXC $vmid dev$i belongs to another device\n"
            if defined($current) && $current !~ m{^/dev/\Q$devices[$i]\E(?:,|$)};
    }
    for my $key (qw(mp2 hookscript)) {
        die "LXC $vmid $key belongs to another configuration\n"
            if defined($conf->{$key}) && normalized($conf->{$key}) ne normalized($desired{$key});
    }
    my $changed = 0;
    for my $key (sort keys %desired) {
        if (normalized($conf->{$key}) ne normalized($desired{$key})) {
            $conf->{$key} = $desired{$key};
            $changed = 1;
        }
    }
    my @required = (
        ['lxc.cgroup2.devices.allow', 'c 226:* rw'],
        ['lxc.mount.entry', '/dev/dri dev/dri none bind,create=dir'],
    );
    if ($vmid == 101) {
        push @required, ['lxc.cgroup2.devices.allow', 'c 10:229 rwm'],
                        ['lxc.mount.entry', '/dev/fuse dev/fuse none bind,create=file 0 0'];
    }
    for my $entry (@required) {
        my ($key, $value) = @$entry;
        die "Conflicting device mount in LXC $vmid\n"
            if $key eq 'lxc.mount.entry' && grep {
                $_->[0] eq $key && (split / /, $_->[1])[0] eq (split / /, $value)[0]
                    && $_->[1] ne $value
            } @raw;
        unless (grep { $_->[0] eq $key && $_->[1] eq $value } @raw) {
            push @raw, $entry;
            $changed = 1;
        }
    }
    if ($changed && $dry ne 'true') {
        die "Stop LXC $vmid before changing GPU devices\n" if PVE::LXC::check_running($vmid);
        $conf->{lxc} = \@raw;
        PVE::LXC::Config->write_config($vmid, $conf);
    }
    print $changed ? "changed\n" : "unchanged\n";
});
PERL
    ) || return 1
    NVIDIA_LXC_CONFIG_CHANGED=false
    [[ "$result" != changed ]] || NVIDIA_LXC_CONFIG_CHANGED=true
}

shutdown_nvidia_guest() {
    # pct shutdown has no skiplock option. Retain our maintenance lock and use
    # the same graceful-stop implementation as PVE's shutdown API under its
    # config mutex, authorizing only this operation's create lock.
    perl - "$1" "${NVIDIA_MAINTENANCE_LOCK:-}" 8>&- 9>&- <<'PERL'
use strict;
use warnings;
use PVE::LXC;
use PVE::LXC::Config;
my ($vmid, $owned_lock) = @ARGV;
die "Invalid GPU LXC ID\n" unless $vmid =~ /^\d+$/;
PVE::LXC::Config->lock_config($vmid, sub {
    my $conf = PVE::LXC::Config->load_config($vmid);
    die "LXC $vmid is not held by NVIDIA maintenance\n"
        unless $owned_lock eq 'create' && ($conf->{lock} // '') eq $owned_lock;
    return unless PVE::LXC::check_running($vmid);
    PVE::LXC::vm_stop($vmid, 0, 120, 0);
});
PERL
}

configure_nvidia_guest_sync() {
    local ct_id="$1" mode="${2:-check}"
    case "$mode" in check|apply) ;; *) return 2 ;; esac
    # Stream the exact same files used by offline maintenance. Guest temporary
    # files belong to this invocation and are removed even after a failed check.
    tar -C "$WORK_DIR/scripts" -cf - nvidia-guest-files.sh nvidia-userspace-sync.sh \
        nvidia-userspace-sync.service nvidia-docker.conf |
        pct exec "$ct_id" -- bash -c '
set -euo pipefail
tmp=$(mktemp -d)
trap '\''rm -rf "$tmp"'\'' EXIT
tar -xf - -C "$tmp"
bash "$tmp/nvidia-guest-files.sh" "$tmp" / "$1"
' bash "$mode"
}

prepare_nvidia_guest() {
    local ct_id="$1" mode="${2:-check}"
    case "$mode" in check|apply|stage) ;; *) return 2 ;; esac
    pct exec "$ct_id" -- bash -s -- "--$mode" < "$WORK_DIR/scripts/nvidia-guest-runtime.sh"
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
