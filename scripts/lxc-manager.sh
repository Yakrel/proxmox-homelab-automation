#!/bin/bash

# Unified LXC creation + minimal provisioning (Alpine/Debian)
# Fail fast approach
set -euo pipefail

STACK_NAME=$1
WORK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)"

# --- Load Shared Functions ---
source "$WORK_DIR/scripts/helper-functions.sh"

# Load stack configuration using shared function
get_stack_config "$STACK_NAME"

# Get latest template based on stack type - ensures we always use the newest available
get_latest_template() {
    local template_type=$1
    pveam update > /dev/null || true

    # Get the latest available template name from repository
    local latest_available=$(pveam available | awk "/${template_type}/ {print \$2}" | sort -V | tail -n 1)
    [[ -n "$latest_available" ]] || { print_error "No ${template_type} template available"; exit 1; }

    # Check if we already have this exact template locally
    local local_template=$(pveam list "$STORAGE_POOL" | awk "/${template_type}/ {print \$1}" | sort -V | tail -n 1 | sed "s|^${STORAGE_POOL}:vztmpl/||")

    # If local template doesn't match latest available, download the new one
    if [[ "$local_template" != "$latest_available" ]]; then
        print_info "Downloading latest ${template_type} template: $latest_available" >&2
        pveam download "$STORAGE_POOL" "$latest_available" >/dev/null || { print_error "Failed to download ${template_type} template"; exit 1; }
        # After download, get the actual filename from local storage
        local_template=$(pveam list "$STORAGE_POOL" | awk "/${template_type}/ {print \$1}" | sort -V | tail -n 1 | sed "s|^${STORAGE_POOL}:vztmpl/||")
        print_success "Downloaded template: $local_template" >&2
    else
        print_info "Using up-to-date template: $local_template" >&2
    fi

    echo "$local_template"
}

# Choose template based on stack type - always use latest
if [ "$STACK_NAME" = "backup" ] || [ "$STACK_NAME" = "media" ]; then
    LATEST_TEMPLATE=$(get_latest_template "debian-.*-standard")
else
    LATEST_TEMPLATE=$(get_latest_template "alpine-.*-default")
fi

# Container exists check - handle gracefully for idempotency
if check_container_exists "$CT_ID"; then
    print_info "Container $CT_ID already exists, verifying state"
    SKIP_CREATION=true
else
    SKIP_CREATION=false
fi

# Create container only if it doesn't exist
if [[ "$SKIP_CREATION" == "false" ]]; then
    print_info "Creating LXC container $CT_ID ($CT_HOSTNAME)"
    pct create "$CT_ID" "${STORAGE_POOL}:vztmpl/${LATEST_TEMPLATE}" \
        --hostname "$CT_HOSTNAME" \
        --storage "$STORAGE_POOL" \
        --cores "$CT_CPU_CORES" \
        --memory "$CT_MEMORY_MB" \
        --swap 0 \
        --features keyctl=1,nesting=1 \
        --net0 name=eth0,bridge="$NETWORK_BRIDGE",ip="$CT_IP"/24,gw="$NETWORK_GATEWAY" \
        --onboot 1 \
        --unprivileged 1 \
        --rootfs "$STORAGE_POOL":"$CT_DISK_GB" || { print_error "Failed to create container"; exit 1; }

    # Mount datapool for all stacks
    print_info "Mounting datapool"
    pct set "$CT_ID" -mp0 "$DATAPOOL",mp="$DATAPOOL",acl=1 || { print_error "Failed to mount datapool"; exit 1; }
    
    # GPU passthrough for media stack - cgroup v2 method
    if [[ "$STACK_NAME" == "media" ]]; then
        print_info "Configuring GPU passthrough for media container (cgroup v2 method)"
        LXC_CONFIG_PATH="/etc/pve/lxc/${CT_ID}.conf"
        {
            echo ''
            echo '# GPU Passthrough (cgroup v2)'
            echo 'lxc.cgroup2.devices.allow: c 195:* rwm'
            echo 'lxc.cgroup2.devices.allow: c 511:* rwm'
            echo 'lxc.mount.entry: /dev/nvidia0 dev/nvidia0 none bind,optional,create=file'
            echo 'lxc.mount.entry: /dev/nvidiactl dev/nvidiactl none bind,optional,create=file'
            echo 'lxc.mount.entry: /dev/nvidia-uvm dev/nvidia-uvm none bind,optional,create=file'
            echo 'lxc.mount.entry: /dev/nvidia-uvm-tools dev/nvidia-uvm-tools none bind,optional,create=file'
            echo 'lxc.mount.entry: /dev/nvidia-modeset dev/nvidia-modeset none bind,optional,create=file'
        } >> "$LXC_CONFIG_PATH"
        print_success "GPU passthrough configured for $CT_ID"
    fi
fi

# Ensure container is running (both new and existing containers)
print_info "Ensuring container is running"
if ! pct status "$CT_ID" >/dev/null 2>&1 || [[ "$(pct status "$CT_ID" 2>/dev/null | awk '{print $2}')" != "running" ]]; then
    print_info "Starting container"
    pct start "$CT_ID" || { print_error "Failed to start container"; exit 1; }
fi

# Verify container is ready (both new and existing containers)
print_info "Verifying container is ready"
pct exec "$CT_ID" -- test -f /sbin/init || { print_error "Container failed to initialize properly"; exit 1; }
print_success "Container $CT_ID is ready"

# Fix config permissions for LXC containers (idempotent)
fix_config_permissions

