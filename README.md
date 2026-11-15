# Proxmox Homelab Automation

Personal Proxmox VE homelab running services across 7 unprivileged LXC containers. The repository contains the LXC definitions, Docker Compose stacks, deployment scripts, firewall setup, and encrypted deployment secrets.

The setup is built around Proxmox VE, ZFS, Docker Compose, Tailscale, Cloudflare Tunnel, Nginx Proxy Manager, AdGuard Home, Restic/Backrest, and a shared NVIDIA GPU for selected workloads.

- **Overview:** https://infra.byetgin.com/
- **Network topology:** https://infra.byetgin.com/topology.html

---

> **This is a personal homelab setup, not a general-purpose installer.** The `.env.enc` files are encrypted with the owner's private passphrase and cannot be decrypted with any other key. Hardware and network details (`192.168.1.x` addressing, LXC IDs 100–106, `fastpool`/`datapool` ZFS pools, NVIDIA GTX 970, domains, Cloudflare Tunnel, Tailscale) are hardcoded, and the installer always downloads from this repository. To reuse it, fork the repo, point `installer.sh` at your fork, replace every `.env.enc` with your own (see [Secret Handling](#secret-handling)), and adapt `stacks.yaml` and the compose files to your environment.

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

The repository depends on this cloud-managed Tailscale policy, which is not stored here and must be maintained in the Tailscale admin console:

- Personal devices (`autogroup:member`) have full access to the tailnet and the subnet route.
- The work PC carries `tag:work`, which has exactly one grant: `192.168.1.104` on `tcp:8888` (Hindsight API, per-project banks named after the project directory). `tag:work` is listed in `tagOwners`, and a `tests` block asserts that it cannot reach the Proxmox host, the gateway NPM admin or any other LXC port.

Tailnet clients reach the LAN through the PVE host, which masquerades them as `192.168.1.10`. LXC firewall rules therefore see `192.168.1.10`, not the client. The Tailscale policy is the only filter for host-level services: tailscaled's `ts-input` chain accepts everything arriving on `tailscale0`, so the host firewall and its `management` IP set do not apply to the Proxmox web UI or SSH when reached through the tailnet.

### Firewall

LXC inbound traffic is generally default-deny. Required source/port combinations are explicitly allowed for reverse proxy traffic, management devices, monitoring, inter-service dependencies, and selected protocols such as SMB. Each LXC's complete PVE guest firewall file is stored as `firewall/<stack>.fw` and applied on every deploy and redeploy.

Each LXC also has the PVE IP filter enabled, so a guest cannot send traffic with another guest's source address. The host firewall restricts SSH, the Proxmox web UI, and SPICE to the `management` IP set in `/etc/pve/firewall/cluster.fw` for LAN clients (not for the tailnet, see Remote administration), and sshd accepts root logins only from Sshwifty (desktop LXC) and loopback. Both are written by the host helper menu's security option, not by the per-stack deployment. Tailscale SSH is enabled by the Tailscale host setup script and is handled by tailscaled, so it is unaffected by the sshd restriction.

The Tailscale host setup script also installs a mangle `FORWARD` rule that clears Tailscale's packet mark once a packet is bridged to an LXC. Without it, an LXC with `firewall=1` sits behind a firewall bridge, the packet is masqueraded a second time to the host's Tailscale address, and the LXC replies to an address it cannot route. With it, LXC firewall rules are evaluated for tailnet clients as well. The AI LXC allows `192.168.1.10` to the Hindsight API on `8888` for that reason.

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

Sanoid-managed snapshots provide fast local rollback for configuration mistakes, accidental deletion, and other local recovery cases. `fastpool` (configuration and application state) keeps 24 hourly, 7 daily, and 1 monthly snapshot; `datapool` and `rpool/ROOT` keep 7 daily and 1 monthly. LXC root filesystems are not snapshotted because the deployment scripts recreate them.

### Restic / Backrest

Backrest writes to an encrypted Restic repository. The repository is then mirrored with rclone to remote targets including an Oracle VPS and Google Drive. Samba does not expose the local repository: its container mounts an empty read-only directory over `/datapool/backup`.

