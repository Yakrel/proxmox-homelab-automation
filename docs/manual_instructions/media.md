# MEDIA STACK INSTALLATION (LXC ID: 102)
#
# === STEP 1: PROXMOX HOST COMMANDS ===
# Run these commands on the Proxmox host system:
#
#    # Create directory structure
#    mkdir -p /datapool/config/{sonarr-config,radarr-config,bazarr-config,jellyfin-config,jellyseerr-config,qbittorrent-config,prowlarr-config,flaresolverr-config,watchtower-media-config,recyclarr-config,youtube-dl-config}
#    mkdir -p /datapool/media/{tv,movies,youtube/{playlists,channels}}
#    mkdir -p /datapool/torrents/{tv,movies}
#    
#    # Set LXC ownership (100000 is the default LXC UID/GID mapping)
#    chown -R 100000:100000 /datapool
#    
#    # Mount datapool to LXC
#    pct set 102 -mp0 /datapool,mp=/datapool

networks:
  media-net:
    driver: bridge

