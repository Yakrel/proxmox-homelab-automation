#!/bin/bash
set -e

echo "Media LXC (lxc-media-01, ID: 101) preparation will be done."
read -p "Do you want to create folders for Media LXC? (y/N): " response

if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    # Create directory structure for config
    mkdir -p /datapool/config/sonarr
    mkdir -p /datapool/config/radarr
    mkdir -p /datapool/config/bazarr
    mkdir -p /datapool/config/jellyfin
    mkdir -p /datapool/config/jellyseerr
    mkdir -p /datapool/config/qbittorrent
    mkdir -p /datapool/config/prowlarr
    mkdir -p /datapool/config/flaresolverr
    mkdir -p /datapool/config/watchtower-media
    mkdir -p /datapool/config/recyclarr
    mkdir -p /datapool/config/metube
    
    # Create media directories
    mkdir -p /datapool/media/tv
    mkdir -p /datapool/media/movies
    mkdir -p /datapool/media/youtube/playlists
    mkdir -p /datapool/media/youtube/channels
    
    # Create torrents directories
    mkdir -p /datapool/torrents/tv
    mkdir -p /datapool/torrents/movies
    mkdir -p /datapool/torrents/incomplete
    
    # Set ownership for main directories only
    chown -R 100000:100000 /datapool/config
    chown -R 100000:100000 /datapool/media
    chown -R 100000:100000 /datapool/torrents
    
    # Mount datapool to LXC
    pct set 101 -mp0 /datapool,mp=/datapool
    
    echo "Media LXC preparation completed."
else
    echo "Operation cancelled."
fi

echo "-------------------------------------"
echo "Now enter the LXC and install Docker and Docker Compose:"
echo "pct enter 101"
echo ""
echo "Then copy and run the docker-compose.yml file."
echo "-------------------------------------"
