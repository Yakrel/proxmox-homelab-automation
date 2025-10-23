# Proxmox Homelab Automation

Production homelab infrastructure running **40+ containerized services** across **8 specialized LXC containers** on Proxmox VE. Fully automated deployment with shell scripts, zero-touch configuration, and comprehensive monitoring.

## 🚀 Quick Start

**One-line installer on Proxmox host:**
```bash
bash <(curl -s https://raw.githubusercontent.com/Yakrel/proxmox-homelab-automation/main/installer.sh)
```

Interactive menu guides you through stack selection and deployment. Only one password required (master encryption key).

---

## 📦 What's Included

### **Media Automation Stack** (LXC 101)
Complete media management with GPU acceleration for transcoding and ML:
- **Jellyfin** - Media server with NVIDIA GPU transcoding (GTX 970)
- **Immich** - Photo/video management with GPU-accelerated ML (face recognition, object detection)
- **Sonarr/Radarr/Bazarr** - TV/Movie/Subtitle automation
- **Jellyseerr** - Media request management
- **Prowlarr** - Indexer manager
- **qBittorrent** - Torrent client
- **FlareSolverr** - Cloudflare bypass for indexers
- **Recyclarr** - Automatic quality profile sync
- **Cleanuperr** - Automatic torrent cleanup

### **Monitoring & Observability Stack** (LXC 104)
Full monitoring infrastructure with auto-configured dashboards:
- **Prometheus** - Metrics collection (30-day retention)
- **Grafana** - Visualization with auto-imported dashboards (#10347, #893, #12611)
- **Loki** - Log aggregation (30-day retention)
- **Promtail** - Log collection from all LXC containers
- **PVE Exporter** - Proxmox metrics with auto-generated credentials
- **cAdvisor** - Container metrics

### **File Management Stack** (LXC 102)
Download and file handling services:
- **JDownloader 2** - Direct download manager
- **MeTube** - YouTube-dl web interface
- **Palmr** - File management and sharing

### **Web Tools Stack** (LXC 103)
Productivity and development tools:
- **Homepage** - Unified dashboard with service widgets
- **Chrome** - Browser-in-browser (web-accessible)
- **Obsidian** - Note-taking with web access
- **CouchDB** - Database for Obsidian sync
- **Portainer** - Docker management UI

### **Proxy & Tunnel Stack** (LXC 100)
External access and monitoring agents:
- **Cloudflared** - Cloudflare tunnel for secure remote access
- **Promtail** - Log shipping
- **Watchtower** - Auto-updates

### **Backup Stack** (LXC 106)
Automated backup solution:
- **Backrest** - Web-based backup UI (powered by restic)
- Automated backups: `/datapool/config` + Immich media

### **Game Servers Stack** (LXC 105)
Dedicated game hosting (extensible framework):
- **Satisfactory** - Factory building game server
- **Palworld** - Multiplayer survival server

### **Development Stack** (LXC 107)
Development environment (not in production deployment docs yet)

---

## 🎯 Key Features

### **Zero-Touch Deployment**
- Single command deployment per stack
- Encrypted credentials in `.env.enc` files (AES-256-CBC)
- Automatic service configuration (API keys, passwords, integrations)
- Idempotent scripts - safe to re-run

### **GPU Acceleration**
- NVIDIA GTX 970 passthrough to unprivileged LXC
- Jellyfin hardware transcoding (447 fps / 18.64x real-time tested)
- Immich ML acceleration for face/object recognition
- Automatic driver installation and cgroup configuration

### **Comprehensive Monitoring**
- Every LXC has Promtail (log shipping) + cAdvisor (metrics)
- Central Grafana with pre-imported production dashboards
- 30-day retention for metrics and logs
- Automated Prometheus datasource configuration

### **Security & Isolation**
- Unprivileged LXC containers with UID/GID mapping
- Encrypted secrets management
- Network isolation per stack
- Regular automated updates via Watchtower

---

## ⚠️ Personal Homelab Notice

**This is a production homelab optimized for a specific environment.** It uses hardcoded values for reliability and simplicity:

- **Network**: `192.168.1.x` range, `vmbr0` bridge, `192.168.1.1` gateway
- **Storage**: ZFS pool named `datapool`
- **Timezone**: `Europe/Istanbul`
- **Passwords**: Pre-encrypted in `.env.enc` files

**Not plug-and-play by design.** To adapt: fork the repo, modify hardcoded values in scripts/configs, re-encrypt secrets with your key, test thoroughly.

## 📁 Project Structure

```
├── installer.sh           # One-line installer entry point
├── scripts/               # Deployment automation
│   ├── deploy-stack.sh   # Stack deployment orchestrator
│   ├── lxc-manager.sh    # LXC lifecycle management
│   └── helper-*.sh       # Utilities (menus, encryption, etc.)
├── docker/               # Service stacks (compose files + configs)
│   ├── media/           # 15+ media services
│   ├── monitoring/      # Prometheus + Grafana + Loki
│   ├── files/           # Download managers
│   ├── webtools/        # Dashboard + productivity
│   ├── proxy/           # Cloudflare tunnel
│   ├── backup/          # Backrest
│   └── gameservers/     # Game servers
└── stacks.yaml          # Central configuration (IPs, resources, etc.)
```

## 🔧 Requirements

- Proxmox VE 9.x with ZFS storage
- Network: `vmbr0` bridge, `192.168.1.x` range
- Optional: NVIDIA GPU for hardware transcoding/ML

## 🎮 GPU Support (NVIDIA)

Tested with **NVIDIA GTX 970** for Jellyfin transcoding (447 fps / 18.64x) and Immich ML acceleration.

**Setup**: Run Helper Menu → `Setup GPU Passthrough (NVIDIA)` → Reboot → Deploy media stack
- Automatic driver installation, cgroup config, device passthrough
- Works in unprivileged LXC with custom container runtime patches

## 🔐 Security & Secrets

- **Unprivileged LXC containers** with UID/GID mapping (101000:101000 → 1000:1000)
- **Encrypted credentials**: All passwords in `.env.enc` files (AES-256-CBC with pbkdf2)
- **Single master password** during deployment decrypts all secrets
- **Network isolation** per stack with dedicated Docker networks
- **Automated updates** via Watchtower (4x daily schedule)

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.