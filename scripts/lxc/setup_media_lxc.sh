#!/bin/bash
set -e

# Configuration
PUID=1000
PGID=1000

echo "Media LXC (lxc-media-01, ID: 101) preparation will be done."
read -p "Do you want to create folders for Media LXC? (y/N): " response

if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    # Define directory arrays
    CONFIG_DIRS=("sonarr" "radarr" "bazarr" "jellyfin" "jellyseerr" "qbittorrent" "prowlarr" "flaresolverr" "watchtower-media" "recyclarr" "cleanuperr" "huntarr")
    MEDIA_DIRS=("tv" "movies" "youtube/playlists" "youtube/channels")
    TORRENT_DIRS=("tv" "movies" "other")
    
    # Create config directories
    for dir in "${CONFIG_DIRS[@]}"; do
        mkdir -p "/datapool/config/$dir"
    done
    
    # Create media directories
    for dir in "${MEDIA_DIRS[@]}"; do
        mkdir -p "/datapool/media/$dir"
    done
    
    # Create torrents directories
    for dir in "${TORRENT_DIRS[@]}"; do
        mkdir -p "/datapool/torrents/$dir"
    done
    
    # Set ownership for config directories (host-side unprivileged LXC mapping)
    for dir in "${CONFIG_DIRS[@]}"; do
        chown -R 101000:101000 "/datapool/config/$dir"
    done
    
    # Set ownership for media and torrents directories (host-side unprivileged LXC mapping)
    chown -R 101000:101000 /datapool/media 
    chown -R 101000:101000 /datapool/torrents
    
    # Mount datapool to LXC
    pct set 101 -mp0 /datapool,mp=/datapool
    
    echo "Media LXC preparation completed."
else
    echo "Operation cancelled."
fi

echo "Media LXC directory structure created successfully!"
