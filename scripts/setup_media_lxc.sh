#!/bin/bash
set -e

echo "Media LXC (ID: 101) preparation will be done."
read -p "Do you want to create folders and set permissions for Media LXC? (y/N): " response

if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    # Create directory structure
    mkdir -p /datapool/config/{sonarr-config,radarr-config,bazarr-config,jellyfin-config,jellyseerr-config,qbittorrent-config,prowlarr-config,flaresolverr-config,watchtower-media-config,recyclarr-config,youtube-dl-config}
    mkdir -p /datapool/media/{tv,movies,youtube/{playlists,channels}}
    mkdir -p /datapool/torrents/{tv,movies,incomplete}
    
    # Set permissions (100000 is the default LXC UID/GID)
    chown -R 100000:100000 /datapool/config/{sonarr-config,radarr-config,bazarr-config,jellyfin-config,jellyseerr-config,qbittorrent-config,prowlarr-config,flaresolverr-config,watchtower-media-config,recyclarr-config,youtube-dl-config}
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
