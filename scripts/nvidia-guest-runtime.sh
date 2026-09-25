#!/bin/bash
# GPU maintenance only; ordinary application redeploys use --check.
set -euo pipefail
mode=${1:---check}
case "$mode" in --check|--check-config|--apply|--stage) ;; *) exit 2 ;; esac

runtime_ready() {
    command -v python3 >/dev/null && command -v nvidia-ctk >/dev/null && command -v docker >/dev/null || return 1
    python3 - <<'PY'
import json
import pathlib
import sys
import tomllib
try:
    config = tomllib.loads(pathlib.Path('/etc/nvidia-container-runtime/config.toml').read_text())
    cli = config.get('nvidia-container-cli', {})
    docker = json.loads(pathlib.Path('/etc/docker/daemon.json').read_text())
    runtime = docker.get('runtimes', {}).get('nvidia', {})
    valid = (cli.get('no-cgroups') is True and cli.get('load-kmods') is False
             and runtime.get('path') in ('nvidia-container-runtime', '/usr/bin/nvidia-container-runtime'))
except (OSError, ValueError):
    valid = False
sys.exit(0 if valid else 1)
PY
}


if [[ "$mode" == --check-config ]]; then
    runtime_ready
    exit
fi

if [[ "$mode" == --check ]]; then
    [[ ! -e /etc/homelab-nvidia-maintenance ]] || { echo 'GPU maintenance is incomplete' >&2; exit 1; }
    runtime_ready || { echo 'NVIDIA Docker runtime needs GPU menu maintenance' >&2; exit 1; }
    exec /usr/local/bin/nvidia-userspace-sync.sh --check
fi

# A persistent gate survives a failed maintenance run or an unexpected reboot.
# It is removed only after configuration (and, in apply mode, sync) succeeds.
touch /etc/homelab-nvidia-maintenance
if systemctl cat docker.service >/dev/null 2>&1; then
    systemctl stop docker.socket docker.service
fi

packages=(ca-certificates curl gnupg python3 libc-bin libglvnd0 libegl1 libgl1)
missing=false
for package in "${packages[@]}"; do
    status=$(dpkg-query -W -f='${db:Status-Status}' "$package" 2>/dev/null) || status=''
    [[ "$status" == installed ]] || missing=true
done
if [[ "$missing" == true ]]; then
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y "${packages[@]}"
fi

packages=(docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin nvidia-container-toolkit)
missing=false
for package in "${packages[@]}"; do
    status=$(dpkg-query -W -f='${db:Status-Status}' "$package" 2>/dev/null) || status=''
    [[ "$status" == installed ]] || missing=true
done
if [[ "$missing" == true ]]; then
    install -d -m 0755 /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
    chmod 0644 /etc/apt/keyrings/docker.asc
    . /etc/os-release
    cat > /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/debian
Suites: ${VERSION_CODENAME}
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF
    curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey |
        gpg --batch --yes --dearmor -o /etc/apt/keyrings/nvidia-container-toolkit.gpg
    chmod 0644 /etc/apt/keyrings/nvidia-container-toolkit.gpg
    curl -fsSL https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list |
        sed 's#deb https://#deb [signed-by=/etc/apt/keyrings/nvidia-container-toolkit.gpg] https://#' > /etc/apt/sources.list.d/nvidia-container-toolkit.list
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y "${packages[@]}"
fi

if ! runtime_ready; then
    nvidia-ctk config --set nvidia-container-cli.no-cgroups=true --set nvidia-container-cli.load-kmods=false --in-place
    nvidia-ctk runtime configure --runtime=docker
fi
runtime_ready
if [[ "$mode" == --apply ]]; then
    /usr/local/bin/nvidia-userspace-sync.sh
    rm -f /etc/homelab-nvidia-maintenance
fi
systemctl enable docker.service docker.socket
if [[ "$mode" == --apply ]]; then
    systemctl restart nvidia-userspace-sync.service
    systemctl start docker.socket docker.service
fi
