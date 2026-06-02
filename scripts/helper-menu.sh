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

    # datapool (HDD) - Data storage pool
    print_info "Optimizing datapool (HDD)..."
    zfs set compression=lz4 datapool      # Faster decompression for media (research-backed)
    zfs set atime=off datapool
    zfs set sync=disabled datapool        # Homelab standard (max performance, acceptable risk)
    zfs set recordsize=1M datapool        # Optimal for large media files
    zfs set logbias=throughput datapool   # HDD sequential write optimization

    print_info "Writing ZFS ARC memory limit configuration..."
    # For Proxmox with ZFS, use 37.5% of RAM for ARC (more aggressive than default 50% of free RAM)
    # This accounts for Proxmox host + LXC containers while still providing good cache performance
    total_ram_gb=$(free -g | awk 'NR==2{print $2}')
    arc_max_bytes=$(( total_ram_gb * 1024 * 1024 * 1024 * 3 / 8 ))
    mod_config="/etc/modprobe.d/zfs.conf"

    if grep -q "zfs_arc_max" "$mod_config"; then
        print_info "Updating existing zfs_arc_max entry in $mod_config..."
        sed -i -e "s/^\s*options zfs zfs_arc_max=[0-9]*/options zfs zfs_arc_max=${arc_max_bytes}/g" "$mod_config"
    else
        print_info "Adding new zfs_arc_max entry to $mod_config..."
        echo "options zfs zfs_arc_max=${arc_max_bytes}" >> "$mod_config"
    fi

    print_info "ARC max set to $(( arc_max_bytes / 1024 / 1024 / 1024 )) GB (~37.5% of ${total_ram_gb} GB total RAM)"

    print_info "Optimizing system swappiness for Proxmox..."
    sysctl_conf="/etc/sysctl.conf"
    touch "$sysctl_conf"
    if grep -q "^vm.swappiness" "$sysctl_conf" 2>/dev/null; then
        sed -i 's/^vm.swappiness.*/vm.swappiness = 0/' "$sysctl_conf"
        print_info "Updated existing swappiness setting to 0"
    else
        echo "vm.swappiness = 0" >> "$sysctl_conf"
        print_info "Added swappiness = 0 to sysctl.conf"
    fi
    sysctl -w vm.swappiness=0 >/dev/null

    print_info "Updating initramfs..."
    update-initramfs -u -k all
    print_warning "A reboot is required for ZFS ARC changes to take effect."
    print_success "ZFS optimization applied with best practice settings."
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

    detect_interfaces() {
        print_info "Detecting ethernet interfaces..."
        # Updated to include 'nic' (new Proxmox naming) and 'eno' (onboard)
        mapfile -t INTERFACES < <(ip link show | grep -E '^[0-9]+: enp|^[0-9]+: eth|^[0-9]+: eno|^[0-9]+: nic' | cut -d: -f2 | tr -d ' ')
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
        # Idempotent backup - overwrites on subsequent runs
        cp /etc/network/interfaces "/etc/network/interfaces.bak" || true
        
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

    print_info "Setting up NVIDIA GTX 970 for LXC container passthrough (Wayland/Zero-Copy Support)..."

    # Check if NVIDIA drivers are already loaded and working.
    if command -v nvidia-smi &>/dev/null && nvidia-smi &>/dev/null; then
        print_success "NVIDIA drivers already installed and working."
        print_info "Loaded nvidia modules: $(lsmod | grep nvidia | wc -l)"
        print_info "GPU detected: $(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)"
        print_info "Driver Version: $(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1)"
        return 0
    fi

    print_info "Configuring host prerequisites for NVIDIA passthrough..."

    # Ensure build tools and latest kernel headers are available for DKMS
    ensure_packages build-essential dkms "proxmox-headers-$(uname -r)" proxmox-default-headers

    # Blacklist nouveau before installing the proprietary NVIDIA driver.
    cat > /etc/modprobe.d/blacklist-nouveau.conf << 'EOF'
blacklist nouveau
blacklist lbm-nouveau
options nouveau modeset=0
alias nouveau off
alias lbm-nouveau off
EOF

    # Configure GRUB for IOMMU and NVIDIA DRM (Required for Wayland Zero-Copy / /dev/dri)
    local grub_file="/etc/default/grub"
    cp "$grub_file" "${grub_file}.backup" || true

    local grub_params="intel_iommu=on iommu=pt nvidia-drm.modeset=1 nvidia_drm.fbdev=1"
    for param in $grub_params; do
        if ! grep -q "$param" "$grub_file"; then
            sed -i "s/^GRUB_CMDLINE_LINUX_DEFAULT=\"\(.*\)\"/GRUB_CMDLINE_LINUX_DEFAULT=\"\1 $param\"/" "$grub_file"
        fi
    done
    sed -i 's/  */ /g' "$grub_file"
    update-grub

    update-initramfs -u -k all

    # Install NVIDIA driver via official .run file
    print_info "Downloading NVIDIA 580.159.04 driver..."
    local driver_url="https://us.download.nvidia.com/XFree86/Linux-x86_64/580.159.04/NVIDIA-Linux-x86_64-580.159.04.run"
    local driver_file="/root/NVIDIA-Linux-x86_64-580.159.04.run"
    
    if [[ ! -f "$driver_file" ]]; then
        wget -q --show-progress "$driver_url" -O "$driver_file"
        chmod +x "$driver_file"
    fi

    print_info "Installing NVIDIA proprietary driver (this may take a few minutes)..."
    # Run the installer silently, accepting the license, building DKMS module, without 32-bit libs, without X11 config
    "$driver_file" --silent --accept-license --dkms --no-compat32 --no-x-check --no-opengl-files || {
        print_error "NVIDIA driver installation failed. Please check /var/log/nvidia-installer.log"
        return 1
    }

    # Load nvidia modules
    modprobe nvidia || print_warning "Failed to load nvidia module - may need reboot"
    modprobe nvidia_uvm || print_warning "Failed to load nvidia_uvm module - may need reboot"
    modprobe nvidia_drm || print_warning "Failed to load nvidia_drm module - may need reboot"

    # Persist nvidia modules
    echo "nvidia-uvm" > /etc/modules-load.d/nvidia-uvm.conf
    echo "nvidia-drm" > /etc/modules-load.d/nvidia-drm.conf

    # Create udev rules for nvidia devices
    cat > /etc/udev/rules.d/70-nvidia.rules << 'EOF'
KERNEL=="nvidia", RUN+="/bin/bash -c '/usr/bin/nvidia-smi -L && /bin/chmod 666 /dev/nvidia*'"
KERNEL=="nvidia_uvm", RUN+="/bin/bash -c '/usr/bin/nvidia-modprobe -c0 -u && /bin/chmod 666 /dev/nvidia-uvm*'"
EOF

    print_success "NVIDIA GPU passthrough host setup is complete!"
    print_warning "Please REBOOT the Proxmox Host to fully apply kernel parameters and load the driver."
}

run_datapool_cleanup() {
    require_root
    bash "$WORK_DIR/scripts/datapool-cleanup.sh"
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
    echo "   8) Clean Datapool (Remove Cache/Logs)"
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
        8) run_datapool_cleanup; press_enter_to_continue ;;
        b|B) exec bash "$WORK_DIR/scripts/main-menu.sh" ;;
        q|Q) echo "Exiting."; exit 0 ;;
        *) print_error "Invalid choice. Please try again." ;;
    esac
done
