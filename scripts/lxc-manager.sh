#!/bin/bash

# This script is responsible for creating a new LXC container using dynamic templates.

set -e

# --- Arguments and Setup ---
STACK_NAME=$1
WORK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)"

source "$WORK_DIR/scripts/stack-config.sh"

# --- Helper Functions ---
print_info() { echo -e "\033[36m[INFO]\033[0m $1"; }
print_success() { echo -e "\033[32m[SUCCESS]\033[0m $1"; }
print_error() { echo -e "\033[31m[ERROR]\033[0m $1"; }
print_warning() { echo -e "\033[33m[WARNING]\033[0m $1"; }

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
        DOWNLOAD_TEMPLATE_NAME_FULL=$(pveam available | grep "system" | grep "ubuntu" | grep ".04-standard" | sort -V | tail -n 1 | awk \'{print $2}\')
    else
        DOWNLOAD_TEMPLATE_NAME_FULL=$(pveam available | grep "system" | grep "$CT_TEMPLATE_TYPE" | sort -V | tail -n 1 | awk \'{print $2}\')
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
    --swap 0     --features keyctl=1,nesting=1     --net0 name=eth0,bridge="$CT_BRIDGE",ip="$CT_IP_CIDR",gw="$CT_GATEWAY_IP"     --onboot 1     --unprivileged 1

print_info "Mounting datapool with ACL support...";
pct set "$CT_ID" -mp0 /datapool,mp=/datapool,acl=1

print_info "Starting container...";
pct start "$CT_ID"

sleep 10 # Wait for container to boot and network to be ready

# --- Stack-Specific Provisioning ---

if [[ "$STACK_NAME" == "development" ]]; then
    # --- Development Environment Setup ---
    print_info "Provisioning LXC for [development] environment...";
    pct exec "$CT_ID" -- apt-get update

    print_info "Installing Git and cURL..."
    pct exec "$CT_ID" -- apt-get install -y git curl
    print_success "Git and cURL installed."

    print_info "Setting up NodeJS v20 (LTS) repository via NodeSource..."
    pct exec "$CT_ID" -- bash -c "curl -fsSL https://deb.nodesource.com/setup_20.x | bash -"
    print_info "Installing NodeJS v20..."
    pct exec "$CT_ID" -- apt-get install -y nodejs
    print_success "NodeJS v20 (LTS) installed successfully."

    print_info "Installing global CLI tools: Gemini and Claude Code..."
    pct exec "$CT_ID" -- npm install -g @google/gemini-cli @anthropic-ai/claude-code
    print_success "Global CLI tools installed."

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