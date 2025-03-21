#!/bin/bash
set -e

echo "Proxy LXC (ID: 100) preparation will be done."
read -p "Do you want to create folders and set permissions for Proxy LXC? (y/N): " response

if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    # Create directory structure
    mkdir -p /datapool/config/{cloudflared-config,watchtower-proxy-config,adguard-config/{work,conf},firefox-config}
    
    # Set permissions (100000 is the default LXC UID/GID)
    chown -R 100000:100000 /datapool/config/{cloudflared-config,watchtower-proxy-config,adguard-config,firefox-config}
    
    # Mount datapool to LXC
    pct set 100 -mp0 /datapool,mp=/datapool
    
    echo "Proxy LXC preparation completed."
else
    echo "Operation cancelled."
fi
