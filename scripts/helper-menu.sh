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
        b|B) exec bash "$WORK_DIR/scripts/main-menu.sh" ;;
        q|Q) echo "Exiting."; exit 0 ;;
        *) echo "[ERROR] Invalid choice. Please try again."; sleep 2 ;;
    esac
done