The remote copies are mirrors of the same Restic repository rather than independent retention archives, so repository lifecycle operations such as forget/prune are reflected in those mirrors.

After a backup, sync hooks update the remote mirrors and can send Telegram alerts when a mirror operation fails.

---

## Alerts

Host notifications go to the Telegram bot that Watchtower uses. Deploying or redeploying the Utility stack reconciles a `telegram` webhook target and a `telegram-all` matcher in the Proxmox notification system from `WATCHTOWER_TELEGRAM_TOKEN` and `WATCHTOWER_TELEGRAM_CHAT_IDS` (a single chat ID) in `docker/utility/.env.enc`. Mail for root from smartd and ZED is forwarded through the same target. The default e-mail target stays in place but is not relied upon: the ISP address is on a mail blocklist, so host e-mail does not reach external mailboxes.

---

## Service Stacks

### Gateway — LXC 100

**Services:** Nginx Proxy Manager, AdGuard Home, Cloudflared

Provides local DNS, split DNS, reverse proxying, and the Cloudflare Tunnel endpoint for published web services.

### Media — LXC 101

**Services:** Jellyfin, Immich, Sonarr, Radarr, Bazarr, Seerr, Prowlarr, qBittorrent, FlareSolverr, Profilarr, Tdarr, Cleanuparr

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

**Tools:** Claude Code (`claude`), Paseo, Node.js, Python, Git/GitHub CLI

Persistent remote development environment. Claude Code is the coding agent and Paseo serves its web UI (parallel agents, worktrees, terminals, editor, diffs, pull requests) behind the NPM OTP gate. Claude Code uses the Hindsight memory server in the AI LXC through the `@vectorize-io/hindsight-coding-agents` hooks and MCP server. Claude Code state (`/fastpool/config/claude`), Paseo state, and the workspace are stored under `fastpool`; sign in to Claude Code once with `claude`.

Memory is one Hindsight bank per project, named after the directory of the repository's primary checkout (`bankIdTemplate: "{gitProject}"`), so linked worktrees share their repository's bank and every machine and agent using the same project name shares one memory. The name is used as written, so keep project directory names lowercase. The plugin runs on its defaults, except `autoInject: "pages"` (the first prompt of a session gets page search hits instead of a 20-second LLM synthesis), and owns each bank: it seeds the bank from git history, writes its retain strategies and maintains five curated pages per project. Output language, LLM routing and the mental-model refresh floor are set on the Hindsight server in `docker/ai/docker-compose.yml` and apply to every bank.

### Gaming — LXC 106

**Services:** Palworld dedicated server (Windows / Wine with UE4SS)

Provides an isolated game-server workload managed separately from the media and utility stacks.

Uses `ghcr.io/ripps818/docker-palworld-dedicated-server-wine:latest`. Game files and mods persist under `/fastpool/config/gameservers/palworld/game`, with automated backups under `/fastpool/config/gameservers/palworld/backups`. Scheduled backups run every 6 hours (retaining 28 archives); automated restarts are disabled so base chunks stay loaded. The LXC only mounts `/fastpool/config/gameservers` because it publishes game ports to the internet.

---

## Secret Handling

Stack environment files are [SOPS](https://github.com/getsops/sops) dotenv files stored as `docker/<stack>/.env.enc`. Variable names stay readable; only the values are encrypted (AES-256-GCM with an integrity MAC) to the age recipient in `.sops.yaml`.

The age private key is committed only as `.sops-key.age`, encrypted with the master passphrase (age scrypt). The deployment scripts unwrap it once per run and decrypt every required `.env.enc` in memory; `SOPS_AGE_KEY` can supply the identity for non-interactive runs. `age` comes from the Debian package and `sops` from SHA-256-verified GitHub releases.

---

## Project Structure

```text
├── installer.sh                 # Main installer launcher
├── stacks.yaml                  # LXC definitions and resources
├── .sops.yaml                   # age recipient for docker/*/.env.enc
├── .sops-key.age                # age identity encrypted with the master passphrase
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
├── firewall/                    # PVE guest firewall file per stack
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
