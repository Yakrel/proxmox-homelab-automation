#!/bin/bash

# Strict error handling
set -euo pipefail

# --- Global Variables ---

WORK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)"

# --- Load Shared Functions ---
source "$WORK_DIR/scripts/helper-functions.sh"
source "$WORK_DIR/scripts/modules/beszel-agent.sh"
trap cleanup_runtime_temp_files EXIT

# --- Core Logic Functions ---

run_configure_timezone() {
    require_root
    ensure_packages chrony

    print_info "Setting timezone to Europe/Istanbul..."
    timedatectl set-timezone Europe/Istanbul

    print_info "Writing chrony configuration..."
    cat > /etc/chrony/chrony.conf << EOT
pool tr.pool.ntp.org iburst
driftfile /var/lib/chrony/chrony.drift
makestep 1.0 3
rtcsync
leapsectz right/UTC
logdir /var/log/chrony
EOT

    print_info "Restarting chrony service..."
    systemctl restart chronyd
    print_success "Timezone and NTP configuration applied."
}

run_install_security() {
    require_root
    ensure_packages fail2ban

    print_info "Writing Fail2ban filter for Proxmox..."
    mkdir -p /etc/fail2ban/filter.d
    cat > /etc/fail2ban/filter.d/proxmox.conf << EOT
[Definition]
failregex = pvedaemon\[.*authentication failure; rhost=<HOST> user=.* msg=.*
ignoreregex =
journalmatch = _SYSTEMD_UNIT=pvedaemon.service
EOT

    print_info "Writing Fail2ban jail for Proxmox and SSHD..."
    mkdir -p /etc/fail2ban/jail.d
    cat > /etc/fail2ban/jail.d/01-proxmox.conf << EOT
[proxmox]
enabled = true
port = https,http,8006
filter = proxmox
backend = systemd
maxretry = 5
findtime = 2d
bantime = 1h
EOT
    cat > /etc/fail2ban/jail.d/02-sshd.conf << EOT
[sshd]
backend = systemd
enabled = true
EOT

    print_info "Restarting Fail2ban service..."
    systemctl restart fail2ban
    print_success "Fail2ban security configuration applied."
}

run_install_storage() {
    require_root
    # Idempotent package installation
    ensure_packages sanoid

    # --- Sanoid Configuration (Idempotent) ---
    print_info "Ensuring Sanoid configuration is up to date..."
    mkdir -p /etc/sanoid
    cat > /etc/sanoid/sanoid.conf << EOT
[template_system]
hourly = 0
daily = 7
monthly = 1
autosnap = yes
autoprune = yes
[template_data]
daily = 7
monthly = 1
hourly = 0
autosnap = yes
autoprune = yes
[template_config]
hourly = 0
daily = 7
monthly = 1
autosnap = yes
autoprune = yes
[rpool/ROOT]
use_template = system
recursive = yes
[datapool]
use_template = data
recursive = yes
[fastpool]
use_template = config
recursive = no
EOT
    systemctl enable --now sanoid.timer
    
    print_success "Sanoid snapshot management configured successfully."
}

run_optimize_zfs() {
    require_root
    if ! command -v zfs; then
        print_error "ZFS not found. Aborting."
        return 1
    fi

    print_info "Applying ZFS best practice settings..."

    # rpool (SSD) - Proxmox system pool
    print_info "Optimizing rpool (SSD)..."
    zfs set compression=lz4 rpool
    zfs set atime=off rpool
    zfs set sync=standard rpool          # Data integrity (standard for system)
    zfs set recordsize=128K rpool         # Optimal for SSD mixed workload
    zfs set primarycache=all rpool        # Use ARC caching
    zfs set xattr=sa rpool                # System attributes performance
    zpool set autotrim=on rpool           # Enable TRIM for SSD performance and longevity

    # fastpool (SSD) - Config/Database storage pool
    if zpool list | grep -q "fastpool"; then
        print_info "Optimizing fastpool (SSD)..."
        zfs set compression=lz4 fastpool
        zfs set atime=off fastpool
        zfs set sync=standard fastpool       # Data integrity for configs/databases
        zfs set recordsize=128K fastpool     # Optimal for mixed config workloads
        zfs set primarycache=all fastpool     # Use ARC caching
        zfs set xattr=sa fastpool             # System attributes performance
        zpool set autotrim=on fastpool        # Enable TRIM for SSD performance and longevity
    fi

    # datapool (HDD) - Data storage pool
    print_info "Optimizing datapool (HDD)..."
    zfs set compression=lz4 datapool      # Faster decompression for media (research-backed)
    zfs set atime=off datapool
    zfs set sync=standard datapool        # Honor durable writes for backups and application data
    zfs set recordsize=1M datapool        # Optimal for large media files
    zfs set logbias=throughput datapool   # HDD sequential write optimization

    # Import data pools explicitly before the cache and mount stages.
    # This avoids relying on the shared zpool cache, which can be rewritten
    # when another pool is imported during boot.
    print_info "Configuring standard ZFS import services for data pools..."
    systemctl enable zfs-import@datapool.service zfs-import@fastpool.service
    print_success "Standard ZFS import services configured."

    print_success "ZFS dataset and pool properties applied. ARC and swap tuning were left unchanged."
}

run_setup_bonding() {
    require_root

    # Fail-fast: If bond0 exists, assume configuration is intentional
    # User can manually reconfigure via /etc/network/interfaces if needed
    if ip link show bond0 &>/dev/null; then
        print_success "Network bond 'bond0' already exists - configuration preserved."
        return 0
    fi

    local BOND_NAME="bond0"
    local BRIDGE_NAME="vmbr0"
    local IP_ADDRESS=""
    local GATEWAY=""
    local NETWORK_MASK="24"
    local INTERFACES=()
    local BONDING_APPLIED=false

    detect_interfaces() {
        print_info "Detecting physical network interfaces..."
        local iface_path

        for iface_path in /sys/class/net/*; do
            [[ -e "$iface_path/device" ]] || continue
            INTERFACES+=("${iface_path##*/}")
        done

        if [[ ${#INTERFACES[@]} -lt 2 ]]; then
            print_error "At least two physical interfaces are required for bonding"
            return 1
        fi
        print_info "Physical interfaces selected for active-backup: ${INTERFACES[*]}"
    }

    get_network_config() {
        print_info "Auto-detecting network configuration..."
        local CURRENT_IP
        local CURRENT_GW
        CURRENT_IP=$(ip route get 1 | grep -Po '(?<=src )[0-9.]+' | head -1)
        CURRENT_GW=$(ip route | grep default | grep -Po '(?<=via )[0-9.]+' | head -1)
        
        # Use current network settings automatically - fail-fast if cannot detect
        if [[ -z "$CURRENT_IP" || -z "$CURRENT_GW" ]]; then
            print_error "Could not auto-detect current network configuration"
            print_info "Current IP: ${CURRENT_IP:-not found}"
            print_info "Current Gateway: ${CURRENT_GW:-not found}"
            return 1
        fi
        
        IP_ADDRESS="$CURRENT_IP"
        GATEWAY="$CURRENT_GW"
        NETWORK_MASK="24"
        
        print_info "Using detected configuration:"
        print_info "  IP Address: $IP_ADDRESS"
        print_info "  Gateway: $GATEWAY" 
        print_info "  Network Mask: $NETWORK_MASK"
    }

    apply_config() {
        local candidate_file backup_file confirm
        candidate_file=$(mktemp /tmp/interfaces.bond0.XXXXXX)

        cat > "$candidate_file" << EOF
auto lo
iface lo inet loopback

auto $BOND_NAME
iface $BOND_NAME inet manual
    bond-slaves ${INTERFACES[*]}
    bond-miimon 100
    bond-mode active-backup
    bond-primary ${INTERFACES[0]}

auto $BRIDGE_NAME
iface $BRIDGE_NAME inet static
    address $IP_ADDRESS/$NETWORK_MASK
    gateway $GATEWAY
    bridge-ports $BOND_NAME
    bridge-stp off
    bridge-fd 0
EOF

        print_warning "Proposed /etc/network/interfaces replacement:"
        cat "$candidate_file"
        print_warning "This replaces the complete interfaces file and restarts networking."
        read -r -p "   Apply this exact configuration? [y/N]: " confirm
        if [[ ! "$confirm" =~ ^[yY]$ ]]; then
            rm -f "$candidate_file"
            print_info "Bonding configuration cancelled"
            return 0
        fi

        backup_file="/etc/network/interfaces.bak.$(date +%Y%m%d-%H%M%S)"
        print_info "Backing up /etc/network/interfaces to $backup_file"
        cp /etc/network/interfaces "$backup_file"

        install -m 0644 "$candidate_file" /etc/network/interfaces
        rm -f "$candidate_file"

        print_warning "Network connectivity will be briefly interrupted"
        systemctl restart networking
        BONDING_APPLIED=true
    }

    if ! detect_interfaces; then return 1; fi
    if ! get_network_config; then return 1; fi
    apply_config
    [[ "$BONDING_APPLIED" == "true" ]] || return 0
    print_success "Network bonding setup applied. Please verify connectivity."
}

run_setup_gpu_passthrough() (
    require_root
    local target_version target_sha256 active_kernel loaded_version disk_version
    target_version=$(get_nvidia_driver_version "$WORK_DIR/stacks.yaml")
    target_sha256=$(get_nvidia_driver_sha256 "$WORK_DIR/stacks.yaml")
    [[ "$target_version" =~ ^580\.[0-9]+\.[0-9]+$ && "$target_sha256" =~ ^[a-f0-9]{64}$ ]] || {
        print_error "A pinned NVIDIA 580 version and SHA-256 are required in stacks.yaml"
        return 1
    }
    exec 8>/run/lock/homelab-nvidia-operation.lock
    flock -n 8 || { print_error "Another GPU deployment or NVIDIA operation is in progress"; return 1; }
    exec 9>/run/lock/homelab-nvidia.lock
    # PVE start/exec can spawn long-lived processes. They must not inherit the
    # automation locks, which belong exclusively to this menu invocation.
    pct() { command pct "$@" 8>&- 9>&-; }

    local -a gpu_ct_ids=() owned_locks=() maintenance=()
    local -A was_running=() unsafe=()
    local controlled_ct="" ct_id stack status confirm
    # Only this run's known create locks can be removed. After any unsafe
    # mutation, failure leaves the CT stopped and locked for operator recovery.
    cleanup_nvidia_operation() {
        local rc=$? id lock
        trap - EXIT
        if [[ -n "$controlled_ct" ]]; then
            pct stop "$controlled_ct" --skiplock 1 || rc=1
        fi
        for id in "${owned_locks[@]}"; do
            if [[ "${unsafe[$id]:-false}" == true ]]; then
                print_error "LXC $id remains locked for NVIDIA recovery. Do not unlock/start it until host and guest preparation are repaired."
                continue
            fi
            lock=$(pct config "$id" | awk -F': ' '$1 == "lock" {print $2; exit}') || { rc=1; continue; }
            if [[ "$lock" == create ]]; then
                pct unlock "$id" || rc=1
            else
                print_error "LXC $id lock changed unexpectedly; leaving it untouched"
                rc=1
            fi
        done
        cleanup_runtime_temp_files
        exit "$rc"
    }
    trap cleanup_nvidia_operation EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM

    # Lock acquisition is serialized with PVE's whole start operation. A start
    # already past its hook completes before pct set returns; status is read
    # only afterwards. The short hook flock alone cannot provide this safety.
    for stack in media desktop; do
        ct_id=$(yq -r ".stacks.${stack}.ct_id" "$WORK_DIR/stacks.yaml")
        if check_container_exists "$ct_id"; then
            assert_nvidia_lxc_config "$ct_id"
            local ha_config
            ha_config=$(ha-manager config)
            if grep -Eq "^ct:[[:space:]]*${ct_id}([[:space:]]|$)" <<< "$ha_config"; then
                print_error "Remove LXC $ct_id from HA management before NVIDIA maintenance"
                return 1
            fi
            pct set "$ct_id" --lock create
            owned_locks+=("$ct_id")
            gpu_ct_ids+=("$ct_id")
            status=$(pct status "$ct_id" | awk '{print $2}')
            [[ "$status" == running || "$status" == stopped ]] || return 1
            was_running[$ct_id]=$status
        fi
    done
    export NVIDIA_MAINTENANCE_LOCK=create
    # Lock CT lifecycles before device preparation: a concurrent start may
    # already hold a PVE config mutex while waiting for the device lock.
    flock -w 30 9 || { print_error "NVIDIA device preparation is busy"; return 1; }

    # Network/download/header failures occur before any guest shutdown.
    local boot_status kernel_list kernel dkms_state
    boot_status=$(LC_ALL=C proxmox-boot-tool status)
    if ! grep -Fxq 'System currently booted with uefi' <<< "$boot_status" ||
        ! grep -Eq ' is configured with: uefi( |$)' <<< "$boot_status"; then
        print_error "NVIDIA setup requires Proxmox-managed systemd-boot ESPs; GRUB is not modified"
        return 1
    fi
    [[ -s /etc/kernel/cmdline ]] || { print_error "/etc/kernel/cmdline is missing"; return 1; }
    active_kernel=$(uname -r)
    kernel_list=$(LC_ALL=C proxmox-boot-tool kernel list)
    local -a kernels=("$active_kernel") headers=()
    local -A selected=(["$active_kernel"]=1)
    local selected_count=0
    # Proxmox manages ESP mounts privately. Use its selected kernel set rather
    # than asking bootctl to inspect an ESP mounted at /boot or /efi.
    while IFS= read -r kernel; do
        [[ "$kernel" =~ ^[0-9][a-zA-Z0-9.+~-]*-pve$ ]] || continue
        selected_count=$((selected_count + 1))
        if [[ -z "${selected[$kernel]:-}" ]]; then
            kernels+=("$kernel")
            selected[$kernel]=1
        fi
    done <<< "$kernel_list"
    (( selected_count > 0 )) || {
        print_error "proxmox-boot-tool reported no selected PVE kernels"
        return 1
    }
    for kernel in "${kernels[@]}"; do
        headers+=("proxmox-headers-${kernel}")
    done
    ensure_packages build-essential dkms acl proxmox-default-headers "${headers[@]}"
    for kernel in "${kernels[@]}"; do
        [[ -f "/lib/modules/$kernel/build/Makefile" ]] || {
            print_error "Kernel headers are missing for $kernel"
            return 1
        }
    done
    ensure_nvidia_driver_runfile "$target_version" "$target_sha256"
    install_nvidia_host_prepare
    install_nvidia_prestart_hook
    loaded_version=$(get_loaded_nvidia_driver_version) || loaded_version=""
    disk_version=$(modinfo -k "$active_kernel" -F version nvidia 2>/dev/null) || disk_version=""
    local install_needed=false driver_transition=false host_changed=false reboot_needed=false
    [[ "$disk_version" == "$target_version" ]] || install_needed=true
    if [[ "$install_needed" == true || "$loaded_version" != "$target_version" ]]; then
        driver_transition=true
        reboot_needed=true
    fi

    for ct_id in "${gpu_ct_ids[@]}"; do
        reconcile_nvidia_lxc_config "$ct_id" true
        local guest_change=false
        if [[ "${was_running[$ct_id]}" == running ]]; then
            if ! configure_nvidia_guest_sync "$ct_id" check || ! prepare_nvidia_guest "$ct_id" check; then
                guest_change=true
            fi
        elif ! "$WORK_DIR/scripts/nvidia-guest-stage.sh" "$ct_id" check; then
            guest_change=true
        fi
        if [[ "$NVIDIA_LXC_CONFIG_CHANGED" == true || "$guest_change" == true || "$driver_transition" == true ]]; then
            maintenance+=("$ct_id")
        fi
    done
    if [[ ${#maintenance[@]} -gt 0 ]]; then
        print_warning "NVIDIA maintenance requires stopping/preparing LXCs: ${maintenance[*]}"
        print_warning "Stopped guests may be started temporarily with Docker blocked. No automatic rollback is attempted on failure."
        [[ "$driver_transition" == false ]] || print_warning "GPU guests will stay stopped until the host is rebooted."
        read -r -p "   Proceed with this maintenance? [y/N]: " confirm
        if [[ ! "$confirm" =~ ^[yY]$ ]]; then
            print_info "Cancelled; no containers were stopped."
            return 0
        fi
    fi

    # Prepare packages/runtime against the CURRENT host/config before replacing
    # any module. The offline gate blocks both Docker and userspace sync during
    # this controlled boot, including guests never configured for GPU access.
    for ct_id in "${maintenance[@]}"; do
        if [[ "${was_running[$ct_id]}" == running ]]; then
            shutdown_nvidia_guest "$ct_id"
        fi
        unsafe[$ct_id]=true
        "$WORK_DIR/scripts/nvidia-guest-stage.sh" "$ct_id" stage
        # Retain every CT config lock while letting the existing GPU hook run.
        flock -u 9
        controlled_ct=$ct_id
        pct start "$ct_id" --skiplock 1
        prepare_nvidia_guest "$ct_id" stage
        shutdown_nvidia_guest "$ct_id"
        controlled_ct=""
        flock -n 9 || { print_error "Another NVIDIA operation acquired the host lock"; return 1; }
        reconcile_nvidia_lxc_config "$ct_id"
    done

    # Reconcile only exact GPU tokens in the active loader's command line.
    # Unrelated tokens and GRUB configuration are left untouched.
    local cmdline token desired_cmdline="" original_cmdline
    original_cmdline=$(cat /etc/kernel/cmdline)
    read -r -a cmdline <<< "$original_cmdline"
    for token in "${cmdline[@]}"; do
        case "$token" in
            nvidia-drm.modeset=*|nvidia_drm.modeset=*|nvidia-drm.fbdev=*|nvidia_drm.fbdev=*|nouveau.modeset=*) ;;
            *) desired_cmdline+="${desired_cmdline:+ }$token" ;;
        esac
    done
    desired_cmdline+=" nvidia-drm.modeset=1 nvidia_drm.fbdev=1 nouveau.modeset=0"
    desired_cmdline=${desired_cmdline# }
    if [[ "$original_cmdline" != "$desired_cmdline" ]]; then
        printf '%s\n' "$desired_cmdline" > /etc/kernel/cmdline
        host_changed=true
    fi
    write_nvidia_host_config() {
        local destination=$1 staged
        staged=$(mktemp)
        register_runtime_temp_file "$staged"
        cat > "$staged"
        if ! cmp -s "$staged" "$destination"; then
            install -D -m 0644 "$staged" "$destination"
            host_changed=true
        fi
    }
    write_nvidia_host_config /etc/modprobe.d/blacklist-nouveau.conf <<'EOF'
blacklist nouveau
blacklist lbm-nouveau
options nouveau modeset=0
alias nouveau off
alias lbm-nouveau off
EOF
    write_nvidia_host_config /etc/modprobe.d/homelab-nvidia.conf <<'EOF'
options nvidia NVreg_DeviceFileUID=101000 NVreg_DeviceFileGID=101000 NVreg_DeviceFileMode=0660
EOF
    write_nvidia_host_config /etc/udev/rules.d/70-homelab-nvidia.rules <<'EOF'
KERNEL=="nvidia[0-9]*", OWNER="101000", GROUP="101000", MODE="0660"
KERNEL=="nvidiactl", OWNER="101000", GROUP="101000", MODE="0660"
KERNEL=="nvidia-modeset", OWNER="101000", GROUP="101000", MODE="0660"
KERNEL=="nvidia-uvm", OWNER="101000", GROUP="101000", MODE="0660"
KERNEL=="nvidia-uvm-tools", OWNER="101000", GROUP="101000", MODE="0660"
EOF
    if [[ "$install_needed" == true ]]; then
        if systemctl is-active --quiet nvidia-persistenced.service; then
            systemctl stop nvidia-persistenced.service
        fi
        local module
        for module in nvidia_uvm nvidia_drm nvidia_modeset nvidia; do
            if [[ -d "/sys/module/$module" ]]; then
                modprobe -r "$module"
            fi
        done
        print_info "Installing NVIDIA proprietary driver ${target_version}"
        "/etc/homelab-nvidia/NVIDIA-Linux-x86_64-${target_version}.run" \
            --silent --accept-license --dkms --kernel-module-type=proprietary \
            --no-install-compat32-libs --no-x-check --no-opengl-files \
            --no-nouveau-check --skip-module-load || {
                print_error "NVIDIA install failed; see /var/log/nvidia-installer.log. Guests remain stopped."
                return 1
            }
    fi
    # Repair missing DKMS builds without reinstalling a matching host driver.
    for kernel in "${kernels[@]}"; do
        dkms_state=$(dkms status -m nvidia -v "$target_version" -k "$kernel")
        if ! grep -Eq ': installed([[:space:]]|$)' <<< "$dkms_state"; then
            [[ -f "/usr/src/nvidia-${target_version}/dkms.conf" ]] || {
                print_error "NVIDIA DKMS source is missing for $target_version; restore it before continuing"
                return 1
            }
            dkms install -m nvidia -v "$target_version" -k "$kernel"
            host_changed=true
        fi
        [[ $(modinfo -k "$kernel" -F version nvidia) == "$target_version" ]] || {
            print_error "NVIDIA module does not match $target_version for kernel $kernel"
            return 1
        }
        dkms_state=$(dkms status -m nvidia -v "$target_version" -k "$kernel")
        grep -Eq ': installed([[:space:]]|$)' <<< "$dkms_state" || {
            print_error "NVIDIA DKMS installation is incomplete for $kernel"
            return 1
        }
    done
    if [[ "$host_changed" == true || "$install_needed" == true ]]; then
        udevadm control --reload-rules
        update-initramfs -u -k all
        proxmox-boot-tool refresh
        reboot_needed=true
    fi
    publish_nvidia_driver_manifest "$target_version" "$target_sha256"
    for ct_id in "${maintenance[@]}"; do
        "$WORK_DIR/scripts/nvidia-guest-stage.sh" "$ct_id" release
    done
    flock -u 9
    if [[ "$driver_transition" == false ]]; then
        /usr/local/sbin/homelab-nvidia-prepare
        for ct_id in "${maintenance[@]}"; do
            if [[ "${was_running[$ct_id]}" == running ]]; then
                controlled_ct=$ct_id
                pct start "$ct_id" --skiplock 1
                # Wait for boot's dependency transaction, without restarting
                # Docker a second time after its userspace sync has succeeded.
                pct exec "$ct_id" -- systemctl start docker.socket docker.service
                configure_nvidia_guest_sync "$ct_id" check
                prepare_nvidia_guest "$ct_id" check
                controlled_ct=""
            fi
        done
    fi
    # All stopped guests now have a boot gate and a complete runtime; the
    # manifest/hook prevents premature starts against a mismatched host.
    for ct_id in "${maintenance[@]}"; do
        unsafe[$ct_id]=false
    done
    if [[ "$driver_transition" == true ]]; then
        print_success "NVIDIA $target_version and guest runtime configuration are staged."
        print_warning "Reboot the Proxmox host. GPU LXCs are stopped; start those not configured for onboot manually. Their startup gates sync userspace before Docker."
    elif [[ "$reboot_needed" == true ]]; then
        print_success "NVIDIA $target_version is ready; originally stopped guests remain stopped."
        print_warning "Reboot the host to activate the updated boot/module configuration."
    elif [[ ${#maintenance[@]} -eq 0 ]]; then
        print_success "NVIDIA $target_version is already configured. No driver reinstall or guest/Docker restart was needed."
    else
        print_success "NVIDIA $target_version and running GPU guests are ready; originally stopped guests remain stopped."
    fi
)

run_install_beszel_agent() {
    require_root

    local enc_file="$WORK_DIR/docker/utility/.env.enc"
    local env_tmp pass

    [[ -f "$enc_file" ]] || {
        print_error "Encrypted Utility environment not found at $enc_file"
        return 1
    }

    env_tmp=$(mktemp /tmp/beszel-agent-env.XXXXXX)
    register_runtime_temp_file "$env_tmp"
    pass=$(get_or_prompt_env_passphrase)
    if ! decrypt_openssl_file "$enc_file" "$env_tmp" "$pass"; then
        print_error "Failed to decrypt Utility environment"
        return 1
    fi

    install_local_beszel_agent \
        "$env_tmp" "pve" "pve*,zfs*,beszel*" "/fastpool,/datapool"
    unset pass
}


# --- Main Menu ---

while true; do
    clear
    echo "======================================="
    echo "      Proxmox Helper Scripts"
    echo "======================================="
    echo
    echo "   1) Configure Timezone"
    echo "   2) Install Security Tools (Fail2ban)"
    echo "   3) Configure Storage (Sanoid Snapshots)"
    echo "   4) Optimize ZFS Performance"
    echo "   5) Setup Network Bonding (Interactive)"
    echo "   6) Install / Update NVIDIA GPU (GTX 970)"
    echo "   7) Install/Update Beszel Agent (PVE)"
    echo "---------------------------------------"
    echo "   b) Back to Main Menu"
    echo "   q) Quit"
    echo
    read -r -p "   Enter your choice: " choice

    case $choice in
        1) run_configure_timezone; press_enter_to_continue ;;
        2) run_install_security; press_enter_to_continue ;;
        3) run_install_storage; press_enter_to_continue ;;
        4) run_optimize_zfs; press_enter_to_continue ;;
        5) run_setup_bonding; press_enter_to_continue ;;
        6) run_setup_gpu_passthrough; press_enter_to_continue ;;
        7) run_install_beszel_agent; press_enter_to_continue ;;
        b|B) exit 0 ;;
        q|Q) echo "Exiting."; exit 0 ;;
        *) print_error "Invalid choice. Please try again." ;;
    esac
done
