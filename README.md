# Proxmox Homelab Automation

Production-style homelab architected with enterprise-inspired reliability practices, demonstrating infrastructure automation and DevOps patterns. Orchestrates **40+ services** across **7 LXC containers** with **unprivileged NVIDIA GPU passthrough**, custom Docker images with **automated CI/CD pipelines**. Powered by a security-first automation framework consisting of **~3000 lines of Bash scripts** automating Proxmox host provisioning.

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

#### **Defense-in-Depth Boundary**
- **No WAN Port Forwarding**: The router exposes no inbound ports; published web traffic reaches the homelab only through Cloudflare Tunnel.
- **Layered Web Authentication**: Cloudflare Access protects `*.byetgin.com`. Sensitive administrative routes such as the remote Desktop, Code-Server, and recovery terminal also pass through the NPM OTP gate, whose HTTPS-only authenticated cookies expire after one hour.
- **Split DNS**: AdGuard rewrites local `*.byetgin.com` queries to Nginx Proxy Manager at `192.168.1.100`, keeping the same domain-based access paths on the LAN.
- **Recovery Path**: The OTP-protected `terminal.byetgin.com` route is the fallback when the Desktop LXC is unavailable. It is used to reach Proxmox and recover services with tools such as `pct enter`; direct terminal SSH access to the Dev LXC is not required.
- **Privileged Browser Boundary**: The authenticated remote Desktop browser is intentionally trusted to reach internal administration surfaces and stored user sessions. Its Cloudflare Access and NPM OTP layers are therefore critical security controls.

### **Maintained Custom Docker Images**
This project utilizes custom Docker images that are maintained in separate repositories and built via automated CI/CD pipelines on GitHub Actions.

