#!/bin/bash

# Unified LXC creation + minimal provisioning (Alpine/Debian)
# Fail fast approach
set -euo pipefail

STACK_NAME=$1
WORK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)"

# --- Load Shared Functions ---
# shellcheck source=scripts/helper-functions.sh
source "$WORK_DIR/scripts/helper-functions.sh"
trap cleanup_runtime_temp_files EXIT

# Load stack configuration using shared function
get_stack_config "$STACK_NAME"

LXC_RESTART_REQUIRED=false

reconcile_stack_firewall() {
    local firewall_path="/etc/pve/firewall/${CT_ID}.fw"
    local firewall_tmp current_net desired_net

    case "$STACK_NAME" in
        gateway|media|utility|dev|desktop|ai|gaming) ;;
        *) return 0 ;;
    esac

    firewall_tmp=$(mktemp "/tmp/${STACK_NAME}-firewall.XXXXXX")
    register_runtime_temp_file "$firewall_tmp"
    cat > "$firewall_tmp" <<'EOF'
[OPTIONS]
enable: 1
policy_in: DROP
policy_out: ACCEPT

[RULES]
EOF

    case "$STACK_NAME" in
        gateway)
            cat >> "$firewall_tmp" <<'EOF'
# Local Subnet Services (192.168.1.0/24)
# AdGuard Home DNS
IN ACCEPT -source 192.168.1.0/24 -p tcp -dport 53
IN ACCEPT -source 192.168.1.0/24 -p udp -dport 53
# Nginx Proxy Manager (HTTP / HTTPS Ingress)
IN ACCEPT -source 192.168.1.0/24 -p tcp -dport 80
IN ACCEPT -source 192.168.1.0/24 -p tcp -dport 443
# Admin Web UIs (81: NPM Admin, 3000: AdGuard Home Web UI)
# Management Host (192.168.1.10)
IN ACCEPT -source 192.168.1.10 -p tcp -dport 81
IN ACCEPT -source 192.168.1.10 -p tcp -dport 3000
# Workstation (192.168.1.20)
IN ACCEPT -source 192.168.1.20 -p tcp -dport 81
IN ACCEPT -source 192.168.1.20 -p tcp -dport 3000
# Laptop (192.168.1.21)
IN ACCEPT -source 192.168.1.21 -p tcp -dport 81
IN ACCEPT -source 192.168.1.21 -p tcp -dport 3000
# Desktop Container / Homepage Dashboard (192.168.1.103)
IN ACCEPT -source 192.168.1.103 -p tcp -dport 81
IN ACCEPT -source 192.168.1.103 -p tcp -dport 3000
EOF
            ;;
        media)
            cat >> "$firewall_tmp" <<'EOF'
