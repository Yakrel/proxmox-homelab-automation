# LOGGING STACK INSTALLATION (LXC ID: 104)
#
# === STEP 1: PROXMOX HOST COMMANDS ===
# Run these commands on the Proxmox host system:
#
#    # Create directory structure
#    mkdir -p /datapool/config/{elasticsearch-config,logstash-config,kibana-config,filebeat-config,watchtower-logging-config}
#    
#    # Set LXC ownership (100000 is the default LXC UID/GID mapping)
#    chown -R 100000:100000 /datapool
#    
#    # Mount datapool to LXC
#    pct set 104 -mp0 /datapool,mp=/datapool

networks:
  logging-net:
    driver: bridge

services:
  elasticsearch:
