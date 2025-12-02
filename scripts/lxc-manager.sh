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

    # Update template list silently (output would interfere with variable capture below)
    # This is an exception to no-suppression rule as we're in a function that returns via echo
    pveam update >/dev/null 2>&1 || true

    # Fetch both available and local templates in one call each (optimization: reduce pveam calls)
    local available_output local_output
    available_output=$(pveam available 2>/dev/null || echo "")
    local_output=$(pveam list "$TEMPLATE_POOL" 2>/dev/null || echo "")

    # Get the latest available template name from repository
    local latest_available
    latest_available=$(echo "$available_output" | awk "/${template_type}/ {print \$2}" | sort -V | tail -n 1)
    [[ -n "$latest_available" ]] || { print_error "No ${template_type} template available"; exit 1; }

    # Check if we already have this exact template locally
    local local_template
    local_template=$(echo "$local_output" | awk "/${template_type}/ {print \$1}" | sort -V | tail -n 1 | sed "s|^${TEMPLATE_POOL}:vztmpl/||")

    # If local template doesn't match latest available, download the new one
    if [[ "$local_template" != "$latest_available" ]]; then
        print_info "Downloading latest ${template_type} template: $latest_available" >&2
        pveam download "$TEMPLATE_POOL" "$latest_available" >&2
        # After download, query storage to get actual filename (may differ from available name due to version resolution)
        local_template=$(pveam list "$TEMPLATE_POOL" 2>/dev/null | awk "/${template_type}/ {print \$1}" | sort -V | tail -n 1 | sed "s|^${TEMPLATE_POOL}:vztmpl/||")
        print_success "Downloaded template: $local_template" >&2
    else
        print_info "Using up-to-date template: $local_template" >&2
    fi

    echo "$local_template"
}

# Choose template based on stack type - always use latest
# Debian: media (Jellyfin GPU), webtools (Chrome GPU), development (code-server)
# Alpine: all other stacks (lighter, faster)
if [ "$STACK_NAME" = "media" ] || [ "$STACK_NAME" = "webtools" ] || [ "$STACK_NAME" = "development" ]; then
    LATEST_TEMPLATE=$(get_latest_template "debian-.*-standard")
else
    LATEST_TEMPLATE=$(get_latest_template "alpine-.*-default")
fi

# Container exists check - handle gracefully for idempotency
if check_container_exists "$CT_ID"; then
    print_info "Container $CT_ID exists, verifying state"
    SKIP_CREATION=true
else
    SKIP_CREATION=false
fi

# Create container only if it doesn't exist
if [[ "$SKIP_CREATION" == "false" ]]; then
    print_info "Creating container $CT_ID ($CT_HOSTNAME)"
    pct create "$CT_ID" "${TEMPLATE_POOL}:vztmpl/${LATEST_TEMPLATE}" \
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
    pct set "$CT_ID" -mp0 "$DATAPOOL",mp="$DATAPOOL",acl=1 || { print_error "Failed to mount datapool"; exit 1; }
    
    # GPU passthrough for media and webtools stacks - cgroup v2 method
    # media: Jellyfin hardware transcoding (decode/scale/encode) + Immich ML
    # webtools: LinuxServer Chrome automatically enables hardware acceleration with Nvidia passthrough
    if [[ "$STACK_NAME" == "media" ]] || [[ "$STACK_NAME" == "webtools" ]]; then
        print_info "Configuring GPU passthrough for $STACK_NAME container (cgroup v2 method)"

        # Create systemd service for persistent NVIDIA device setup (survives reboots)
        cat > /etc/systemd/system/nvidia-persistenced.service << 'EOF'
[Unit]
Description=NVIDIA Persistence Daemon and Device Setup for LXC
After=local-fs.target

