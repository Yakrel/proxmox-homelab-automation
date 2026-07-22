#!/bin/bash

# Unified LXC creation + minimal provisioning (Alpine/Debian)
# Fail fast approach
set -euo pipefail

STACK_NAME=$1
WORK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)"

# --- Load Shared Functions ---
source "$WORK_DIR/scripts/helper-functions.sh"
trap cleanup_runtime_temp_files EXIT

# Load stack configuration using shared function
get_stack_config "$STACK_NAME"

LXC_RESTART_REQUIRED=false

reconcile_lxc_mount() {
    local mount_key="$1"
    local source_path="$2"
    local desired_value="${source_path},mp=${source_path},acl=1"
    local current_value

    current_value=$(pct config "$CT_ID" | awk -F': ' -v key="$mount_key" '$1 == key {print $2; exit}')
    if [[ "$current_value" != "$desired_value" ]]; then
        print_info "Reconciling ${mount_key} for LXC ${CT_ID}"
        pct set "$CT_ID" "-${mount_key}" "$desired_value"
        LXC_RESTART_REQUIRED=true
    fi
}

reconcile_lxc_device_block() {
    local config_path="/etc/pve/lxc/${CT_ID}.conf"
    local uvm_major="$1"
    local metadata_prefix="# PROXMOX-HOMELAB NVIDIA UVM MAJOR:"
    local metadata_line="${metadata_prefix} ${uvm_major}"
    local managed_major temp_config line
    local -a desired_lines=(
        'lxc.cgroup2.devices.allow: c 195:* rwm'
        "lxc.cgroup2.devices.allow: c ${uvm_major}:* rwm"
        'lxc.cgroup2.devices.allow: c 226:* rwm'
        'lxc.mount.entry: /dev/nvidia0 dev/nvidia0 none bind,optional,create=file'
        'lxc.mount.entry: /dev/nvidiactl dev/nvidiactl none bind,optional,create=file'
        'lxc.mount.entry: /dev/nvidia-uvm dev/nvidia-uvm none bind,optional,create=file'
        'lxc.mount.entry: /dev/nvidia-uvm-tools dev/nvidia-uvm-tools none bind,optional,create=file'
        'lxc.mount.entry: /dev/nvidia-modeset dev/nvidia-modeset none bind,optional,create=file'
        'lxc.mount.entry: /dev/dri dev/dri none bind,optional,create=dir'
    )

    if [[ "$STACK_NAME" == "media" ]]; then
        desired_lines+=(
            'lxc.cgroup2.devices.allow: c 10:229 rwm'
            'lxc.mount.entry: /dev/fuse dev/fuse none bind,create=file 0 0'
        )
    fi

    managed_major=$(awk -v prefix="$metadata_prefix" 'index($0, prefix) == 1 {print $NF; exit}' "$config_path")
    if [[ "$managed_major" == "$uvm_major" ]]; then
        local desired_state_present=true
        for line in "${desired_lines[@]}"; do
            if [[ $(grep -Fxc "$line" "$config_path") -ne 1 ]]; then
                desired_state_present=false
                break
            fi
        done
        [[ "$desired_state_present" == "true" ]] && return 0
    fi

    temp_config=$(mktemp /tmp/lxc-config.XXXXXX)
    register_runtime_temp_file "$temp_config"
    awk -v prefix="$metadata_prefix" -v old_major="$managed_major" '
        index($0, prefix) == 1 {next}
        $0 == "lxc.cgroup2.devices.allow: c 195:* rwm" {next}
        $0 == "lxc.cgroup2.devices.allow: c 226:* rwm" {next}
        $0 == "lxc.cgroup2.devices.allow: c 10:229 rwm" {next}
        old_major != "" && $0 == "lxc.cgroup2.devices.allow: c " old_major ":* rwm" {next}
        $0 ~ /^lxc\.mount\.entry: \/dev\/(nvidia0|nvidiactl|nvidia-uvm|nvidia-uvm-tools|nvidia-modeset|dri|fuse) / {next}
        {print}
    ' "$config_path" > "$temp_config"
    printf '\n%s\n' "$metadata_line" >> "$temp_config"
    for line in "${desired_lines[@]}"; do
        printf '%s\n' "$line" >> "$temp_config"
    done
    cat "$temp_config" > "$config_path"
    LXC_RESTART_REQUIRED=true
}

