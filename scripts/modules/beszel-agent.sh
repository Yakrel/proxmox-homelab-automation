#!/bin/bash

beszel_fingerprint_for_name() {
    local system_name="$1"
    local fingerprint

    fingerprint=$(printf 'proxmox-homelab:%s' "$system_name" | sha256sum)
    fingerprint=${fingerprint%% *}
    printf '%s' "${fingerprint:0:48}"
}

install_local_beszel_agent() {
    local env_file="$1"
    local system_name="$2"
    local service_patterns="$3"
    local extra_filesystems="${4:-}"
    local public_key universal_token agent_script

    public_key=$(get_env_value "BESZEL_PUBLIC_KEY" "$env_file")
    universal_token=$(get_env_value "BESZEL_UNIVERSAL_TOKEN" "$env_file")
    if [[ -z "$public_key" || -z "$universal_token" ]]; then
        print_error "Beszel enrollment values are missing from $env_file"
        return 1
    fi

    # The host runs the same checksum-verified installer as the LXCs.
    agent_script=$(mktemp /tmp/beszel-agent.XXXXXX)
    register_runtime_temp_file "$agent_script"
    write_beszel_agent_script "$agent_script"
    BESZEL_PUBLIC_KEY="$public_key" \
        BESZEL_UNIVERSAL_TOKEN="$universal_token" \
        BESZEL_FINGERPRINT="$(beszel_fingerprint_for_name "$system_name")" \
        BESZEL_SYSTEM_NAME="$system_name" \
        BESZEL_SERVICE_PATTERNS="$service_patterns" \
        BESZEL_EXTRA_FILESYSTEMS="$extra_filesystems" \
        bash "$agent_script"

    unset public_key universal_token
    print_success "Beszel agent reconciled as $system_name"
}

# Writes the agent installer shared by the Proxmox host and every LXC.
write_beszel_agent_script() {
    cat > "$1" <<'GUEST_SCRIPT'
#!/bin/bash
set -euo pipefail

install_tmp=$(mktemp -d /tmp/beszel-agent-install.XXXXXX)
service_env_tmp=$(mktemp /tmp/beszel-agent-service-env.XXXXXX)
trap 'rm -rf "$install_tmp"; rm -f "$service_env_tmp"' EXIT

if [[ -f /etc/alpine-release ]]; then
    service_manager=openrc
    if ! id -u beszel >/dev/null 2>&1; then
        addgroup -S beszel
        adduser -S -D -H -s /sbin/nologin -G beszel beszel
    fi
    if grep -q '^docker:' /etc/group &&
        ! id -nG beszel | tr ' ' '\n' | grep -qx docker; then
        addgroup beszel docker
    fi
else
    service_manager=systemd
    if ! id -u beszel >/dev/null 2>&1; then
        useradd --system --home-dir /nonexistent --shell /usr/sbin/nologin beszel
    fi
    if getent group docker >/dev/null 2>&1; then
        usermod -aG docker beszel
    fi
    if getent group disk >/dev/null 2>&1; then
        usermod -aG disk beszel
    fi
fi

fetch_file() {
    local url="$1"
    local destination="$2"

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$url" -o "$destination"
    else
        wget -q "$url" -O "$destination"
    fi
}

if [[ ! -x /usr/local/bin/beszel-agent ]]; then
    case "$(uname -m)" in
        x86_64) agent_arch=amd64 ;;
        aarch64|arm64) agent_arch=arm64 ;;
        *)
            echo "Unsupported Beszel agent architecture: $(uname -m)" >&2
            exit 1
            ;;
    esac

    fetch_file https://get.beszel.dev/latest-version "$install_tmp/version"
    version=$(<"$install_tmp/version")
    [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]]
    archive="beszel-agent_linux_${agent_arch}.tar.gz"
    if [[ "$agent_arch" == "amd64" ]] &&
        [[ -e /lib64/ld-linux-x86-64.so.2 ||
            -e /lib/x86_64-linux-gnu/ld-linux-x86-64.so.2 ||
            -e /lib/ld-linux-x86-64.so.2 ]]; then
        archive="beszel-agent_linux_amd64_glibc.tar.gz"
    fi

    fetch_file \
        "https://github.com/henrygd/beszel/releases/download/v${version}/beszel_${version}_checksums.txt" \
        "$install_tmp/checksums.txt"
    checksum=$(
        sed -n "s/^[[:space:]]*\\([[:xdigit:]]\\{64\\}\\)[[:space:]]\\+${archive}\$/\\1/p" \
            "$install_tmp/checksums.txt"
    )
    [[ "$checksum" =~ ^[[:xdigit:]]{64}$ ]]
    fetch_file \
        "https://github.com/henrygd/beszel/releases/download/v${version}/${archive}" \
        "$install_tmp/$archive"
    printf '%s  %s\n' "$checksum" "$install_tmp/$archive" | sha256sum -c -
    tar -xzf "$install_tmp/$archive" -C "$install_tmp" beszel-agent
    install -m 0755 "$install_tmp/beszel-agent" /usr/local/bin/beszel-agent
fi

install -d -o beszel -g beszel -m 0755 /var/lib/beszel-agent
printf '%s\n' "$BESZEL_FINGERPRINT" > "$install_tmp/fingerprint"
install -o beszel -g beszel -m 0644 \
    "$install_tmp/fingerprint" /var/lib/beszel-agent/fingerprint