# Reverse Proxy Ingress from Gateway NPM (192.168.1.100)
# 2283: Immich Server | 5055: Jellyseerr | 6767: Bazarr     | 6868: Profilarr
# 7878: Radarr        | 8080: qBittorrent Web UI | 8096: Jellyfin   | 8265: Tdarr Web UI
# 8989: Sonarr        | 9696: Prowlarr  | 11011: Cleanuparr
IN ACCEPT -source 192.168.1.100 -p tcp -dport 2283
IN ACCEPT -source 192.168.1.100 -p tcp -dport 5055
IN ACCEPT -source 192.168.1.100 -p tcp -dport 6767
IN ACCEPT -source 192.168.1.100 -p tcp -dport 6868
IN ACCEPT -source 192.168.1.100 -p tcp -dport 7878
IN ACCEPT -source 192.168.1.100 -p tcp -dport 8080
IN ACCEPT -source 192.168.1.100 -p tcp -dport 8096
IN ACCEPT -source 192.168.1.100 -p tcp -dport 8265
IN ACCEPT -source 192.168.1.100 -p tcp -dport 8989
IN ACCEPT -source 192.168.1.100 -p tcp -dport 9696
IN ACCEPT -source 192.168.1.100 -p tcp -dport 11011
# Desktop Container / Homepage Dashboard Widgets & SiteMonitors (192.168.1.103)
IN ACCEPT -source 192.168.1.103 -p tcp -dport 2283
IN ACCEPT -source 192.168.1.103 -p tcp -dport 5055
IN ACCEPT -source 192.168.1.103 -p tcp -dport 6767
IN ACCEPT -source 192.168.1.103 -p tcp -dport 6868
IN ACCEPT -source 192.168.1.103 -p tcp -dport 7878
IN ACCEPT -source 192.168.1.103 -p tcp -dport 8080
IN ACCEPT -source 192.168.1.103 -p tcp -dport 8096
IN ACCEPT -source 192.168.1.103 -p tcp -dport 8265
IN ACCEPT -source 192.168.1.103 -p tcp -dport 8989
IN ACCEPT -source 192.168.1.103 -p tcp -dport 9696
IN ACCEPT -source 192.168.1.103 -p tcp -dport 11011
# Utility Container / Repackarr Integration (192.168.1.102)
# 8080: qBittorrent Web UI | 9696: Prowlarr API
IN ACCEPT -source 192.168.1.102 -p tcp -dport 8080
IN ACCEPT -source 192.168.1.102 -p tcp -dport 9696
# qBittorrent Public Peer Listening Port (P2P Inbound)
IN ACCEPT -p tcp -dport 6881
IN ACCEPT -p udp -dport 6881
EOF
            ;;
        utility)
            cat >> "$firewall_tmp" <<'EOF'
# Reverse Proxy Ingress from Gateway NPM (192.168.1.100)
# 3080: Karakeep | 5000: ChangeDetection | 8081: MeTube | 8090: Repackarr | 8095: Beszel | 9898: Backrest
IN ACCEPT -source 192.168.1.100 -p tcp -dport 3080
IN ACCEPT -source 192.168.1.100 -p tcp -dport 5000
IN ACCEPT -source 192.168.1.100 -p tcp -dport 8081
IN ACCEPT -source 192.168.1.100 -p tcp -dport 8090
IN ACCEPT -source 192.168.1.100 -p tcp -dport 8095
IN ACCEPT -source 192.168.1.100 -p tcp -dport 9898
# Desktop Container / Homepage Dashboard and Beszel UI (192.168.1.103)
IN ACCEPT -source 192.168.1.103 -p tcp -dport 3080
IN ACCEPT -source 192.168.1.103 -p tcp -dport 5000
IN ACCEPT -source 192.168.1.103 -p tcp -dport 8081
IN ACCEPT -source 192.168.1.103 -p tcp -dport 8090
IN ACCEPT -source 192.168.1.103 -p tcp -dport 8095
IN ACCEPT -source 192.168.1.103 -p tcp -dport 9898
# Beszel agent outbound WebSocket registration
IN ACCEPT -source 192.168.1.10 -p tcp -dport 8095
IN ACCEPT -source 192.168.1.101 -p tcp -dport 8095
IN ACCEPT -source 192.168.1.104 -p tcp -dport 8095
IN ACCEPT -source 192.168.1.105 -p tcp -dport 8095
IN ACCEPT -source 192.168.1.106 -p tcp -dport 8095
# Multicast membership queries from the LAN IGMP querier
IN ACCEPT -source 192.168.1.1 -p igmp
# Workstation (192.168.1.20)
# Beszel UI
IN ACCEPT -source 192.168.1.20 -p tcp -dport 8095
# Samba File Sharing (NetBIOS & SMB)
IN ACCEPT -source 192.168.1.20 -p udp -dport 137
IN ACCEPT -source 192.168.1.20 -p udp -dport 138
IN ACCEPT -source 192.168.1.20 -p tcp -dport 139
IN ACCEPT -source 192.168.1.20 -p tcp -dport 445
# WS-Discovery (Windows & Linux/KDE WSD Auto-Discovery)
IN ACCEPT -source 192.168.1.20 -p udp -dport 3702
IN ACCEPT -source 192.168.1.20 -p tcp -dport 3702
IN ACCEPT -source 192.168.1.20 -p tcp -dport 5357
# mDNS / Avahi (Linux/KDE Dolphin & macOS Finder Bonjour Auto-Discovery)
IN ACCEPT -source 192.168.1.20 -p udp -dport 5353
# LLMNR Name Resolution
IN ACCEPT -source 192.168.1.20 -p udp -dport 5355
IN ACCEPT -source 192.168.1.20 -p tcp -dport 5355
# JDownloader Click'n'Load
IN ACCEPT -source 192.168.1.20 -p tcp -dport 9666
# Laptop (192.168.1.21)
# Beszel UI
IN ACCEPT -source 192.168.1.21 -p tcp -dport 8095
# Samba File Sharing (NetBIOS & SMB)
IN ACCEPT -source 192.168.1.21 -p udp -dport 137
IN ACCEPT -source 192.168.1.21 -p udp -dport 138
IN ACCEPT -source 192.168.1.21 -p tcp -dport 139
IN ACCEPT -source 192.168.1.21 -p tcp -dport 445
# WS-Discovery (Windows & Linux/KDE WSD Auto-Discovery)
IN ACCEPT -source 192.168.1.21 -p udp -dport 3702
IN ACCEPT -source 192.168.1.21 -p tcp -dport 3702
IN ACCEPT -source 192.168.1.21 -p tcp -dport 5357
# mDNS / Avahi (Linux/KDE Dolphin & macOS Finder Bonjour Auto-Discovery)
IN ACCEPT -source 192.168.1.21 -p udp -dport 5353
# LLMNR Name Resolution
IN ACCEPT -source 192.168.1.21 -p udp -dport 5355
IN ACCEPT -source 192.168.1.21 -p tcp -dport 5355
EOF
            ;;
        dev)
            cat >> "$firewall_tmp" <<'EOF'
