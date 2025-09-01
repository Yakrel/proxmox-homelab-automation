#!/bin/bash

# Unified Alpine-based LXC creation + minimal provisioning.
set -e

STACK_NAME=$1
WORK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)"

# --- Load Shared Functions ---
source "$WORK_DIR/scripts/helper-functions.sh"

# Load stack configuration using shared function
get_stack_config "$STACK_NAME"

# Choose template based on stack type
if [ "$STACK_NAME" = "backup" ]; then
    print_info "Locating latest Debian template for PBS..."
    pveam update > /dev/null || true
    LATEST_TEMPLATE=$(pveam list "$STORAGE_POOL" | awk '/debian-.*-standard/ {print $1}' | sort -V | tail -n 1)
    if [ -z "$LATEST_TEMPLATE" ]; then
        print_warning "No local Debian template; downloading..."
        DOWNLOAD_TEMPLATE=$(pveam available | awk '/debian-[0-9.]+(-[0-9]+)?-standard/ {print $NF}' | sort -V | tail -n 1)
        if [ -z "$DOWNLOAD_TEMPLATE" ]; then
            print_error "Could not determine latest Debian template.\n--- pveam available output ---\n$(pveam available | grep debian)" && exit 1
        fi
        pveam download "$STORAGE_POOL" "$DOWNLOAD_TEMPLATE"
        LATEST_TEMPLATE=$(pveam list "$STORAGE_POOL" | awk '/debian-.*-standard/ {print $1}' | sort -V | tail -n 1)
        print_success "Downloaded template: $LATEST_TEMPLATE"
    else
        print_info "Using Debian template: $LATEST_TEMPLATE"
    fi
else
    print_info "Locating latest Alpine template for other stacks..."
    pveam update > /dev/null || true
    LATEST_TEMPLATE=$(pveam list "$STORAGE_POOL" | awk '/alpine-.*-default/ {print $1}' | sort -V | tail -n 1)
    if [ -z "$LATEST_TEMPLATE" ]; then
        print_warning "No local Alpine template; downloading..."
        DOWNLOAD_TEMPLATE=$(pveam available | awk '/alpine-[0-9.]+(-[0-9]+)?-default/ {print $NF}' | sort -V | tail -n 1)
        if [ -z "$DOWNLOAD_TEMPLATE" ]; then
            print_error "Could not determine latest Alpine template.\n--- pveam available output ---\n$(pveam available | grep alpine)" && exit 1
        fi
        pveam download "$STORAGE_POOL" "$DOWNLOAD_TEMPLATE"
        LATEST_TEMPLATE=$(pveam list "$STORAGE_POOL" | awk '/alpine-.*-default/ {print $1}' | sort -V | tail -n 1)
        print_success "Downloaded template: $LATEST_TEMPLATE"
    else
        print_info "Using Alpine template: $LATEST_TEMPLATE"
    fi
fi

print_info "Creating LXC ($CT_ID) $CT_HOSTNAME ..."
pct create "$CT_ID" "$LATEST_TEMPLATE" \
    --hostname "$CT_HOSTNAME" \
    --storage "$STORAGE_POOL" \
    --cores $CT_CPU_CORES \
    --memory $CT_MEMORY_MB \
    --swap 0 \
    --features keyctl=1,nesting=1 \
    --net0 name=eth0,bridge=$NETWORK_BRIDGE,ip=$CT_IP/24,gw=$NETWORK_GATEWAY \
    --onboot 1 \
    --unprivileged 1 \
    --rootfs ${STORAGE_POOL}:$CT_DISK_GB

# Skip datapool mount for development stack
if [ "$STACK_NAME" != "development" ]; then
    print_info "Mounting datapool..."
    pct set "$CT_ID" -mp0 /datapool,mp=/datapool,acl=1
fi

print_info "Starting container..."
pct start "$CT_ID"

print_info "Waiting for container to respond..."
while ! pct exec "$CT_ID" -- test -f /sbin/init >/dev/null 2>&1; do
    sleep 2
done
print_success "Container is up."

print_info "Provisioning inside container (stack: $STACK_NAME)..."

pct exec "$CT_ID" -- sh -c "
set -e
STACK_NAME='$STACK_NAME'

if [ \"\$STACK_NAME\" = 'backup' ]; then
    # PBS: Debian-based setup - minimal dependencies
    apt-get update >/dev/null
    apt-get install -y curl gnupg2 >/dev/null
    
    # Add Proxmox repository key and source (bookworm for Debian 12)
    curl -fsSL https://enterprise.proxmox.com/debian/proxmox-release-bookworm.gpg -o /etc/apt/trusted.gpg.d/proxmox-release-bookworm.gpg
    echo 'deb http://download.proxmox.com/debian/pbs bookworm pbs-no-subscription' >> /etc/apt/sources.list
    
    # Install PBS with non-interactive mode
    apt-get update >/dev/null
    export DEBIAN_FRONTEND=noninteractive
    export IFUPDOWN2_NO_IFRELOAD=1
    apt-get install -y proxmox-backup-server
    
    # Configure systemd autologin for tty1
    mkdir -p /etc/systemd/system/getty@tty1.service.d
    cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf << 'EOFLOGIN'
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin root --noclear %I \$TERM
EOFLOGIN
    
    # Disable SSH for security (don't remove to prevent dependency issues)
    systemctl disable ssh || true
    systemctl stop ssh || true
    
    # Cleanup
    apt-get -y autoremove >/dev/null
    apt-get -y autoclean >/dev/null
    
else
    # Common Alpine setup
    apk update
    apk upgrade
    
    if [ \"\$STACK_NAME\" = 'development' ]; then
        # Development: NO Docker; only AI CLI tools
        apk add --no-cache util-linux nodejs npm git curl python3 py3-pip bash nano vim htop openssh-client ca-certificates
        npm config set fund false >/dev/null 2>&1 || true
        npm config set update-notifier false >/dev/null 2>&1 || true
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
    # Alpine autologin - direct approach
    sed -i 's|^tty1::|#&|' /etc/inittab 2>/dev/null || true
    echo 'tty1::respawn:/sbin/agetty --autologin root --noclear tty1 38400 linux' >> /etc/inittab
    kill -HUP 1 2>/dev/null || true
fi

# Remove root password (allow passwordless login)
passwd -d root || true

# Create hushlogin to suppress login messages  
touch /root/.hushlogin

# Remove openssh if present (reduce attack surface)
if [ \"\$STACK_NAME\" != 'backup' ]; then
    apk del openssh || true
fi
"

print_success "Provisioning complete for [$STACK_NAME]."
print_success "LXC container for [$STACK_NAME] created and ready."