# Get latest template based on stack type - ensures we always use the newest available
get_latest_template() {
    local template_type=$1

    # Keep stdout quiet because this function returns the template name.
    pveam update >/dev/null

    # Fetch both available and local templates in one call each (optimization: reduce pveam calls)
    local available_output local_output
    available_output=$(pveam available)
    local_output=$(pveam list "$TEMPLATE_POOL")

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
        local_template=$(pveam list "$TEMPLATE_POOL" | awk "/${template_type}/ {print \$1}" | sort -V | tail -n 1 | sed "s|^${TEMPLATE_POOL}:vztmpl/||")
        print_success "Downloaded template: $local_template" >&2
    else
        print_info "Using up-to-date template: $local_template" >&2
    fi

    echo "$local_template"
}

# Container exists check - handle gracefully for idempotency
if check_container_exists "$CT_ID"; then
    print_info "Container $CT_ID exists, verifying state"
    SKIP_CREATION=true
else
    SKIP_CREATION=false
    
    # Choose template based on stack type - always use latest
    # Debian: media (Jellyfin GPU), desktop (Brave GPU), dev (code-server)
    # Alpine: all other stacks (lighter, faster) — including ai (OpenRouter, no GPU needed)
    if [ "$STACK_NAME" = "media" ] || [ "$STACK_NAME" = "desktop" ] || [ "$STACK_NAME" = "dev" ]; then
        LATEST_TEMPLATE=$(get_latest_template "debian-.*-standard")
    else
        LATEST_TEMPLATE=$(get_latest_template "alpine-.*-default")
    fi
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
fi

# Storage mounts are host infrastructure and must be reconciled for both new
# and existing containers. OS/package provisioning remains creation-only.
reconcile_lxc_mount mp0 "$DATAPOOL"
reconcile_lxc_mount mp1 "$FASTPOOL"

if [[ "$STACK_NAME" == "media" ]] || [[ "$STACK_NAME" == "desktop" ]]; then
    target_version=$(get_nvidia_driver_version "$WORK_DIR/stacks.yaml")
    [[ -n "$target_version" ]] || { print_error "NVIDIA driver version is not configured"; exit 1; }

    configure_nvidia_host_runtime "$target_version" true
    ensure_nvidia_driver_runfile "$target_version"

    uvm_major=$(awk '$2 == "nvidia-uvm" {print $1; exit}' /proc/devices)
    [[ -n "$uvm_major" ]] || { print_error "Could not detect nvidia-uvm device major"; exit 1; }
    reconcile_lxc_device_block "$uvm_major"
    print_success "GPU passthrough configuration reconciled for LXC $CT_ID"
fi

# Ensure container is running (Start AFTER all config changes)
CT_STATUS=$(pct status "$CT_ID" | awk '{print $2}')

if [[ "$CT_STATUS" == "running" && "$LXC_RESTART_REQUIRED" == "true" && "$SKIP_CREATION" == "true" ]]; then
    print_info "Restarting LXC $CT_ID to apply host configuration changes"
    pct reboot "$CT_ID" --timeout 60
elif [[ "$CT_STATUS" != "running" ]]; then
    print_info "Starting container"
    pct start "$CT_ID"
fi

# Verify container is ready
pct exec "$CT_ID" -- test -f /sbin/init
print_success "Container $CT_ID ready"

# Install NVIDIA user-space drivers inside the container (if applicable)
if [[ "$STACK_NAME" == "media" ]] || [[ "$STACK_NAME" == "desktop" ]]; then
    print_info "Configuring NVIDIA user-space drivers inside container..."

    # Keep both the script and unit current on existing containers as well.
    pct push "$CT_ID" "$WORK_DIR/scripts/nvidia-userspace-sync.sh" "/usr/local/bin/nvidia-userspace-sync.sh"
    pct exec "$CT_ID" -- bash -c 'chmod 0755 /usr/local/bin/nvidia-userspace-sync.sh
