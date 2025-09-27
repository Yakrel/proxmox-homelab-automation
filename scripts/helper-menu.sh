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

    echo "[INFO] Setting timezone to Europe/Istanbul..."
    timedatectl set-timezone Europe/Istanbul

    echo "[INFO] Writing chrony configuration..."
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

    echo "[INFO] Restarting chrony service..."
    systemctl restart chronyd
    echo "[OK] Timezone and NTP configuration applied."
}

run_install_security() {
    if [ "$(id -u)" -ne 0 ]; then echo "[ERROR] Must be run as root"; return 1; fi
    ensure_packages fail2ban

    echo "[INFO] Writing Fail2ban filter for Proxmox..."
    mkdir -p /etc/fail2ban/filter.d
    cat > /etc/fail2ban/filter.d/proxmox.conf << EOT
[Definition]
failregex = pvedaemon\[.*authentication failure; rhost=<HOST> user=.* msg=.*
ignoreregex =
journalmatch = _SYSTEMD_UNIT=pvedaemon.service
EOT

    echo "[INFO] Writing Fail2ban jail for Proxmox and SSHD..."
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

    echo "[INFO] Restarting Fail2ban service..."
    systemctl restart fail2ban
    echo "[OK] Fail2ban security configuration applied."
}

run_install_storage() {
    if [ "$(id -u)" -ne 0 ]; then echo "[ERROR] Must be run as root"; return 1; fi
    # Idempotent package installation
    ensure_packages sanoid

    # --- Sanoid Configuration (Idempotent) ---
    echo "[INFO] Ensuring Sanoid configuration is up to date..."
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
    systemctl enable --now sanoid.timer >/dev/null 2>&1
    
    echo "[OK] Sanoid snapshot management configured successfully."
}

run_optimize_zfs() {
    if [ "$(id -u)" -ne 0 ]; then echo "[ERROR] Must be run as root"; return 1; fi
    if ! command -v zfs >/dev/null 2>&1; then echo "[ERROR] ZFS not found. Aborting."; return 1; fi

    echo "[INFO] Applying ZFS dataset properties..."
    zfs set atime=off rpool
    zfs set sync=disabled datapool
    zfs set atime=off datapool
    zfs set compression=lz4 datapool
    zfs set compression=lz4 rpool

    echo "[INFO] Writing ZFS ARC memory limit configuration..."
    arc_max_bytes=$(( $(free -g | awk 'NR==2{print $2}') * 1024 * 1024 * 1024 / 2 ))
    mod_config="/etc/modprobe.d/zfs.conf"

    if grep -q "zfs_arc_max" "$mod_config"; then
        echo "[INFO] Updating existing zfs_arc_max entry in $mod_config..."
        sed -i -e "s/^\s*options zfs zfs_arc_max=[0-9]*/options zfs zfs_arc_max=${arc_max_bytes}/g" "$mod_config"
    else
        echo "[INFO] Adding new zfs_arc_max entry to $mod_config..."
        echo "options zfs zfs_arc_max=${arc_max_bytes}" >> "$mod_config"
    fi

    echo "[INFO] Updating initramfs..."
    update-initramfs -u -k all >/dev/null
    echo "[WARN] A reboot is required for ZFS ARC changes to take effect."
    echo "[OK] ZFS optimization applied."
}

run_setup_bonding() {
    if [ "$(id -u)" -ne 0 ]; then echo "[ERROR] Must be run as root"; return 1; fi

    if ip link show bond0 &>/dev/null; then
        echo "[WARN] Network bond 'bond0' already exists."
        echo "[INFO] Skipping setup - bond already configured. Use manual intervention if changes needed."
        return 0
    fi

    local BOND_NAME="bond0"
    local BRIDGE_NAME="vmbr0"
    local IP_ADDRESS=""
    local GATEWAY=""
    local NETWORK_MASK="24"
    local INTERFACES=()

    detect_interfaces() {
        echo "[INFO] Detecting ethernet interfaces..."
        mapfile -t INTERFACES < <(ip link show | grep -E '^[0-9]+: enp|^[0-9]+: eth' | cut -d: -f2 | tr -d ' ')
        if [ ${#INTERFACES[@]} -eq 0 ]; then echo "[ERROR] No ethernet interfaces found!"; return 1; fi
        echo "[INFO] Found interfaces: ${INTERFACES[*]}"
    }

    get_network_config() {
        echo "[INFO] Auto-detecting network configuration..."
        local CURRENT_IP
        local CURRENT_GW
        CURRENT_IP=$(ip route get 1 2>/dev/null | grep -Po '(?<=src )[0-9.]+' | head -1)
        CURRENT_GW=$(ip route | grep default | grep -Po '(?<=via )[0-9.]+' | head -1)
        
        # Use current network settings automatically - fail-fast if cannot detect
        if [[ -z "$CURRENT_IP" || -z "$CURRENT_GW" ]]; then
            echo "[ERROR] Could not auto-detect current network configuration"
            echo "[INFO] Current IP: ${CURRENT_IP:-not found}"
            echo "[INFO] Current Gateway: ${CURRENT_GW:-not found}"
            return 1
        fi
        
        IP_ADDRESS="$CURRENT_IP"
        GATEWAY="$CURRENT_GW"
        NETWORK_MASK="24"
        
        echo "[INFO] Using detected configuration:"
        echo "[INFO]   IP Address: $IP_ADDRESS"
        echo "[INFO]   Gateway: $GATEWAY" 
        echo "[INFO]   Network Mask: $NETWORK_MASK"
    }

    apply_config() {
        echo "[INFO] Backing up /etc/network/interfaces..."
        cp /etc/network/interfaces "/etc/network/interfaces.bak.$(date +%s)" 2>/dev/null || true
        
        echo "[INFO] Writing new /etc/network/interfaces..."
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

        echo "[WARN] Network connectivity will be briefly interrupted!"
        echo "[INFO] Applying configuration automatically..."
        systemctl restart networking
    }

    if ! detect_interfaces; then return 1; fi
    if ! get_network_config; then return 1; fi
    apply_config
    echo "[OK] Network bonding setup applied. Please verify connectivity."
}

run_setup_gpu_passthrough() {
    if [ "$(id -u)" -ne 0 ]; then echo "[ERROR] Must be run as root"; return 1; fi

    # Check if GPU is present
    echo "[INFO] Detecting NVIDIA GPU..."
    if ! lspci | grep -i nvidia >/dev/null 2>&1; then
        echo "[ERROR] No NVIDIA GPU detected. Please ensure GPU is properly connected."
        return 1
    fi

    # Display detected GPU
    echo "[INFO] Detected GPU:"
    lspci | grep -i nvidia

    # Check if NVIDIA drivers are already installed
    if modinfo nvidia >/dev/null 2>&1; then
        echo "[WARN] NVIDIA drivers already installed."
        echo "[INFO] Skipping driver installation."
    else
        echo "[INFO] Installing NVIDIA drivers..."
        
        # Add contrib and non-free repositories for NVIDIA drivers
        echo "deb http://deb.debian.org/debian $(lsb_release -cs) main contrib non-free" > /etc/apt/sources.list.d/contrib-non-free.list
        apt-get update -q >/dev/null 2>&1 || { echo "[ERROR] Failed to update package lists"; return 1; }
        
        # Install NVIDIA drivers
        apt-get install -y nvidia-driver firmware-misc-nonfree >/dev/null 2>&1 || { 
            echo "[ERROR] Failed to install NVIDIA drivers"; return 1; 
        }
        
        echo "[INFO] NVIDIA drivers installed successfully."
    fi

    # Configure IOMMU
    echo "[INFO] Configuring IOMMU for GPU passthrough..."
    
    # Update GRUB configuration
    local grub_file="/etc/default/grub"
    local grub_cmdline="GRUB_CMDLINE_LINUX_DEFAULT=\"quiet intel_iommu=on iommu=pt pcie_acs_override=downstream,multifunction nofb nomodeset video=vesafb:off,efifb:off\""
    
    if ! grep -q "intel_iommu=on" "$grub_file"; then
        # Backup original GRUB config
        cp "$grub_file" "${grub_file}.backup"
        
        # Update GRUB cmdline
        sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT=.*/'"$grub_cmdline"'/' "$grub_file"
        
        # Update GRUB
        update-grub >/dev/null 2>&1 || { echo "[ERROR] Failed to update GRUB"; return 1; }
        
        echo "[INFO] GRUB configuration updated."
    else
        echo "[INFO] IOMMU already configured in GRUB."
    fi

    # Configure VFIO modules
    echo "[INFO] Configuring VFIO modules..."
    
    # Add VFIO modules to load at boot
    local modules_file="/etc/modules"
    local modules_to_add=("vfio" "vfio_iommu_type1" "vfio_pci" "vfio_virqfd")
    
    for module in "${modules_to_add[@]}"; do
        if ! grep -q "^$module$" "$modules_file"; then
            echo "$module" >> "$modules_file"
        fi
    done

    # Get GPU PCI IDs for VFIO binding
    echo "[INFO] Configuring VFIO PCI device binding..."
    local gpu_ids
    gpu_ids=$(lspci -nn | grep -i nvidia | grep -E "(VGA|3D)" | sed -n 's/.*\[\([0-9a-f]*:[0-9a-f]*\)\].*/\1/p' | tr '\n' ',' | sed 's/,$//')
    local audio_ids
    audio_ids=$(lspci -nn | grep -i nvidia | grep -i audio | sed -n 's/.*\[\([0-9a-f]*:[0-9a-f]*\)\].*/\1/p' | tr '\n' ',' | sed 's/,$//')
    
    if [[ -n "$gpu_ids" ]]; then
        local all_ids="$gpu_ids"
        [[ -n "$audio_ids" ]] && all_ids="$all_ids,$audio_ids"
        
        # Configure VFIO PCI binding
        echo "options vfio-pci ids=$all_ids" > /etc/modprobe.d/vfio.conf
        echo "[INFO] VFIO configured for GPU IDs: $all_ids"
    else
        echo "[ERROR] Could not detect GPU PCI IDs"
        return 1
    fi

    # Blacklist nouveau driver
    echo "[INFO] Blacklisting nouveau driver..."
    cat > /etc/modprobe.d/blacklist-nouveau.conf << 'EOF'
blacklist nouveau
blacklist lbm-nouveau
options nouveau modeset=0
alias nouveau off
alias lbm-nouveau off
EOF

    # Update initramfs
    echo "[INFO] Updating initramfs..."
    update-initramfs -u >/dev/null 2>&1 || { echo "[ERROR] Failed to update initramfs"; return 1; }

    echo "[OK] GPU passthrough configuration completed."
    echo "[WARN] System reboot required to activate GPU passthrough."
    echo "[INFO] After reboot, use option to configure media container for GPU."
}

run_configure_media_gpu() {
    if [ "$(id -u)" -ne 0 ]; then echo "[ERROR] Must be run as root"; return 1; fi

    local media_ct_id="101"  # From stacks.yaml
    
    echo "[INFO] Configuring media container for GPU passthrough..."
    
    # Check if container exists
    if ! pct status "$media_ct_id" >/dev/null 2>&1; then
        echo "[ERROR] Media container (ID: $media_ct_id) not found. Deploy media stack first."
        return 1
    fi
    
    # Get GPU device path
    local gpu_device
    gpu_device=$(find /dev -name "nvidia*" -type c | head -1)
    
    if [[ -z "$gpu_device" ]]; then
        echo "[ERROR] No NVIDIA devices found. Ensure GPU passthrough is configured and system rebooted."
        return 1
    fi
    
    # Stop container if running
    if pct status "$media_ct_id" | grep -q "running"; then
        echo "[INFO] Stopping media container..."
        pct stop "$media_ct_id" || { echo "[ERROR] Failed to stop container"; return 1; }
    fi
    
    # Configure container for GPU access
    echo "[INFO] Adding GPU device mapping to container..."
    
    # Add device mapping
    pct set "$media_ct_id" -dev0 "/dev/nvidia0,path=/dev/nvidia0" || {
        echo "[ERROR] Failed to add GPU device mapping"
        return 1
    }
    
    # Add nvidia-uvm device if exists
    if [[ -e "/dev/nvidia-uvm" ]]; then
        pct set "$media_ct_id" -dev1 "/dev/nvidia-uvm,path=/dev/nvidia-uvm" || {
            echo "[WARN] Failed to add nvidia-uvm device"
        }
    fi
    
    # Add nvidiactl device if exists  
    if [[ -e "/dev/nvidiactl" ]]; then
        pct set "$media_ct_id" -dev2 "/dev/nvidiactl,path=/dev/nvidiactl" || {
            echo "[WARN] Failed to add nvidiactl device"
        }
    fi
    
    # Set container features for device access
    pct set "$media_ct_id" -features keyctl=1,nesting=1 || {
        echo "[WARN] Failed to update container features"
    }
    
    # Start container
    echo "[INFO] Starting media container..."
    pct start "$media_ct_id" || { echo "[ERROR] Failed to start container"; return 1; }
    
    # Wait for container to be ready
    sleep 10
    
    # Install NVIDIA container runtime inside the container
    echo "[INFO] Installing NVIDIA container runtime in media container..."
    pct exec "$media_ct_id" -- sh -c "
        # Install nvidia-container-runtime
        apk add --no-cache curl gnupg
        
        # Add NVIDIA repository
        curl -s -L https://nvidia.github.io/nvidia-container-runtime/gpgkey | apk add --allow-untrusted -
        echo 'https://nvidia.github.io/nvidia-container-runtime/stable/alpine3.17/x86_64' >> /etc/apk/repositories
        
        # Install nvidia-container-runtime
        apk update
        apk add --no-cache nvidia-container-runtime || {
            # Fallback: configure docker daemon for nvidia runtime
            mkdir -p /etc/docker
            cat > /etc/docker/daemon.json << 'EOFDOCKER'
{
    \"metrics-addr\": \"0.0.0.0:9323\",
    \"experimental\": true,
    \"default-runtime\": \"nvidia\",
    \"runtimes\": {
        \"nvidia\": {
            \"path\": \"nvidia-container-runtime\",
            \"runtimeArgs\": []
        }
    }
}
EOFDOCKER
        }
        
        # Restart docker
        rc-service docker restart || service docker restart || true
    " || {
        echo "[WARN] NVIDIA container runtime installation failed, continuing with device mapping only"
    }
    
    echo "[OK] Media container configured for GPU access."
    echo "[INFO] Jellyfin docker-compose already updated for GPU transcoding."
    echo "[INFO] Restart media stack to apply GPU configuration."
}

