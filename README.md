# Proxmox Terraform and Ansible Homelab Automation

This repository provides automation for creating and configuring LXC containers on Proxmox using Terraform and Ansible, specifically for automatically deploying services with Docker Compose.

## Quick Start

To use this project, follow these steps:

1. **Management Container Setup**:
   - Download the `setup_homelab.sh` script from GitHub
   - Run this script on your Proxmox host
   - The script will create a management container (ID:900) and install necessary tools

2. **Other LXC Setup (Inside Management Container)**:
   - SSH or Console into the management container
   - Clone the repository
   - Use Terraform and Ansible to create and configure other containers

## System Architecture

### LXC Containers
Each with isolated environments and dedicated networks for service groups:

1. **Management Container**: ID 900 (or custom ID)
   - **Operating System**: Ubuntu 24.04 or Debian 12 (selectable during setup)
   - Terraform, Ansible and other automation tools
   - Management of other container creation and configuration

2. **Proxy Stack**: ID 125, IP 192.168.1.125
   - **Operating System**: Alpine Linux
   - **Resources**: 2GB RAM, 2 CPU cores
   - Cloudflared (Cloudflare tunnel)
   - AdGuard Home (DNS Server)
   - Watchtower

3. **Media Stack**: ID 102, IP 192.168.1.102
   - **Operating System**: Alpine Linux
   - **Resources**: 16GB RAM, 4 CPU cores
   - Media services (Sonarr, Radarr, Bazarr, Jellyfin, Jellyseerr)
   - Download tools (qBittorrent, Prowlarr)
   - Support services (FlareSolverr, Watchtower, Recyclarr, Youtube-dl)

4. **Monitoring Stack**: ID 103, IP 192.168.1.103
   - **Operating System**: Alpine Linux
   - **Resources**: 4GB RAM, 2 CPU cores
   - Prometheus, Grafana, Alertmanager, Node Exporter, Watchtower

5. **Logging Stack**: ID 104, IP 192.168.1.104
   - **Operating System**: Alpine Linux
   - **Resources**: 4GB RAM, 2 CPU cores
   - Elasticsearch, Logstash, Kibana, Filebeat, Watchtower

### Access Management

- **Management Container**: Console root access via Proxmox (passwordless)
- **Other LXCs**: 
  - Console root access via Proxmox (passwordless)
  - Ansible access from management container (SSH key-based)
  - No direct external network access

## Storage Structure

### Created Directory Structure
```
/datapool/                       # ZFS pool mount point (must exist)
├── config/                      # All service configurations (created by script)
│   ├── sonarr-config/
│   ├── radarr-config/
│   ├── prometheus-config/
│   ├── elasticsearch-config/
│   └── ...
├── media/                       # Main media library (created by script)
│   ├── movies/                  # Movies
│   ├── tv/                      # TV shows
│   └── youtube/                 # YouTube downloads
└── torrents/                    # Download folder (created by script)
    ├── movies/                  # Movie downloads
    └── tv/                      # TV show downloads
```

## Important Notes

- All Docker data is stored under `/datapool`, so data persists even if containers are deleted
- Docker and Docker Compose are automatically installed on Alpine Linux containers
- Ubuntu or Debian options are provided for the management LXC - Debian is lighter
- Watchtower runs separately for each stack and automatically updates them
- Docker Compose files are copied to the root directory (`/root`) of each LXC and executed
- CPU and RAM values are optimized for a server with 32GB RAM, adjust if necessary
- RAM values for LXC containers are not strict limits, unused RAM can be utilized by other containers

## Configuration

- `setup_homelab.sh`: Contains all steps for creating and configuring the management LXC
- `terraform/terraform.tfvars.example`: Example LXC container configuration, copy to `terraform.tfvars` before use
- `docker/`: Docker Compose configuration files for each service
- `ansible/`: Ansible playbooks for automatic configuration of all containers