cat > /etc/systemd/system/nvidia-userspace-sync.service << "EOF"
[Unit]
Description=Sync NVIDIA User-Space Libraries with Host
Before=docker.service
After=local-fs.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/nvidia-userspace-sync.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable nvidia-userspace-sync.service
systemctl restart nvidia-userspace-sync.service'
fi

# Prepare the dev stack's persistent bind sources on the host. Docker stacks
# prepare their own bind sources in docker-deployment.sh.
if [[ "$STACK_NAME" == "dev" ]]; then
    prepare_host_directory /fastpool/config/code-server
    prepare_host_directory /fastpool/config/code-server/config
    prepare_host_directory /fastpool/config/code-server/data
fi

# OS provisioning is an initial-build operation. Existing containers are
# treated as already provisioned; stack configuration is handled separately.
if [[ "$SKIP_CREATION" == "false" ]]; then
    SSH_ENABLED=""
    ROOT_PASSWORD=""
    if [[ -f "$WORK_DIR/.env" ]]; then
        SSH_ENABLED=$(get_env_value "SSH_ENABLED" "$WORK_DIR/.env")
        ROOT_PASSWORD=$(get_env_value "ROOT_PASSWORD" "$WORK_DIR/.env")
    fi

    print_info "Provisioning container OS (stack: $STACK_NAME)"

    # The command below is an embedded script interpreted inside the LXC.
    # shellcheck disable=SC1078,SC1079,SC1083,SC2140
    pct exec "$CT_ID" -- env SSH_ENABLED="${SSH_ENABLED}" ROOT_PASSWORD="${ROOT_PASSWORD}" sh -c "
set -e
STACK_NAME='${STACK_NAME}'

