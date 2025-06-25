# Proxmox Homelab Automation

This repository contains a collection of automation tools designed to customize your Proxmox server and quickly deploy various services.

## Quick Setup

```bash
bash -c "$(wget -qO - https://raw.githubusercontent.com/Yakrel/proxmox-homelab-automation/main/setup.sh)"
```

From the menu you can choose:
- **Options 1-6**: Deploy individual stacks (proxy, media, files, webtools, monitoring, development)
- **Options 7-8**: Security setup, storage setup, system maintenance


## Deployment Approach

This project uses 6 specialized LXC containers:
- **Automated LXC Creation**: Uses Alpine Docker templates for Docker stacks, Ubuntu for development
- **Stack-based Architecture**: 6 separate stacks for better resource management and isolation
- **Individual Stack Deployment**: Deploy each stack separately for better control
- **Interactive Configuration**: Automated password and configuration setup
- **Idempotent Scripts**: All scripts can be safely run multiple times for updates and maintenance
- Docker stacks include their own watchtower for automatic updates

## System Overview

This project deploys a complete homelab automation solution across 6 specialized LXC containers:

- **Proxy Stack (LXC 100)**: Secure external access via Cloudflare tunnels
- **Media Stack (LXC 101)**: Complete media automation with Sonarr, Radarr, Jellyfin, qBittorrent
- **Files Stack (LXC 102)**: File management with JDownloader2, MeTube, and Palmr file sharing
- **Webtools Stack (LXC 103)**: Web dashboard (Homepage) and administrative tools including remote Firefox browser
- **Monitoring Stack (LXC 104)**: System monitoring with Prometheus, Grafana, and Alertmanager
- **Development Stack (LXC 150)**: Ubuntu development environment with Claude Code and Node.js

## LXC Container Specifications

### Recommended Resource Allocation

| Container Name | ID  | Purpose | CPU Cores | RAM | Storage | IP Address | Container Type |
|---------------|-----|---------|-----------|-----|---------|------------|----------------|
| proxy     | 100 | Proxy Services | 1 core | 512MB | 8GB + datapool | 192.168.1.100/24 | Unprivileged LXC |
| media     | 101 | Media Automation | 2 cores | 2GB | 16GB + datapool | 192.168.1.101/24 | Unprivileged LXC |
| files     | 102 | File Management | 1 core | 1GB | 10GB + datapool | 192.168.1.102/24 | Unprivileged LXC |
| webtools  | 103 | Web Tools & Dashboard | 1 core | 1GB | 10GB + datapool | 192.168.1.103/24 | Unprivileged LXC |
| monitoring| 104 | Monitoring & Metrics | 2 cores | 2GB | 12GB + datapool | 192.168.1.104/24 | Unprivileged LXC |
| development| 150 | Development Environment | 2 cores | 2GB | 16GB | 192.168.1.150/24 | Unprivileged LXC |

### ⚠️ LXC Permission System (IMPORTANT)

All LXC containers in this project use **unprivileged containers** for security. This requires specific PUID/PGID configuration:

#### Docker Container Configuration
- **PUID=1000** and **PGID=1000** must be used in ALL Docker containers
- These are the standard user/group IDs inside the LXC container

#### Host-side File Ownership  
- **Host ownership**: Files must be owned by `101000:101000` on the Proxmox host
- **LXC mapping**: UID 1000 (inside container) → UID 101000 (on host)
- **Command**: Use `chown -R 101000:101000 /path/to/directory` on the host

#### Why This Matters
- Unprivileged LXCs use ID mapping for security isolation
- Container UID 1000 automatically maps to host UID 101000
- Wrong ownership (like 1000:1000 on host) will cause permission denied errors
- ALL Docker services expect PUID=1000/PGID=1000 configuration

This permission system is automatically handled by the automation scripts, but manual file operations require these ownership settings.

## Stack Contents & Access URLs

### Proxy Stack (proxy, ID: 100)
- **Cloudflared** – Secure tunnel to external services
- **Access**: Check Cloudflare Zero Trust dashboard for tunnel status

