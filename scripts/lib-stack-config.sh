#!/bin/bash
# Shared helper: load stack configuration from stacks.yml (single source of truth).
# yq is now mandatory; legacy hardcoded fallback removed.

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
  ensure_yq || { echo "[ERROR] yq is required but could not be installed" >&2; return 1; }
  [ -f "$STACKS_YAML" ] || { echo "[ERROR] stacks.yml not found: $STACKS_YAML" >&2; return 1; }
  local id hostname ip cores mem disk
  id=$(yq -r ".stacks.$stack_name.id" "$STACKS_YAML" 2>/dev/null || true)
  if [ -z "$id" ] || [ "$id" = "null" ]; then
    echo "[ERROR] Stack '$stack_name' not defined in stacks.yml" >&2
    return 1
  fi
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
}
