# Proxmox Homelab Automation

This repository contains a collection of automation tools designed to customize your Proxmox server and quickly deploy various services.

## Quick Setup

### One-Command Complete Deployment

**Deploy Everything (All 5 Stacks):**
```bash
bash -c "$(wget -qO - https://raw.githubusercontent.com/Yakrel/proxmox-homelab-automation/main/setup.sh)" && echo "8" | bash -c "$(wget -qO - https://raw.githubusercontent.com/Yakrel/proxmox-homelab-automation/main/setup.sh)"
```

**Individual Stack Deployment:**
```bash
# Download and run setup script
bash -c "$(wget -qO - https://raw.githubusercontent.com/Yakrel/proxmox-homelab-automation/main/setup.sh)"

# Choose option 8 (Automated Deployment) from menu
# Then select individual stack or complete deployment
```

### Manual Setup Options
The setup script provides these options:
1. Security Installation (Fail2Ban)
2. Storage Installation (Samba, Sanoid) 
3. Individual LXC preparation
8. **Automated Deployment (Recommended)**

## Deployment Approach

This project uses a **fully automated deployment** approach with 5 specialized LXC containers:
- **Automated LXC Creation**: Uses community Alpine Docker templates for consistent setup
- **Stack-based Architecture**: 5 separate stacks for better resource management and isolation
- **One-Click Deployment**: Complete homelab deployment with a single command
- **Interactive Configuration**: Automated password and configuration setup
- Each stack includes its own watchtower for automatic updates

## Overview

This project deploys a complete homelab automation solution with 5 specialized stacks:

- **Security & Storage Setup**: Enhance Proxmox security with Fail2Ban and configure Samba/Sanoid
- **Media Stack (LXC 101)**: Complete media automation with Sonarr, Radarr, Jellyfin, qBittorrent
- **Proxy Stack (LXC 100)**: Secure external access via Cloudflare tunnels
- **Downloads Stack (LXC 102)**: General downloading with JDownloader2 and MeTube
- **Utility Stack (LXC 103)**: Administrative tools including remote Firefox browser
- **Monitoring Stack (LXC 104)**: System monitoring with Prometheus, Grafana, and Alertmanager

## LXC Container Specifications

### Recommended Resource Allocation

| Container Name | ID  | Purpose | CPU Cores | RAM | Storage | IP Address | Container Type |
|---------------|-----|---------|-----------|-----|---------|------------|----------------|
| lxc-proxy-01     | 100 | Proxy Services | 1 core | 2GB | 8GB + datapool | 192.168.1.100/24 | Unprivileged LXC |
| lxc-media-01     | 101 | Media Automation | 4 cores | 8GB | 16GB + datapool | 192.168.1.101/24 | Unprivileged LXC |
| lxc-downloads-01 | 102 | Download Management | 2 cores | 4GB | 8GB + datapool | 192.168.1.102/24 | Unprivileged LXC |
| lxc-utility-01   | 103 | Utility Services | 2 cores | 4GB | 8GB + datapool | 192.168.1.103/24 | Unprivileged LXC |
| lxc-monitoring-01| 104 | Monitoring & Metrics | 2 cores | 4GB | 10GB + datapool | 192.168.1.104/24 | Unprivileged LXC |

## Stack Contents & Access URLs

### Proxy Stack (lxc-proxy-01, ID: 100)
- **Cloudflared** – Secure tunnel to external services
- **Access**: Check Cloudflare Zero Trust dashboard for tunnel status

### Media Stack (lxc-media-01, ID: 101)
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

### Downloads Stack (lxc-downloads-01, ID: 102)  
- **JDownloader2** – Download manager | http://192.168.1.102:5801
  - **MeTube** – YouTube downloader | http://192.168.1.102:8082

### Utility Stack (lxc-utility-01, ID: 103)
- **Firefox** – Remote browser | http://192.168.1.103:5800 | VNC: 192.168.1.103:5900

### Monitoring Stack (lxc-monitoring-01, ID: 104)
- **Grafana** – Metrics dashboard | http://192.168.1.104:3000
- **Prometheus** – Metrics collection | http://192.168.1.104:9090
- **Alertmanager** – Alert management | http://192.168.1.104:9093
  - **cAdvisor** – Container metrics | http://192.168.1.104:8081
