#!/bin/bash

# Strict error handling
set -euo pipefail

# --- Global Variables ---

WORK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)"

# --- Load Shared Functions ---
source "$WORK_DIR/scripts/helper-functions.sh"
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
server 0.tr.pool.ntp.org iburst
server 1.tr.pool.ntp.org iburst
server 2.tr.pool.ntp.org iburst
pool 0.pool.ntp.org iburst
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
daily = 7
monthly = 1
hourly = 24
autosnap = yes
autoprune = yes
[template_data]
daily = 7
monthly = 1
hourly = 0
autosnap = yes
autoprune = yes
[template_config]
hourly = 24
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

run_setup_gpu_passthrough() {
    require_root

    local target_version
    target_version=$(get_nvidia_driver_version "$WORK_DIR/stacks.yaml")
    if [[ -z "$target_version" ]]; then
        print_error "NVIDIA driver version is not configured in stacks.yaml. Aborting."
        return 1
    fi

    print_info "Configuring NVIDIA ${target_version} for unprivileged LXC passthrough"

    # Blacklist nouveau before installing the proprietary NVIDIA driver.
    cat > /etc/modprobe.d/blacklist-nouveau.conf << 'EOF'
blacklist nouveau
blacklist lbm-nouveau
options nouveau modeset=0
alias nouveau off
alias lbm-nouveau off
EOF

    # Reconcile boot parameters even when the requested driver is already
    # loaded; a matching driver alone does not prove passthrough is complete.
    local grub_file="/etc/default/grub"
    local grub_params="intel_iommu=on iommu=pt nvidia-drm.modeset=1 nvidia_drm.fbdev=1 nouveau.modeset=0"
    local boot_config_changed=false
    local param
    if [[ -f "$grub_file" ]]; then
        for param in $grub_params; do
            if ! grep -q "$param" "$grub_file"; then
                sed -i "s/^GRUB_CMDLINE_LINUX_DEFAULT=\"\(.*\)\"/GRUB_CMDLINE_LINUX_DEFAULT=\"\1 $param\"/" "$grub_file"
                boot_config_changed=true
            fi
        done
        sed -i 's/  */ /g' "$grub_file"
        if [[ "$boot_config_changed" == "true" ]]; then
            update-grub
        fi
    fi

    # Configure systemd-boot cmdline if using proxmox-boot-tool
    local cmdline_file="/etc/kernel/cmdline"
    if [[ -f "$cmdline_file" ]]; then
        local cmdline_content
        cmdline_content=$(cat "$cmdline_file")
        local cmdline_modified=false
        for param in $grub_params; do
            if [[ ! " $cmdline_content " == *" $param "* ]]; then
                cmdline_content="$cmdline_content $param"
                cmdline_modified=true
            fi
        done
        if [[ "$cmdline_modified" == "true" ]]; then
            cmdline_content=$(echo "$cmdline_content" | sed 's/  */ /g' | sed 's/^ *//;s/ *$//')
            echo "$cmdline_content" > "$cmdline_file"
            boot_config_changed=true
            proxmox-boot-tool refresh
        fi
    fi

    local installed_version=""
    installed_version=$(get_loaded_nvidia_driver_version) || installed_version=""
    if [[ "$installed_version" == "$target_version" ]]; then
        configure_nvidia_host_runtime "$target_version" true
        if [[ "$boot_config_changed" == "true" ]]; then
            update-initramfs -u -k all
            print_warning "Reboot the Proxmox host to apply updated boot parameters"
        fi
        print_success "NVIDIA driver and LXC runtime are ready (version ${target_version})"
        return 0
    fi

    if [[ -n "$installed_version" ]]; then
        print_info "Upgrading host NVIDIA driver from ${installed_version} to ${target_version}"
    else
        print_info "Installing NVIDIA host driver ${target_version}"
    fi

    ensure_packages build-essential dkms "proxmox-headers-$(uname -r)" proxmox-default-headers

    # Stop GPU-using LXC containers and unload NVIDIA modules for a clean driver installation.
    # The installer cannot replace a kernel module that is currently in use.
    local gpu_ct_ids=()
    for conf in /etc/pve/lxc/*.conf; do
        [[ -f "$conf" ]] || continue
        if grep -q "nvidia" "$conf"; then
            local ct_id
            ct_id=$(basename "$conf" .conf)
            if pct status "$ct_id" | grep -q "running"; then
                gpu_ct_ids+=("$ct_id")
            fi
        fi
    done

    if [[ ${#gpu_ct_ids[@]} -gt 0 ]]; then
        print_warning "The following GPU-using LXC containers must be stopped to install the driver:"
        for ct_id in "${gpu_ct_ids[@]}"; do
            local ct_name
            ct_name=$(pct config "$ct_id" | awk '/^hostname:/ {print $2; exit}')
            ct_name=${ct_name:-unknown}
            print_warning "  LXC $ct_id ($ct_name)"
        done
        print_warning "They will remain stopped until you reboot the host."
        echo
        read -r -p "   Proceed and stop these containers? [y/N]: " confirm
        if [[ ! "$confirm" =~ ^[yY]$ ]]; then
            print_info "Aborted. Please stop the containers manually before running this again."
            return 1
        fi

        for ct_id in "${gpu_ct_ids[@]}"; do
            print_info "Stopping LXC $ct_id..."
            pct stop "$ct_id"
        done
    fi

    local service
    for service in proxmox-lxc-nvidia-devices.service nvidia-persistenced.service; do
        if systemctl is-active --quiet "$service"; then
            systemctl stop "$service"
        fi
    done

    local module
    for module in nvidia_uvm nvidia_drm nvidia_modeset nvidia; do
        if lsmod | awk '{print $1}' | grep -Fxq "$module"; then
            modprobe -r "$module"
        fi
    done

    ensure_nvidia_driver_runfile "$target_version"
    local driver_file="/fastpool/config/temp/NVIDIA-Linux-x86_64-${target_version}.run"

    print_info "Installing NVIDIA proprietary driver (this may take a few minutes)..."
    # Run the installer silently, accepting the license, building DKMS module, without 32-bit libs, without X11 config
    "$driver_file" --silent --accept-license --dkms --no-install-compat32-libs --no-x-check --no-opengl-files || {
        print_error "NVIDIA driver installation failed. Please check /var/log/nvidia-installer.log"
        return 1
    }

    # Write the project-owned runtime unit now; it will start on the reboot
    # that loads the new kernel module and boot parameters.
    configure_nvidia_host_runtime "$target_version" false
    update-initramfs -u -k all

    print_success "NVIDIA GPU passthrough host setup is complete!"
    print_warning "Please REBOOT the Proxmox Host to fully apply kernel parameters and load the driver."
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
    echo "   6) Setup GPU Passthrough (NVIDIA GTX 970)"
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
        b|B) exit 0 ;;
        q|Q) echo "Exiting."; exit 0 ;;
        *) print_error "Invalid choice. Please try again." ;;
    esac
done
