#!/bin/bash
set -e

# Configuration
PUID=1000
PGID=1000

echo "Proxy LXC (lxc-proxy-01, ID: 100) preparation will be done."
read -p "Do you want to create folders for Proxy LXC? (y/N): " response

if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    # Create directory structure
    CONFIG_DIRS=("cloudflared" "watchtower-proxy")
    
    for dir in "${CONFIG_DIRS[@]}"; do
        mkdir -p "/datapool/config/$dir"
    done

    # Set ownership for config directories
    for dir in "${CONFIG_DIRS[@]}"; do
        chown -R "${PUID}:${PGID}" "/datapool/config/$dir"
    done

    # Mount datapool to LXC
    pct set 100 -mp0 /datapool,mp=/datapool
    
    echo "Proxy LXC preparation completed."
else
    echo "Operation cancelled."
fi
