#!/bin/bash
set -e

echo "Utility LXC (lxc-utility-01, ID: 103) preparation will be done."
read -p "Do you want to create folders for Utility LXC? (y/N): " response

if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    # Create directory structure for utility stack
    mkdir -p /datapool/config/firefox
    mkdir -p /datapool/config/watchtower-utility
    
    # Set ownership for specific config subdirectories
    chown -R 1000:1000 /datapool/config/firefox
    chown -R 1000:1000 /datapool/config/watchtower-utility
    
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