# Proxmox Homelab Automation

This repository contains a collection of automation tools designed to customize your Proxmox server and quickly deploy various services.

## Quick Setup

**Remote Execution:**

```bash
bash -c "$(wget -qO - https://raw.githubusercontent.com/Yakrel/proxmox-homelab-automation/main/setup.sh)"
```

## Deployment Approach

This project uses an **improved automated installation** approach:
- The `setup.sh` script now includes options for:
  - Security installation (Fail2Ban)
  - Storage setup (Samba, Sanoid)
  - Proxy LXC preparation
  - Media Server LXC preparation
- Each script automates the directory structure creation, permission setting, and volume mounting.
- You'll still need to manually install Docker and Docker Compose inside the LXC containers.

## Overview

With this project, you can deploy the following services:

- **Security Setup**: Enhance Proxmox and SSH security with Fail2Ban.
- **Storage Setup**: Configure Samba sharing and manage ZFS snapshots with Sanoid.
- **Media Server**: Deploy Sonarr, Radarr, Jellyfin, and more.
- **Proxy System**: Deploy Cloudflared, AdGuard Home, and Firefox Remote Browser.

## Container Contents

### Proxy (ID: 100)
- Cloudflared – Cloudflare Tunnel
- AdGuard Home – DNS filtering
- Firefox – Remote accessible browser

### Media Server (ID: 101)
- Sonarr, Radarr – TV shows and movie tracking
- Bazarr – Subtitle management
- Jellyfin – Media server
- Jellyseerr – Media requests
- qBittorrent, Prowlarr, Flaresolverr, Recyclarr
- YouTube-DL – YouTube video downloading

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
