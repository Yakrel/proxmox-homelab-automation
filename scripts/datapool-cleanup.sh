#!/bin/bash
# Datapool cleanup script - removes temporary files excluded from backups
# Safe to run - only cleans cache, logs, and regenerable data
# Based on backrest exclude patterns

set -euo pipefail

echo "=== Datapool Cleanup Script ==="
echo "This will clean cache, logs, and temporary files that can be regenerated"
echo ""

# Show disk usage before cleanup
echo "=== Before Cleanup ==="
df -h /datapool | grep -v Filesystem
echo "Config size: $(du -sh /datapool/config 2>/dev/null | cut -f1)"
echo ""

# Function to safely remove directory contents
clean_dir() {
    local dir="$1"
    if [ -d "$dir" ]; then
        local size=$(du -sh "$dir" 2>/dev/null | cut -f1 || echo "0")
        rm -rf "$dir"/*
        echo "  Cleaned: $dir ($size)"
    fi
}

# Function to safely remove entire directory
remove_dir() {
    local dir="$1"
    if [ -d "$dir" ]; then
        local size=$(du -sh "$dir" 2>/dev/null | cut -f1 || echo "0")
        rm -rf "$dir"
        echo "  Removed: $dir ($size)"
    fi
}

echo "=== Cleaning Cache Directories ==="
clean_dir "/datapool/config/jellyfin/cache"
clean_dir "/datapool/config/jellyfin/.cache"
clean_dir "/datapool/config/qbittorrent/.cache"
clean_dir "/datapool/config/bazarr/cache"
clean_dir "/datapool/config/immich/cache"
clean_dir "/datapool/config/jellyseerr/cache"

echo ""
echo "=== Cleaning Log Directories ==="
clean_dir "/datapool/config/cleanuperr/logs"
clean_dir "/datapool/config/homepage/logs"
clean_dir "/datapool/config/jellyseerr/logs"
clean_dir "/datapool/config/prowlarr/logs"
clean_dir "/datapool/config/radarr/logs"
clean_dir "/datapool/config/sonarr/logs"
clean_dir "/datapool/config/bazarr/log"
clean_dir "/datapool/config/jellyfin/log"
clean_dir "/datapool/config/qbittorrent/qBittorrent/logs"

echo ""
echo "=== Cleaning Automatic Backups ==="
# Application automatic config backups (regenerated on next config change)
clean_dir "/datapool/config/prowlarr/Backups"
clean_dir "/datapool/config/radarr/Backups"
clean_dir "/datapool/config/sonarr/Backups"

echo ""
echo "=== Cleaning Regenerable Data ==="
# Jellyfin metadata (posters, artwork) - can be regenerated
remove_dir "/datapool/config/jellyfin/data/metadata"
# Media covers - can be re-downloaded
remove_dir "/datapool/config/radarr/MediaCover"
remove_dir "/datapool/config/sonarr/MediaCover"
# GeoIP database - will be re-downloaded
remove_dir "/datapool/config/qbittorrent/qBittorrent/GeoDB"
# Sentry error reporting data
clean_dir "/datapool/config/prowlarr/Sentry"
clean_dir "/datapool/config/radarr/Sentry"
clean_dir "/datapool/config/sonarr/Sentry"
# ASP.NET temp files
clean_dir "/datapool/config/jellyfin/.aspnet"

echo ""
echo "=== After Cleanup ==="
df -h /datapool | grep -v Filesystem
echo "Config size: $(du -sh /datapool/config 2>/dev/null | cut -f1)"
echo ""
echo "=== Cleanup Complete ==="
echo ""
echo "Note: Some services may need to regenerate data on next startup:"
echo "  - Jellyfin: Will regenerate metadata/artwork (may take time)"
echo "  - Radarr/Sonarr: Will re-download media covers and create new backups"
echo "  - Prowlarr: Will create new config backups"
echo "  - qBittorrent: Will re-download GeoIP database"
echo ""
echo "Protected directories (never cleaned):"
echo "  - Grafana/Loki/Prometheus data and configs"
echo "  - Homepage config (requires redeployment if cleaned)"
echo "  - Desktop workspace (user files)"
echo "  - All database directories"
