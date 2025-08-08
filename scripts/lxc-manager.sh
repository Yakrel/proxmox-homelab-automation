#!/bin/bash

# Unified Alpine-based LXC creation + minimal provisioning.
set -e

STACK_NAME=$1

print_info() { echo -e "\033[36m[INFO]\033[0m $1"; }
print_success() { echo -e "\033[32m[SUCCESS]\033[0m $1"; }
print_error() { echo -e "\033[31m[ERROR]\033[0m $1"; }
print_warning() { echo -e "\033[33m[WARNING]\033[0m $1"; }

STACK_NAME=$1

# Attempt to load unified stack config from stacks.yml (optional, backward compatible)
STACKS_YAML="$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)/stacks.yml"

load_from_yaml() {
    command -v yq >/dev/null 2>&1 || return 1
    [ -f "$STACKS_YAML" ] || return 1
    CT_ID=$(yq -r ".stacks.$STACK_NAME.id" "$STACKS_YAML") || return 1
    [ "$CT_ID" = "null" ] && return 1
    CT_HOSTNAME=$(yq -r ".stacks.$STACK_NAME.hostname" "$STACKS_YAML")
    CT_IP_CIDR=$(yq -r ".stacks.$STACK_NAME.ip" "$STACKS_YAML")
    CT_CORES=$(yq -r ".stacks.$STACK_NAME.cores" "$STACKS_YAML")
    CT_RAM_MB=$(yq -r ".stacks.$STACK_NAME.memory" "$STACKS_YAML")
    CT_DISK_GB=$(yq -r ".stacks.$STACK_NAME.disk" "$STACKS_YAML")
    [ -z "$CT_ID" -o "$CT_ID" = "null" ] && return 1
    return 0
}

get_stack_config() {
    CT_IP_CIDR_BASE="192.168.1"; CT_GATEWAY_IP="192.168.1.1"; CT_BRIDGE="vmbr0"; STORAGE_POOL="datapool"
    case "$1" in
        proxy)
            CT_ID=100
            CT_HOSTNAME="lxc-proxy-01"
            CT_CORES=2
            CT_RAM_MB=2048
            CT_DISK_GB=10
            CT_IP_CIDR="$CT_IP_CIDR_BASE.100/24"
            ;;
        media)
            CT_ID=101
            CT_HOSTNAME="lxc-media-01"
            CT_CORES=6
            CT_RAM_MB=10240
            CT_DISK_GB=20
            CT_IP_CIDR="$CT_IP_CIDR_BASE.101/24"
            ;;
        files)
            CT_ID=102
            CT_HOSTNAME="lxc-files-01"
            CT_CORES=2
            CT_RAM_MB=3072
            CT_DISK_GB=15
            CT_IP_CIDR="$CT_IP_CIDR_BASE.102/24"
            ;;
        webtools)
            CT_ID=103
            CT_HOSTNAME="lxc-webtools-01"
            CT_CORES=2
            CT_RAM_MB=6144
            CT_DISK_GB=15
            CT_IP_CIDR="$CT_IP_CIDR_BASE.103/24"
get_stack_config() {
    STACK_NAME=$1

    # Source shared config loader
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if ! source "$SCRIPT_DIR/lib-stack-config.sh" 2>/dev/null; then
        print_error "Failed to load lib-stack-config.sh"; exit 1
    fi

    load_stack_config "$STACK_NAME" || { print_error "Could not resolve stack config for $STACK_NAME"; exit 1; }
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