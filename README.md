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

### Available Stacks

#### Proxy Stack

-   **Directory:** `docker/proxy/`
-   **LXC Configuration:** 2 Cores, 2048MB RAM
-   **Services:**
    -   Cloudflared
    -   cAdvisor
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
    -   cAdvisor
    -   Watchtower
    -   Cleanuparr

#### Files Stack

-   **Directory:** `docker/files/`
-   **LXC Configuration:** 2 Cores, 3072MB RAM
-   **Services:**
    -   JDownloader 2
    -   MeTube
    -   Palmr
    -   cAdvisor
    -   Watchtower

#### Webtools Stack

-   **Directory:** `docker/webtools/`
-   **LXC Configuration:** 2 Cores, 6144MB RAM
-   **Services:**
    -   Homepage
    -   Firefox
    -   cAdvisor
    -   Watchtower

#### Monitoring Stack

-   **Directory:** `docker/monitoring/`
-   **LXC Configuration:** 4 Cores, 6144MB RAM
-   **Services:**
    -   Prometheus
    -   Grafana
    -   cAdvisor
    -   Prometheus PVE Exporter
    -   Watchtower

## Grafana Dashboards

After deploying the monitoring stack, you can import pre-configured dashboards into Grafana. Go to `Dashboards -> New -> Import` and use the following IDs:

-   **Proxmox VE Overview:** `10347`
    -   Provides a high-level overview of your Proxmox host and all guest VMs/LXCs.
-   **cAdvisor Exporter:** `13979`
    -   Provides detailed container-level metrics for each LXC. Use the dropdown at the top to switch between different instances.
-   **Loki & Promtail:** `12423`
    -   Offers a comprehensive overview of the Loki logging system and the Promtail agent's performance.