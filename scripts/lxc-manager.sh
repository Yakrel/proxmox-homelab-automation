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
    local read_only="${3:-false}"
    local desired_value="${source_path},mp=${source_path},acl=1"
    local current_value

    if [[ "$read_only" == "true" ]]; then
        desired_value+=",ro=1"
    fi

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
    local temp_config line
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

    local desired_state_present=true
    for line in "${desired_lines[@]}"; do
        if [[ $(grep -Fxc "$line" "$config_path") -ne 1 ]]; then
            desired_state_present=false
            break
        fi
    done
    [[ "$desired_state_present" == "true" ]] && return 0

    temp_config=$(mktemp /tmp/lxc-config.XXXXXX)
    register_runtime_temp_file "$temp_config"
    awk '
        /^lxc\.cgroup2\.devices\.allow: c ([0-9]+:\*|10:229) rwm$/ {next}
        /^lxc\.mount\.entry: \/dev\/(nvidia0|nvidiactl|nvidia-uvm|nvidia-uvm-tools|nvidia-modeset|dri|fuse) / {next}
        {print}
    ' "$config_path" > "$temp_config"

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
        --cmode shell \
        --net0 name=eth0,bridge="$NETWORK_BRIDGE",ip="$CT_IP"/24,gw="$NETWORK_GATEWAY" \
        --onboot 1 \
        --unprivileged 1 \
        --rootfs "$STORAGE_POOL":"$CT_DISK_GB" || { print_error "Failed to create container"; exit 1; }
fi

# The Proxmox console is the trusted administrative entry point. Shell mode
# opens a root shell directly and avoids distribution-specific getty handling.
# Reconcile it for existing containers as well as setting it at creation time.
pct set "$CT_ID" --cmode shell

# Limit every LXC to the shared paths used by its stack. In particular, never
# expose the fastpool root because it also contains the other LXC root filesystems.
if [[ "$STACK_NAME" != "gateway" ]]; then
    reconcile_lxc_mount mp0 "$DATAPOOL"
fi
reconcile_lxc_mount mp1 /fastpool/config

if [[ "$STACK_NAME" == "media" ]] || [[ "$STACK_NAME" == "desktop" ]]; then
    target_version=$(get_nvidia_driver_version "$WORK_DIR/stacks.yaml")
    target_sha256=$(get_nvidia_driver_sha256 "$WORK_DIR/stacks.yaml")
    [[ -n "$target_version" ]] || { print_error "NVIDIA driver version is not configured"; exit 1; }
    [[ "$target_sha256" =~ ^[a-f0-9]{64}$ ]] || { print_error "NVIDIA driver SHA-256 is not configured"; exit 1; }

    configure_nvidia_host_runtime "$target_version" true
    ensure_nvidia_driver_runfile "$target_version" "$target_sha256"

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

# Install NVIDIA user-space drivers inside the container (if applicable)
if [[ "$STACK_NAME" == "media" ]] || [[ "$STACK_NAME" == "desktop" ]]; then
    print_info "Configuring NVIDIA user-space drivers inside container..."

    # Keep both the script and unit current on existing containers as well.
    pct push "$CT_ID" "$WORK_DIR/scripts/nvidia-userspace-sync.sh" "/usr/local/bin/nvidia-userspace-sync.sh"
    # The expected checksum is passed as data to the container shell and written
    # into the unit; the shared runfile is verified again on every sync.
    # shellcheck disable=SC2016
    pct exec "$CT_ID" -- env "NVIDIA_DRIVER_SHA256=$target_sha256" bash -c 'chmod 0755 /usr/local/bin/nvidia-userspace-sync.sh
