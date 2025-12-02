# Proxmox Homelab Automation

Production homelab running **40+ services** across **8 LXC containers** with **NVIDIA GPU passthrough in unprivileged LXC**, **custom Docker images with automated CI/CD**, and **comprehensive monitoring**. Fully automated deployment with **2100+ lines of shell scripts**.

> **About**: My production homelab that I actively use and develop. Publicly shared to demonstrate DevOps, infrastructure automation, and advanced Linux system administration capabilities. All values are hardcoded for my specific environment for maximum reliability.

---

## 🚀 Quick Start

**One-line installer on Proxmox host:**
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/Yakrel/proxmox-homelab-automation/main/installer.sh)"
```

Interactive menu guides you through stack selection and deployment. Only one password required (master encryption key).

---

## 🏆 Technical Highlights

### **Advanced LXC Configuration**
- **NVIDIA GPU passthrough in unprivileged containers** (cgroup v2 method)
- **Jellyfin**: 18.64x real-time hardware transcoding (447 fps on GTX 970)
- **Immich ML**: GPU-accelerated face recognition + object detection
- **Chrome**: Hardware-accelerated rendering in desktop workspace
- Direct device mounting with CUDA library integration

### **Enterprise-Grade Security & Networking**
- **Zero Trust Architecture**: Cloudflare Access protects public endpoints with Email OTP & Geo-blocking (Turkey only).
- **Split DNS Strategy**: 
  - **Internal**: AdGuard Home resolves `*.byetgin.com` to local Nginx (192.168.1.100) for gigabit speed & zero hairpinning.
  - **External**: Cloudflare Tunnel handles remote access without opening any inbound ports (CGNAT friendly).
- **Secure Remote Access**: Cloudflare WARP integration for full VPN-less access to internal subnets (`192.168.1.0/24`).
- **Wildcard SSL**: Automated Let's Encrypt wildcard certificates via DNS challenge for full internal HTTPS.

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

### **Infrastructure as Code**
- **2100+ lines** of modular shell automation
- **Idempotent operations** - safe to re-run
- **Encrypted secrets** - AES-256-CBC with pbkdf2
- **Mixed LXC types**: Alpine (lightweight) + Debian (GPU stacks)
- **Comprehensive monitoring**: Prometheus + Grafana + Loki (30-day retention)

### **Automated Offsite Backups**
- Pre-configured Backrest with restic repositories
- Post-backup hooks trigger rclone sync to Google Drive
- Encrypted offsite backups with OAuth2 authentication
- CI/CD pipeline ensures latest versions

---

## 📦 Service Stacks

### **Media Automation** (LXC 101)
Jellyfin, Immich, Sonarr, Radarr, Bazarr, Jellyseerr, Prowlarr, qBittorrent, FlareSolverr, Recyclarr, Cleanuperr

### **Monitoring & Observability** (LXC 104)
Prometheus, Grafana, Loki, Promtail, PVE Exporter, cAdvisor

### **File Management** (LXC 102)
JDownloader 2, MeTube, Palmr

### **Web Tools** (LXC 103)
Homepage, Desktop Workspace, CouchDB, Vaultwarden

### **Proxy & DNS** (LXC 100)
Nginx Proxy Manager, AdGuard Home, Cloudflared, Promtail, Watchtower

### **Backup** (LXC 106)
Backrest-Rclone (custom image with Google Drive sync)

### **Game Servers** (LXC 105)
Satisfactory, Palworld

### **Development** (LXC 107)
Extensible development environment

---

## ⚠️ Personal Homelab Notice

**This is my production homelab optimized for my specific environment.** Values are hardcoded for reliability:

- **Network**: `192.168.1.x` range, `vmbr0` bridge
- **Storage**: ZFS pool `datapool`
- **Timezone**: `Europe/Istanbul`
- **Secrets**: Pre-encrypted in `.env.enc` files

**Not plug-and-play.** This project demonstrates infrastructure automation and DevOps skills. To adapt for your environment: fork, modify hardcoded values, re-encrypt secrets, test thoroughly.

## 📁 Project Structure

```
├── installer.sh              # One-line installer
├── scripts/                  # 2100+ lines of deployment automation
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
