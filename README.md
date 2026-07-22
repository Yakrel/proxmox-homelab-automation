# Proxmox Homelab Automation

Production-style homelab architected with enterprise-inspired reliability practices, demonstrating infrastructure automation and DevOps patterns. Orchestrates **40+ services** across **6 LXC containers** with **unprivileged NVIDIA GPU passthrough**, custom Docker images with **automated CI/CD pipelines**. Powered by a security-first automation framework consisting of **~3000 lines of Bash scripts** automating Proxmox host provisioning.

> **About**: Production homelab running family media services (Jellyfin, Immich), AI automation (Hermes Agent), and productivity tools with production-style infrastructure patterns. Features **configuration-driven automation**, **ZFS-backed storage**, **encrypted secret management**, and **disaster recovery** architecture.

---

## 🚀 Quick Start

**One-line installer on Proxmox host:**
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/Yakrel/proxmox-homelab-automation/main/installer.sh)"
```

Interactive menu guides you through stack selection and deployment. Only one password required (master encryption key).

---

## 🏆 Technical Highlights

### **Advanced Virtualization & Resource Management**
- **Unprivileged LXC GPU Passthrough**: Engineered secure GPU access for unprivileged containers using cgroup v2 mapping, avoiding security risks of privileged containers.
- **Nested Docker Optimization**: Configured efficient Docker-in-LXC runtime, combining the lightweight nature of LXC with the portability of Docker.
- **Shared Hardware Acceleration**: Centralized NVIDIA driver management on host, mapped to multiple containers for concurrent CUDA/NVENC workloads.
- **ZFS Storage Foundation**: `lz4` compression, automated snapshots, and ARC caching provide a reliable base for mixed workloads without adding operational complexity.

### **Enterprise-Grade Security & Networking**

#### **Network Topology & Access Architecture**
A visualization of the Zero Trust architecture, highlighting how **WARP** provides seamless "LAN-like" experience for family devices while **Cloudflare Tunnel** secures public web access.

> 🗺️ **Interactive Architecture Dashboard**
>
> Explore the live system topology, data flow, and microservices map:
> **[👉 Launch Interactive Dashboard](https://infra.byetgin.com/)**

- **Seamless Family Experience**: Mobile devices run **Cloudflare WARP** in "Always-On" mode. This creates a secure, transparent VPN directly to the home network.
  - *Result:* Family members can open the Jellyfin app anywhere in the world and it works exactly as if they were on the couch. No logins, no OTPs.
- **Strict Public Access**: Browser-based access (e.g., from a work computer) is protected by **Cloudflare Access** with Wildcard Email OTP policies.
- **Dual-Layer Tunneling**:
  - **Tailscale (Primary VPN)**: Used for high-performance, direct "LAN-like" access to the entire network (`192.168.1.0/24`). Ideal for admin tasks, gaming, and bypassing restrictive ISP firewalls.
  - **Cloudflare Tunnel (Web Services)**: Routes public ingress traffic for web applications without opening ports.

#### **Hybrid Access Strategy**
A robust dual-path architecture ensuring reliable access even in restrictive network environments (e.g., corporate firewalls, mobile carrier NATs):

| Access Method | Technology | Route | Use Case |
|--------------|------------|-------|----------|
| **Admin / VPN** | **Tailscale** | Device -> Tailscale (P2P/DERP) -> Home Network | Full network access, SSH, Gaming, Proxmox GUI |
| **Web App** | **Cloudflare** | Internet -> Cloudflare Edge -> Cloudflared -> NPM | User-friendly HTTPS access (e.g., `immich.byetgin.com`) |
| **Local** | **Direct LAN** | Device -> WiFi -> Nginx Proxy Manager | Maximum speed for media streaming at home |

**Implementation:**
- **Tailscale Subnet Router**: Runs directly on the Proxmox host and advertises the `192.168.1.0/24` route to authenticated devices.
- **Cloudflare Tunnel**: Dedicated purely to serving web applications via public domains, protected by Zero Trust policies.

### **Maintained Custom Docker Images**
This project utilizes custom Docker images that are maintained in separate repositories and built via automated CI/CD pipelines on GitHub Actions.

| Image | Repository | Description |
| :--- | :--- | :--- |
| **desktop-workspace** | [Yakrel/docker-desktop-workspace](https://github.com/Yakrel/docker-desktop-workspace) | Multi-app web environment (Brave + Obsidian) |
| **backrest-rclone** | [Yakrel/docker-backrest-rclone](https://github.com/Yakrel/docker-backrest-rclone) | Backup solution with Google Drive sync hooks |

**Pipeline Features:**
- Bi-weekly automatic rebuilds
- Automated tag management via GHCR
- Published to GHCR: `ghcr.io/yakrel/...`

### **DevOps & Automation Practices**
- **Configuration-driven Infrastructure**: LXC identities and resources are defined in `stacks.yaml`; service state is defined by Docker Compose and application templates.
- **Repeatable Deployment Paths**: LXC provisioning assumes a clean installation, while application redeploys reconcile Compose and generated configuration state.
- **Secret Management**: Production-grade secret handling using AES-256-CBC encryption for all configuration files.

### **Business Continuity & Disaster Recovery**
- **Off-site Copy**: Local ZFS snapshots plus an encrypted Google Drive mirror of the restic repository.
- **Automated Cloud Sync**: Backrest repositories synced to Google Drive via post-backup hooks (rclone).
- **Secure Archives**: Client-side encryption ensuring data privacy in public cloud environments.
- **CI/CD Maintained**: Custom `backrest-rclone` image automatically rebuilt twice a week for up-to-date security and cloud sync compatibility.
- **Rebuild Path**: After storage and secrets are available, `installer.sh` provides a repeatable path for recreating the LXC and application stacks on the Proxmox host.

---

## 📦 Service Stacks

### **Proxy & DNS (Gateway)** (LXC 100 - `192.168.1.100`)
Nginx Proxy Manager, AdGuard Home, Cloudflared

### **Media Automation** (LXC 101 - `192.168.1.101`)
Jellyfin, Immich, Sonarr, Radarr, Bazarr, Jellyseerr, Prowlarr, qBittorrent, FlareSolverr, Tor Proxy, Recyclarr, Tdarr, Cleanuperr

### **Utility & Backup** (LXC 102 - `192.168.1.102`)
JDownloader 2, Samba, Repackarr, Backrest-Rclone (Backup with Google Drive sync), MeTube, Changedetection.io, Karakeep

### **Desktop Workspace (Web Tools)** (LXC 103 - `192.168.1.103`)
Homepage, Desktop Workspace, Guacamole, Sshwifty, CouchDB, Vaultwarden, Desktop OTP Gate, Radicale CalDAV

### **AI & Automation** (LXC 105 - `192.168.1.105`)
Hermes Agent, OmniRoute, Agentmemory

### **Development (Dev)** (LXC 106 - `192.168.1.106`)
Code-Server, Node.js, Python, Git/GitHub CLI, Codex CLI, OpenCode, Antigravity CLI, Pi Coding Agent

Dev stack redeploys verify Agentmemory reachability and run isolated Agy, OpenCode, Codex, and Pi integration smoke tests. The integration tests use in-process mocks or read-only file checks and do not create Agentmemory sessions or observations. Pi also installs the `pi-antigravity` provider automatically; complete its Google OAuth flow interactively with `/login antigravity` on first use.

---

## ⚠️ Personal Homelab Notice

**This is my production homelab optimized for my specific environment.** Values are hardcoded for reliability:

- **Network**: `192.168.1.x` range, `vmbr0` bridge
- **Storage**: ZFS pools `fastpool` (SSD, configs/databases) and `datapool` (HDD, media/backups)
- **Timezone**: `Europe/Istanbul`
- **Secrets**: Pre-encrypted in `.env.enc` files

**Not plug-and-play.** This project demonstrates infrastructure automation and DevOps skills. To adapt for your environment: fork, perform necessary network/storage refactoring, re-encrypt secrets, and test thoroughly.

---

## 📁 Project Structure

```
├── installer.sh              # One-line installer launcher
├── stacks.yaml              # Central configuration (LXC resources, IPs, hostnames)
├── scripts/                  # ~3000 lines of deployment automation
│   ├── main-menu.sh         # Main interactive CLI menu
│   ├── helper-menu.sh       # Proxmox host helpers menu
│   ├── deploy-stack.sh      # Main orchestrator
│   ├── lxc-manager.sh       # LXC lifecycle management
│   ├── fast-redeploy.sh     # Fast Docker stack redeploy
│   ├── helper-functions.sh  # Common shell utilities
│   ├── nvidia-userspace-sync.sh # NVIDIA user-space library sync for LXC
│   ├── setup-tailscale-host.sh # Tailscale host subnet configuration
│   └── modules/             # Specialized deployment modules
│       ├── docker-deployment.sh
│       └── backrest-deployment.sh
├── docker/                   # Docker Compose stacks
│   ├── ai/                  # Hermes Agent, OmniRoute, Agentmemory
│   ├── desktop/             # Dashboard, desktop workspace, guacamole, sshwifty, radicale
│   ├── dev/                 # Development stack (no compose, managed by LXC manager)
│   ├── gateway/             # Nginx Proxy Manager, AdGuard, Cloudflared
│   ├── media/               # Media automation + GPU acceleration (Jellyfin, Immich, Tdarr)
│   └── utility/             # Download managers, Backrest backup, Samba, Changedetection, Karakeep
└── config/                   # Shared configurations
    ├── antigravity/         # Antigravity CLI hooks and memory config
    ├── backrest/            # Backrest config.json template
    ├── codex/               # Codex CLI Agentmemory wrapper
    ├── homepage/            # Dashboard widgets
    ├── metube/              # MeTube encrypted browser cookies
    ├── opencode/            # OpenCode CLI configuration and memory
    ├── pi/                  # Pi CLI wrapper and native Agentmemory lifecycle extension
    ├── samba/               # Samba share template config
    ├── sshwifty/            # sshwifty profile template config
    ├── couchdb/             # CouchDB local.ini configuration
    ├── vaultwarden/         # Vaultwarden configuration templates
    └── guacamole/           # Apache Guacamole user-mapping configs
```

## 🔧 Requirements

- **Proxmox VE**: 9.x with ZFS storage
- **Network**: `vmbr0` bridge, `192.168.1.x` range
- **Storage**: ZFS pools — `fastpool` (SSD) for configs/databases, `datapool` (HDD) for media/backups
- **GPU** (optional): NVIDIA for hardware transcoding/ML acceleration

## 🔐 Security

- **Unprivileged LXC containers** with UID/GID mapping (101000:101000 → 1000:1000)
- **Encrypted secrets**: AES-256-CBC with pbkdf2
- **Single master key** decrypts stack `.env.enc` files and service-specific encrypted configuration
- **MeTube authentication**: Utility deploys decrypt `config/metube/youtube-location.cookies.enc` directly into the protected runtime configuration; plaintext browser cookies are never committed
- **Per-stack Docker bridge networks**, with selected services published to the homelab LAN
- **Automated container updates and notifications** via Watchtower configured per stack

## 📄 License

MIT License - see [LICENSE](LICENSE) file for details.
