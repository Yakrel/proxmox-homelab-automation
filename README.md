# Proxmox Homelab Automation

Production homelab architected with enterprise-grade practices, demonstrating advanced DevOps capabilities. Orchestrates **40+ microservices** across **8 LXC containers** with **unprivileged NVIDIA GPU passthrough**, custom Docker images with **automated CI/CD pipelines**, and **full-stack observability**. Powered by a security-first automation framework consisting of **~3000 lines of Bash scripts** automating Proxmox host provisioning.

> **About**: A production-grade **Hybrid Cloud Simulation** architected to demonstrate enterprise DevOps capabilities. Features a **Declarative Infrastructure** managed as code, **Zero Trust** security posture, and a **Disaster Recovery Ready** architecture.

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

### **Enterprise-Grade Security & Networking**

#### **Network Topology & Access Architecture**
A visualization of the Zero Trust architecture, highlighting how **WARP** provides seamless "LAN-like" experience for family devices while **Cloudflare Tunnel** secures public web access.

> 🗺️ **Interactive Architecture Dashboard**
>
> Explore the live system topology, data flow, and microservices map:
> **[👉 Launch Interactive Dashboard](https://yakrel.github.io/proxmox-homelab-automation/)**

- **Seamless Family Experience**: Mobile devices run **Cloudflare WARP** in "Always-On" mode. This creates a secure, transparent VPN directly to the home network.
  - *Result:* The wife and child can open the Jellyfin app anywhere in the world and it works exactly as if they were on the couch. No logins, no OTPs.
- **Strict Public Access**: Browser-based access (e.g., from a work computer) is protected by **Cloudflare Access** with Wildcard Email OTP policies.
- **Zero Trust Tunnel**: No open ports on the router. All ingress traffic is routed through `cloudflared` daemon.

#### **Hybrid Access Strategy (Split Subdomains)**
A sophisticated solution to bypass Cloudflare's "Split DNS" paywall (Enterprise feature), ensuring optimal routing for both local and remote access:

| Access Method | Domain Format | Route | Features |
|--------------|---------------|-------|----------|
| **Remote (Public)** | `service.byetgin.com` | Internet -> Cloudflare Tunnel -> Home | Protected by Cloudflare Access, slower |
| **Local / WARP** | `service.local.byetgin.com` | Device -> WARP -> Local Network -> NPM | Direct connection, max speed, no auth prompt |
| **Internal Only** | `service.byetgin.com` | Device -> WARP -> Local Network -> NPM | Services without public CNAME records resolve directly to local IP via wildcard DNS |

**Implementation:**
- **Cloudflare DNS**: `*.byetgin.com` -> `192.168.1.100` (DNS Only) handles all internal/local traffic.
- **Nginx Proxy Manager**: Hosts configured with dual domains (`service` + `service.local`) and wildcard SSL.
- **Homepage**: Smart linking uses `.local` domains for public services to force direct connection when using WARP.

### **Custom Docker Images + Automated CI/CD**
Two custom images built and maintained with automated pipelines:
- **desktop-workspace**: Multi-app web environment (Chrome + Obsidian + file manager)
- **backrest-rclone**: Backup solution with Google Drive sync hooks

**Pipeline Features:**
- Bi-weekly automatic rebuilds (always fresh base images)
- Multi-stage builds with layer caching
- Automated tag management (keep last 3 versions)
- Zero-downtime updates via Watchtower
- Published to DockerHub: `yakrel93/desktop-workspace`, `yakrel93/backrest-rclone`

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

### **Media Automation** (LXC 101 - 192.168.1.101)
Jellyfin, Immich, Sonarr, Radarr, Bazarr, Jellyseerr, Prowlarr, qBittorrent, FlareSolverr, Recyclarr, Cleanuperr

### **Monitoring & Observability** (LXC 104 - 192.168.1.104)
Prometheus, Grafana, Loki, Promtail, PVE Exporter, cAdvisor

### **File Management** (LXC 102 - 192.168.1.102)
JDownloader 2, MeTube, Palmr

### **Web Tools** (LXC 103 - 192.168.1.103)
Homepage, Desktop Workspace, CouchDB, Vaultwarden

### **Proxy & DNS** (LXC 100 - 192.168.1.100)
Nginx Proxy Manager, AdGuard Home, Cloudflared, Promtail, Watchtower

### **Backup** (LXC 106 - 192.168.1.106)
Backrest-Rclone (custom image with Google Drive sync)

### **Game Servers** (LXC 105 - 192.168.1.105)
Satisfactory, Palworld

### **Development** (LXC 107 - 192.168.1.107)
Extensible development environment

---

## ⚠️ Personal Homelab Notice

**This is my production homelab optimized for my specific environment.** Values are hardcoded for reliability:

- **Network**: `192.168.1.x` range, `vmbr0` bridge
- **Storage**: ZFS pool `datapool`
- **Timezone**: `Europe/Istanbul`
- **Secrets**: Pre-encrypted in `.env.enc` files

**Not plug-and-play.** This project demonstrates infrastructure automation and DevOps skills. To adapt for your environment: fork, perform necessary network/storage refactoring, re-encrypt secrets, and test thoroughly.

## 📁 Project Structure

```
├── installer.sh              # One-line installer
├── scripts/                  # ~3000 lines of deployment automation
│   ├── deploy-stack.sh      # Main orchestrator
│   ├── lxc-manager.sh       # LXC lifecycle management
│   ├── modules/             # Specialized deployment modules
│   └── helper-*.sh          # Utility functions
├── docker-images/            # Custom Docker images with CI/CD
│   ├── desktop-workspace/   # Chrome + Obsidian web environment
│   └── backrest-rclone/     # Backup solution with cloud sync
├── docker/                   # Docker Compose stacks
│   ├── media/               # Media automation + GPU acceleration
│   ├── monitoring/          # Prometheus + Grafana + Loki
│   ├── backup/              # Backrest with Google Drive sync
│   ├── webtools/            # Dashboard + desktop workspace
│   ├── files/               # Download managers
│   ├── proxy/               # Cloudflare tunnel
│   └── gameservers/         # Game servers
├── config/                   # Shared configurations
│   ├── prometheus/          # Metrics + alerting rules
│   ├── promtail/            # Log collection config
│   └── homepage/            # Dashboard widgets
└── stacks.yaml              # Central configuration (LXC resources, IPs, hostnames)
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
- **Automated security updates** via Watchtower

## 📄 License

MIT License - see [LICENSE](LICENSE) file for details.