print_info "Provisioning container (stack: $STACK_NAME)"

pct exec "$CT_ID" -- sh -c "
set -e
STACK_NAME='${STACK_NAME}'

if [ \"\$STACK_NAME\" = 'backup' ]; then
    # PBS: Use latest Debian with latest PBS packages
    # Set environment to prevent interactive prompts and locale issues
    export DEBIAN_FRONTEND=noninteractive
    export DEBIAN_PRIORITY=critical
    export IFUPDOWN2_NO_IFRELOAD=1
    export LC_ALL=C
    export LANG=C
    
    apt-get update
    apt-get install -y curl gnupg2
    
    # Get Debian codename dynamically
    DEBIAN_CODENAME=\$(lsb_release -cs 2>/dev/null || cat /etc/os-release | grep VERSION_CODENAME | cut -d= -f2)
    
    # Add Proxmox repository key for current Debian version
    curl -fsSL \"https://enterprise.proxmox.com/debian/proxmox-release-\${DEBIAN_CODENAME}.gpg\" -o /usr/share/keyrings/proxmox-archive-keyring.gpg
    
    # Configure Proxmox PBS repository for current Debian version
    echo \"deb [signed-by=/usr/share/keyrings/proxmox-archive-keyring.gpg] http://download.proxmox.com/debian/pbs \${DEBIAN_CODENAME} pbs-no-subscription\" > /etc/apt/sources.list.d/proxmox-backup.list
    
    # Install latest Proxmox Backup Server
    apt-get update
    apt-get install -y proxmox-backup-server -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold
    
    # Configure systemd autologin for tty1
    mkdir -p /etc/systemd/system/getty@tty1.service.d
    cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf << 'EOFLOGIN'
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin root --noclear %I \$TERM
EOFLOGIN
    
    # Disable SSH for security
    systemctl disable ssh || true
    systemctl stop ssh || true
    
    # Cleanup
    apt-get -y autoremove >/dev/null
    apt-get -y autoclean >/dev/null
    
elif [ \"$STACK_NAME\" = 'media' ]; then
    # Media Stack: Debian with Docker (GPU passthrough configured via LXC)
    apt-get update
    apt-get upgrade -y
    
    # Install Docker and essential packages (latest available versions)
    apt-get install -y docker.io curl wget util-linux
    
    # Configure Docker daemon with metrics and enable service
    mkdir -p /etc/docker
    cat > /etc/docker/daemon.json << 'EOFDOCKER'
{
    \"metrics-addr\": \"0.0.0.0:9323\",
    \"experimental\": true
}
EOFDOCKER
    systemctl enable docker
    systemctl start docker
    
    # Install latest Docker Compose standalone
    curl -SL https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64 -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose
    
    # Configure systemd autologin for tty1
    mkdir -p /etc/systemd/system/getty@tty1.service.d
    cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf << 'EOFLOGIN'
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin root --noclear %I \$TERM
EOFLOGIN
    
    # Disable SSH for security
    systemctl disable ssh || true
    systemctl stop ssh || true

else
    # Common Alpine setup - use latest packages
    apk update
    apk upgrade
    
    if [ \"\$STACK_NAME\" = 'development' ]; then
        # Development: NO Docker; only latest AI CLI tools and development packages
        apk add --no-cache util-linux nodejs npm git curl python3 py3-pip bash nano vim htop openssh-client ca-certificates github-cli
        npm config set fund false || true
        npm config set update-notifier false || true
        # Install latest AI CLI tools
        npm install -g @anthropic-ai/claude-code
        npm install -g @google/gemini-cli
    else
        # Other stacks: Docker runtime
        apk add --no-cache docker docker-cli-compose util-linux
        
        # Configure Docker daemon with metrics
        mkdir -p /etc/docker
        cat > /etc/docker/daemon.json <<EOFDOCKER
{
    \"metrics-addr\": \"0.0.0.0:9323\",
    \"experimental\": true
}
EOFDOCKER
        
        # Add docker to boot runlevel and start
        rc-update add docker boot
        service docker start || rc-service docker start || true
    fi
fi

# Common setup for all containers  
if [ \"\$STACK_NAME\" != 'backup' ] && [ \"\$STACK_NAME\" != 'media' ]; then
    # Alpine autologin
    sed -i 's|^tty1::|#&|' /etc/inittab 2>/dev/null || true
    echo 'tty1::respawn:/sbin/agetty --autologin root --noclear tty1 38400 linux' >> /etc/inittab
    kill -HUP 1 2>/dev/null || true
    
    # Alpine timezone setup
    apk add --no-cache tzdata || true
    ln -sf /usr/share/zoneinfo/Europe/Istanbul /etc/localtime 2>/dev/null || true
else
    # Debian timezone setup (PBS and Media)
    timedatectl set-timezone Europe/Istanbul 2>/dev/null || true
fi

# Set terminal colors for all containers (fix colorless terminal issue)
echo 'export TERM=xterm-256color' >> /etc/profile
echo 'export TERM=xterm-256color' >> /root/.bashrc

# Remove root password (allow passwordless login)
passwd -d root || true

# Create hushlogin to suppress login messages  
touch /root/.hushlogin

# Remove openssh if present (reduce attack surface)
if [ \"\$STACK_NAME\" != 'backup' ] && [ \"\$STACK_NAME\" != 'media' ]; then
    apk del openssh || true
else
    apt-get remove -y openssh-server || true
fi
" || { print_error "Provisioning failed"; exit 1; }

print_success "Container [$STACK_NAME] created and ready"