### Media Stack (media, ID: 101)
- **Sonarr** – TV show automation | http://192.168.1.101:8989
- **Radarr** – Movie automation | http://192.168.1.101:7878  
- **Bazarr** – Subtitle management | http://192.168.1.101:6767
- **Jellyfin** – Media server | http://192.168.1.101:8096
- **Jellyseerr** – Media requests | http://192.168.1.101:5055
- **qBittorrent** – Torrent client | http://192.168.1.101:8080
- **Prowlarr** – Indexer proxy | http://192.168.1.101:9696
- **Flaresolverr** – Cloudflare bypass | http://192.168.1.101:8191
- **Recyclarr** – *arr configuration tool (no web UI)
- **Cleanuperr** – Media library cleanup | http://192.168.1.101:9555
- **Huntarr** – Torrent hunting tool | http://192.168.1.101:9705

### Files Stack (files, ID: 102)  
- **JDownloader2** – Download manager | http://192.168.1.102:5801
- **MeTube** – YouTube downloader | http://192.168.1.102:8082
- **Palmr** – File sharing platform | http://192.168.1.102:5487

### Webtools Stack (webtools, ID: 103)
- **Homepage** – Dashboard | http://192.168.1.103:3000
- **Firefox** – Remote browser | http://192.168.1.103:5800 | VNC: 192.168.1.103:5900

### Monitoring Stack (monitoring, ID: 104)
- **Grafana** – Metrics dashboard | http://192.168.1.104:3000
- **Prometheus** – Metrics collection | http://192.168.1.104:9090
- **Alertmanager** – Alert management | http://192.168.1.104:9093
- **cAdvisor** – Container metrics | http://192.168.1.104:8080
- **Proxmox Exporter** – Proxmox metrics | http://192.168.1.104:9221

### Development Stack (development, ID: 150)
- **Ubuntu LTS** – Latest Ubuntu LTS base system  
- **Node.js & npm** – JavaScript runtime and package manager (latest LTS)
- **Git** – Version control
- **Claude Code** – AI-powered coding assistant by Anthropic
- **Python3** – Python development environment
- **Development Tools** – build-essential, tree, jq, tmux, screen, and more
- **Access**: Console via `pct enter 150`

## Media Server: Folder Structure & Configuration

### Recommended Folder Structure (TRaSH Guides Compatible)

To ensure proper hardlinks and atomic moves, the following folder structure is used:

```
/datapool
├── config/
│   ├── sonarr/           # Media Stack (LXC 101)
│   ├── radarr/           # Media Stack (LXC 101)
│   ├── bazarr/           # Media Stack (LXC 101)
│   ├── jellyfin/         # Media Stack (LXC 101)
│   ├── jellyseerr/       # Media Stack (LXC 101)
│   ├── qbittorrent/      # Media Stack (LXC 101)
│   ├── prowlarr/         # Media Stack (LXC 101)
│   ├── flaresolverr/     # Media Stack (LXC 101)
│   ├── recyclarr/        # Media Stack (LXC 101)
│   ├── cloudflared/      # Proxy Stack (LXC 100)
│   ├── jdownloader2/     # Files Stack (LXC 102)
│   ├── metube/           # Files Stack (LXC 102)
│   ├── palmr/            # Files Stack (LXC 102)
│   ├── homepage/         # Webtools Stack (LXC 103)
│   ├── firefox/          # Webtools Stack (LXC 103)
│   └── monitoring/       # Monitoring Stack (LXC 104)
│       ├── prometheus/   # Prometheus configuration
│       ├── grafana/      # Grafana configuration
│       └── alertmanager/ # Alertmanager configuration
├── torrents/
│   ├── movies/        # Complete movie torrents
│   ├── tv/            # Complete TV show torrents
│   └── other/         # Other torrents
├── files/             # Palmr file sharing storage
└── media/
    ├── movies/        # Final location for movies
    ├── tv/            # Final location for TV shows
    └── youtube/
        ├── playlists/
        └── channels/
```

**📖 Media Configuration**: For detailed qBittorrent, Sonarr/Radarr setup and hardlinks configuration, refer to the TRaSH Guides or service documentation.

## Monitoring System

The monitoring stack provides comprehensive system and application monitoring using Prometheus, Grafana, and Alertmanager.

**📖 Detailed Setup**: For complete setup instructions including Proxmox user creation, environment configuration, and troubleshooting, see [docker/monitoring/README-MONITORING.md](docker/monitoring/README-MONITORING.md).



## License

MIT
