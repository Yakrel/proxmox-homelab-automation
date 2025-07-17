#!/bin/bash

# This script is responsible for creating a new LXC container using dynamic templates.

set -e

# --- Arguments and Setup ---
STACK_NAME=$1

# --- Helper Functions ---
print_info() { echo -e "\033[36m[INFO]\033[0m $1"; }
print_success() { echo -e "\033[32m[SUCCESS]\033[0m $1"; }
print_error() { echo -e "\033[31m[ERROR]\033[0m $1"; }
print_warning() { echo -e "\033[33m[WARNING]\033[0m $1"; }

# --- Hardcoded Stack Configuration ---
get_stack_config() {
    local stack=$1
    case $stack in
        "proxy")
            CT_ID="100"; CT_HOSTNAME="lxc-proxy-01"; CT_CORES="2"; CT_RAM_MB="2048"; CT_IP_CIDR="192.168.1.100/24"; CT_GATEWAY_IP="192.168.1.1"; CT_BRIDGE="vmbr0"; STORAGE_POOL="datapool"; CT_DISK_GB="20";
            CT_TEMPLATE_TYPE="alpine"
            ;;
        "media")
            CT_ID="101"; CT_HOSTNAME="lxc-media-01"; CT_CORES="4"; CT_RAM_MB="10240"; CT_IP_CIDR="192.168.1.101/24"; CT_GATEWAY_IP="192.168.1.1"; CT_BRIDGE="vmbr0"; STORAGE_POOL="datapool"; CT_DISK_GB="20";
            CT_TEMPLATE_TYPE="alpine"
            ;;
        "files")
            CT_ID="102"; CT_HOSTNAME="lxc-files-01"; CT_CORES="2"; CT_RAM_MB="3072"; CT_IP_CIDR="192.168.1.102/24"; CT_GATEWAY_IP="192.168.1.1"; CT_BRIDGE="vmbr0"; STORAGE_POOL="datapool"; CT_DISK_GB="20";
            CT_TEMPLATE_TYPE="alpine"
            ;;
        "webtools")
            CT_ID="103"; CT_HOSTNAME="lxc-webtools-01"; CT_CORES="2"; CT_RAM_MB="6144"; CT_IP_CIDR="192.168.1.103/24"; CT_GATEWAY_IP="192.168.1.1"; CT_BRIDGE="vmbr0"; STORAGE_POOL="datapool"; CT_DISK_GB="20";
            CT_TEMPLATE_TYPE="alpine"
            ;;
        "monitoring")
            CT_ID="104"; CT_HOSTNAME="lxc-monitoring-01"; CT_CORES="4"; CT_RAM_MB="6144"; CT_IP_CIDR="192.168.1.104/24"; CT_GATEWAY_IP="192.168.1.1"; CT_BRIDGE="vmbr0"; STORAGE_POOL="datapool"; CT_DISK_GB="20";
            CT_TEMPLATE_TYPE="alpine"
            ;;
        "development")
            CT_ID="150"; CT_HOSTNAME="lxc-development-01"; CT_CORES="4"; CT_RAM_MB="8192"; CT_IP_CIDR="192.168.1.150/24"; CT_GATEWAY_IP="192.168.1.1"; CT_BRIDGE="vmbr0"; STORAGE_POOL="datapool"; CT_DISK_GB="20";
            CT_TEMPLATE_TYPE="ubuntu"
            ;;
        *)
            echo -e "\033[31m[ERROR]\033[0m Unknown stack: $stack" >&2
            exit 1
            ;;
    esac
}

# --- LXC Creation Logic ---

get_stack_config "$STACK_NAME"

print_info "Finding the latest template for type '$CT_TEMPLATE_TYPE'...";
pveam update > /dev/null

# Dynamically find the latest template filename
LATEST_TEMPLATE=$(pveam list "$STORAGE_POOL" | grep "$CT_TEMPLATE_TYPE" | sort -V | tail -n 1 | awk '{print $1}')

if [ -z "$LATEST_TEMPLATE" ]; then
    print_warning "No local template found for '$CT_TEMPLATE_TYPE'. Downloading the latest version...";
    # Dynamically find the latest available template name from pveam available
    # This assumes the template type is in the second column and we need to strip the date/arch suffix
    if [[ "$CT_TEMPLATE_TYPE" == "ubuntu" ]]; then
        # Filter for Ubuntu LTS versions only (even years ending in .04)
        DOWNLOAD_TEMPLATE_NAME_FULL=$(pveam available | grep "system" | grep "ubuntu" | grep -E "\b(1[6-9]|[2-9][02468])\.04-standard" | sort -V | tail -n 1 | awk '{print $2}')
    else
        DOWNLOAD_TEMPLATE_NAME_FULL=$(pveam available | grep "system" | grep "$CT_TEMPLATE_TYPE" | sort -V | tail -n 1 | awk '{print $2}')
    fi

    # Strip the date and architecture suffix (e.g., _20250617_amd64)
    DOWNLOAD_TEMPLATE_NAME="$DOWNLOAD_TEMPLATE_NAME_FULL"

    if [ -z "$DOWNLOAD_TEMPLATE_NAME" ]; then
        print_error "Could not find an available template for '$CT_TEMPLATE_TYPE'. Please check 'pveam available' output."
        exit 1
    fi
    pveam download "$STORAGE_POOL" "$DOWNLOAD_TEMPLATE_NAME"
    # Re-run the find command after download
    LATEST_TEMPLATE=$(pveam list "$STORAGE_POOL" | grep "$CT_TEMPLATE_TYPE" | sort -V | tail -n 1 | awk '{print $1}')
    print_success "Downloaded: $LATEST_TEMPLATE"
