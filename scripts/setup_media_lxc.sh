#!/bin/bash
set -e

echo "Media LXC (ID: 101) preparation will be done."
read -p "Do you want to create folders and set permissions for Media LXC? (y/N): " response

if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    # Create directory structure for config
    mkdir -p /datapool/config/sonarr-config
    mkdir -p /datapool/config/radarr-config
    mkdir -p /datapool/config/bazarr-config
    mkdir -p /datapool/config/jellyfin-config
    mkdir -p /datapool/config/jellyseerr-config
    mkdir -p /datapool/config/qbittorrent-config
    mkdir -p /datapool/config/prowlarr-config
    mkdir -p /datapool/config/flaresolverr-config
    mkdir -p /datapool/config/watchtower-media-config
    mkdir -p /datapool/config/recyclarr-config
    mkdir -p /datapool/config/youtube-dl-config
    
    # Create media directories
    mkdir -p /datapool/media/tv
    mkdir -p /datapool/media/movies
    mkdir -p /datapool/media/youtube/playlists
    mkdir -p /datapool/media/youtube/channels
    
    # Create torrents directories
    mkdir -p /datapool/torrents/tv
    mkdir -p /datapool/torrents/movies
    mkdir -p /datapool/torrents/incomplete
    
    # Set permissions (100000 is the default LXC UID/GID)
    chown -R 100000:100000 /datapool/config/sonarr-config
    chown -R 100000:100000 /datapool/config/radarr-config
    chown -R 100000:100000 /datapool/config/bazarr-config
    chown -R 100000:100000 /datapool/config/jellyfin-config
    chown -R 100000:100000 /datapool/config/jellyseerr-config
    chown -R 100000:100000 /datapool/config/qbittorrent-config
    chown -R 100000:100000 /datapool/config/prowlarr-config
    chown -R 100000:100000 /datapool/config/flaresolverr-config
    chown -R 100000:100000 /datapool/config/watchtower-media-config
    chown -R 100000:100000 /datapool/config/recyclarr-config
    chown -R 100000:100000 /datapool/config/youtube-dl-config
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