# Code-Server (VS Code Web IDE - 8680)
# Reverse Proxy Ingress from Gateway NPM (192.168.1.100)
IN ACCEPT -source 192.168.1.100 -p tcp -dport 8680
EOF
            ;;
        desktop)
            cat >> "$firewall_tmp" <<'EOF'
# Reverse Proxy Ingress from Gateway NPM (192.168.1.100)
# 3000: Homepage Dashboard           | 5800: Desktop Workspace HTTPS Web UI
# 8080: Apache Guacamole Web UI      | 7079: Desktop Workspace OTP Gate
# 5984: CouchDB (Obsidian LiveSync)  | 8201: Vaultwarden Password Manager
# 7681: Sshwifty Web Terminal        | 5232: Radicale CalDAV/CardDAV
IN ACCEPT -source 192.168.1.100 -p tcp -dport 3000
IN ACCEPT -source 192.168.1.100 -p tcp -dport 5800
IN ACCEPT -source 192.168.1.100 -p tcp -dport 8080
IN ACCEPT -source 192.168.1.100 -p tcp -dport 7079
IN ACCEPT -source 192.168.1.100 -p tcp -dport 5984
IN ACCEPT -source 192.168.1.100 -p tcp -dport 8201
IN ACCEPT -source 192.168.1.100 -p tcp -dport 7681
IN ACCEPT -source 192.168.1.100 -p tcp -dport 5232
EOF
            ;;
        ai)
            cat >> "$firewall_tmp" <<'EOF'
# Reverse Proxy Ingress from Gateway NPM (192.168.1.100)
# 9119: Hermes Agent Dashboard | 20128: OmniRoute AI Gateway API/UI | 9999: Hindsight Memory Dashboard
IN ACCEPT -source 192.168.1.100 -p tcp -dport 9119
IN ACCEPT -source 192.168.1.100 -p tcp -dport 20128
IN ACCEPT -source 192.168.1.100 -p tcp -dport 9999
# Hindsight Memory API Direct Access (Port 8888)
# Workstation (192.168.1.20)
IN ACCEPT -source 192.168.1.20 -p tcp -dport 8888
# Laptop (192.168.1.21)
IN ACCEPT -source 192.168.1.21 -p tcp -dport 8888
# Dev Container / Agent Workspaces (192.168.1.105)
IN ACCEPT -source 192.168.1.105 -p tcp -dport 8888
EOF
            ;;
        gaming)
            cat >> "$firewall_tmp" <<'EOF'
