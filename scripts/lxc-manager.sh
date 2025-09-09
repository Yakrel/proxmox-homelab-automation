#!/bin/bash

# Unified Alpine-based LXC creation + minimal provisioning
# Fail fast approach
set -euo pipefail

STACK_NAME=$1
WORK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)"

# --- Load Shared Functions ---
source "$WORK_DIR/scripts/helper-functions.sh"

# Load stack configuration using shared function
get_stack_config "$STACK_NAME"

# Choose template based on stack type - always use latest
if [ "$STACK_NAME" = "backup" ]; then
    print_info "Getting latest Debian template for PBS"
    pveam update > /dev/null || true
    LATEST_TEMPLATE=$(pveam list "$STORAGE_POOL" | awk '/debian-.*-standard/ {print $1}' | sort -V | tail -n 1)
    if [ -z "$LATEST_TEMPLATE" ]; then
        print_info "Downloading latest Debian template"
        DOWNLOAD_TEMPLATE=$(pveam available | awk '/debian-[0-9.]+(-[0-9]+)?-standard/ {print $NF}' | sort -V | tail -n 1)
        [[ -n "$DOWNLOAD_TEMPLATE" ]] || { print_error "No Debian template found"; exit 1; }
        pveam download "$STORAGE_POOL" "$DOWNLOAD_TEMPLATE" || { print_error "Failed to download Debian template"; exit 1; }
        LATEST_TEMPLATE=$(pveam list "$STORAGE_POOL" | awk '/debian-.*-standard/ {print $1}' | sort -V | tail -n 1)
        print_success "Downloaded Debian template: $LATEST_TEMPLATE"
    else
        print_info "Using Debian template: $LATEST_TEMPLATE"
    fi
else
    print_info "Getting latest Alpine template"
    pveam update > /dev/null || true
    LATEST_TEMPLATE=$(pveam list "$STORAGE_POOL" | awk '/alpine-.*-default/ {print $1}' | sort -V | tail -n 1)
    if [ -z "$LATEST_TEMPLATE" ]; then
        print_info "Downloading latest Alpine template"
        DOWNLOAD_TEMPLATE=$(pveam available | awk '/alpine-[0-9.]+(-[0-9]+)?-default/ {print $NF}' | sort -V | tail -n 1)
        [[ -n "$DOWNLOAD_TEMPLATE" ]] || { print_error "No Alpine template found"; exit 1; }
        pveam download "$STORAGE_POOL" "$DOWNLOAD_TEMPLATE" || { print_error "Failed to download Alpine template"; exit 1; }
        LATEST_TEMPLATE=$(pveam list "$STORAGE_POOL" | awk '/alpine-.*-default/ {print $1}' | sort -V | tail -n 1)
        print_success "Downloaded Alpine template: $LATEST_TEMPLATE"
    else
        print_info "Using Alpine template: $LATEST_TEMPLATE"
    fi
fi

# Container exists check
if check_container_exists "$CT_ID"; then
    print_error "Container $CT_ID already exists"
    press_enter_to_continue
    exit 1
fi

# Create container
print_info "Creating LXC container $CT_ID ($CT_HOSTNAME)"
pct create "$CT_ID" "$LATEST_TEMPLATE" \
    --hostname "$CT_HOSTNAME" \
    --storage "$STORAGE_POOL" \
    --cores "$CT_CPU_CORES" \
    --memory "$CT_MEMORY_MB" \
    --swap 0 \
    --features keyctl=1,nesting=1 \
    --net0 name=eth0,bridge="$NETWORK_BRIDGE",ip="$CT_IP"/24,gw="$NETWORK_GATEWAY" \
    --onboot 1 \
    --unprivileged 1 \
    --rootfs "$STORAGE_POOL":"$CT_DISK_GB" || { print_error "Failed to create container"; press_enter_to_continue; exit 1; }

# Mount datapool for all stacks except development
if [ "$STACK_NAME" != "development" ]; then
    print_info "Mounting datapool"
    pct set "$CT_ID" -mp0 "$DATAPOOL",mp="$DATAPOOL",acl=1 || { print_error "Failed to mount datapool"; press_enter_to_continue; exit 1; }
fi

print_info "Starting container"
pct start "$CT_ID" || { print_error "Failed to start container"; press_enter_to_continue; exit 1; }

print_info "Waiting for container"
while ! pct exec "$CT_ID" -- test -f /sbin/init >/dev/null 2>&1; do
    sleep 2
done
print_success "Container ready"

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
    
    apt-get update >/dev/null 2>&1
    apt-get install -y curl gnupg2 >/dev/null 2>&1
    
    # Add Proxmox repository key  
    curl -fsSL https://enterprise.proxmox.com/debian/proxmox-release-bookworm.gpg -o /usr/share/keyrings/proxmox-archive-keyring.gpg
    
    # Configure Proxmox PBS repository (no-subscription for latest)
    echo \"deb [signed-by=/usr/share/keyrings/proxmox-archive-keyring.gpg] http://download.proxmox.com/debian/pbs bookworm pbs-no-subscription\" > /etc/apt/sources.list.d/proxmox-backup.list
    
    # Install latest Proxmox Backup Server
    apt-get update >/dev/null 2>&1
    apt-get install -y proxmox-backup-server -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold >/dev/null 2>&1
    
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
    
else
    # Common Alpine setup - use latest packages
    apk update
    apk upgrade
    
    if [ \"\$STACK_NAME\" = 'development' ]; then
        # Development: NO Docker; only latest AI CLI tools and development packages
        apk add --no-cache util-linux nodejs npm git curl python3 py3-pip bash nano vim htop openssh-client ca-certificates github-cli
        npm config set fund false >/dev/null 2>&1 || true
        npm config set update-notifier false >/dev/null 2>&1 || true
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
if [ \"\$STACK_NAME\" != 'backup' ]; then
    # Alpine autologin
    sed -i 's|^tty1::|#&|' /etc/inittab 2>/dev/null || true
    echo 'tty1::respawn:/sbin/agetty --autologin root --noclear tty1 38400 linux' >> /etc/inittab
    kill -HUP 1 2>/dev/null || true
    
    # Alpine timezone setup
    apk add --no-cache tzdata >/dev/null 2>&1 || true
    ln -sf /usr/share/zoneinfo/Europe/Istanbul /etc/localtime 2>/dev/null || true
else
    # Debian timezone setup (PBS)
    timedatectl set-timezone Europe/Istanbul 2>/dev/null || true
fi

# Remove root password (allow passwordless login)
passwd -d root || true

# Create hushlogin to suppress login messages  
touch /root/.hushlogin

# Remove openssh if present (reduce attack surface)
if [ \"\$STACK_NAME\" != 'backup' ]; then
    apk del openssh || true
fi
" || { print_error "Provisioning failed"; press_enter_to_continue; exit 1; }

print_success "Container [$STACK_NAME] created and ready"
press_enter_to_continue