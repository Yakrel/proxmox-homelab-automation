# Proxmox Homelab Automation

This repository contains a collection of scripts and configurations to automate the setup of a personal homelab environment on Proxmox VE. The architecture is based on creating separate LXC containers for different service stacks, each managed by Docker Compose.

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

### Available Stacks

#### Proxy Stack

-   **Directory:** `docker/proxy/`
-   **LXC Configuration:** 2 Cores, 2048MB RAM
-   **Services:**
    -   Cloudflared
    -   Node Exporter
    -   Watchtower

#### Media Stack

-   **Directory:** `docker/media/`
-   **LXC Configuration:** 4 Cores, 10240MB RAM
-   **Services:**
    -   Sonarr
    -   Radarr
    -   Bazarr
    -   Jellyfin
    -   Jellyseerr
    -   qBittorrent
    -   Prowlarr
    -   FlareSolverr
    -   Recyclarr
    -   Node Exporter
    -   Watchtower
    -   Cleanuparr

#### Files Stack

-   **Directory:** `docker/files/`
-   **LXC Configuration:** 2 Cores, 3072MB RAM
-   **Services:**
    -   JDownloader 2
    -   MeTube
    -   Palmr
    -   Node Exporter
    -   Watchtower

#### Webtools Stack

-   **Directory:** `docker/webtools/`
-   **LXC Configuration:** 2 Cores, 6144MB RAM
-   **Services:**
    -   Homepage
    -   Firefox
    -   Node Exporter
    -   Watchtower

#### Monitoring Stack

-   **Directory:** `docker/monitoring/`
-   **LXC Configuration:** 4 Cores, 6144MB RAM
-   **Services:**
    -   Prometheus
    -   Grafana
    -   Node Exporter
    -   Prometheus PVE Exporter
    -   Watchtower

## Grafana Dashboards

After deploying the monitoring stack, you can import pre-configured dashboards into Grafana. Go to `Dashboards -> New -> Import` and use the following IDs:

-   **Proxmox VE Overview:** `10347`
    -   Provides a high-level overview of your Proxmox host and all guest VMs/LXCs.
-   **Node Exporter Full:** `1860`
    -   Provides detailed metrics for individual Linux systems (your LXC containers). Use the dropdown at the top to switch between different instances.