# Palworld Dedicated Server (8211: UDP Game, 27015: UDP Query)
# Local Subnet (192.168.1.0/24)
IN ACCEPT -source 192.168.1.0/24 -p udp -dport 8211
IN ACCEPT -source 192.168.1.0/24 -p udp -dport 27015
# Public / Inbound Game Ports (if forwarded by router/firewall)
IN ACCEPT -p udp -dport 8211
IN ACCEPT -p udp -dport 27015
EOF
            ;;
    esac

    if [[ ! -f "$firewall_path" ]] || ! cmp -s "$firewall_tmp" "$firewall_path"; then
        print_info "Reconciling firewall rules for $STACK_NAME LXC $CT_ID"
        cat "$firewall_tmp" > "$firewall_path"
    fi

    current_net=$(pct config "$CT_ID" | awk -F': ' '$1 == "net0" {print $2; exit}')
    [[ -n "$current_net" ]] || { print_error "LXC $CT_ID has no net0 configuration"; exit 1; }
    if [[ "$current_net" == *"firewall="* ]]; then
        desired_net=$(sed -E 's/(^|,)firewall=[^,]*/\1firewall=1/' <<< "$current_net")
    else
        desired_net="${current_net},firewall=1"
    fi
    if [[ "$current_net" != "$desired_net" ]]; then
        pct set "$CT_ID" --net0 "$desired_net"
    fi

    # Guest firewall rules are enforced only while the Datacenter firewall is
    # enabled. Node firewalling remains independently disabled unless it is
    # explicitly configured by the operator, so this does not filter host SSH
    # or the Proxmox web interface.
    pvesh set /cluster/firewall/options --enable 1
}

reconcile_dev_features() {
    [[ "$STACK_NAME" == "dev" ]] || return 0

    local current_features
    current_features=$(pct config "$CT_ID" | awk -F': ' '$1 == "features" {print $2; exit}')
    if [[ "$current_features" != "nesting=1" ]]; then
        print_info "Reconciling systemd nesting for Dev LXC $CT_ID"
        pct set "$CT_ID" --features nesting=1
        LXC_RESTART_REQUIRED=true
    fi
}

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

get_host_template_arch() {
    local template_arch
    template_arch=$(dpkg --print-architecture)

    case "$template_arch" in
        amd64|arm64) ;;
        *)
            print_error "Unsupported Proxmox host architecture: $template_arch"
            exit 1
            ;;
    esac

    printf '%s\n' "$template_arch"
}

# Get latest template based on stack type - ensures we always use the newest
# template that matches the Proxmox host architecture.
get_latest_template() {
    local template_type=$1
    local template_arch
    template_arch=$(get_host_template_arch)

    # Keep stdout quiet because this function returns the template name.
    pveam update >/dev/null

    # Fetch both available and local templates in one call each (optimization: reduce pveam calls)
    local available_output local_output
    available_output=$(pveam available)
    local_output=$(pveam list "$TEMPLATE_POOL")

    # pveam can expose amd64 and arm64 templates on the same host. Never choose
    # by version alone: doing so can create a foreign-architecture LXC that the
    # host cannot start.
    local latest_available
    latest_available=$(awk -v type="$template_type" -v arch="$template_arch" \
        '$2 ~ type && index($2, "_" arch ".tar.") {print $2}' \
        <<< "$available_output" | sort -V | tail -n 1)
    [[ -n "$latest_available" ]] || {
        print_error "No ${template_type} template available for ${template_arch}"
        exit 1
    }

    # Check if we already have this exact native-architecture template locally.
    # Foreign-architecture cache entries are intentionally ignored.
    local local_template
    local_template=$(awk -v type="$template_type" -v arch="$template_arch" \
        '$1 ~ type && index($1, "_" arch ".tar.") {print $1}' \
        <<< "$local_output" | sort -V | tail -n 1 | sed "s|^${TEMPLATE_POOL}:vztmpl/||")

    # If local template doesn't match latest available, download the new one
    if [[ "$local_template" != "$latest_available" ]]; then
        print_info "Downloading latest ${template_type} ${template_arch} template: $latest_available" >&2
        pveam download "$TEMPLATE_POOL" "$latest_available" >&2
        # After download, query storage to get actual filename (may differ from available name due to version resolution)
        local_template=$(pveam list "$TEMPLATE_POOL" | awk -v type="$template_type" -v arch="$template_arch" \
            '$1 ~ type && index($1, "_" arch ".tar.") {print $1}' | \
            sort -V | tail -n 1 | sed "s|^${TEMPLATE_POOL}:vztmpl/||")
        print_success "Downloaded template: $local_template" >&2
    else
        print_info "Using up-to-date template: $local_template" >&2
    fi

    echo "$local_template"
}

