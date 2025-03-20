#!/bin/bash
set -e

echo "Proxy LXC (ID: 100) hazırlığı yapılacak."
read -p "Proxy LXC için klasörler oluşturulsun ve izinler ayarlansın mı? (y/N): " response

if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    # Dizin yapısını oluştur
    mkdir -p /datapool/config/{cloudflared-config,watchtower-proxy-config,adguard-config/{work,conf},firefox-config}
    
    # İzinleri ayarla (100000 varsayılan LXC UID/GID)
    chown -R 100000:100000 /datapool/config/{cloudflared-config,watchtower-proxy-config,adguard-config,firefox-config}
    
    # LXC'ye datapool'u bağla
    pct set 100 -mp0 /datapool,mp=/datapool
    
    echo "Proxy LXC hazırlığı tamamlandı."
else
    echo "İşlem iptal edildi."
fi
