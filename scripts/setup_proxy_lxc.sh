#!/bin/bash
set -e  # Herhangi bir komut hata verdiğinde scripti durdur

echo "==== Proxy LXC (ID: 100) Hazırlanıyor ===="

# Dizin yapısını oluştur
echo "Dizin yapısı oluşturuluyor..."
mkdir -p /datapool/config/{cloudflared-config,watchtower-proxy-config,adguard-config/{work,conf},firefox-config}

# İzinleri ayarla (100000 varsayılan LXC UID/GID eşleştirmesidir)
echo "Dizin izinleri ayarlanıyor..."
# Sadece Proxy LXC için oluşturulan dizinlerin izinlerini değiştir
chown -R 100000:100000 /datapool/config/{cloudflared-config,watchtower-proxy-config,adguard-config,firefox-config}

# LXC'ye datapool'u bağla
echo "Datapool LXC'ye bağlanıyor..."
pct set 100 -mp0 /datapool,mp=/datapool

echo "Proxy LXC hazırlıkları tamamlandı."
echo "-------------------------------------"
echo "Şimdi LXC'nin içine geçip Docker ve Docker Compose'u yükleyin:"
echo "pct enter 100"
echo ""
echo "Ardından docker-compose.yml ve .env dosyalarını kopyalayıp çalıştırın."
echo "-------------------------------------"
