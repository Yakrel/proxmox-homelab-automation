# Proxmox Homelab Automation

This repository provides automation for creating and configuring Alpine Linux LXC containers on Proxmox using Terraform and Ansible, specifically for deploying services with Docker Compose.

## Quick Start

To use this project, follow these steps:

1. **Prerequisites**:
   - Proxmox VE server installed and configured
   - ZFS datapool already set up on the Proxmox host
   - WSL2 installed on your Windows machine
   - Terraform and Ansible installed in your WSL environment

2. **Initial Setup on Proxmox Host**:
   - Transfer the scripts to your Proxmox host
   - Run the storage configuration: `bash scripts/storage.sh`
   - Run the security hardening: `bash scripts/security.sh`
   - Make sure the datapool is properly configured

3. **Configure Terraform**:
   - Copy `terraform/terraform.tfvars.example` to `terraform/terraform.tfvars`
   - Modify the variables to match your Proxmox setup, including API credentials
   - Ensure your Proxmox API token has the necessary permissions

4. **Run Terraform to Create LXC Containers**:
   - `cd terraform`
   - `terraform init`
   - `terraform apply`
   - Verify that all containers are created successfully

5. **Prepare Environment Variables**:
   - Copy `.env.example` files to `.env` in the respective directories:
     - `cp docker/monitoring/.env.example docker/monitoring/.env`
     - `cp docker/proxy/.env.example docker/proxy/.env`
   - Edit the `.env` files with your credentials

6. **Configure Ansible**:
   - Copy `ansible/inventory.ini.example` to `ansible/inventory.ini`
   - Make sure the IPs match the ones assigned by Terraform
   - Test connection with: `ansible -i inventory.ini all -m ping`

7. **Run Ansible to Deploy Services**:
   - `cd ansible`
   - `ansible-playbook -i inventory.ini deploy.yml`
   - Verify that all services are running correctly: `ansible -i inventory.ini all -a "docker ps"`

## System Architecture

### LXC Containers
Each with isolated environments and dedicated networks for service groups:

1. **Proxy Stack**: ID 125, IP 192.168.1.125
   - **Operating System**: Alpine Linux
   - **Resources**: 2GB RAM, 2 CPU cores
   - Cloudflared (Cloudflare tunnel)
   - AdGuard Home (DNS Server)
   - Watchtower

2. **Media Stack**: ID 102, IP 192.168.1.102
   - **Operating System**: Alpine Linux
   - **Resources**: 16GB RAM, 4 CPU cores
   - Media services (Sonarr, Radarr, Bazarr, Jellyfin, Jellyseerr)
   - Download tools (qBittorrent, Prowlarr)
   - Support services (FlareSolverr, Watchtower, Recyclarr, Youtube-dl)

3. **Monitoring Stack**: ID 103, IP 192.168.1.103
   - **Operating System**: Alpine Linux
   - **Resources**: 4GB RAM, 2 CPU cores
   - Prometheus, Grafana, Alertmanager, Node Exporter, Watchtower

4. **Logging Stack**: ID 104, IP 192.168.1.104
   - **Operating System**: Alpine Linux
   - **Resources**: 4GB RAM, 2 CPU cores
   - Elasticsearch, Logstash, Kibana, Filebeat, Watchtower

### Access Management

- **LXC Access**:
  - Console root access via Proxmox (passwordless)
  - Ansible access from WSL (SSH key-based)
  - No direct external network access except specific ports

## Storage Structure

### Directory Structure
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
- Watchtower runs separately for each stack and automatically updates them
- Docker Compose files are copied to the root directory (`/root`) of each LXC and executed
- CPU and RAM values are optimized for a server with 32GB RAM, adjust if necessary
- RAM values for LXC containers are not strict limits, unused RAM can be utilized by other containers

## Configuration

- `setup_homelab.sh`: Contains all steps for creating and configuring the management LXC
- `terraform/terraform.tfvars.example`: Example LXC container configuration, copy to `terraform.tfvars` before use
- `docker/`: Docker Compose configuration files for each service
- `ansible/`: Ansible playbooks for automatic configuration of all containers



alpine linux indirmesi kontrol edilecek.