if [[ "$STACK_NAME" == media || "$STACK_NAME" == desktop ]]; then
    # Serialize automated deployment with GPU maintenance without holding the
    # device-preparation lock needed by the Proxmox pre-start hook.
    exec 8>/run/lock/homelab-nvidia-operation.lock
    flock -n 8 || { print_error "GPU maintenance or deployment is in progress"; exit 1; }
    pct() { command pct "$@" 8>&-; }
    target_version=$(get_nvidia_driver_version "$WORK_DIR/stacks.yaml")
    target_sha256=$(get_nvidia_driver_sha256 "$WORK_DIR/stacks.yaml")
    [[ "$target_version" =~ ^580\.[0-9]+\.[0-9]+$ && "$target_sha256" =~ ^[a-f0-9]{64}$ ]] || {
        print_error "Expected a pinned NVIDIA 580 driver and SHA-256 in stacks.yaml"
        exit 1
    }
    [[ -r "$NVIDIA_DRIVER_MANIFEST" ]] || {
        print_error "NVIDIA host setup has not been completed. Run GPU setup from the helper menu first"
        exit 1
    }
    read -r active_version active_sha256 < "$NVIDIA_DRIVER_MANIFEST"
    [[ "$active_version" == "$target_version" && "$active_sha256" == "$target_sha256" ]] || {
        print_error "NVIDIA host version does not match stacks.yaml; finish host setup/reboot first"
        exit 1
    }
    [[ "$(get_loaded_nvidia_driver_version)" == "$target_version" ]] || {
        print_error "NVIDIA host kernel module is not ready; reboot after host setup"
        exit 1
    }
    [[ -x /usr/local/sbin/homelab-nvidia-prepare ]] || {
        print_error "Run Install / Update NVIDIA GPU from the helper menu first"
        exit 1
    }
fi

HOST_TEMPLATE_ARCH=$(get_host_template_arch)

# Container exists check - handle gracefully for idempotency
if check_container_exists "$CT_ID"; then
    SKIP_CREATION=true

    current_container_arch=$(pct config "$CT_ID" | awk -F': ' '$1 == "arch" {print $2; exit}')
    if [[ -n "$current_container_arch" && "$current_container_arch" != "$HOST_TEMPLATE_ARCH" ]]; then
        print_error "LXC $CT_ID architecture ${current_container_arch} does not match Proxmox host ${HOST_TEMPLATE_ARCH}"
        print_error "Destroy the mismatched LXC and redeploy it: pct destroy $CT_ID --purge 1"
        exit 1
    fi
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

if [[ "$SKIP_CREATION" == true && ( "$STACK_NAME" == media || "$STACK_NAME" == desktop ) ]]; then
    reconcile_nvidia_lxc_config "$CT_ID" true
    [[ "$NVIDIA_LXC_CONFIG_CHANGED" == false ]] || {
        print_error "GPU devices need maintenance. Run Install / Update NVIDIA GPU from the helper menu"
        exit 1
    }
    if check_container_running "$CT_ID"; then
        configure_nvidia_guest_sync "$CT_ID" check
        prepare_nvidia_guest "$CT_ID" check
    fi
fi

