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

    # Get the latest available template name from repository
    local latest_available
    latest_available=$(pveam available 2>/dev/null | awk "/${template_type}/ {print \$2}" | sort -V | tail -n 1)
    [[ -n "$latest_available" ]] || { print_error "No ${template_type} template available"; exit 1; }

    # Check if we already have this exact template locally
    local local_template
    local_template=$(pveam list "$STORAGE_POOL" 2>/dev/null | awk "/${template_type}/ {print \$1}" | sort -V | tail -n 1 | sed "s|^${STORAGE_POOL}:vztmpl/||")

    # If local template doesn't match latest available, download the new one
    if [[ "$local_template" != "$latest_available" ]]; then
        print_info "Downloading latest ${template_type} template: $latest_available" >&2
        pveam download "$STORAGE_POOL" "$latest_available" >&2
        # After download, get the actual filename from local storage
        local_template=$(pveam list "$STORAGE_POOL" 2>/dev/null | awk "/${template_type}/ {print \$1}" | sort -V | tail -n 1 | sed "s|^${STORAGE_POOL}:vztmpl/||")
        print_success "Downloaded template: $local_template" >&2
    else
        print_info "Using up-to-date template: $local_template" >&2
    fi

    echo "$local_template"
}

# Choose template based on stack type - always use latest
if [ "$STACK_NAME" = "media" ]; then
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
    # This configuration enables NVIDIA GPU (GTX 970) passthrough to unprivileged LXC container
    # for Jellyfin hardware transcoding (decode/scale/encode)
    if [[ "$STACK_NAME" == "media" ]]; then
        print_info "Configuring GPU passthrough for media container (cgroup v2 method)"

        # Create systemd service for persistent NVIDIA device setup (survives reboots)
        # This ensures nvidia-uvm module is loaded and devices are created on every boot
        print_info "Creating systemd service for persistent NVIDIA device setup"
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
            print_warning "nvidia-uvm device not found after service start - GPU transcoding may not work"
        else
            print_success "nvidia-uvm devices created successfully"
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

# Ensure container is running (both new and existing containers)
print_info "Ensuring container is running"
CT_STATUS=$(pct status "$CT_ID" | awk '{print $2}')
if [[ "$CT_STATUS" != "running" ]]; then
    print_info "Starting container"
    pct start "$CT_ID"
fi

# Verify container is ready (both new and existing containers)
print_info "Verifying container is ready"
pct exec "$CT_ID" -- test -f /sbin/init
print_success "Container $CT_ID is ready"

# Fix config permissions for LXC containers (idempotent)
fix_config_permissions

print_info "Provisioning container (stack: $STACK_NAME)"

pct exec "$CT_ID" -- sh -c "
set -e
STACK_NAME='${STACK_NAME}'

if [ \"\$STACK_NAME\" = 'media' ]; then
    # Media Stack: Debian with Docker and latest NVIDIA drivers for GTX 970 transcoding
    # Set environment to prevent interactive prompts and locale issues
    export DEBIAN_FRONTEND=noninteractive
    export DEBIAN_PRIORITY=critical
    export LC_ALL=C
    export LANG=C

    # Initial update and install core dependencies
    apt-get update
    apt-get upgrade -y
    apt-get install -y debian-archive-keyring ca-certificates curl gnupg wget util-linux

    # Add all repositories at once (Debian non-free + Docker + NVIDIA)
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

    # Add Docker GPG key and repository
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc
    DEBIAN_CODENAME=\$(. /etc/os-release && echo \$VERSION_CODENAME)
    echo \"deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \$DEBIAN_CODENAME stable\" | tee /etc/apt/sources.list.d/docker.list > /dev/null

    # Add NVIDIA container toolkit repository
    rm -f /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
    curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
    curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
    sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
    tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

    # Single update after all repos added, then install everything
    apt-get update
    apt-get install -y nvidia-driver nvidia-kernel-dkms docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin nvidia-container-toolkit

    # Relax NVIDIA runtime cgroup requirements for unprivileged LXC containers using nvidia-ctk
    # Configure NVIDIA Container Toolkit for unprivileged containers
    nvidia-ctk runtime configure \
        --runtime=docker \
        --config=/etc/docker/daemon.json \
        --set-as-default=false || true
    
    # Configure NVIDIA runtime config if it exists
    if [ -f /etc/nvidia-container-runtime/config.toml ]; then
        # Explicitly set no-cgroups = true for unprivileged LXC
        sed -i 's|^#no-cgroups = false|no-cgroups = true|' /etc/nvidia-container-runtime/config.toml || true
        sed -i 's|^no-cgroups = false|no-cgroups = true|' /etc/nvidia-container-runtime/config.toml || true
        sed -i 's#^debug = .*#debug = "/var/log/nvidia-container-runtime.log"#' /etc/nvidia-container-runtime/config.toml || true
    fi

    # Configure Docker daemon with NVIDIA runtime available (default stays runc)
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

    # Enable and restart Docker to apply changes
    systemctl enable docker --now
    systemctl restart docker
    
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
    apt-get -y autoremove
    apt-get -y autoclean

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
        
        # Add docker to boot runlevel and start
        rc-update add docker boot
        service docker start || rc-service docker start || true
    fi
fi

# Common setup for all containers  
if [ \"\$STACK_NAME\" != 'media' ]; then
    # Alpine autologin
    sed -i 's|^tty1::|#&|' /etc/inittab || true
    echo 'tty1::respawn:/sbin/agetty --autologin root --noclear tty1 38400 linux' >> /etc/inittab
    kill -HUP 1 || true
    
    # Alpine timezone setup
    apk add --no-cache tzdata || true
    ln -sf /usr/share/zoneinfo/Europe/Istanbul /etc/localtime || true
else
    # Debian timezone setup (Media only)
    timedatectl set-timezone Europe/Istanbul || true
fi

# Set terminal colors for all containers (fix colorless terminal issue)
echo 'export TERM=xterm-256color' >> /etc/profile
echo 'export TERM=xterm-256color' >> /root/.bashrc

# Remove root password (allow passwordless login)
passwd -d root || true

# Create hushlogin to suppress login messages  
touch /root/.hushlogin

# Remove openssh if present (reduce attack surface)
if [ \"\$STACK_NAME\" != 'media' ]; then
    apk del openssh || true
else
    apt-get remove -y openssh-server || true
fi
"

print_success "Container [$STACK_NAME] created and ready"