cat > /etc/systemd/system/nvidia-userspace-sync.service << EOF
[Unit]
Description=Sync NVIDIA User-Space Libraries with Host
Before=docker.service
After=local-fs.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/nvidia-userspace-sync.sh ${NVIDIA_DRIVER_SHA256}
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
    print_info "Provisioning container OS (stack: $STACK_NAME)"

    # The command below is an embedded script interpreted inside the LXC.
    # shellcheck disable=SC1078,SC1079,SC1083,SC2140
    pct exec "$CT_ID" -- sh -c "
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

        # Configure the official GitHub CLI repository during initial OS provisioning.
        install -m 0755 -d /etc/apt/keyrings
        gh_keyring=\$(mktemp /tmp/githubcli-keyring.XXXXXX)
        trap 'rm -f \"\$gh_keyring\"' EXIT
        curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg -o \"\$gh_keyring\"
        install -m 0644 \"\$gh_keyring\" /etc/apt/keyrings/githubcli-archive-keyring.gpg
        rm -f \"\$gh_keyring\"
        trap - EXIT
        printf 'deb [arch=%s signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main\n' \"\$(dpkg --print-architecture)\" \
            > /etc/apt/sources.list.d/github-cli.list
        apt-get update -qq
        apt-get install -y -qq gh

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

        # Prevent encryption key variables from leaking into shell history.
        # HISTCONTROL=ignoreboth: leading-space commands + consecutive duplicates are excluded.
        # HISTIGNORE: any command containing KEY= is excluded even without leading space.
        if ! grep -q 'HISTIGNORE' /root/.bashrc 2>/dev/null; then
            cat >> /root/.bashrc <<'HIST_EOF'
export HISTCONTROL=ignoreboth
export HISTIGNORE='*KEY=*'
HIST_EOF
        fi

        # Security boundary: code-server intentionally relies on the desktop-otp
        # SNO TOTP auth_request gate at its NPM proxy host; the three-attempt
        # limit is configured in docker/desktop/docker-compose.yml. NPM and PVE
        # firewall rules are live state, so block untrusted direct access to 8680.
        # The application package itself is reconciled after OS provisioning.
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

    # Set timezone
    timedatectl set-timezone Europe/Istanbul

    # Debian stacks do not expose SSH.
    apt-get remove -y -qq openssh-server

else
    # Alpine stacks: all other stacks (lighter, faster)
    apk update
    apk upgrade
    
    # Alpine stacks: Docker runtime + Bash (for script compatibility)
    apk add --no-cache docker docker-cli-compose bash
    
    # Add docker to boot runlevel and start
    rc-update add docker boot
    # Configure DOCKER_ULIMIT to bypass LXC resource limit restrictions
    if [ -f /etc/conf.d/docker ]; then
        grep -q DOCKER_ULIMIT /etc/conf.d/docker && sed -i '/DOCKER_ULIMIT/d' /etc/conf.d/docker
        echo 'DOCKER_ULIMIT=\" \"' >> /etc/conf.d/docker
    fi
    rc-service docker start

    # Alpine timezone setup
    apk add --no-cache tzdata
    ln -sf /usr/share/zoneinfo/Europe/Istanbul /etc/localtime

    # SSH is intentionally not installed. Hermes' web dashboard terminal
    # replaces the former AI-LXC Sshwifty access path.
fi

# Common setup for all containers
printf '%s\n' 'export TERM=xterm-256color' > /etc/profile.d/term.sh
# Proxmox shell-mode console bypasses guest authentication, so keep the root
# password locked against guest login paths.
passwd -l root

# Create hushlogin to suppress login messages  
touch /root/.hushlogin
"

    print_success "Container OS provisioned"
fi

# Proxmox shell mode launches the root account's configured shell directly.
# Alpine defaults to BusyBox ash with a minimal "/ #" prompt, so use the Bash
# package already provisioned above and match Debian's informative root prompt.
if [[ "$STACK_NAME" != "media" && "$STACK_NAME" != "desktop" && "$STACK_NAME" != "dev" ]]; then
    pct exec "$CT_ID" -- sh -c '