# Create container only if it doesn't exist
if [[ "$SKIP_CREATION" == "false" ]]; then
    print_info "Creating container $CT_ID ($CT_HOSTNAME)"
    create_feature_args=()
    if [[ "$STACK_NAME" == "dev" ]]; then
        # Debian 13 systemd requires nesting for service isolation. Dev does
        # not run Docker, so keyctl remains disabled.
        create_feature_args=(--features nesting=1)
    else
        create_feature_args=(--features "keyctl=1,nesting=1")
    fi
    pct create "$CT_ID" "${TEMPLATE_POOL}:vztmpl/${LATEST_TEMPLATE}" \
        --hostname "$CT_HOSTNAME" \
        --storage "$STORAGE_POOL" \
        --cores "$CT_CPU_CORES" \
        --memory "$CT_MEMORY_MB" \
        --swap 0 \
        "${create_feature_args[@]}" \
        --net0 name=eth0,bridge="$NETWORK_BRIDGE",ip="$CT_IP"/24,gw="$NETWORK_GATEWAY" \
        --onboot 1 \
        --unprivileged 1 \
        --rootfs "$STORAGE_POOL":"$CT_DISK_GB" || { print_error "Failed to create container"; exit 1; }
fi

# The Proxmox console is the trusted administrative entry point. Shell mode
# opens a root shell directly and avoids distribution-specific getty handling.
# Applied to new and existing containers through the same path.
pct set "$CT_ID" --cmode shell
reconcile_dev_features
reconcile_stack_firewall

# Limit every LXC to the shared paths used by its stack. In particular, never
# expose the fastpool root because it also contains the other LXC root filesystems.
# Gaming publishes game ports to the internet, so it only sees its own data.
if [[ "$STACK_NAME" == "gaming" ]]; then
    prepare_host_directory /fastpool/config/gameservers
    reconcile_lxc_mount mp1 /fastpool/config/gameservers
else
    if [[ "$STACK_NAME" != "gateway" ]]; then
        reconcile_lxc_mount mp0 "$DATAPOOL"
    fi
    reconcile_lxc_mount mp1 /fastpool/config
fi

if [[ "$SKIP_CREATION" == false && ( "$STACK_NAME" == media || "$STACK_NAME" == desktop ) ]]; then
    systemctl start homelab-nvidia-prepare.service
    reconcile_nvidia_lxc_config "$CT_ID"
    print_success "GPU passthrough configured for new LXC $CT_ID"
fi

# Ensure container is running (Start AFTER all config changes)
CT_STATUS=$(pct status "$CT_ID" | awk '{print $2}')

if [[ "$CT_STATUS" == "running" && "$LXC_RESTART_REQUIRED" == "true" && "$SKIP_CREATION" == "true" ]]; then
    print_info "Restarting LXC $CT_ID to apply host configuration changes"
    pct reboot "$CT_ID" --timeout 60
elif [[ "$CT_STATUS" != "running" ]]; then
    print_info "Starting container"
    if ! pct start "$CT_ID"; then
        if [[ "$SKIP_CREATION" == "false" ]]; then
            print_warning "Removing newly created LXC $CT_ID after startup failure"
            pct destroy "$CT_ID" --purge 1 || true
        fi
        print_error "Failed to start LXC $CT_ID"
        exit 1
    fi
fi

# Verify container is ready
pct exec "$CT_ID" -- test -f /sbin/init


