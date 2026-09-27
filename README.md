# Proxmox Homelab Automation

Personal Proxmox VE homelab running services across 7 unprivileged LXC containers. The repository contains the LXC definitions, Docker Compose stacks, deployment scripts, firewall setup, and encrypted deployment secrets.

The setup is built around Proxmox VE, ZFS, Docker Compose, Tailscale, Cloudflare Tunnel, Nginx Proxy Manager, AdGuard Home, Restic/Backrest, and a shared NVIDIA GPU for selected workloads.

- **Overview:** https://infra.byetgin.com/
- **Network topology:** https://infra.byetgin.com/topology.html

---

## Quick Start

Run this command on the Proxmox host:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/Yakrel/proxmox-homelab-automation/main/installer.sh)"
```

This opens the interactive deployment menu.

To run an operation directly, append one of the following arguments to the command:

| Arguments | Action |
| --- | --- |
| `ai` | Deploy a specific stack; replace `ai` with another stack name |
| `redeploy ai` | Fast redeploy a single running stack |
| `redeploy all` | Fast redeploy all running stacks |

Encrypted environment files are decrypted with the homelab master key during deployment.

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

The LXCs are unprivileged. Selected containers receive access to the NVIDIA GPU through host-side device mapping and userspace library synchronization. A one-shot host unit prepares the GPU devices before Proxmox starts guests after a reboot.

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
- host directory and permission preparation
- encrypted environment handling
- firewall rule application
- NVIDIA userspace synchronization
- stack redeployment
- host helper tasks

Application services are primarily defined with Docker Compose. The Dev LXC is managed directly by the LXC deployment scripts rather than a Compose stack.

### NVIDIA GPU installation and maintenance

Use **Helper Scripts → Install / Update NVIDIA GPU (GTX 970)** for both
initial host setup and upgrades. The target is the proprietary 580-series
version and SHA-256 in `stacks.yaml`, not the newest driver found online.
This deployment targets the homelab's systemd-boot PVE host and the default
unprivileged UID mapping of media (101) and desktop (103).

- The host owns kernel modules and device permissions. The pinned NVIDIA
  runfile installs the host driver through DKMS; headers and DKMS builds are
  checked for the running kernel and every kernel selected by
  `proxmox-boot-tool kernel list`. ESPs need not remain mounted at `/boot` or
  `/efi`; Proxmox manages their mounts.
- `/etc/homelab-nvidia` holds the manifest and verified installer artifacts.
  GPU guests receive this directory read-only through `mp2`; artifacts are
  not stored below the guests' writable `/fastpool/config` mount.
- Existing GPU guests are inspected first. Maintenance asks before stopping
  them; previously stopped guests may be started temporarily with Docker
  blocked to prepare their runtime. PVE configuration locks prevent concurrent
  starts while devices or the host driver are changing.
  Graceful shutdown uses PVE's `vm_stop` under its configuration mutex while
  retaining the owned maintenance lock (`pct shutdown` has no `--skiplock`).
  Its 120-second graceful timeout does not fall back to a forced shutdown.
- The same guest preparation path is used for a newly provisioned GPU LXC.
  It installs userspace libraries without kernel modules or `nvidia-modprobe`,
  configures the NVIDIA Container Toolkit with `load-kmods=false` and
  `no-cgroups=true`, and starts Docker only after synchronization succeeds.
- If a driver transition requires reboot, GPU guests remain stopped.
  After the operator reboots the host, guests with `onboot=1` synchronize their
  libraries automatically before Docker starts. Other guests remain stopped
  until explicitly started. No second GPU menu run is required.
- A repeat run with matching configuration does not reinstall the driver or
  restart guests/Docker. Selected-stack redeploy and Fast Redeploy All only
  check an existing guest's GPU configuration; drift directs the operator to
  the GPU menu instead of changing drivers beneath running applications.

Driver maintenance is intentionally not a live library update. Download and
host-header preparation happen before shutdown; guest package preparation
may require network access during the approved maintenance window.
On failure after an unsafe change, affected guests remain stopped with a
Proxmox `create` lock. A guest-side maintenance marker also prevents Docker
startup. Diagnose the failed command before clearing either guard; do not
blindly unlock guests or remove the marker. Initial provisioning failures
still require deleting and recreating the incomplete LXC.

#### One-time cleanup of older guest helpers

Older runfile installations may have installed `nvidia-modprobe` inside the
guest. It can change PVE-provided device ownership; the new deployment refuses
to use it and never deletes it automatically. Immediately before the first
GPU menu run, execute this once from the PVE console. It stops Docker in each
affected guest and refuses to delete a package-owned executable:

```bash
bash <<'HOST'
set -euo pipefail
for ct in 101 103; do
    pct exec "$ct" -- bash -s <<'GUEST'
