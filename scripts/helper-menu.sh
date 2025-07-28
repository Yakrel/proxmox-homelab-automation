#!/bin/bash

set -e

# --- Global Variables ---

WORK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)"

# --- Generic Helper Functions ---

ensure_packages() {
    echo "[INFO] Ensuring packages '$*' are installed..."
    apt-get update >/dev/null
    apt-get install -y "$@"
}

press_enter_to_continue() {
    echo
    read -p "Press Enter to continue..."
}

# --- Core Logic Functions ---

run_configure_timezone() {
    if [ "$(id -u)" -ne 0 ]; then echo "[ERROR] Must be run as root"; return 1; fi
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
    ensure_packages samba sanoid

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

    # --- Idempotent Samba Configuration ---
    
    # 1. Enforce the desired state for the main smb.conf file.
    # This guarantees the 'include' directive is present and correct.
    echo "[INFO] Enforcing desired state for main Samba config..."
    local smb_conf="/etc/samba/smb.conf"
    cat > "$smb_conf" << EOF
# --- Base Samba Configuration (Managed by Automation) ---
[global]
    workgroup = WORKGROUP
    server role = standalone server
    security = user
    log file = /var/log/samba/log.%m
    max log size = 1000
    socket options = TCP_NODELAY IPTOS_LOWDELAY
    read raw = yes
    write raw = yes
    strict locking = no

# --- Share Definitions ---
# Modular configuration for shares.
include = /etc/samba/conf.d/datapool.conf
EOF

    # 2. Ensure the share configuration directory exists.
    local conf_d_dir="/etc/samba/conf.d"
    mkdir -p "$conf_d_dir"

    # 3. Get user info and ensure the system user exists.
    echo "[INFO] Configuring Samba user and share..."
    read -p "Enter Samba username to manage: " samba_username
    if ! id "$samba_username" &>/dev/null; then
        echo "[INFO] Creating new system user '$samba_username'..."
        useradd -r -s /bin/false "$samba_username"
    fi
    
    read -s -p "Enter new Samba password for $samba_username: " samba_password
    echo

    # 4. Idempotently manage the Samba database user.
    if [ -n "$samba_password" ]; then
        # First, attempt to add the user. The '-a' flag is for adding.
        # If the user already exists, this command will fail.
        if (echo "$samba_password"; echo "$samba_password") | smbpasswd -a -s "$samba_username" >/dev/null 2>&1; then
            echo "[INFO] Added new user '$samba_username' to Samba."
        else
            # If adding failed, assume the user exists and just update the password.
            echo "[INFO] User '$samba_username' already exists. Updating password..."
            (echo "$samba_password"; echo "$samba_password") | smbpasswd -s "$samba_username" >/dev/null
        fi
    fi

    # 5. Enforce the desired state for the share configuration file.
    local share_conf_file="$conf_d_dir/datapool.conf"
    echo "[INFO] Writing desired state for share to $share_conf_file..."
    cat > "$share_conf_file" << EOF
# --- Datapool Share Definition (Managed by Automation) ---
[datapool]
    path = /datapool
    browseable = yes
    read only = no
    valid users = $samba_username
    force user = root
    force group = root
    create mask = 0664
    directory mask = 0775
    guest ok = no
EOF
    
    echo "[INFO] Restarting Samba service to apply changes..."
    systemctl restart smbd
    echo "[OK] Storage configuration applied successfully."
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
    arc_max_bytes=$(( $(free -g | awk 'NR==2{print $2}') / 2 * 1024 * 1024 * 1024 ))
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
        read -p "Do you want to re-run the setup? This will overwrite the existing config. (y/N): " confirm
        if [[ ! $confirm =~ ^[Yy]$ ]]; then
            echo "[INFO] Operation cancelled."
            return 0
        fi
    fi

    local BOND_NAME="bond0"
    local BRIDGE_NAME="vmbr0"
    local IP_ADDRESS=""
    local GATEWAY=""
    local NETWORK_MASK="24"
    local INTERFACES=()

    detect_interfaces() {
        echo "[INFO] Detecting ethernet interfaces..."
        INTERFACES=($(ip link show | grep -E '^[0-9]+: enp|^[0-9]+: eth' | cut -d: -f2 | tr -d ' '))
        if [ ${#INTERFACES[@]} -eq 0 ]; then echo "[ERROR] No ethernet interfaces found!"; return 1; fi
        echo "[INFO] Found interfaces: ${INTERFACES[*]}"
    }

    get_network_config() {
        echo "[INFO] Please provide network configuration:"
        local CURRENT_IP=$(ip route get 1 2>/dev/null | grep -Po '(?<=src )[0-9.]+' | head -1)
        local CURRENT_GW=$(ip route | grep default | grep -Po '(?<=via )[0-9.]+' | head -1)
        read -p "IP Address [$CURRENT_IP]: " IP_ADDRESS
        IP_ADDRESS=${IP_ADDRESS:-$CURRENT_IP}
        read -p "Gateway [$CURRENT_GW]: " GATEWAY
        GATEWAY=${GATEWAY:-$CURRENT_GW}
        read -p "Network Mask (CIDR) [24]: " NETWORK_MASK
        NETWORK_MASK=${NETWORK_MASK:-24}
    }

    apply_config() {
        echo "[INFO] Backing up /etc/network/interfaces..."
        cp /etc/network/interfaces /etc/network/interfaces.bak.$(date +%s) 2>/dev/null || true
        
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
        read -p "Press Enter to apply configuration or Ctrl+C to abort..."
        systemctl restart networking
    }

    if ! detect_interfaces; then return 1; fi
    get_network_config
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
    echo "   3) Configure Storage (Samba + Sanoid)"
    echo "   4) Optimize ZFS Performance"
    echo "   5) Setup Network Bonding (Interactive)"
    echo "   6) Manage Fail2ban"
    echo "---------------------------------------"
    echo "   b) Back to Main Menu"
    echo "   q) Quit"
    echo
    read -p "   Enter your choice: " choice

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
