#!/bin/bash
set -e

# Configuration
PUID=1000
PGID=1000

echo "Downloads LXC (lxc-downloads-01, ID: 102) preparation will be done."
read -p "Do you want to create folders for Downloads LXC? (y/N): " response

if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    # Define config directories
    CONFIG_DIRS=("jdownloader2" "metube" "watchtower-downloads")
    
    # Create directory structure for downloads stack
    for dir in "${CONFIG_DIRS[@]}"; do
        mkdir -p "/datapool/config/$dir"
    done
    
    # Set ownership for config directories
    for dir in "${CONFIG_DIRS[@]}"; do
        chown -R "${PUID}:${PGID}" "/datapool/config/$dir"
    done
    
    # Mount datapool to LXC
    pct set 102 -mp0 /datapool,mp=/datapool
    
    echo "Downloads LXC preparation completed."
else
    echo "Operation cancelled."
fi

echo "-------------------------------------"
echo "Now enter the LXC and install Docker and Docker Compose:"
echo "pct enter 102"
echo ""
echo "Then copy and run the docker-compose.yml file."
echo "-------------------------------------"