set -euo pipefail
if helper=$(command -v nvidia-modprobe); then
    if dpkg-query -S "$helper"; then
        echo "Package-owned helper: review its owning package before removal" >&2
        exit 1
    fi
    systemctl stop docker.socket docker.service
    rm -- "$helper"
fi
GUEST
done
HOST
```

Do not remove the host's `nvidia-modprobe`; the host preparation command uses
it. The host unit and hook are updated in place, not deleted. After a
successful cutover, obsolete runfiles under `/fastpool/config/temp` may be
removed manually; no recurring residue cleanup is part of deployment.

For live acceptance, verify a host reboot, a second no-op GPU menu run, an
application-only redeploy, and actual NVENC/EGL/CUDA workloads. Local shell
and isolated lifecycle checks cannot establish GPU functionality on PVE.

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

The repository manages infrastructure and deployment; `/fastpool/config` holds application configuration and state. Restore persistent application state from Restic to its corresponding `/fastpool/config` paths before starting services after data loss; intentional service resets are separate operations. Keep the repository decryption key and Restic password accessible independently of the backups.

---

## Service Stacks

### Gateway — LXC 100

**Services:** Nginx Proxy Manager, AdGuard Home, Cloudflared

Provides local DNS, split DNS, reverse proxying, and the Cloudflare Tunnel endpoint for published web services.

### Media — LXC 101

**Services:** Jellyfin, Immich, Sonarr, Radarr, Bazarr, Seerr, Prowlarr, qBittorrent, FlareSolverr, Tor Proxy, Profilarr, Tdarr, Cleanuparr

Media and photo workloads run here. Selected services use NVIDIA GPU acceleration. Application databases and internal dependencies use dedicated Docker networks where applicable.

### Utility — LXC 102

**Services:** JDownloader 2, Samba, Repackarr, Backrest-Rclone, MeTube, Changedetection.io, Karakeep, Beszel

Contains download, file-sharing, utility, monitoring, and backup-related services. The Beszel Hub runs in Docker, while PVE and LXC agents run as native system services (systemd on Debian/PVE and OpenRC on Alpine) so LXC and nested Docker metrics remain accurate. Agent configuration is reconciled during both full deployments and Fast Redeploy.

### Desktop — LXC 103

**Services:** Homepage, Desktop Workspace, Guacamole, Sshwifty, CouchDB, Vaultwarden, Desktop OTP Gate, Radicale

Provides the browser-based remote workspace and supporting personal services.

### AI — LXC 104

**Services:** Hermes Agent, OmniRoute, Hindsight

Contains the AI agent interface, model/API routing, and memory services used by the homelab.

### Dev — LXC 105

**Tools:** Code-Server, Node.js, Python, Git/GitHub CLI, Oh My Pi

Provides a persistent remote development environment. Workspace and Code-Server state are stored under `fastpool`.

Dev packages, Code-Server, Oh My Pi, the terminal font, and Oh My Zsh are installed only when creating the LXC. Both selected-stack redeploy and Fast Redeploy reconcile local configuration without updating these tools; missing prerequisites fail the deployment rather than triggering repair. Tool upgrades are explicit maintenance operations: run `omp update` in the Dev console to update Oh My Pi.

### Gaming — LXC 106

**Services:** Palworld dedicated server (Windows / Wine with UE4SS)

Provides an isolated game-server workload managed separately from the media and utility stacks.

Uses `ghcr.io/ripps818/docker-palworld-dedicated-server-wine:latest`. Game files and mods persist under `/fastpool/config/gameservers/palworld/game`, with automated backups under `/fastpool/config/gameservers/palworld/backups`. Scheduled backups run every 6 hours (retaining 28 archives) and automated restarts run daily at 04:00, Europe/Istanbul.
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
│   ├── nvidia-gpu-prepare.sh     # Host GPU device preparation
│   ├── homelab-nvidia-prepare.service # Prepare devices before PVE guests
│   ├── nvidia-gpu-prestart.sh    # PVE GPU LXC pre-start hook
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