# Debian stacks: media (Jellyfin GPU), desktop (Brave GPU), dev (code-server)
if [ \"\$STACK_NAME\" = 'media' ] || [ \"\$STACK_NAME\" = 'desktop' ] || [ \"\$STACK_NAME\" = 'dev' ]; then
    export DEBIAN_FRONTEND=noninteractive
    export DEBIAN_PRIORITY=critical
    export LC_ALL=C
    export LANG=C

    apt-get update -qq
    apt-get upgrade -y -qq
    apt-get install -y -qq debian-archive-keyring ca-certificates curl gnupg wget util-linux
    if [ \"\$STACK_NAME\" = 'media' ]; then
        apt-get install -y -qq gocryptfs
    fi

    # Keep repositories aligned with the Debian template selected by pveam.
    . /etc/os-release
    debian_codename=\${VERSION_CODENAME:-}
    if [ -z \"\$debian_codename\" ]; then
        echo \"Could not determine Debian VERSION_CODENAME\" >&2
        exit 1
    fi

    cat > /etc/apt/sources.list.d/debian.sources <<EOS
Types: deb
URIs: http://deb.debian.org/debian
Suites: \${debian_codename} \${debian_codename}-updates
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

Types: deb
URIs: http://security.debian.org/debian-security
Suites: \${debian_codename}-security
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
EOS

    # Dev stack: code-server + AI CLI tools (no Docker, no GPU)
    if [ \"\$STACK_NAME\" = 'dev' ]; then
        nodesource_installer=\$(mktemp /tmp/nodesource-setup.XXXXXX)
        trap 'rm -f \"\$nodesource_installer\"' EXIT
        curl -fsSL https://deb.nodesource.com/setup_22.x -o \"\$nodesource_installer\"
        bash \"\$nodesource_installer\"
        rm -f \"\$nodesource_installer\"
        trap - EXIT
        apt-get install -y -qq nodejs git python3 python3-pip bash nano vim htop

        # Configure npm
        npm config set fund false
        npm config set update-notifier false

        # Configure locales for Turkish character and UTF-8 support
        apt-get install -y -qq locales
        sed -i 's/^# *en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
        sed -i 's/^# *tr_TR.UTF-8 UTF-8/tr_TR.UTF-8 UTF-8/' /etc/locale.gen
        locale-gen
        update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8

        # Ensure ~/.local/bin is in PATH for the installation session and future shells
        export PATH=\"/root/.local/bin:\$PATH\"
        if ! grep -q \"/root/.local/bin\" /root/.bashrc 2>/dev/null; then
            echo 'export PATH=\"/root/.local/bin:\$PATH\"' >> /root/.bashrc
        fi

        # Install code-server (latest version)
        # Using HTTP redirect to avoid GitHub API rate limits
        CODE_SERVER_URL=\$(curl -fsSLI -o /dev/null -w "%{url_effective}" https://github.com/coder/code-server/releases/latest)
        CODE_SERVER_TAG=\${CODE_SERVER_URL##*/}
        CODE_SERVER_VERSION=\${CODE_SERVER_TAG#v}
        CODE_SERVER_ARCH=\$(dpkg --print-architecture)
        case \"\$CODE_SERVER_ARCH\" in
            amd64|arm64) ;;
            *)
                echo \"Unsupported code-server architecture: \$CODE_SERVER_ARCH\" >&2
                exit 1
                ;;
        esac

        code_server_package=\$(mktemp --suffix=.deb /tmp/code-server.XXXXXX)
        trap 'rm -f \"\$code_server_package\"' EXIT
        curl -fsSL \
            \"https://github.com/coder/code-server/releases/download/v\${CODE_SERVER_VERSION}/code-server_\${CODE_SERVER_VERSION}_\${CODE_SERVER_ARCH}.deb\" \
            -o \"\$code_server_package\"
        dpkg -i \"\$code_server_package\"
        rm -f "\$code_server_package"
        trap - EXIT

        # Configure code-server (no auth - homelab internal network only)
        # Persist config and data (extensions/user-data) to fastpool
        mkdir -p /fastpool/config/code-server/config
        mkdir -p /fastpool/config/code-server/data
        
        mkdir -p /root/.config
        mkdir -p /root/.local/share

        # A regular directory here is unexpected; ln fails instead of deleting it.
        ln -sfnT /fastpool/config/code-server/config /root/.config/code-server
        ln -sfnT /fastpool/config/code-server/data /root/.local/share/code-server

        # Write config file through the persistent symlink.
        cat > /root/.config/code-server/config.yaml << 'EOFCS'
bind-addr: 0.0.0.0:8680
auth: none
cert: false
EOFCS

        # Enable code-server service
        systemctl enable --now code-server@root
    else
        # GPU stacks (media, desktop): Docker + NVIDIA

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
        
        # Install Docker + NVIDIA user-space libraries and toolkit (avoid compiling kernel modules inside LXC)
        apt-get update -qq
        apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin nvidia-container-toolkit
        
        # Configure no-cgroups for an unprivileged LXC.
        nvidia-ctk config --set nvidia-container-cli.no-cgroups=true --in-place
        
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
    timedatectl set-timezone Europe/Istanbul

    # Debian stacks do not expose SSH.
    apt-get remove -y -qq openssh-server

else
    # Alpine stacks: all other stacks (lighter, faster)
    apk update
    apk upgrade
    
    # Alpine stacks: Docker runtime + Bash (for script compatibility)
    apk add --no-cache docker docker-cli-compose util-linux bash
    
    # Add docker to boot runlevel and start
    rc-update add docker boot
    # Configure DOCKER_ULIMIT to bypass LXC resource limit restrictions
    if [ -f /etc/conf.d/docker ]; then
        grep -q DOCKER_ULIMIT /etc/conf.d/docker && sed -i '/DOCKER_ULIMIT/d' /etc/conf.d/docker
        echo 'DOCKER_ULIMIT=\" \"' >> /etc/conf.d/docker
    fi
    rc-service docker start

    # Alpine autologin
    sed -i 's|^tty1::|#&|' /etc/inittab
    grep -qF 'autologin root' /etc/inittab || echo 'tty1::respawn:/sbin/agetty --autologin root --noclear tty1 38400 linux' >> /etc/inittab
    kill -HUP 1
    
    # Alpine timezone setup
    apk add --no-cache tzdata
    ln -sf /usr/share/zoneinfo/Europe/Istanbul /etc/localtime

    # Configure SSH dynamically if requested
    if [ \"\$SSH_ENABLED\" = 'true' ] && [ -n \"\$ROOT_PASSWORD\" ]; then
        apk add --no-cache openssh
        rc-update add sshd default
        echo \"root:\$ROOT_PASSWORD\" | chpasswd
        sed -i 's/#PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
        rc-service sshd start
    fi
fi

# Common setup for all containers
printf '%s\n' 'export TERM=xterm-256color' > /etc/profile.d/term.sh

# Remove root password (allow passwordless login) if SSH password was not set
if [ \"\${SSH_ENABLED:-}\" != 'true' ] || [ -z \"\${ROOT_PASSWORD:-}\" ]; then
    passwd -d root
fi

# Create hushlogin to suppress login messages  
touch /root/.hushlogin
"

    print_success "Container OS provisioned"
else
    print_info "Container $CT_ID already provisioned; skipping OS package setup"
fi

# Dev CLI applications are application state, so reconcile them on both initial
# provisioning and selected-stack redeploys without repeating OS provisioning.
if [[ "$STACK_NAME" == "dev" ]]; then
    print_info "Reconciling dev CLI applications"

    agentmemory_env_file="${AGENTMEMORY_ENV_FILE:-}"
    [[ -f "$agentmemory_env_file" ]] || {
        print_error "Decrypted AI environment is required for the dev stack"
        exit 1
    }
    agentmemory_secret=$(get_env_value "AGENTMEMORY_SECRET" "$agentmemory_env_file")
    [[ -n "$agentmemory_secret" ]] || {
        print_error "AGENTMEMORY_SECRET is missing from the decrypted AI environment"
        exit 1
    }

    agentmemory_secret_file=$(mktemp /tmp/agentmemory-secret.XXXXXX)
    register_runtime_temp_file "$agentmemory_secret_file"
    (
        umask 077
        printf '%s\n' "$agentmemory_secret" > "$agentmemory_secret_file"
    )

    pct exec "$CT_ID" -- mkdir -p \
        /root/.config/agentmemory \
        /root/.pi/agent/extensions/agentmemory \
        /root/.local/bin
    pct push "$CT_ID" "$WORK_DIR/config/pi/pi-memory" /root/.local/bin/pi-memory
    pct push "$CT_ID" "$WORK_DIR/config/pi/agentmemory/index.ts" /root/.pi/agent/extensions/agentmemory/index.ts
    pct push "$CT_ID" "$WORK_DIR/config/pi/agentmemory/security.ts" /root/.pi/agent/extensions/agentmemory/security.ts
    pct push "$CT_ID" "$agentmemory_secret_file" /root/.config/agentmemory/secret
    pct exec "$CT_ID" -- bash -c 'printf "https://memory.byetgin.com" > /root/.config/agentmemory/url'
    pct exec "$CT_ID" -- chmod 0600 /root/.config/agentmemory/secret
    pct exec "$CT_ID" -- chmod 0644 /root/.pi/agent/extensions/agentmemory/index.ts
    pct exec "$CT_ID" -- chmod 0644 /root/.pi/agent/extensions/agentmemory/security.ts
    pct exec "$CT_ID" -- chmod 0755 /root/.local/bin/pi-memory

    pct exec "$CT_ID" -- bash -c '
set -e

# pct exec starts a non-login shell, so it does not load root'"'"'s .bashrc.
# Keep user-local and system-local CLI installations visible explicitly.
export HOME=/root
export PATH="/root/.local/share/pi-node/current/bin:/root/.local/bin:/usr/local/bin:$PATH"

# Use the GitHub CLI maintainers'"'"' official Debian repository. The Debian
# community package can lag behind versions supported by GitHub APIs.
install -m 0755 -d /etc/apt/keyrings
gh_keyring=$(mktemp /tmp/githubcli-keyring.XXXXXX)
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg -o "$gh_keyring"
install -m 0644 "$gh_keyring" /etc/apt/keyrings/githubcli-archive-keyring.gpg
rm -f "$gh_keyring"
chmod 0644 /etc/apt/keyrings/githubcli-archive-keyring.gpg
printf "deb [arch=%s signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main\n" "$(dpkg --print-architecture)" > /etc/apt/sources.list.d/github-cli.list

apt-get update -qq
apt-get install -y -qq gh

# npm is already part of the provisioned dev environment.
npm install --global @openai/codex
test -x "$(command -v codex)"

# Pi uses a native Agentmemory extension for automatic recall and capture.
# Keep the upstream integration current on every dev application reconcile.
pi_setup_tmp=$(mktemp -d /tmp/pi-setup.XXXXXX)
trap "rm -rf \"$pi_setup_tmp\"" EXIT
npm install --global --ignore-scripts --min-release-age=0 \
    --prefix /root/.local/share/pi-runtime --no-fund --no-audit \
    --loglevel=error --progress=false @earendil-works/pi-coding-agent
test -x /root/.local/share/pi-runtime/bin/pi
ln -sfnT /root/.local/share/pi-runtime/bin/pi /usr/local/bin/pi-real
/usr/local/bin/pi-real install npm:pi-antigravity
ln -sfnT /root/.local/bin/pi-memory /usr/local/bin/pi

# Install Antigravity directly, without CLI wrappers.
antigravity_installer=$(mktemp /tmp/antigravity-install.XXXXXX)
curl -fsSL https://antigravity.google/cli/install.sh -o "$antigravity_installer"
bash "$antigravity_installer" --dir /root/.local/lib/antigravity
test -x /root/.local/lib/antigravity/agy
ln -sfnT /root/.local/lib/antigravity/agy /usr/local/bin/agy
rm -f "$antigravity_installer"

for command_name in node npm git gh python3 bash nano vim htop agy codex pi code-server; do
    command -v "$command_name" || {
        echo "Missing required dev command: $command_name" >&2
        exit 1
    }
done

node --version
npm --version
git --version
gh --version
python3 --version
agy --version
codex --version
pi --version
code-server --version
systemctl is-enabled code-server@root
systemctl is-active code-server@root
'
    print_info "Running Pi Agentmemory integration smoke tests"
    if ! pct exec "$CT_ID" -- bash -c '
set -e
export HOME=/root
export PATH="/root/.local/bin:/usr/local/bin:$PATH"

agentmemory_url=$(cat /root/.config/agentmemory/url)
agentmemory_secret=$(cat /root/.config/agentmemory/secret)
smoke_output=$(mktemp /tmp/agentmemory-smoke-output.XXXXXX)
trap "rm -f \"$smoke_output\"" EXIT

run_agentmemory_smoke_test() {
    smoke_label=$1
    shift
    if ! "$@" > "$smoke_output" 2>&1; then
        printf "Agentmemory smoke check failed: %s\n" "$smoke_label" >&2
        cat "$smoke_output" >&2
        return 1
    fi
}

run_agentmemory_smoke_test "server health" \
    curl -fsS --max-time 10 \
        -H "Authorization: Bearer ${agentmemory_secret}" \
        "${agentmemory_url}/agentmemory/health"
run_agentmemory_smoke_test "Pi native extension" \
    /root/.local/bin/pi-memory --agentmemory-self-test

test "$(readlink -f "$(command -v codex)")" = "$(npm root -g)/@openai/codex/bin/codex.js"
test "$(readlink -f "$(command -v agy)")" = /root/.local/lib/antigravity/agy
! command -v opencode >/dev/null 2>&1
'; then
        print_error "Pi Agentmemory integration smoke tests failed; dev redeploy stopped"
        exit 1
    fi
    print_success "Pi Agentmemory integration smoke tests passed"
    print_success "Dev CLI applications reconciled and verified"
fi

print_success "Container [$STACK_NAME] created and ready"
