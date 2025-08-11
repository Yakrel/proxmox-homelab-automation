#!/bin/bash

# Unified Alpine-based LXC creation + minimal provisioning.
set -e

STACK_NAME=$1
STACKS_FILE="/root/stacks.yaml"

print_info() { echo -e "\033[36m[INFO]\033[0m $1"; }
print_success() { echo -e "\033[32m[SUCCESS]\033[0m $1"; }
print_error() { echo -e "\033[31m[ERROR]\033[0m $1"; }
print_warning() { echo -e "\033[33m[WARNING]\033[0m $1"; }

get_stack_config() {
    # Auto-install yq if not present
    if ! command -v yq >/dev/null 2>&1; then
        print_info "Installing yq (YAML processor)..."
        wget -q https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -O /usr/bin/yq
        chmod +x /usr/bin/yq
        print_success "yq installed successfully."
    fi
    
    if [ ! -f "$STACKS_FILE" ]; then
        print_error "Stacks file not found: $STACKS_FILE. Ensure stacks.yaml is placed there."
        exit 1
    fi
    CT_ID=$(yq -r ".stacks.$1.ct_id" "$STACKS_FILE")
    CT_HOSTNAME=$(yq -r ".stacks.$1.hostname" "$STACKS_FILE")
    CT_CORES=$(yq -r ".stacks.$1.cpu_cores" "$STACKS_FILE")
    CT_RAM_MB=$(yq -r ".stacks.$1.memory_mb" "$STACKS_FILE")
    CT_DISK_GB=$(yq -r ".stacks.$1.disk_gb" "$STACKS_FILE")
    CT_IP_CIDR_BASE=$(yq -r ".network.ip_base" "$STACKS_FILE")
    CT_GATEWAY_IP=$(yq -r ".network.gateway" "$STACKS_FILE")
    CT_BRIDGE=$(yq -r ".network.bridge" "$STACKS_FILE")
    STORAGE_POOL=$(yq -r ".storage.pool" "$STACKS_FILE")
    ip_octet=$(yq -r ".stacks.$1.ip_octet" "$STACKS_FILE")
    CT_IP_CIDR="$CT_IP_CIDR_BASE.$ip_octet/24"
    if [ -z "$CT_ID" ] || [ "$CT_ID" = "null" ]; then
        print_error "Stack '$1' not found or incomplete in $STACKS_FILE"
        exit 1
    fi
}

get_stack_config "$STACK_NAME"

print_info "Locating latest Alpine template (local cache)..."
pveam update > /dev/null || true
LATEST_TEMPLATE=$(pveam list "$STORAGE_POOL" | awk '/alpine-.*-default/ {print $1}' | sort -V | tail -n 1)
if [ -z "$LATEST_TEMPLATE" ]; then
    print_warning "No local Alpine template; downloading..."
    DOWNLOAD_TEMPLATE=$(pveam available | awk '/^system\s+alpine-[0-9]+-default/ {print $2}' | sort -V | tail -n 1)
    [ -z "$DOWNLOAD_TEMPLATE" ] && print_error "Could not determine latest Alpine template" && exit 1
    pveam download "$STORAGE_POOL" "$DOWNLOAD_TEMPLATE"
    LATEST_TEMPLATE=$(pveam list "$STORAGE_POOL" | awk '/alpine-.*-default/ {print $1}' | sort -V | tail -n 1)
    print_success "Downloaded template: $LATEST_TEMPLATE"
else
    print_info "Using template: $LATEST_TEMPLATE"
fi

print_info "Creating LXC ($CT_ID) $CT_HOSTNAME ..."
pct create "$CT_ID" "$LATEST_TEMPLATE" \
    --hostname "$CT_HOSTNAME" \
    --storage "$STORAGE_POOL" \
    --cores $CT_CORES \
    --memory $CT_RAM_MB \
    --swap 0 \
    --features keyctl=1,nesting=1 \
    --net0 name=eth0,bridge=$CT_BRIDGE,ip=$CT_IP_CIDR,gw=$CT_GATEWAY_IP \
    --onboot 1 \
    --unprivileged 1 \
    --rootfs ${STORAGE_POOL}:$CT_DISK_GB

print_info "Mounting datapool..."
pct set "$CT_ID" -mp0 /datapool,mp=/datapool,acl=1

print_info "Starting container..."
pct start "$CT_ID"

print_info "Waiting for container to respond..."
for i in $(seq 1 20); do
    if pct exec "$CT_ID" -- uname -a >/dev/null 2>&1; then
        print_success "Container is up."
        break
    fi
    sleep 3
    [ $i -eq 20 ] && print_error "Timeout waiting for container" && exit 1
done

print_info "Provisioning inside container (stack: $STACK_NAME)..."

pct exec "$CT_ID" -- sh -c "set -e
apk update
if [ "$STACK_NAME" = 'development' ]; then
        # Development: NO Docker; only what is needed for Gemini CLI & autologin.
        apk add --no-cache util-linux nodejs npm git curl
        npm config set fund false >/dev/null 2>&1 || true
        npm config set update-notifier false >/dev/null 2>&1 || true
else
        # Other stacks: Docker runtime only.
        apk add --no-cache docker docker-cli-compose util-linux
fi
rc-update add docker boot
mkdir -p /etc/docker
cat > /etc/docker/daemon.json <<EOFDOCKER
{
    \"metrics-addr\": \"0.0.0.0:9323\",
    \"experimental\": true
}
EOFDOCKER
if [ "$STACK_NAME" != 'development' ]; then
    service docker start || rc-service docker start || true
fi
passwd -d root || true
mkdir -p /etc/local.d
cat > /etc/local.d/autologin.start <<'EOFAUTO'
#!/bin/sh
sed -i "s|^tty1::.*|tty1::respawn:/sbin/agetty --autologin root --noclear tty1 38400 linux|" /etc/inittab
kill -HUP 1
EOFAUTO
chmod +x /etc/local.d/autologin.start
rc-update add local default
/etc/local.d/autologin.start || true
touch /root/.hushlogin
apk del openssh || true
"

print_success "Provisioning complete for [$STACK_NAME]."
print_success "LXC container for [$STACK_NAME] created and ready."