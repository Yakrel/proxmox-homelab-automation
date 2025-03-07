# MONITORING STACK INSTALLATION (LXC ID: 103)
#
# === STEP 1: PROXMOX HOST COMMANDS ===
# Run these commands on the Proxmox host system:
#
#    # Create directory structure
#    mkdir -p /datapool/config/{prometheus-config,grafana-config,alertmanager-config,watchtower-monitoring-config}
#    
#    # Set LXC ownership (100000 is the default LXC UID/GID mapping)
#    chown -R 100000:100000 /datapool
#    
#    # Mount datapool to LXC
#    pct set 103 -mp0 /datapool,mp=/datapool

networks:
  monitoring-net:
    driver: bridge

services:
  prometheus:
