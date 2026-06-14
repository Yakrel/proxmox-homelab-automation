# Proxmox Homelab Automation

Production-style homelab architected with enterprise-inspired reliability practices, demonstrating infrastructure automation and DevOps patterns. Orchestrates **30+ services** across **7 LXC containers** with **unprivileged NVIDIA GPU passthrough**, custom Docker images with **automated CI/CD pipelines**, and **full-stack observability**. Powered by a security-first automation framework consisting of **~3000 lines of Bash scripts** automating Proxmox host provisioning.

> **About**: Production homelab running family media services (Jellyfin, Immich) with production-grade infrastructure patterns. Features **declarative infrastructure-as-code**, **ZFS-backed storage**, **encrypted secret management**, **full-stack monitoring**, and **disaster recovery** architecture.

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
- **Tailscale Subnet Router**: Runs as a lightweight sidecar in the Proxy stack, advertising the `192.168.1.0/24` route to authenticated devices.
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
- **Declarative Infrastructure (IaC)**: Entire infrastructure state defined in `stacks.yaml` (Single Source of Truth).
- **Idempotent Orchestration**: Bash scripts perform state reconciliation, ensuring reproducible deployments without side effects.
- **Secret Management**: Production-grade secret handling using AES-256-CBC encryption for all configuration files.
- **Full-Stack Observability**: Centralized logging (Loki) and metrics (Prometheus) stack monitoring host, containers, and services.

### **Business Continuity & Disaster Recovery**
- **3-2-1 Strategy**: Local ZFS snapshots (Hot) + Encrypted Cloud Archives (Cold).
- **Automated Cloud Sync**: Backrest repositories synced to Google Drive via post-backup hooks (rclone).
- **Secure Archives**: Client-side encryption ensuring data privacy in public cloud environments.
- **CI/CD Maintained**: Custom `backrest-rclone` image automatically rebuilt twice a week for up-to-date security and cloud sync compatibility.
- **Layer 3 Recovery**: In a disaster scenario, the entire server fleet can be rebuilt on the **Proxmox Host** in minutes using the `installer.sh` automation suite.

---

## 📦 Service Stacks

### **Proxy & DNS (Gateway)** (LXC 100 - `192.168.1.100`)
Nginx Proxy Manager, AdGuard Home, Cloudflared, Tailscale Subnet Router, Promtail

### **Media Automation** (LXC 101 - `192.168.1.101`)
Jellyfin, Immich, Sonarr, Radarr, Bazarr, Jellyseerr, Prowlarr, qBittorrent, FlareSolverr, Recyclarr, Cleanuperr, Tdarr

### **Utility & Backup** (LXC 102 - `192.168.1.102`)
JDownloader 2, Samba, Repackarr, Backrest-Rclone (Backup with Google Drive sync), MeTube

### **Desktop Workspace (Web Tools)** (LXC 103 - `192.168.1.103`)
Homepage, Desktop Workspace, Guacamole, Sshwifty, CouchDB, Vaultwarden

### **Monitoring & Observability** (LXC 104 - `192.168.1.104`)
Prometheus, Grafana, Loki, Promtail, PVE Exporter, cAdvisor, Diun (update notifications)

### **Game Servers (Gaming)** (LXC 105 - `192.168.1.105`)
Palworld, Satisfactory, Conan Exiles

### **Development (Dev)** (LXC 106 - `192.168.1.106`)
Code-Server, Node.js, Python, Git, Antigravity CLI

---

## ⚠️ Personal Homelab Notice

**This is my production homelab optimized for my specific environment.** Values are hardcoded for reliability:

- **Network**: `192.168.1.x` range, `vmbr0` bridge
- **Storage**: ZFS pool `datapool`
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
│   ├── fail2ban-manager.sh  # Fail2ban client management
│   ├── helper-functions.sh  # Common shell utilities
│   ├── datapool-cleanup.sh  # Cache/log cleaner
│   ├── setup-tailscale-host.sh # Tailscale host subnet configuration
│   └── modules/             # Specialized deployment modules
│       ├── docker-deployment.sh
│       ├── monitoring-deployment.sh
│       └── backrest-deployment.sh
├── docker/                   # Docker Compose stacks
│   ├── _infra/              # Shared infrastructure (cAdvisor, promtail, etc.)
│   ├── desktop/             # Dashboard, desktop workspace, guacamole, sshwifty
│   ├── gaming/              # Satisfactory, Palworld, Conan Exiles servers
│   ├── gateway/             # Nginx Proxy Manager, AdGuard, Cloudflared
│   ├── media/               # Media automation + GPU acceleration (Jellyfin, Immich)
│   ├── monitor/             # Prometheus + Grafana + Loki + Diun
│   └── utility/             # Download managers, Backrest backup, Samba shares
└── config/                   # Shared configurations
    ├── prometheus/          # prometheus.yml, metrics + alerting rules
    ├── promtail/            # Log collection config
    ├── homepage/            # Dashboard widgets
    ├── samba/               # Samba share template config
    ├── sshwifty/            # sshwifty profile template config
    ├── couchdb/             # CouchDB local.ini configuration
    ├── loki/                # Loki configuration files
    ├── grafana/             # Grafana dashboard templates
    └── guacamole/           # Apache Guacamole user-mapping configs
```

## 🔧 Requirements

- **Proxmox VE**: 9.x with ZFS storage
- **Network**: `vmbr0` bridge, `192.168.1.x` range
- **GPU** (optional): NVIDIA for hardware transcoding/ML acceleration

## 🔐 Security

- **Unprivileged LXC containers** with UID/GID mapping (101000:101000 → 1000:1000)
- **Encrypted secrets**: AES-256-CBC with pbkdf2
- **Single master key** decrypts all `.env.enc` files
- **Network isolation** per stack
- **Centralized container update management** via Diun (Docker Image Update Notifier) on monitoring LXC

## 📄 License

MIT License - see [LICENSE](LICENSE) file for details.