cat > "$service_env_tmp" <<EOF
KEY="$BESZEL_PUBLIC_KEY"
TOKEN=$BESZEL_UNIVERSAL_TOKEN
HUB_URL=http://192.168.1.102:8095
SYSTEM_NAME=$BESZEL_SYSTEM_NAME
DISABLE_SSH=true
DATA_DIR=/var/lib/beszel-agent
FILESYSTEM=/
SERVICE_PATTERNS=$BESZEL_SERVICE_PATTERNS
EOF
if [[ -n "${BESZEL_EXTRA_FILESYSTEMS:-}" ]]; then
    printf 'EXTRA_FILESYSTEMS=%s\n' "$BESZEL_EXTRA_FILESYSTEMS" >> "$service_env_tmp"
fi
if [[ "$service_manager" == "openrc" ]]; then
    printf 'SKIP_SYSTEMD=true\n' >> "$service_env_tmp"
fi
install -m 0600 "$service_env_tmp" /etc/beszel-agent.env

if [[ "$service_manager" == "openrc" ]]; then
    install -d -m 0755 /etc/init.d /etc/periodic/daily
    cat > /etc/init.d/beszel-agent <<'EOF'
#!/sbin/openrc-run

name="beszel-agent"
description="Beszel Agent Service"
command="/usr/local/bin/beszel-agent"
command_user="beszel:beszel"
command_background="yes"
pidfile="/run/${RC_SVCNAME}.pid"
output_log="/var/log/beszel-agent.log"
error_log="/var/log/beszel-agent.err"
required_files="/etc/beszel-agent.env"

set -a
. /etc/beszel-agent.env
set +a

start_pre() {
    checkpath -f -m 0644 -o beszel:beszel "$output_log" "$error_log"
}

depend() {
    need net
    after firewall
}
EOF
    chmod 0755 /etc/init.d/beszel-agent
    cat > /etc/periodic/daily/beszel-agent-update <<'EOF'
#!/bin/sh
exec /usr/local/bin/beszel-agent update
EOF
    chmod 0755 /etc/periodic/daily/beszel-agent-update

    if ! rc-service crond status >/dev/null 2>&1; then
        rc-service crond start
    fi
    rc-update add crond default
    rc-update add beszel-agent default
    rc-service beszel-agent restart
    rc-service beszel-agent status
else
    cat > /etc/systemd/system/beszel-agent.service <<'EOF'
[Unit]
Description=Beszel Agent Service
Wants=network-online.target
After=network-online.target

[Service]
EnvironmentFile=/etc/beszel-agent.env
ExecStart=/usr/local/bin/beszel-agent
User=beszel
Restart=on-failure
RestartSec=5
StateDirectory=beszel-agent
KeyringMode=private
LockPersonality=yes
ProtectClock=yes
ProtectHome=read-only
ProtectHostname=yes
ProtectKernelLogs=yes
ProtectSystem=strict
RemoveIPC=yes
RestrictSUIDSGID=true

[Install]
WantedBy=multi-user.target
EOF
    cat > /etc/systemd/system/beszel-agent-update.service <<'EOF'
[Unit]
Description=Update Beszel Agent if needed
Wants=beszel-agent.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/beszel-agent update
EOF
    cat > /etc/systemd/system/beszel-agent-update.timer <<'EOF'
[Unit]
Description=Run Beszel Agent update daily

[Timer]
OnCalendar=daily
Persistent=true
RandomizedDelaySec=4h

[Install]
WantedBy=timers.target
EOF

    systemctl daemon-reload
    systemctl enable --now beszel-agent-update.timer
    systemctl enable beszel-agent.service
    systemctl restart beszel-agent.service
    systemctl is-active --quiet beszel-agent.service
fi
GUEST_SCRIPT
}

deploy_lxc_beszel_agent() {
    local ct_id="$1"
    local system_name="$2"
    local env_file="$3"
    local service_patterns="${4:-docker*,beszel*}"
    local public_key universal_token fingerprint
    local guest_script remote_script

    public_key=$(get_env_value "BESZEL_PUBLIC_KEY" "$env_file")
    universal_token=$(get_env_value "BESZEL_UNIVERSAL_TOKEN" "$env_file")
    if [[ -z "$public_key" || -z "$universal_token" ]]; then
        print_error "Beszel enrollment values are missing from $env_file"
        return 1
    fi
    fingerprint=$(beszel_fingerprint_for_name "$system_name")

    guest_script=$(mktemp /tmp/beszel-lxc-agent.XXXXXX)
    register_runtime_temp_file "$guest_script"
    remote_script="/tmp/beszel-lxc-agent.sh"

    write_beszel_agent_script "$guest_script"

    pct push "$ct_id" "$guest_script" "$remote_script"
    pct exec "$ct_id" -- chmod 0700 "$remote_script"
    if ! pct exec "$ct_id" -- env \
        BESZEL_PUBLIC_KEY="$public_key" \
        BESZEL_UNIVERSAL_TOKEN="$universal_token" \
        BESZEL_FINGERPRINT="$fingerprint" \
        BESZEL_SYSTEM_NAME="$system_name" \
        BESZEL_SERVICE_PATTERNS="$service_patterns" \
        "$remote_script"; then
        pct exec "$ct_id" -- rm -f "$remote_script" || true
        print_error "Failed to configure Beszel agent in LXC $ct_id"
        return 1
    fi
    pct exec "$ct_id" -- rm -f "$remote_script"

    unset public_key universal_token
    print_success "LXC $ct_id Beszel agent reconciled as $system_name"
}
