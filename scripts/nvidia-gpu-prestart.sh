#!/bin/bash
# Preparation's flock is deliberately short-lived, not a whole-start lock.
# PVE holds its config mutex through startup; the menu acquires a create lock
# under that mutex before examining status or replacing the host driver.
# dev[n] paths must already exist; the host boot unit prepares them earlier.
set -euo pipefail

ct_id="${1:-}"
phase="${2:-}"
[[ "$phase" == "pre-start" ]] || exit 0

case "$ct_id" in
    101|103) ;;
    *) echo "Unexpected GPU LXC: $ct_id" >&2; exit 1 ;;
esac

exec /usr/local/sbin/homelab-nvidia-prepare
