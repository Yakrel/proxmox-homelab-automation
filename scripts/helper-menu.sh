#!/bin/bash

# Strict error handling
set -euo pipefail

# --- Global Variables ---

WORK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)"

# --- Load Shared Functions ---
source "$WORK_DIR/scripts/helper-functions.sh"

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
hourly = 0
autosnap = yes
autoprune = yes
[template_data]
daily = 15
monthly = 2
hourly = 0
autosnap = yes
autoprune = yes
[rpool/ROOT]
use_template = system
recursive = yes
[datapool]
use_template = data
recursive = yes
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

    print_info "Applying ZFS dataset properties..."
    zfs set atime=off rpool
    zfs set sync=disabled datapool
    zfs set atime=off datapool
    zfs set compression=lz4 datapool
    zfs set compression=lz4 rpool

    print_info "Writing ZFS ARC memory limit configuration..."
    arc_max_bytes=$(( $(free -g | awk 'NR==2{print $2}') * 1024 * 1024 * 1024 / 2 ))
    mod_config="/etc/modprobe.d/zfs.conf"

    if grep -q "zfs_arc_max" "$mod_config"; then
        print_info "Updating existing zfs_arc_max entry in $mod_config..."
        sed -i -e "s/^\s*options zfs zfs_arc_max=[0-9]*/options zfs zfs_arc_max=${arc_max_bytes}/g" "$mod_config"
    else
        print_info "Adding new zfs_arc_max entry to $mod_config..."
        echo "options zfs zfs_arc_max=${arc_max_bytes}" >> "$mod_config"
    fi

    print_info "Updating initramfs..."
    update-initramfs -u -k all
    print_warning "A reboot is required for ZFS ARC changes to take effect."
    print_success "ZFS optimization applied."
}

run_setup_bonding() {
    require_root

    if ip link show bond0; then
        print_warning "Network bond 'bond0' already exists."
        print_info "Skipping setup - bond already configured. Use manual intervention if changes needed."
        return 0
    fi

    local BOND_NAME="bond0"
    local BRIDGE_NAME="vmbr0"
    local IP_ADDRESS=""
    local GATEWAY=""
    local NETWORK_MASK="24"
    local INTERFACES=()

    detect_interfaces() {
        print_info "Detecting ethernet interfaces..."
        mapfile -t INTERFACES < <(ip link show | grep -E '^[0-9]+: enp|^[0-9]+: eth' | cut -d: -f2 | tr -d ' ')
        if [ ${#INTERFACES[@]} -eq 0 ]; then
            print_error "No ethernet interfaces found!"
            return 1
        fi
        print_info "Found interfaces: ${INTERFACES[*]}"
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
        print_info "Backing up /etc/network/interfaces..."
        cp /etc/network/interfaces "/etc/network/interfaces.bak.$(date +%s)" || true
        
        print_info "Writing new /etc/network/interfaces..."
        cat > /etc/network/interfaces << EOF
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

        print_warning "Network connectivity will be briefly interrupted!"
        print_info "Applying configuration automatically..."
        systemctl restart networking
    }

    if ! detect_interfaces; then return 1; fi
    if ! get_network_config; then return 1; fi
    apply_config
    print_success "Network bonding setup applied. Please verify connectivity."
}

run_setup_gpu_passthrough() {
    require_root

    print_info "Setting up NVIDIA GTX 970 for LXC container passthrough..."

    # Install required packages for compilation
    ensure_packages build-essential dkms linux-headers-$(uname -r)

    # Blacklist nouveau first
    cat > /etc/modprobe.d/blacklist-nouveau.conf << 'EOF'
blacklist nouveau
blacklist lbm-nouveau
options nouveau modeset=0
alias nouveau off
alias lbm-nouveau off
EOF

    # Configure IOMMU - hardcoded for homelab
    local grub_file="/etc/default/grub"
    cp "$grub_file" "${grub_file}.backup"
    sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT="quiet intel_iommu=on iommu=pt"/' "$grub_file"
    update-grub

    # Update initramfs and suggest reboot first
    update-initramfs -u

    print_info "Phase 1 complete. System needs reboot to disable nouveau."
    print_warning "Please reboot and run this option again to install NVIDIA drivers."
    print_info "After reboot, NVIDIA driver will be downloaded and installed automatically."
}

run_configure_media_gpu() {
    require_root

    local media_ct_id="101"
    
    print_info "Configuring media container for GTX 970..."
    
    # Stop container
    pct stop "$media_ct_id"
    
    # Add GPU devices - hardcoded paths
    pct set "$media_ct_id" -dev0 "/dev/nvidia0,path=/dev/nvidia0"
    pct set "$media_ct_id" -dev1 "/dev/nvidiactl,path=/dev/nvidiactl" 
    pct set "$media_ct_id" -dev2 "/dev/nvidia-uvm,path=/dev/nvidia-uvm"
    pct set "$media_ct_id" -features keyctl=1,nesting=1
    
    # Start container
    pct start "$media_ct_id"
    
    print_success "Media container configured for GTX 970."
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
    echo "   6) Manage Fail2ban"
    echo "   7) Setup GPU Passthrough (NVIDIA GTX 970)"
    echo "   8) Configure Media Container GPU"
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
        6) bash "$WORK_DIR/scripts/fail2ban-manager.sh"; press_enter_to_continue ;;
        7) run_setup_gpu_passthrough; press_enter_to_continue ;;
        8) run_configure_media_gpu; press_enter_to_continue ;;
        b|B) exec bash "$WORK_DIR/scripts/main-menu.sh" ;;
        q|Q) echo "Exiting."; exit 0 ;;
        *) print_error "Invalid choice. Please try again." ;;
    esac
done