# Prepare the dev stack's persistent bind sources on the host. Docker stacks
# prepare their own bind sources in docker-deployment.sh.
if [[ "$STACK_NAME" == "dev" ]]; then
    prepare_host_directory /fastpool/config/code-server
    prepare_host_directory /fastpool/config/code-server/config
    prepare_host_directory /fastpool/config/code-server/data
    prepare_host_directory /fastpool/config/dev 0700
    prepare_host_directory /fastpool/config/dev/workspace 0700
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

    # Dev stack: code-server + developer CLI tools + headless browser runtime (no Docker, no GPU)
    if [ \"\$STACK_NAME\" = 'dev' ]; then
        nodesource_installer=\$(mktemp /tmp/nodesource-setup.XXXXXX)
        trap 'rm -f \"\$nodesource_installer\"' EXIT
        curl -fsSL https://deb.nodesource.com/setup_lts.x -o \"\$nodesource_installer\"
        bash \"\$nodesource_installer\"
        rm -f \"\$nodesource_installer\"
        trap - EXIT
        apt-get install -y -qq \
            nodejs git python3 python3-pip python3-yaml bash nano vim htop shellcheck yq \
            zsh zsh-autosuggestions zsh-syntax-highlighting eza bat zoxide btop \
            libglib2.0-0t64 libnss3 libatk1.0-0t64 libatk-bridge2.0-0t64 libcups2t64 libdrm2 \
            libxkbcommon0 libxcomposite1 libxdamage1 libxfixes3 libxrandr2 libgbm1 \
            libpango-1.0-0 libcairo2 libasound2t64 libx11-6 libx11-xcb1 libxcb1 libxext6 \
            fonts-liberation
        node -e 'if (!process.release.lts) process.exit(1)'

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

    else
        # GPU stacks install Docker and its NVIDIA runtime through the shared
        # GPU preparation path after base OS provisioning below.
        :
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

# Proxmox shell-mode console bypasses guest authentication, so keep the root
# password locked against guest login paths.
passwd -l root

# Create hushlogin to suppress login messages  
touch /root/.hushlogin
"

    print_success "Container OS provisioned"
fi

if [[ "$STACK_NAME" == media || "$STACK_NAME" == desktop ]]; then
    if [[ "$SKIP_CREATION" == false ]]; then
        configure_nvidia_guest_sync "$CT_ID" apply
        prepare_nvidia_guest "$CT_ID" apply
    else
        # Redeploys never install drivers, rewrite GPU units or change runtime.
        configure_nvidia_guest_sync "$CT_ID" check
        prepare_nvidia_guest "$CT_ID" check
    fi
fi

# Proxmox shell mode launches the root account's configured shell directly.
# Alpine defaults to BusyBox ash with a minimal "/ #" prompt, so use the Bash
# package already provisioned above and match Debian's informative root prompt.
if [[ "$STACK_NAME" != "media" && "$STACK_NAME" != "desktop" && "$STACK_NAME" != "dev" ]]; then
    # Variables in this single-quoted script expand inside the container.
    # shellcheck disable=SC2016
    pct exec "$CT_ID" -- sh -c '
set -e
sed -i "/^root:/ s|:[^:]*$|:/bin/bash|" /etc/passwd
quote=$(printf "\047")
printf "PS1=%s%s%s\n" "$quote" "\\u@\\h:\\w\\\$ " "$quote" > /root/.bashrc
'
fi

# Proxmox shell mode starts the root shell with a cleared environment: HOME is
# unset, TERM is "linux" and the working directory is /. The shell is not a
# login shell, so /etc/profile.d is never read; configure it in .bashrc. Export
# HOME first, since later .bashrc lines (for example the Dev Cargo env) expand
# it, then move a newly opened console to /root while keeping other working
# directories unchanged.
# Variables in this single-quoted script expand inside the container.
# shellcheck disable=SC2016
pct exec "$CT_ID" -- sh -c '
set -e
grep -qxF "export TERM=xterm-256color" /root/.bashrc ||
    sed -i "1i export TERM=xterm-256color" /root/.bashrc
grep -qxF "export HOME=/root" /root/.bashrc ||
    sed -i "1i export HOME=/root" /root/.bashrc
start_dir_line="[ \"\$PWD\" != / ] || cd /root"
grep -qxF "$start_dir_line" /root/.bashrc ||
    printf "%s\n" "$start_dir_line" >> /root/.bashrc
'

# Install Dev applications only on a new LXC. Both redeploy entry points
# reconcile local configuration and validate the existing installation.
if [[ "$STACK_NAME" == "dev" ]]; then
    print_info "Reconciling dev CLI applications"

    # Variables in this single-quoted script expand inside the container.
    # shellcheck disable=SC2016,SC2026
    pct exec "$CT_ID" -- env SKIP_CREATION="$SKIP_CREATION" bash -c '
set -euo pipefail

# pct exec starts a non-login shell, so the root .bashrc is not loaded.
# Keep user-local and system-local CLI installations visible explicitly.
export HOME=/root
export PATH="/root/.local/bin:/usr/local/bin:$PATH"

# Keep Code-Server settings, user data, and the development workspace on
# fastpool. A regular directory at any link target is unexpected and causes the
# reconcile to fail instead of deleting or migrating user data.
mkdir -p /root/.config /root/.local/share
ln -sfnT /fastpool/config/code-server/config /root/.config/code-server
ln -sfnT /fastpool/config/code-server/data /root/.local/share/code-server
ln -sfnT /fastpool/config/dev/workspace /root/workspace

# Code-Server authentication is delegated to the SNO OTP gate at its NPM proxy
# host. The Dev LXC firewall admits port 8680 only from NPM.
code_server_config="bind-addr: 0.0.0.0:8680
auth: none
cert: false"
code_server_config_changed=false
if [[ ! -f /root/.config/code-server/config.yaml || "$(</root/.config/code-server/config.yaml)" != "$code_server_config" ]]; then
    printf "%s\n" "$code_server_config" > /root/.config/code-server/config.yaml
    code_server_config_changed=true
fi

# Application downloads belong to initial provisioning, not redeploys.
if [[ "$SKIP_CREATION" == "false" ]]; then
    CODE_SERVER_URL=$(curl -fsSLI -o /dev/null -w "%{url_effective}" https://github.com/coder/code-server/releases/latest)
    CODE_SERVER_TAG=${CODE_SERVER_URL##*/}
    CODE_SERVER_VERSION=${CODE_SERVER_TAG#v}
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

    # Oh My Pi is the single coding-agent CLI. Updates are a separate,
    # explicit maintenance operation rather than a redeploy side effect.
    curl -fsSL https://omp.sh/install | sh

    # Serve the terminal font through code-server; browser clients cannot
    # use fonts installed only in the LXC.
    workbench_dir=/usr/lib/code-server/lib/vscode/out/vs/code/browser/workbench
    font_tmp=$(mktemp /tmp/JetBrainsMonoNerdFontMono.XXXXXX.ttf)
    cleanup_font() { rm -f "$font_tmp"; }
    trap cleanup_font EXIT
    curl -fsSL \
        https://raw.githubusercontent.com/ryanoasis/nerd-fonts/master/patched-fonts/JetBrainsMono/Ligatures/JetBrainsMonoNerdFontMono-Regular.ttf \
        -o "$font_tmp"
    install -m 0644 "$font_tmp" "$workbench_dir/JetBrainsMonoNerdFontMono-Regular.ttf"
    rm -f "$font_tmp"
    trap - EXIT

    install -d -m 0755 /root/.oh-my-zsh
    git -C /root/.oh-my-zsh init -q
    git -C /root/.oh-my-zsh config remote.origin.url https://github.com/ohmyzsh/ohmyzsh.git
    git -C /root/.oh-my-zsh config remote.origin.fetch "+refs/heads/master:refs/remotes/origin/master"
    git -C /root/.oh-my-zsh fetch -q --depth=1 origin master
    git -C /root/.oh-my-zsh reset -q --hard FETCH_HEAD
fi

for command_name in node npm git gh python3 bash nano vim htop shellcheck yq omp code-server; do
    command -v "$command_name" >/dev/null 2>&1 || {
        echo "Missing required dev command: $command_name" >&2
        exit 1
    }
done
python3 -c "import yaml"

omp --version
# Restarting code-server kills its open terminals; do it only for a new config.
systemctl enable --now code-server@root
if [[ "$code_server_config_changed" == true ]]; then
    systemctl restart code-server@root
fi

systemctl is-enabled code-server@root >/dev/null 2>&1
systemctl is-active code-server@root >/dev/null 2>&1
'
    print_success "Dev CLI applications reconciled"
fi

print_success "Container [$STACK_NAME] ready"
