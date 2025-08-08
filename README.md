# Proxmox Homelab Automation

This repository contains a collection of scripts and configurations to automate the setup of a personal homelab environment on Proxmox VE. The architecture is based on creating separate LXC containers for different service stacks, each managed by Docker Compose.

## ⚠️ Project Philosophy & Disclaimer

This repository documents my personal homelab setup, tailored specifically to my own hardware and network configuration. It is shared publicly to showcase my approach to infrastructure-as-code, automation, and GitOps principles.

**Please be aware that this is not a universal, one-click deployment solution.**

By design, many values such as IP addresses, container IDs, and specific paths are hard-coded for my own convenience and rapid, repeatable deployments. If you wish to adapt this project for your own use, you should be prepared to:

*   Thoroughly review all scripts and configuration files.
*   Replace hard-coded values with your own environment's settings.
*   Adjust resource allocations (CPU, RAM) to match your hardware.

Feel free to fork this repository and use it as an inspiration or a template for your own homelab automation journey!

## Quick Start

Run this command on your Proxmox host to start the setup:

```bash
bash <(curl -s https://raw.githubusercontent.com/Yakrel/proxmox-homelab-automation/main/installer.sh)
```

This will download and run the installer script that will guide you through the initial setup and LXC container configuration.

## Architecture Overview

The philosophy of this project is to isolate different categories of services into their own lightweight Proxmox LXC containers. Each container runs a specific stack of services using Docker and Docker Compose. This approach offers several advantages:

- **Isolation:** Services are separated, preventing dependency conflicts and improving security.
- **Resource Efficiency:** LXC containers are more lightweight than full virtual machines.
- **Modularity:** You can easily deploy, update, or remove a specific stack without affecting others.

The main management is done via the `main-menu.sh` script, which provides an interactive menu to manage the deployment and configuration of these stacks.

## Idempotency & GitOps Philosophy

This project is designed with idempotency and GitOps principles in mind. This means that running the scripts multiple times will always lead to the same desired state, without causing unintended side effects. Configurations are treated as code, allowing for consistent and repeatable deployments across your homelab environment.

## Prerequisites

Before you begin, ensure you have the following:

- A working Proxmox VE installation.
- Your Proxmox host and the new LXC containers should be on the same network.

## Service Stacks

This project is divided into several service stacks, each with its own `docker-compose.yml` and configuration. The deployment scripts will guide you through configuring the necessary environment variables for each stack.

### Available Stacks (Alpine-based)

All LXC containers use Alpine for minimal footprint; only the "development" container includes Node.js (npm). Other stacks contain only Docker Engine + Compose plugin (and Docker daemon metrics). Root console autologin is enabled and SSH server removed (lab convenience assumption).

#### Proxy Stack

- **Directory:** `docker/proxy/`
- **LXC Configuration:** 2 Cores, 2048MB RAM
- **Services:**
    - Cloudflared
    - Watchtower

#### Media Stack

- **Directory:** `docker/media/`
- **LXC Configuration:** 6 Cores, 10240MB RAM
- **Services:**
    - Sonarr
    - Radarr
    - Bazarr
    - Jellyfin
    - Jellyseerr
    - qBittorrent
    - Prowlarr
    - FlareSolverr
    - Recyclarr
    - Watchtower
    - Cleanuparr

#### Files Stack

- **Directory:** `docker/files/`
- **LXC Configuration:** 2 Cores, 3072MB RAM
- **Services:**
    - JDownloader 2
    - MeTube
    - Palmr
    - Watchtower

#### Webtools Stack

- **Directory:** `docker/webtools/`
- **LXC Configuration:** 2 Cores, 6144MB RAM
- **Services:**
    - Homepage
    - Firefox
    - Watchtower

#### Monitoring Stack

- **Directory:** `docker/monitoring/`
- **LXC Configuration:** 4 Cores, 6144MB RAM
- **Services:**
    - Prometheus
    - Grafana
    - Prometheus PVE Exporter
    - Loki
    - Promtail
    - Watchtower

#### Development Stack

- **Directory:** (created on demand)
- **LXC Configuration:** 4 Cores, 6144MB RAM
- **Contents:** Node.js + npm (for development purposes, e.g., Gemini CLI); Docker is not installed.

## Metrics & Dashboards

Container metrics are collected via Docker Engine daemon metrics (`metrics-addr: 0.0.0.0:9323`) instead of cAdvisor. The Prometheus `docker_engine` job scrapes each LXC's Docker daemon. This provides core cgroup CPU / memory / I/O counters; per-layer filesystem details from cAdvisor are intentionally omitted for lower overhead.

Suggested Grafana dashboards:

- **Proxmox VE Overview:** `10347` – High-level view of host and guests.
- **Docker Engine Basic Panels:** Build simple panels with: `rate(container_cpu_usage_seconds_total[5m])`, `container_memory_usage_bytes`, network RX/TX counters.
- **Loki & Promtail Overview:** `12423` – Log pipeline health.