[Service]
Type=forking
ExecStartPre=/sbin/modprobe nvidia-uvm
ExecStartPre=/usr/bin/nvidia-modprobe -u -c0
ExecStart=/usr/bin/nvidia-persistenced --user root --persistence-mode --verbose
ExecStartPost=/bin/chmod 666 /dev/nvidia-uvm /dev/nvidia-uvm-tools
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

        # Enable and start the service
        systemctl daemon-reload
        systemctl enable nvidia-persistenced.service
        systemctl restart nvidia-persistenced.service || print_warning "nvidia-persistenced service failed to start"

        # Wait for devices to be created
        sleep 2

        # Verify devices exist
        if [[ ! -c /dev/nvidia-uvm ]]; then
            print_warning "nvidia-uvm device not found - GPU may not work"
        fi
        
        LXC_CONFIG_PATH="/etc/pve/lxc/${CT_ID}.conf"
        [[ -f "$LXC_CONFIG_PATH" ]] || touch "$LXC_CONFIG_PATH"

        if ! grep -Fxq '# GPU Passthrough (cgroup v2)' "$LXC_CONFIG_PATH"; then
            printf '\n# GPU Passthrough (cgroup v2)\n' >> "$LXC_CONFIG_PATH"
        fi

        gpu_passthrough_lines=(
            # cgroup device permissions for NVIDIA GPU
            'lxc.cgroup.devices.allow: c 195:* rwm'   # NVIDIA GPU devices (195:0 = nvidia0)
            'lxc.cgroup.devices.allow: c 510:* rwm'   # nvidia-uvm (510:0)
            'lxc.cgroup.devices.allow: c 511:* rwm'   # nvidia-uvm (511:0 on some systems)
            'lxc.cgroup2.devices.allow: c 195:* rwm'  # cgroup v2 permissions
            'lxc.cgroup2.devices.allow: c 510:* rwm'  # cgroup v2 for nvidia-uvm
            'lxc.cgroup2.devices.allow: c 511:* rwm'  # cgroup v2 for nvidia-uvm (alternate)
            # Device bind mounts - pass GPU devices into container
            'lxc.mount.entry: /dev/nvidia0 dev/nvidia0 none bind,optional,create=file'
            'lxc.mount.entry: /dev/nvidiactl dev/nvidiactl none bind,optional,create=file'
            # CRITICAL: nvidia-uvm devices required for CUDA to work
            # Without these, ffmpeg will fail with "Cannot load libcuda.so.1"
            'lxc.mount.entry: /dev/nvidia-uvm dev/nvidia-uvm none bind,optional,create=file'
            'lxc.mount.entry: /dev/nvidia-uvm-tools dev/nvidia-uvm-tools none bind,optional,create=file'
            'lxc.mount.entry: /dev/nvidia-modeset dev/nvidia-modeset none bind,optional,create=file'
        )

        for gpu_line in "${gpu_passthrough_lines[@]}"; do
            if ! grep -Fxq "$gpu_line" "$LXC_CONFIG_PATH"; then
                echo "$gpu_line" >> "$LXC_CONFIG_PATH"
            fi
        done

        print_success "GPU passthrough configured for $CT_ID"
    fi
fi

# Ensure container is running
CT_STATUS=$(pct status "$CT_ID" | awk '{print $2}')
if [[ "$CT_STATUS" != "running" ]]; then
    print_info "Starting container"
    pct start "$CT_ID"
fi

# Verify container is ready
pct exec "$CT_ID" -- test -f /sbin/init
print_success "Container $CT_ID ready"

# Fix config permissions for LXC containers (idempotent)
fix_config_permissions

print_info "Provisioning container (stack: $STACK_NAME)"

pct exec "$CT_ID" -- sh -c "
set -e
STACK_NAME='${STACK_NAME}'

