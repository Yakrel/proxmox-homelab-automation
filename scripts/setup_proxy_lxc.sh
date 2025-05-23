#!/bin/bash
set -e

echo "Proxy LXC (lxc-proxy-01, ID: 100) preparation will be done."
read -p "Do you want to create folders for Proxy LXC? (y/N): " response

if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    # Create directory structure
    mkdir -p /datapool/config/cloudflared
    mkdir -p /datapool/config/watchtower-proxy
    mkdir -p /datapool/config/adguard/work
    mkdir -p /datapool/config/adguard/conf
    mkdir -p /datapool/config/firefox

    # Set ownership for specific subdirectories only
    chown -R 100000:100000 /datapool/config/cloudflared
    chown -R 100000:100000 /datapool/config/watchtower-proxy
    chown -R 100000:100000 /datapool/config/adguard
    chown -R 100000:100000 /datapool/config/firefox

    # Mount datapool to LXC
    pct set 100 -mp0 /datapool,mp=/datapool
    
    echo "Proxy LXC preparation completed."
else
    echo "Operation cancelled."
fi
