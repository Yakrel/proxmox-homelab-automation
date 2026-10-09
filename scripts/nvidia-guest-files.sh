#!/bin/bash
# Run as guest root (also usable in its user namespace against a mounted rootfs).
set -euo pipefail
source_dir=$1
root=${2%/}
mode=${3:-apply}
[[ "$mode" == apply || "$mode" == check ]] || exit 2
changed=false
while read -r source destination permissions; do
    if [[ ! -f "$root$destination" ]] ||
        ! cmp -s "$source_dir/$source" "$root$destination" ||
        [[ $(stat -c %a "$root$destination") != "$permissions" ]]; then
        if [[ "$mode" == check ]]; then
            echo "GPU managed file needs updating: $destination" >&2
            exit 1
        fi
        install -D -m "$permissions" "$source_dir/$source" "$root$destination"
        changed=true
    fi
done <<'FILES'
nvidia-userspace-sync.sh /usr/local/bin/nvidia-userspace-sync.sh 755
nvidia-userspace-sync.service /etc/systemd/system/nvidia-userspace-sync.service 644
nvidia-docker.conf /etc/systemd/system/docker.service.d/nvidia-userspace.conf 644
nvidia-docker.conf /etc/systemd/system/docker.socket.d/nvidia-userspace.conf 644
FILES
link=/etc/systemd/system/multi-user.target.wants/nvidia-userspace-sync.service
if [[ $(readlink "$root$link" || true) != /etc/systemd/system/nvidia-userspace-sync.service ]]; then
    [[ "$mode" == apply ]] || exit 1
    mkdir -p "$root/etc/systemd/system/multi-user.target.wants"
    ln -sfn /etc/systemd/system/nvidia-userspace-sync.service "$root$link"
    changed=true
fi
if [[ -z "$root" && "$changed" == true ]]; then
    systemctl daemon-reload
fi