set -e
sed -i "/^root:/ s|:[^:]*$|:/bin/bash|" /etc/passwd
quote=$(printf "\047")
printf "PS1=%s%s%s\n" "$quote" "\\u@\\h:\\w\\\$ " "$quote" > /root/.bashrc
'
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
    validate_agentmemory_secret_value "$agentmemory_secret" || {
        print_error "AGENTMEMORY_SECRET must be exactly 64 hexadecimal characters"
        exit 1
    }

    agentmemory_secret_file=$(mktemp /tmp/agentmemory-secret.XXXXXX)
    register_runtime_temp_file "$agentmemory_secret_file"
    (
        umask 077
        printf '%s\n' "$agentmemory_secret" > "$agentmemory_secret_file"
    )
    unset agentmemory_secret

    pct exec "$CT_ID" -- mkdir -p \
        /root/.config/agentmemory \
        /root/.pi/agent/extensions/agentmemory \
        /root/.local/bin
    pct push "$CT_ID" "$WORK_DIR/config/pi/pi-memory" /root/.local/bin/pi-memory
    pct push "$CT_ID" "$WORK_DIR/config/pi/agentmemory/index.ts" /root/.pi/agent/extensions/agentmemory/index.ts
    pct push "$CT_ID" "$WORK_DIR/config/pi/agentmemory/client.ts" /root/.pi/agent/extensions/agentmemory/client.ts
    pct push "$CT_ID" "$WORK_DIR/config/pi/agentmemory/security.ts" /root/.pi/agent/extensions/agentmemory/security.ts
    pct push "$CT_ID" "$agentmemory_secret_file" /root/.config/agentmemory/secret
    pct exec "$CT_ID" -- bash -c 'printf "https://memory.byetgin.com\n" > /root/.config/agentmemory/url'
    pct exec "$CT_ID" -- chmod 0600 /root/.config/agentmemory/secret
    pct exec "$CT_ID" -- chmod 0644 /root/.pi/agent/extensions/agentmemory/index.ts
    pct exec "$CT_ID" -- chmod 0644 /root/.pi/agent/extensions/agentmemory/client.ts
    pct exec "$CT_ID" -- chmod 0644 /root/.pi/agent/extensions/agentmemory/security.ts
    pct exec "$CT_ID" -- chmod 0755 /root/.local/bin/pi-memory
    rm -f -- "$agentmemory_secret_file"

    # Variables in this single-quoted script expand inside the container.
    # shellcheck disable=SC2016
    pct exec "$CT_ID" -- bash -c '
set -e

# pct exec starts a non-login shell, so the root .bashrc is not loaded.
# Keep user-local and system-local CLI installations visible explicitly.
export HOME=/root
export PATH="/root/.local/share/pi-node/current/bin:/root/.local/bin:/usr/local/bin:$PATH"

# Keep code-server current with the other dev applications without repeating
# repository or base-package provisioning.
CODE_SERVER_URL=$(curl -fsSLI -o /dev/null -w "%{url_effective}" https://github.com/coder/code-server/releases/latest)
CODE_SERVER_TAG=${CODE_SERVER_URL##*/}
CODE_SERVER_VERSION=${CODE_SERVER_TAG#v}
CURRENT_CODE_SERVER_VERSION=""
if command -v code-server >/dev/null 2>&1; then
    CURRENT_CODE_SERVER_VERSION=$(code-server --version | awk "NR == 1 {print \$1}")
fi
if [ "$CURRENT_CODE_SERVER_VERSION" != "$CODE_SERVER_VERSION" ]; then
    CODE_SERVER_ARCH=$(dpkg --print-architecture)
    case "$CODE_SERVER_ARCH" in
        amd64|arm64) ;;
        *)
            echo "Unsupported code-server architecture: $CODE_SERVER_ARCH" >&2
            exit 1
            ;;
    esac
    code_server_package=$(mktemp --suffix=.deb /tmp/code-server.XXXXXX)
    cleanup_code_server_package() { rm -f "$code_server_package"; }
    trap cleanup_code_server_package EXIT
    curl -fsSL \
        "https://github.com/coder/code-server/releases/download/v${CODE_SERVER_VERSION}/code-server_${CODE_SERVER_VERSION}_${CODE_SERVER_ARCH}.deb" \
        -o "$code_server_package"
    dpkg -i "$code_server_package"
    rm -f "$code_server_package"
    trap - EXIT
fi
systemctl enable --now code-server@root

# npm is already part of the provisioned dev environment.
npm install --global @openai/codex
test -x "$(command -v codex)"

# Pi uses a native Agentmemory extension for automatic recall and capture.
# Keep the upstream integration current on every dev application reconcile.
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
    command -v "$command_name" >/dev/null 2>&1 || {
        echo "Missing required dev command: $command_name" >&2
        exit 1
    }
done

systemctl is-enabled code-server@root >/dev/null 2>&1
systemctl is-active code-server@root >/dev/null 2>&1
test "$(readlink -f "$(command -v codex)")" = "$(npm root -g)/@openai/codex/bin/codex.js"
test "$(readlink -f "$(command -v agy)")" = /root/.local/lib/antigravity/agy
test "$(readlink -f "$(command -v pi)")" = /root/.local/bin/pi-memory
test -s /root/.config/agentmemory/secret
test -s /root/.config/agentmemory/url
! command -v opencode >/dev/null 2>&1
'
    print_success "Dev CLI applications reconciled"
fi

print_success "Container [$STACK_NAME] ready"