# Debian stacks: media (Jellyfin GPU), webtools (Chrome GPU), development (code-server)
if [ \"\$STACK_NAME\" = 'media' ] || [ \"\$STACK_NAME\" = 'webtools' ] || [ \"\$STACK_NAME\" = 'development' ]; then
    export DEBIAN_FRONTEND=noninteractive
    export DEBIAN_PRIORITY=critical
    export LC_ALL=C
    export LANG=C

    # Initial system update
    apt-get update -qq
    apt-get upgrade -y -qq
    apt-get install -y -qq debian-archive-keyring ca-certificates curl gnupg wget util-linux

    # Configure Debian repositories with non-free for GPU drivers
    cat > /etc/apt/sources.list.d/debian.sources <<'EOS'
Types: deb
URIs: http://deb.debian.org/debian
Suites: trixie trixie-updates
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

Types: deb
URIs: http://security.debian.org/debian-security
Suites: trixie-security
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
EOS

    # Development stack: code-server + AI CLI tools (no Docker, no GPU)
    if [ \"\$STACK_NAME\" = 'development' ]; then
        apt-get update -qq
        apt-get install -y -qq nodejs npm git python3 python3-pip bash nano vim htop

        # Configure npm
        npm config set fund false || true
        npm config set update-notifier false || true

        # Install AI CLI tools (optional - failures are non-critical)
        npm install -g @anthropic-ai/claude-code 2>/dev/null || echo 'Note: claude-code installation skipped'
        npm install -g @google/gemini-cli 2>/dev/null || echo 'Note: gemini-cli installation skipped'

        # Install code-server (latest version)
        CODE_SERVER_VERSION=\$(curl -fsSL https://api.github.com/repos/coder/code-server/releases/latest | grep tag_name | awk '{print substr(\$2, 3, length(\$2)-4)}')
        curl -fOL \"https://github.com/coder/code-server/releases/download/v\${CODE_SERVER_VERSION}/code-server_\${CODE_SERVER_VERSION}_amd64.deb\"
        dpkg -i code-server_\${CODE_SERVER_VERSION}_amd64.deb
        rm -f code-server_\${CODE_SERVER_VERSION}_amd64.deb

        # Configure code-server (no auth - homelab internal network only)
        mkdir -p /root/.config/code-server
        cat > /root/.config/code-server/config.yaml << 'EOFCS'
bind-addr: 0.0.0.0:8680
auth: none
cert: false
EOFCS

        # Enable code-server service
        systemctl enable --now code-server@root
    else
        # GPU stacks (media, webtools): Docker + NVIDIA

        # Add Docker's official GPG key and repository (following official docs)
        install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
        chmod a+r /etc/apt/keyrings/docker.asc

        # Add the repository to Apt sources using DEB822 format
        cat > /etc/apt/sources.list.d/docker.sources <<DOCKERSOURCES
Types: deb
URIs: https://download.docker.com/linux/debian
Suites: \$(. /etc/os-release && echo \$VERSION_CODENAME)
Components: stable
Architectures: \$(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
DOCKERSOURCES

        # Add NVIDIA container toolkit repository
        curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | gpg --yes --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
        curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
        sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
        tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
        
        # Install Docker + NVIDIA drivers and toolkit
        apt-get update -qq
        apt-get install -y -qq nvidia-driver nvidia-kernel-dkms docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin nvidia-container-toolkit
        
        # Configure NVIDIA runtime for Docker (unprivileged LXC compatible)
        nvidia-ctk runtime configure --runtime=docker --config=/etc/docker/daemon.json --set-as-default=false || true
        
        if [ -f /etc/nvidia-container-runtime/config.toml ]; then
            sed -i 's|^#no-cgroups = false|no-cgroups = true|' /etc/nvidia-container-runtime/config.toml || true
            sed -i 's|^no-cgroups = false|no-cgroups = true|' /etc/nvidia-container-runtime/config.toml || true
        fi
        
        # Ensure Docker daemon has NVIDIA runtime configured
        mkdir -p /etc/docker
        cat > /etc/docker/daemon.json << 'EOFDOCKER'
{
    \"runtimes\": {
        \"nvidia\": {
            \"path\": \"/usr/bin/nvidia-container-runtime\",
            \"runtimeArgs\": []
        }
    }
}
EOFDOCKER

        # Enable Docker
        systemctl enable docker --now
        systemctl restart docker
    fi

    # Common Debian configuration
    mkdir -p /etc/systemd/system/getty@tty1.service.d
    cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf << 'EOFLOGIN'
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin root --noclear %I \$TERM
EOFLOGIN

    # Set timezone
    timedatectl set-timezone Europe/Istanbul || true

    # Remove SSH for security
    systemctl disable ssh 2>/dev/null || true
    systemctl stop ssh 2>/dev/null || true
    apt-get remove -y -qq openssh-server 2>/dev/null || true

    # Cleanup
    apt-get -y autoremove -qq
    apt-get -y autoclean -qq

else
    # Alpine stacks: all other stacks (lighter, faster)
    apk update
    apk upgrade
    
    # Alpine stacks: Docker runtime
    apk add --no-cache docker docker-cli-compose util-linux
    
    # Add docker to boot runlevel and start
    rc-update add docker boot
    service docker start || rc-service docker start || true

    # Alpine autologin
    sed -i 's|^tty1::|#&|' /etc/inittab || true
    echo 'tty1::respawn:/sbin/agetty --autologin root --noclear tty1 38400 linux' >> /etc/inittab
    kill -HUP 1 || true
    
    # Alpine timezone setup
    apk add --no-cache tzdata || true
    ln -sf /usr/share/zoneinfo/Europe/Istanbul /etc/localtime || true

    # Remove openssh (reduce attack surface)
    apk del openssh || true
fi

# Common setup for all containers
echo 'export TERM=xterm-256color' >> /etc/profile
echo 'export TERM=xterm-256color' >> /root/.bashrc

# Remove root password (allow passwordless login)
passwd -d root || true

# Create hushlogin to suppress login messages  
touch /root/.hushlogin
"

print_success "Container [$STACK_NAME] created and ready"