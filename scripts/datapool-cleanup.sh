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
echo "Config size: $(du -sh /fastpool/config 2>/dev/null | cut -f1)"
echo ""

# Function to safely remove directory contents
clean_dir() {
    local dir="$1"
    if [ -d "$dir" ]; then
        local size=$(du -sh "$dir" 2>/dev/null | cut -f1 || echo "0")
        find "$dir" -mindepth 1 -delete
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
clean_dir "/fastpool/config/qbittorrent/.cache"
clean_dir "/fastpool/config/bazarr/cache"
clean_dir "/fastpool/config/immich/cache"
clean_dir "/fastpool/config/jellyseerr/cache"

echo ""
echo "=== Cleaning Log Directories ==="
clean_dir "/fastpool/config/cleanuperr/logs"
clean_dir "/fastpool/config/homepage/logs"
clean_dir "/fastpool/config/jellyseerr/logs"
clean_dir "/fastpool/config/prowlarr/logs"
clean_dir "/fastpool/config/radarr/logs"
clean_dir "/fastpool/config/sonarr/logs"
clean_dir "/fastpool/config/bazarr/log"
clean_dir "/fastpool/config/jellyfin/log"
clean_dir "/fastpool/config/qbittorrent/qBittorrent/logs"
clean_dir "/fastpool/config/npm/data/logs"
clean_dir "/fastpool/config/code-server/data/coder-logs"
clean_dir "/fastpool/config/tdarr/server/Tdarr/Logs"

echo ""
echo "=== Cleaning Automatic Backups ==="
# Application automatic config backups (regenerated on next config change)
clean_dir "/fastpool/config/prowlarr/Backups"
clean_dir "/fastpool/config/radarr/Backups"
clean_dir "/fastpool/config/sonarr/Backups"
clean_dir "/fastpool/config/bazarr/backup"
clean_dir "/fastpool/config/tdarr/server/Tdarr/Backups"

echo ""
echo "=== Cleaning Regenerable Data ==="
# GeoIP database - will be re-downloaded
remove_dir "/fastpool/config/qbittorrent/qBittorrent/GeoDB"
# App-maintained downloaded definitions and templates
remove_dir "/fastpool/config/prowlarr/Definitions"
remove_dir "/fastpool/config/recyclarr/resources"
remove_dir "/fastpool/config/recyclarr/repositories"
# Temporary upload and runtime data
clean_dir "/fastpool/config/npm/data/nginx/temp"
clean_dir "/fastpool/config/vaultwarden/tmp"
clean_dir "/fastpool/config/tdarr/server/Tdarr/DB2/JobReports"
# Sentry error reporting data
clean_dir "/fastpool/config/prowlarr/Sentry"
clean_dir "/fastpool/config/radarr/Sentry"
clean_dir "/fastpool/config/sonarr/Sentry"
# ASP.NET temp files
clean_dir "/fastpool/config/jellyfin/.aspnet"

echo ""
echo "=== After Cleanup ==="
df -h /datapool | grep -v Filesystem
echo "Config size: $(du -sh /fastpool/config 2>/dev/null | cut -f1)"
echo ""
echo "=== Cleanup Complete ==="
echo ""
echo "Note: Some services may need to regenerate data on next startup:"
echo "  - Radarr/Sonarr/Prowlarr/Tdarr: Will create new automatic app backups"
echo "  - Prowlarr: Will create new config backups"
echo "  - qBittorrent: Will re-download GeoIP database"
echo "  - Recyclarr: Will re-download TRaSH Guides resources"
echo ""
echo "Protected directories (never cleaned):"
echo "  - Jellyfin metadata/cache/subtitles"
echo "  - Radarr/Sonarr media covers"
echo "  - Vaultwarden icon cache"
echo "  - Homepage config (requires redeployment if cleaned)"
echo "  - Desktop workspace (user files)"
echo "  - All database directories"
