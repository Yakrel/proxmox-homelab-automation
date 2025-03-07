# PROXY STACK INSTALLATION (LXC ID: 125)
#
# === STEP 1: PROXMOX HOST COMMANDS ===
# Run these commands on the Proxmox host system:
#
#    # Create directory structure
#    mkdir -p /datapool/config/{cloudflared-config,watchtower-proxy-config,adguard-config/{work,conf}}
#    
#    # Set LXC ownership (100000 is the default LXC UID/GID mapping)
#    chown -R 100000:100000 /datapool
#    
#    # Mount datapool to LXC
#    pct set 125 -mp0 /datapool,mp=/datapool

networks:
  proxy-net:
    driver: bridge

services:
  cloudflared:
