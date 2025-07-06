# Proxmox Homelab Automation

This repository contains a collection of scripts and configurations to automate the setup of a personal homelab environment on Proxmox VE. The architecture is based on creating separate LXC containers for different service stacks, each managed by Docker Compose.

## Architecture Overview

The philosophy of this project is to isolate different categories of services into their own lightweight Proxmox LXC containers. Each container runs a specific stack of services using Docker and Docker Compose. This approach offers several advantages:

- **Isolation:** Services are separated, preventing dependency conflicts and improving security.
- **Resource Efficiency:** LXC containers are more lightweight than full virtual machines.
- **Modularity:** You can easily deploy, update, or remove a specific stack without affecting others.

The main management is done via the `main-menu.sh` script, which provides an interactive menu to manage the deployment and configuration of these stacks.

## Directory Structure

```
.
├── .gitignore
├── installer.sh
├── README.md
├── config/
│   └── homepage/
│       ├── bookmarks.yaml
│       ├── docker.yaml
│       ├── services.yaml
│       ├── settings.yaml
│       └── widgets.yaml
├── docker/
│   ├── files/
│   │   ├── .env.example
│   │   └── docker-compose.yml
│   ├── media/
│   │   ├── .env.example
│   │   └── docker-compose.yml
│   ├── monitoring/
│   │   ├── .env.example
│   │   └── docker-compose.yml
│   ├── proxy/
│   │   ├── .env.example
│   │   └── docker-compose.yml
│   └── webtools/
│       ├── .env.example
│       └── docker-compose.yml
└── scripts/
    ├── deploy-stack.sh
    ├── helper-menu.sh
    ├── lxc-manager.sh
    ├── main-menu.sh
    └── stack-config.sh
```

## Prerequisites

Before you begin, ensure you have the following:

- A working Proxmox VE installation.
- A prepared LXC template (e.g., Debian or Ubuntu) with basic tools like `curl` and `git` installed.
- Your Proxmox host and the new LXC containers should be on the same network.
- A local DNS server (like Pi-hole or AdGuard Home) is recommended for easy service access via hostnames.

## Getting Started

### Quick Start

Run this command on your Proxmox host to start the setup:

```bash
bash <(curl -s https://raw.githubusercontent.com/Yakrel/proxmox-homelab-automation/main/installer.sh)
```

This will download and run the installer script that will guide you through the initial setup and LXC container configuration.

## Service Stacks

This project is divided into several service stacks, each with its own `docker-compose.yml` and configuration. Before deploying a stack, you must configure its corresponding `.env` file.

### How to Configure a Stack

For each stack you want to deploy (e.g., `monitoring`, `media`):

1.  Navigate to the stack's directory (e.g., `cd docker/monitoring`).
2.  Copy the example environment file: `cp .env.example .env`.
3.  Edit the `.env` file with your specific values (domain names, paths, credentials, etc.).

### Available Stacks

#### Monitoring Stack

-   **Directory:** `docker/monitoring/`
-   **Services:**
    -   **Prometheus:** For metrics collection.
    -   **Grafana:** For visualizing metrics with pre-configured dashboards.
    -   **Alertmanager:** For handling alerts.
    -   **Node Exporter:** For exporting host metrics.
-   **Default Credentials:**
    -   **Grafana:** `admin:grafana` (it is highly recommended to change this).
-   **Ports:**
    -   Grafana: `3000`
    -   Prometheus: `9090`

#### Media Stack

-   **Directory:** `docker/media/`
-   **Services:** *[List of services to be added, e.g., Plex, Sonarr, Radarr]*
-   **Configuration:** Details about `.env` variables for media paths, etc.

#### Proxy Stack

-   **Directory:** `docker/proxy/`
-   **Services:** *[e.g., Nginx Proxy Manager, Traefik]*
-   **Configuration:** Details about domain configuration and network settings.

#### Other Stacks

-   `docker/files/`
-   `docker/webtools/`

*(These sections should be filled out with details similar to the Monitoring stack.)*

## Usage

The main interaction with this project is through the `scripts/main-menu.sh`. This script provides a user-friendly interface to:

-   Deploy a new service stack to a new LXC container.
-   Update an existing stack.
-   Manage configurations.

To start the menu, run:
```bash
bash scripts/main-menu.sh
```

## Homepage Configuration

The `config/homepage` directory contains the configuration for a [Homepage dashboard](https://gethomepage.dev/). This allows you to have a central, browser-based dashboard to access all your homelab services. The configuration files are:

-   `services.yaml`: Defines the services to be displayed.
-   `bookmarks.yaml`: For your favorite links.
-   `settings.yaml`: General settings for the homepage.
-   `widgets.yaml`: To display dynamic information (e.g., system stats).