- **Proxmox Exporter** – Proxmox metrics | http://192.168.1.104:9221

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
│   ├── watchtower-media/ # Media Stack (LXC 101)
│   ├── cloudflared/      # Proxy Stack (LXC 100)
│   ├── watchtower-proxy/ # Proxy Stack (LXC 100)
│   ├── jdownloader2/     # Downloads Stack (LXC 102)
│   ├── metube/           # Downloads Stack (LXC 102)
│   ├── watchtower-downloads/ # Downloads Stack (LXC 102)
│   ├── firefox/          # Utility Stack (LXC 103)
│   ├── watchtower-utility/   # Utility Stack (LXC 103)
│   ├── monitoring/       # Monitoring Stack (LXC 104)
│   │   ├── prometheus/   # Prometheus configuration
│   │   ├── grafana/      # Grafana configuration
│   │   └── alertmanager/ # Alertmanager configuration
│   └── watchtower-monitoring/ # Monitoring Stack (LXC 104)
├── torrents/
│   ├── movies/        # Complete movie torrents
│   ├── tv/            # Complete TV show torrents
│   └── other/         # Other torrents
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
   - Disable "Append .!qB extension to incomplete files"

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

## Monitoring System Setup

The monitoring stack provides comprehensive system and application monitoring using Prometheus, Grafana, and Alertmanager.

### Automated Setup
The monitoring stack can be deployed automatically using the setup script:
```bash
# Run setup script and choose option 8 (Automated Deployment)
bash -c "$(wget -qO - https://raw.githubusercontent.com/Yakrel/proxmox-homelab-automation/main/setup.sh)"
# Then select option 5 (Deploy Monitoring Stack)
```

### Manual Configuration Steps

After the automated deployment, complete these manual steps:

#### 1. Proxmox API User Setup
Create a monitoring user in Proxmox for the PVE exporter:

1. Go to Datacenter > Permissions > Users
2. Add user: `monitoring@pve`
3. Set a strong password
4. Go to Datacenter > Permissions > Groups
5. Create group: `monitoring`
6. Go to Datacenter > Permissions
7. Add permission: Path: `/`, User: `monitoring@pve`, Role: `PVEAuditor`

#### 2. Environment Variables
Set these environment variables in your monitoring LXC before starting services:
```bash
export GRAFANA_ADMIN_PASSWORD="your_secure_password"
export PVE_USER="monitoring@pve"
export PVE_PASSWORD="your_proxmox_monitoring_password"
export PVE_URL="https://your_proxmox_ip:8006"
```

#### 3. Update Prometheus Configuration
Edit `/datapool/config/monitoring/prometheus/prometheus.yml` and update the IP addresses to match your LXC containers:
- Replace `10.0.0.100` with your Proxy LXC IP
- Replace `10.0.0.101` with your Media LXC IP  
- Replace `10.0.0.102` with your Downloads LXC IP
- Replace `10.0.0.103` with your Utility LXC IP

#### 4. Grafana Dashboard Import
After services start, access Grafana at `http://your_monitoring_lxc_ip:3000`:

1. Login with admin/your_password
2. Go to Dashboards > Import
3. Import these dashboard IDs:
   - **10347** - Proxmox via Prometheus
   - **1860** - Node Exporter Full
   - **193** - Docker Container & Host Metrics

#### 5. Configure Alertmanager (Optional)
Edit `/datapool/config/monitoring/alertmanager/alertmanager.yml` to configure notifications:
- Email alerts
- Slack/Discord webhooks
- Custom notification channels

### Port Overview
- **Grafana**: 3000
- **Prometheus**: 9090  
- **Alertmanager**: 9093
- **cAdvisor**: 8080
- **PVE Exporter**: 9221
- **Node Exporters**: 9100-9103 (one per LXC)

### Planned Features

These features are planned for future releases:

### Logging System
- Elasticsearch – Log storage
- Logstash – Log processing
- Kibana – Log visualization
- Filebeat – Log collection

## License

MIT