else
    print_info "Found latest available template: $LATEST_TEMPLATE"
fi

print_info "Creating LXC container $CT_ID ($CT_HOSTNAME) using $LATEST_TEMPLATE...";

pct create "$CT_ID" "$LATEST_TEMPLATE" \
    --hostname "$CT_HOSTNAME" \
    --storage "$STORAGE_POOL" \
    --cores "$CT_CORES" \
    --memory "$CT_RAM_MB" \
    --swap 0     --features keyctl=1,nesting=1     --net0 name=eth0,bridge="$CT_BRIDGE",ip="$CT_IP_CIDR",gw="$CT_GATEWAY_IP"     --onboot 1     --unprivileged 1 \
    --rootfs ${STORAGE_POOL}:${CT_DISK_GB}

print_info "Mounting datapool with ACL support...";
pct set "$CT_ID" -mp0 /datapool,mp=/datapool,acl=1

print_info "Starting container...";
pct start "$CT_ID"

print_info "Waiting for container to be ready...";
max_wait=60
interval=3
elapsed=0
until pct exec "$CT_ID" -- hostname >/dev/null 2>&1; do
    if [ "$elapsed" -ge "$max_wait" ]; then
        print_error "Container failed to start within $max_wait seconds."
        exit 1
    fi
    sleep "$interval"
    elapsed=$((elapsed + interval))
done
print_success "Container is ready."

# --- Stack-Specific Provisioning ---

if [[ "$STACK_NAME" == "development" ]]; then
    # --- Development Environment Setup ---
    print_info "Provisioning LXC for [development] environment...";

    # Generate and set the locale to avoid warnings
    print_info "Generating en_US.UTF-8 locale to prevent package configuration errors..."
    pct exec "$CT_ID" -- bash -c "export DEBIAN_FRONTEND=noninteractive; apt-get update && apt-get install -y locales && locale-gen en_US.UTF-8 && update-locale LANG=en_US.UTF-8"
    print_success "Locale configured successfully."

    print_info "Installing Git and cURL..."
    pct exec "$CT_ID" -- apt-get install -y git curl
    print_success "Git and cURL installed."

    # Autologin configuration for Ubuntu
    print_info "Configuring autologin for root user..."
    pct exec "$CT_ID" -- passwd -d root # Delete root password
    pct exec "$CT_ID" -- apt-get install -y util-linux # Install util-linux for agetty
    pct exec "$CT_ID" -- sh -c 'mkdir -p /etc/systemd/system/getty@tty1.service.d'
    pct exec "$CT_ID" -- sh -c 'cat <<EOF >/etc/systemd/system/getty@tty1.service.d/autologin.conf
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin root --noclear %I \$TERM
EOF'
    pct exec "$CT_ID" -- systemctl daemon-reload
    pct exec "$CT_ID" -- systemctl restart getty@tty1.service
    pct exec "$CT_ID" -- touch /root/.hushlogin # Prevent MOTD on login
    print_success "Autologin configured."

else
    # --- Standard Docker-based Setup ---
    print_info "Installing Docker and essential tools inside the container...";
    if [[ "$CT_TEMPLATE_TYPE" == "alpine" ]]; then
        pct exec "$CT_ID" -- apk update
        pct exec "$CT_ID" -- apk add --no-cache docker docker-cli-compose
        pct exec "$CT_ID" -- rc-update add docker boot
        pct exec "$CT_ID" -- service docker start
        # Autologin configuration
        print_info "Configuring autologin for root user..."
        pct exec "$CT_ID" -- passwd -d root # Delete root password
        pct exec "$CT_ID" -- apk add --no-cache util-linux # Install util-linux for agetty
        pct exec "$CT_ID" -- sh -c 'mkdir -p /etc/local.d'
        pct exec "$CT_ID" -- sh -c 'cat <<EOF >/etc/local.d/autologin.start
#!/bin/sh
sed -i '\''s|^tty1::respawn:.*|tty1::respawn:/sbin/agetty --autologin root --noclear tty1 38400 linux|'\'' /etc/inittab
kill -HUP 1
EOF'
        pct exec "$CT_ID" -- sh -c 'chmod +x /etc/local.d/autologin.start'
        pct exec "$CT_ID" -- rc-update add local # Add to runlevel
        pct exec "$CT_ID" -- sh -c '/etc/local.d/autologin.start' # Apply immediately
        pct exec "$CT_ID" -- touch /root/.hushlogin # Prevent MOTD on login
        print_success "Autologin configured."
    elif [[ "$CT_TEMPLATE_TYPE" == "ubuntu" ]]; then
        pct exec "$CT_ID" -- apt-get update
        pct exec "$CT_ID" -- apt-get install -y docker.io docker-compose-plugin
        pct exec "$CT_ID" -- systemctl enable --now docker
        # Autologin configuration for Ubuntu
        print_info "Configuring autologin for root user..."
        pct exec "$CT_ID" -- passwd -d root # Delete root password
        pct exec "$CT_ID" -- apt-get install -y util-linux # Install util-linux for agetty
        pct exec "$CT_ID" -- sh -c 'mkdir -p /etc/systemd/system/getty@tty1.service.d'
        pct exec "$CT_ID" -- sh -c 'cat <<EOF >/etc/systemd/system/getty@tty1.service.d/autologin.conf
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin root --noclear %I \$TERM
EOF'
        pct exec "$CT_ID" -- systemctl daemon-reload
        pct exec "$CT_ID" -- systemctl restart getty@tty1.service
        pct exec "$CT_ID" -- touch /root/.hushlogin # Prevent MOTD on login
        print_success "Autologin configured."
    fi
fi

print_success "LXC container for [$STACK_NAME] created and ready."