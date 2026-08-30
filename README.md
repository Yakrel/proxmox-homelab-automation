# Proxmox Homelab Automation

Personal Proxmox VE homelab running services across 7 unprivileged LXC containers. The repository contains the LXC definitions, Docker Compose stacks, deployment scripts, firewall setup, backup configuration, and supporting service templates used to run and rebuild the environment.

The setup is built around Proxmox VE, ZFS, Docker Compose, Tailscale, Cloudflare Tunnel, Nginx Proxy Manager, AdGuard Home, Restic/Backrest, and a shared NVIDIA GPU for selected workloads.

- **Overview:** https://infra.byetgin.com/
- **Network topology:** https://infra.byetgin.com/topology.html

---

## Quick Start

Run on the Proxmox host:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/Yakrel/proxmox-homelab-automation/main/installer.sh)"
```

The installer opens an interactive menu for deploying and managing the available stacks. Encrypted environment files are decrypted with the homelab master key during deployment.

---

## Architecture

The environment uses one physical Proxmox host with separate LXCs for gateway, media, utility, desktop, AI, development, and gaming workloads.

| LXC | Address | Purpose |
| --- | --- | --- |
| `100` — `lxc-gateway` | `192.168.1.100` | DNS, reverse proxy, Cloudflare Tunnel |
| `101` — `lxc-media` | `192.168.1.101` | Media and photo services |
| `102` — `lxc-utility` | `192.168.1.102` | Downloads, file sharing, utilities, backup |
| `103` — `lxc-desktop` | `192.168.1.103` | Remote workspace and personal services |
| `104` — `lxc-ai` | `192.168.1.104` | AI and API routing services |
| `105` — `lxc-dev` | `192.168.1.105` | Development tools and runtimes |
| `106` — `lxc-gaming` | `192.168.1.106` | Dedicated game servers (Palworld) |

The LXCs are unprivileged. Selected containers receive access to the NVIDIA GPU through host-side device mapping and userspace library synchronization.

### Storage

- `fastpool` — SSD-backed configuration, databases, and application state
- `datapool` — HDD-backed media and backup data
- ZFS snapshots are used for local rollback
- Restic/Backrest is used for encrypted backups

This is a single-node homelab, not an HA cluster. A host outage therefore causes service downtime; recovery is based on ZFS snapshots, encrypted backups, and repeatable deployment scripts.

---

## Network and Access

There are no inbound WAN port forwards on the router.

### Public web services

Selected web applications are published through:

```text
Internet
  -> Cloudflare Edge
  -> Cloudflare Tunnel
  -> Nginx Proxy Manager
  -> application LXC
