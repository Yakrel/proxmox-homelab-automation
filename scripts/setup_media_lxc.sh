#!/bin/bash
set -e

echo "Media LXC (ID: 101) hazırlığı yapılacak."
read -p "Media LXC için klasörler oluşturulsun ve izinler ayarlansın mı? (y/N): " response

if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    # Dizin yapısını oluştur
    mkdir -p /datapool/config/{sonarr-config,radarr-config,bazarr-config,jellyfin-config,jellyseerr-config,qbittorrent-config,prowlarr-config,flaresolverr-config,watchtower-media-config,recyclarr-config,youtube-dl-config}
    mkdir -p /datapool/media/{tv,movies,youtube/{playlists,channels}}
    mkdir -p /datapool/torrents/{tv,movies}
    
    # İzinleri ayarla (100000 varsayılan LXC UID/GID)
    chown -R 100000:100000 /datapool/config/{sonarr-config,radarr-config,bazarr-config,jellyfin-config,jellyseerr-config,qbittorrent-config,prowlarr-config,flaresolverr-config,watchtower-media-config,recyclarr-config,youtube-dl-config}
    chown -R 100000:100000 /datapool/media
    chown -R 100000:100000 /datapool/torrents
    
    # LXC'ye datapool'u bağla
    pct set 101 -mp0 /datapool,mp=/datapool
    
    echo "Media LXC hazırlığı tamamlandı."
else
    echo "İşlem iptal edildi."
fi

echo "-------------------------------------"
echo "Şimdi LXC'nin içine geçip Docker ve Docker Compose'u yükleyin:"
echo "pct enter 101"
echo ""
echo "Ardından docker-compose.yml dosyasını kopyalayıp çalıştırın."
echo "-------------------------------------"
