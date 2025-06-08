#!/bin/bash
set -e

echo "Downloads LXC (lxc-downloads-01, ID: 102) preparation will be done."
read -p "Do you want to create folders for Downloads LXC? (y/N): " response

if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    # Create directory structure for downloads stack
    mkdir -p /datapool/config/jdownloader2
    mkdir -p /datapool/config/metube
    mkdir -p /datapool/config/watchtower-downloads
    
    # Set ownership for specific config subdirectories
    chown -R 1000:1000 /datapool/config/jdownloader2
    chown -R 1000:1000 /datapool/config/metube
    chown -R 1000:1000 /datapool/config/watchtower-downloads
    
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