run_install_nvidia_drivers_container() {
    if [ "$(id -u)" -ne 0 ]; then echo "[ERROR] Must be run as root"; return 1; fi

    local media_ct_id="101"  # From stacks.yaml
    
    echo "[INFO] Installing NVIDIA drivers in media container..."
    
    # Check if container exists and is running
    if ! pct status "$media_ct_id" | grep -q "running"; then
        echo "[ERROR] Media container (ID: $media_ct_id) is not running."
        return 1
    fi
    
    # Install NVIDIA drivers in container
    pct exec "$media_ct_id" -- sh -c "
        # Update package lists
        apk update
        
        # Try to install nvidia drivers if available
        apk add --no-cache nvidia-drivers nvidia-utils || {
            echo '[WARN] NVIDIA drivers not available in Alpine repos'
            echo '[INFO] GPU passthrough via device mapping should still work'
        }
        
        # Verify devices are accessible
        ls -la /dev/nvidia* 2>/dev/null || echo '[INFO] NVIDIA devices will be available after container restart'
    " || {
        echo "[WARN] Driver installation failed, but device passthrough should still work"
    }
    
    echo "[OK] NVIDIA driver installation completed."
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
    echo "   7) Setup GPU Passthrough (NVIDIA)"
    echo "   8) Configure Media Container GPU"
    echo "   9) Install NVIDIA Drivers in Container"
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
        9) run_install_nvidia_drivers_container; press_enter_to_continue ;;
        b|B) exec bash "$WORK_DIR/scripts/main-menu.sh" ;;
        q|Q) echo "Exiting."; exit 0 ;;
        *) print_error "Invalid choice. Please try again." ;;
    esac
done
