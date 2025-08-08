#!/bin/bash
# Shared helper: load stack configuration from stacks.yml (single source of truth)
# Falls back to legacy hardcoded values only if YAML or yq is unavailable.

STACKS_YAML="$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)/stacks.yml"

ensure_yq() {
  if command -v yq >/dev/null 2>&1; then
    return 0
  fi
  echo "[INFO] yq not found, attempting lightweight install..." >&2
  local url arch
  arch=$(uname -m)
  case "$arch" in
    x86_64|amd64) arch=amd64 ;;
    aarch64|arm64) arch=arm64 ;;
    *) echo "[WARN] Unsupported arch $arch for auto yq install" >&2; return 1 ;;
  esac
  url="https://github.com/mikefarah/yq/releases/latest/download/yq_linux_${arch}"
  if curl -fsSL "$url" -o /usr/local/bin/yq; then
    chmod +x /usr/local/bin/yq
    echo "[INFO] yq installed to /usr/local/bin/yq" >&2
    return 0
  else
    echo "[WARN] Failed to download yq binary" >&2
    return 1
  fi
}

load_stack_config() {
  local stack_name=$1
  # Try YAML path first
  if ensure_yq && [ -f "$STACKS_YAML" ]; then
    local id hostname ip cores mem disk
    id=$(yq -r ".stacks.$stack_name.id" "$STACKS_YAML" 2>/dev/null || true)
    if [ -n "$id" ] && [ "$id" != "null" ]; then
      hostname=$(yq -r ".stacks.$stack_name.hostname" "$STACKS_YAML")
      ip=$(yq -r ".stacks.$stack_name.ip" "$STACKS_YAML")
      cores=$(yq -r ".stacks.$stack_name.cores" "$STACKS_YAML")
      mem=$(yq -r ".stacks.$stack_name.memory" "$STACKS_YAML")
      disk=$(yq -r ".stacks.$stack_name.disk" "$STACKS_YAML")
      CT_ID=$id
      CT_HOSTNAME=$hostname
      CT_IP_CIDR=$ip
      CT_CORES=$cores
      CT_RAM_MB=$mem
      CT_DISK_GB=$disk
      CT_GATEWAY_IP=${CT_GATEWAY_IP:-192.168.1.1}
      CT_BRIDGE=${CT_BRIDGE:-vmbr0}
      STORAGE_POOL=${STORAGE_POOL:-datapool}
      return 0
    fi
  fi
  # Fallback legacy mapping
  case "$stack_name" in
    proxy)       CT_ID=100; CT_HOSTNAME="lxc-proxy-01";       CT_CORES=2; CT_RAM_MB=2048;  CT_DISK_GB=10;  CT_IP_CIDR="192.168.1.100/24" ;;
    media)       CT_ID=101; CT_HOSTNAME="lxc-media-01";       CT_CORES=6; CT_RAM_MB=10240; CT_DISK_GB=20;  CT_IP_CIDR="192.168.1.101/24" ;;
    files)       CT_ID=102; CT_HOSTNAME="lxc-files-01";       CT_CORES=2; CT_RAM_MB=3072;  CT_DISK_GB=15;  CT_IP_CIDR="192.168.1.102/24" ;;
    webtools)    CT_ID=103; CT_HOSTNAME="lxc-webtools-01";    CT_CORES=2; CT_RAM_MB=6144;  CT_DISK_GB=15;  CT_IP_CIDR="192.168.1.103/24" ;;
    monitoring)  CT_ID=104; CT_HOSTNAME="lxc-monitoring-01";  CT_CORES=4; CT_RAM_MB=6144;  CT_DISK_GB=15;  CT_IP_CIDR="192.168.1.104/24" ;;
    development) CT_ID=150; CT_HOSTNAME="lxc-development-01"; CT_CORES=4; CT_RAM_MB=6144;  CT_DISK_GB=15;  CT_IP_CIDR="192.168.1.150/24" ;;
    *) echo "[ERROR] Unknown stack: $stack_name" >&2; return 1 ;;
  esac
  CT_GATEWAY_IP=192.168.1.1
  CT_BRIDGE=vmbr0
  STORAGE_POOL=datapool
}
