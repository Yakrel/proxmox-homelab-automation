# Proxmox Homelab Automation

This repository contains a collection of automation tools designed to customize your Proxmox server and quickly deploy various services.

## Quick Setup

**Remote Execution:**

```bash
bash -c "$(wget -qO - https://raw.githubusercontent.com/Yakrel/proxmox-homelab-automation/main/setup.sh)"
```

## Deployment Approach

This project uses a **semi-automated installation** approach:
- The `setup.sh` script performs only the security and storage installations.
- For Docker Compose deployments, manually copy the Docker Compose files to the respective LXC containers and run `docker compose up -d`.
- Each Docker Compose file includes the necessary initial setup commands.

## Overview

With this project, you can deploy the following services:

- **Security Setup**: Enhance Proxmox and SSH security with Fail2Ban.
- **Storage Setup**: Configure Samba sharing and manage ZFS snapshots with Sanoid.
- **Media Server**: Deploy Sonarr, Radarr, Jellyfin, and more.
- **Monitoring System**: Deploy Prometheus, Grafana, and Alertmanager.
- **Logging System**: Deploy an ELK Stack (Elasticsearch, Logstash, Kibana).
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

### Monitoring (ID: 102)
- Prometheus – Metrics collection
- Grafana – Metrics visualization
- Alertmanager – Alert management
- Node Exporter – Host metrics

### Logging (ID: 103)
- Elasticsearch – Log storage
- Logstash – Log processing
- Kibana – Log visualization
- Filebeat – Log collection

## License

MIT
