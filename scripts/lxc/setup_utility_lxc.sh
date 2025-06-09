#!/bin/bash
set -e

# Configuration
PUID=1000
PGID=1000

echo "Utility LXC (lxc-utility-01, ID: 103) preparation will be done."
read -p "Do you want to create folders for Utility LXC? (y/N): " response

if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    # Define config directories
    CONFIG_DIRS=("firefox" "watchtower-utility")
    
    # Create directory structure for utility stack
    for dir in "${CONFIG_DIRS[@]}"; do
        mkdir -p "/datapool/config/$dir"
    done
    
    # Set ownership for config directories
    for dir in "${CONFIG_DIRS[@]}"; do
        chown -R "${PUID}:${PGID}" "/datapool/config/$dir"
    done
    
    # Mount datapool to LXC
    pct set 103 -mp0 /datapool,mp=/datapool
    
    echo "Utility LXC preparation completed."
else
    echo "Operation cancelled."
fi

echo "-------------------------------------"
echo "Now enter the LXC and install Docker and Docker Compose:"
echo "pct enter 103"
echo ""
echo "Then copy and run the docker-compose.yml file."
echo "-------------------------------------"