| Image | Repository | Description |
| :--- | :--- | :--- |
| **desktop-workspace** | [Yakrel/docker-desktop-workspace](https://github.com/Yakrel/docker-desktop-workspace) | Multi-app web environment (Brave + Obsidian) |
| **backrest-rclone** | [Yakrel/docker-backrest-rclone](https://github.com/Yakrel/docker-backrest-rclone) | Backup solution with Oracle VPS and Google Drive sync hooks |

**Pipeline Features:**
- Scheduled weekly rebuilds
- Automated tag management via GHCR
- Published to GHCR: `ghcr.io/yakrel/...`

### **DevOps & Automation Practices**
- **Configuration-driven Infrastructure**: LXC identities and resources are defined in `stacks.yaml`; service state is defined by Docker Compose and application templates.
- **Repeatable Deployment Paths**: LXC provisioning assumes a clean installation, while application redeploys reconcile Compose and generated configuration state.
- **Secret Management**: Repository secrets use salted AES-256-CBC with an explicit 600,000-iteration PBKDF2-HMAC-SHA256 work factor.

### **Business Continuity & Disaster Recovery**
- **Local Recovery**: Sanoid-managed ZFS snapshots provide an independent local rollback path for configuration errors and accidental deletion.
- **Off-site Availability Mirrors**: Backrest creates one client-side encrypted restic repository; rclone maintains exact mirrors of that repository on Oracle VPS and Google Drive.
- **Mirror Semantics**: Remote mirrors follow the local repository lifecycle, including forget/prune deletions, and are availability copies rather than independent retention archives.
- **Automated Mirror Sync**: Post-backup rclone hooks update both remote mirrors and send a Telegram degradation alert if either target fails.
- **CI/CD Maintained**: Custom container images are rebuilt on a weekly schedule for upstream updates and security fixes.
- **Rebuild Path**: After storage and secrets are available, `installer.sh` provides a repeatable path for recreating the LXC and application stacks on the Proxmox host.

---

## 📦 Service Stacks

### **Proxy & DNS (Gateway)** (LXC 100 - `192.168.1.100`)
Nginx Proxy Manager, AdGuard Home, Cloudflared

### **Media Automation** (LXC 101 - `192.168.1.101`)
Jellyfin, Immich, Sonarr, Radarr, Bazarr, Seerr, Prowlarr, qBittorrent, FlareSolverr, Tor Proxy, Profilarr, Tdarr, Cleanuperr

### **Utility & Backup** (LXC 102 - `192.168.1.102`)
JDownloader 2, Samba, Repackarr, Backrest-Rclone (encrypted repository with Oracle VPS and Google Drive mirrors), MeTube, Changedetection.io, Karakeep

### **Desktop Workspace** (LXC 103 - `192.168.1.103`)
Homepage, Desktop Workspace, Guacamole, Sshwifty, CouchDB, Vaultwarden, Desktop OTP Gate, Radicale CalDAV

The LXC firewall accepts published application traffic only from Nginx Proxy Manager. This keeps the OTP-protected remote browser and the other Desktop services reachable through their domain routes without exposing their direct ports to the LAN.

### **AI & Automation** (LXC 104 - `192.168.1.104`)
Hermes Agent, OmniRoute

The LXC firewall accepts the Hermes and OmniRoute application ports only from Nginx Proxy Manager. Outbound agent access remains allowed.

### **Development (Dev)** (LXC 105 - `192.168.1.105`)
Code-Server, Node.js, Python, Git/GitHub CLI, Oh My Pi

Code-Server is reachable through the OTP-protected Nginx Proxy Manager route; provisioning enables the Datacenter firewall while leaving node firewalling unchanged, and the LXC firewall permits direct port `8680` traffic only from NPM and the Homepage health monitor. Dev enables LXC nesting for Debian 13 systemd service isolation but leaves Docker-specific keyctl disabled. Code-Server settings and extensions persist under `/fastpool/config/code-server`, while `/root/workspace` persists under `/fastpool/config/dev/workspace`. Its integrated terminal mirrors the NixOS workstation shell with Zsh, Oh My Zsh (`git` + `robbyrussell`), autosuggestions, syntax highlighting, eza, bat, btop, zoxide, JetBrainsMono Nerd Font, and the same Tokyo Night palette. Oh My Pi is the only coding-agent CLI provisioned for Dev and provides the multi-provider agent surface; CLI authentication state remains disposable with the Dev LXC.

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
│       ├── backrest-deployment.sh
│       └── dev-terminal.sh
├── docker/                   # Docker Compose stacks
│   ├── ai/                  # Hermes Agent and OmniRoute
│   ├── desktop/             # Dashboard, desktop workspace, guacamole, sshwifty, radicale
│   ├── dev/                 # Development stack (no compose, managed by LXC manager)
│   ├── gateway/             # Nginx Proxy Manager, AdGuard, Cloudflared
│   ├── media/               # Media automation + GPU acceleration (Jellyfin, Immich, Tdarr)
│   └── utility/             # Download managers, Backrest backup, Samba, Changedetection, Karakeep
└── config/                   # Shared configurations
    ├── backrest/            # Backrest config.json template
    ├── homepage/            # Dashboard widgets
    ├── samba/               # Samba share template config
    ├── sshwifty/            # sshwifty profile template config
    ├── couchdb/             # CouchDB local.ini configuration
    └── guacamole/           # Apache Guacamole user-mapping configs
```

## 🔧 Requirements

- **Proxmox VE**: 9.x with ZFS storage
- **Network**: `vmbr0` bridge, `192.168.1.x` range
- **Storage**: ZFS pools — `fastpool` (SSD) for configs/databases and `datapool` (HDD) for media/backups
- **GPU**: NVIDIA is required by the current Media and Desktop stack definitions; other stacks do not require it

## 🔐 Security

- **Unprivileged LXC containers** with UID/GID mapping (101000:101000 → 1000:1000)
- **Console-first administration**: LXC SSH servers are omitted; Proxmox console shell mode provides direct root access through the trusted host
- **Encrypted secrets**: AES-256-CBC with PBKDF2-HMAC-SHA256 and an explicit 600,000-iteration work factor
- **Single master key** decrypts stack `.env.enc` files and service-specific encrypted configuration
- **Per-stack Docker networks**, with selected services published to the homelab LAN
- **Scoped management mounts**: service configuration is exposed through `/fastpool/config` without exposing the LXC root filesystems stored at the pool root
- **Automated container updates and notifications** via Watchtower configured per stack

## 📄 License

Copyright © 2025–2026 Berkay Yetgin

Licensed under the MIT License. See [LICENSE](LICENSE).
