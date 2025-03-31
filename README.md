# Proxmox Homelab Automation

This repository contains a collection of automation tools designed to customize your Proxmox server and quickly deploy various services.

## Quick Setup

**Remote Execution:**

```bash
bash -c "$(wget -qO - https://raw.githubusercontent.com/Yakrel/proxmox-homelab-automation/main/setup.sh)"
```

The setup script will automatically download all necessary script files from the GitHub repository, so you don't need to manually transfer any files to your Proxmox server.

## Deployment Approach

This project uses an **improved automated installation** approach:
- The `setup.sh` script now includes options for:
  - Security installation (Fail2Ban)
  - Storage setup (Samba, Sanoid)
  - Proxy LXC preparation
  - Media Server LXC preparation
- Each script automates the directory structure creation, permission setting, and volume mounting.

## Overview

With this project, you can deploy the following services:

- **Security Setup**: Enhance Proxmox and SSH security with Fail2Ban.
- **Storage Setup**: Configure Samba sharing and manage ZFS snapshots with Sanoid.
- **Media Server**: Deploy Sonarr, Radarr, Jellyfin, and more.
- **Proxy System**: Deploy Cloudflared, AdGuard Home, and Firefox Remote Browser.

## LXC Container Specifications

### Recommended Resource Allocation

| Container Name | ID  | Purpose | CPU Cores | RAM | Storage | IP Address | Container Type |
|---------------|-----|---------|-----------|-----|---------|------------|----------------|
| lxc-proxy-01  | 100 | Proxy   | 2 cores   | 4GB | 10GB + datapool | 192.168.1.100/24 | Unprivileged LXC |
| lxc-media-01  | 101 | Media   | 4 cores   | 12GB | 20GB + datapool | 192.168.1.101/24 | Unprivileged LXC |

## Container Contents

### Proxy (lxc-proxy-01, ID: 100)
- Cloudflared – Cloudflare Tunnel
- AdGuard Home – DNS filtering
- Firefox – Remote accessible browser

### Media Server (lxc-media-01, ID: 101)
- Sonarr, Radarr – TV shows and movie tracking
- Bazarr – Subtitle management
- Jellyfin – Media server
- Jellyseerr – Media requests
- qBittorrent, Prowlarr, Flaresolverr, Recyclarr
- MeTube – YouTube video downloading

## Media Server: Folder Structure & Configuration

### Recommended Folder Structure (TRaSH Guides Compatible)

To ensure proper hardlinks and atomic moves, the following folder structure is used:

```
/datapool
├── config/
│   ├── sonarr/
│   ├── radarr/
│   ├── bazarr/
│   ├── jellyfin/
│   ├── jellyseerr/
│   ├── qbittorrent/
│   ├── prowlarr/
│   ├── flaresolverr/
│   ├── watchtower-media/
│   ├── recyclarr/
│   └── metube/
├── torrents/
│   ├── movies/        # Complete movie torrents
│   └── tv/            # Complete TV show torrents 
└── media/
    ├── movies/        # Final location for movies
    ├── tv/            # Final location for TV shows
    └── youtube/
        ├── playlists/
        └── channels/
```

### qBittorrent Configuration

For proper hardlinks and optimal performance, configure qBittorrent as follows:

1. Go to Settings > Downloads
   - Enable "Keep incomplete torrents in:" and set it to a temporary location *inside* the container if desired (e.g., `/tmp/incomplete`), but it's often simpler to let qBittorrent manage this internally without a specific path.
   - Ensure "Move completed torrents to" is **disabled** (categories will handle this).
   - Disable "Append .!qB extension to incomplete files`

2. Add Categories:
   - Category: `tv`
     - Save Path: `/datapool/torrents/tv`
   - Category: `movies`
     - Save Path: `/datapool/torrents/movies`

3. Go to Settings > BitTorrent:
   - Disable "Automatically add torrents from:" option

4. Go to Settings > Connection:
   - Set proper port number that doesn't conflict with other services

### Sonarr/Radarr Configuration

1. Media Management Settings:
   - Enable "Use Hardlinks instead of Copy"
   - Disable "Copy using Hardlinks when importing from torrents"

2. Root Folders:
   - Sonarr: `/datapool/media/tv`
   - Radarr: `/datapool/media/movies`

3. Download Client Settings (qBittorrent):
   - Host: qbittorrent
   - Port: 8080
   - Category: `tv` (for Sonarr) or `movies` (for Radarr)
   - Directory: (leave empty)

### Hardlinks Verification

To verify hardlinks are working properly:

```bash
# Create a test file in torrents folder
touch /datapool/torrents/movies/test-file

# Create a hardlink in media folder
ln /datapool/torrents/movies/test-file /datapool/media/movies/test-hardlink

# Verify both files have the same inode number (should match)
ls -i /datapool/torrents/movies/test-file /datapool/media/movies/test-hardlink

# Clean up test files
rm /datapool/torrents/movies/test-file /datapool/media/movies/test-hardlink
```

If both files show the same inode number, hardlinks are working correctly.

## Planned Features

These features are planned for future releases:

### Monitoring System
- Prometheus – Metrics collection
- Grafana – Metrics visualization
- Alertmanager – Alert management
- Node Exporter – Host metrics

### Logging System
- Elasticsearch – Log storage
- Logstash – Log processing
- Kibana – Log visualization
- Filebeat – Log collection

## License

MIT