```

`cloudflared`, Nginx Proxy Manager, and AdGuard Home run inside `lxc-gateway`.

### Local access

AdGuard Home provides local DNS and split-DNS records for the homelab domains. LAN clients resolve local service names to the gateway address and then connect directly to Nginx Proxy Manager for HTTP/HTTPS services.

### Remote administration

Tailscale provides private access to the Proxmox host and the `192.168.1.0/24` homelab network. Management traffic does not depend on the public Cloudflare path.

### Firewall

LXC inbound traffic is generally default-deny. Required source/port combinations are explicitly allowed for reverse proxy traffic, management devices, monitoring, inter-service dependencies, and selected protocols such as SMB.

---

## Deployment and Automation

`stacks.yaml` contains the LXC IDs, hostnames, CPU, memory, disk sizes, and related deployment settings.

The deployment scripts handle tasks such as:

- LXC creation and lifecycle management
- Docker installation and Compose deployment
- configuration rendering
- encrypted environment handling
- firewall rule application
- NVIDIA userspace synchronization
- stack redeployment
- host helper tasks

Application services are primarily defined with Docker Compose. The Dev LXC is managed directly by the LXC deployment scripts rather than a Compose stack.

Custom container images used by this environment are maintained separately:

| Image | Repository | Purpose |
| --- | --- | --- |
| `desktop-workspace` | [Yakrel/docker-desktop-workspace](https://github.com/Yakrel/docker-desktop-workspace) | Browser + Obsidian remote workspace |
| `backrest-rclone` | [Yakrel/docker-backrest-rclone](https://github.com/Yakrel/docker-backrest-rclone) | Backrest with off-site mirror tooling |

These images are built and published through GitHub Actions.

---

## Backup and Recovery

The backup setup has two main layers:

### ZFS snapshots

Sanoid-managed snapshots provide fast local rollback for configuration mistakes, accidental deletion, and other local recovery cases.

### Restic / Backrest

Backrest writes to an encrypted Restic repository. The repository is then mirrored with rclone to remote targets including an Oracle VPS and Google Drive.

The remote copies are mirrors of the same Restic repository rather than independent retention archives, so repository lifecycle operations such as forget/prune are reflected in those mirrors.

After a backup, sync hooks update the remote mirrors and can send Telegram alerts when a mirror operation fails.

---

## Service Stacks

### Gateway — LXC 100

**Services:** Nginx Proxy Manager, AdGuard Home, Cloudflared

Provides local DNS, split DNS, reverse proxying, and the Cloudflare Tunnel endpoint for published web services.

### Media — LXC 101

**Services:** Jellyfin, Immich, Sonarr, Radarr, Bazarr, Seerr, Prowlarr, qBittorrent, FlareSolverr, Tor Proxy, Profilarr, Tdarr, Cleanuparr

Media and photo workloads run here. Selected services use NVIDIA GPU acceleration. Application databases and internal dependencies use dedicated Docker networks where applicable.

### Utility — LXC 102

**Services:** JDownloader 2, Samba, Repackarr, Backrest-Rclone, MeTube, Changedetection.io, Karakeep

Contains download, file-sharing, utility, monitoring, and backup-related services. SMB access is restricted to the configured administrator devices.

### Desktop — LXC 103

**Services:** Homepage, Desktop Workspace, Guacamole, Sshwifty, CouchDB, Vaultwarden, Desktop OTP Gate, Radicale

Provides the browser-based remote workspace and supporting personal services.

### AI — LXC 104

**Services:** Hermes Agent, OmniRoute, Hindsight

Contains the AI agent interface, model/API routing, and memory services used by the homelab.

### Dev — LXC 105

**Tools:** Code-Server, Node.js, Python, Git/GitHub CLI, Oh My Pi

Provides a persistent remote development environment. Workspace and Code-Server state are stored under `fastpool`.

### Gaming — LXC 106

**Services:** Palworld dedicated server

Provides an isolated game-server workload managed separately from the media and utility stacks.

---

## Secret Handling

Stack environment files are stored encrypted as `.env.enc` files.

Current encryption settings use:

- AES-256-CBC
- PBKDF2-HMAC-SHA256
- 600,000 PBKDF2 iterations

The deployment scripts decrypt the required files at deployment time using the master key.

---

## Project Structure

```text
├── installer.sh                 # Main installer launcher
├── stacks.yaml                  # LXC definitions and resources
├── scripts/
│   ├── main-menu.sh             # Interactive deployment menu
│   ├── helper-menu.sh           # Host helper menu
│   ├── deploy-stack.sh          # Stack deployment orchestration
│   ├── lxc-manager.sh           # LXC lifecycle management
│   ├── fast-redeploy.sh         # Docker stack redeployment
│   ├── helper-functions.sh      # Shared shell functions
│   ├── nvidia-userspace-sync.sh # NVIDIA library sync for LXC
│   ├── setup-tailscale-host.sh  # Tailscale host/subnet setup
│   └── modules/                 # Deployment modules
├── docker/
│   ├── ai/
│   ├── desktop/
│   ├── gaming/
│   ├── gateway/
│   ├── media/
│   └── utility/
├── config/
│   ├── backrest/
│   ├── homepage/
│   ├── samba/
│   ├── sshwifty/
│   ├── couchdb/
│   └── guacamole/
└── docs/
    ├── index.html               # Homelab overview
    └── topology.html            # Network/access topology
```

---

## Requirements

The current configuration assumes:

- Proxmox VE 9.x
- ZFS storage
- `vmbr0` network bridge
- `192.168.1.0/24` LAN
- `fastpool` and `datapool` ZFS pools
- Europe/Istanbul timezone
- NVIDIA GPU for the workloads currently configured to use hardware acceleration

The repository is tailored to this homelab rather than intended as a generic plug-and-play installer. Adapting it to another environment requires changing network, storage, GPU, and secret configuration as needed.

---

## License

Copyright © 2025–2026 Berkay Yetgin

Licensed under the MIT License. See [LICENSE](LICENSE).
