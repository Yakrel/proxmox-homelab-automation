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
Complete media management with GPU acceleration:
- **Jellyfin** - Media server with hardware transcoding
- **Immich** - Photo/video management with ML (face recognition, object detection)
- **Sonarr/Radarr/Bazarr** - TV/Movie/Subtitle automation
- **Jellyseerr** - Media request management
- **Prowlarr** - Indexer manager
- **qBittorrent** - Torrent client
- **FlareSolverr** - Cloudflare bypass
- **Recyclarr** - Quality profile sync
- **Cleanuperr** - Automatic torrent cleanup

### **Monitoring & Observability Stack** (LXC 104)
Full monitoring infrastructure with auto-configured dashboards:
- **Prometheus** - Metrics collection (30-day retention)
- **Grafana** - Visualization with auto-imported dashboards
- **Loki** - Log aggregation (30-day retention)
- **Promtail** - Log collection from all LXC containers
- **PVE Exporter** - Proxmox metrics
- **cAdvisor** - Container metrics

### **File Management Stack** (LXC 102)
Download and file handling:
- **JDownloader 2** - Direct download manager
- **MeTube** - YouTube-dl web interface
- **Palmr** - File management and sharing

### **Web Tools Stack** (LXC 103)
Productivity and development tools:
- **Homepage** - Unified dashboard with service widgets
- **Desktop Workspace** - Web-based Chrome + Obsidian environment
- **CouchDB** - Database for Obsidian sync
- **Portainer** - Docker management UI

### **Proxy & Tunnel Stack** (LXC 100)
External access and monitoring:
- **Cloudflared** - Cloudflare tunnel for secure remote access
- **Promtail** - Log shipping
- **Watchtower** - Auto-updates

### **Backup Stack** (LXC 106)
Automated backup with cloud sync:
- **Backrest** - Web-based backup UI (powered by restic)
- **Rclone** - Google Drive sync via post-backup hooks
- Automated backups: `/datapool/config` + Immich media
- Encrypted offsite backups to Google Drive

### **Game Servers Stack** (LXC 105)
Dedicated game hosting:
- **Satisfactory** - Factory building game server
- **Palworld** - Multiplayer survival server

### **Development Stack** (LXC 107)
Development environment (extensible framework)

---

## 🛠️ Technical Highlights

### Custom Docker Image Development
**Desktop Workspace** - Containerized web-based desktop environment

**Features:**
- Multi-app integration: **Google Chrome** + **Obsidian** + **PCManFM**
- Web-based access via Selkies-GStreamer (WebRTC)
- Automated CI/CD: GitHub Actions → DockerHub
- Weekly automatic rebuilds

**CI/CD Pipeline:**
```
Trigger: Push to main OR Weekly (Sunday 2 AM)
   ↓
Build: Docker Buildx with layer caching
   ↓
Push: DockerHub (latest + SHA tags)
   ↓
Deploy: Watchtower auto-pulls in homelab
```

**Source:** [`docker-images/desktop-workspace/`](docker-images/desktop-workspace/)

### GPU Hardware Acceleration
**NVIDIA GPU Passthrough in Unprivileged LXC**
- **Media Stack**: Jellyfin hardware transcoding (18.64x real-time, 447 fps) + Immich ML acceleration
- **Webtools Stack**: Chrome GPU acceleration in desktop-workspace container
- Direct device mounting with CUDA library integration
- Production-tested with NVIDIA GTX 970

**Setup:** Helper Menu → `Setup GPU Passthrough (NVIDIA)` → Reboot → Deploy stacks

### Infrastructure as Code
- **8 production stacks** with automated deployment
- **40+ containerized services** via Docker Compose
- **Debian-based LXC containers** for all stacks (unified infrastructure)
- **Encrypted secrets**: AES-256-CBC with pbkdf2
- **Idempotent scripts**: Safe to re-run
- **Comprehensive monitoring**: Prometheus + Grafana + Loki

---

## 🎯 Key Features

### **Zero-Touch Deployment**
- Single command deployment per stack
- Encrypted credentials in `.env.enc` files
- Automatic service configuration
- Idempotent scripts

### **Automated Offsite Backups**
- Backrest hooks trigger rclone sync after successful backups
- Google Drive integration (15 GB free tier)
- OAuth2 authentication stored encrypted
- Runs inside Alpine LXC (no host dependencies)

### **Comprehensive Monitoring**
- Every LXC has Promtail + cAdvisor
- Central Grafana with pre-imported dashboards
- 30-day retention for metrics and logs

### **Security & Isolation**
- Unprivileged LXC containers with UID/GID mapping
- Encrypted secrets management
- Network isolation per stack
- Regular automated updates via Watchtower

---

## ⚠️ Personal Homelab Notice

**This is a production homelab optimized for a specific environment.** Hardcoded values for reliability:

- **Network**: `192.168.1.x` range, `vmbr0` bridge
- **Storage**: ZFS pool `datapool`
- **Timezone**: `Europe/Istanbul`
- **Passwords**: Pre-encrypted in `.env.enc`

**Not plug-and-play.** To adapt: fork, modify hardcoded values, re-encrypt secrets, test.

## 📁 Project Structure

```
├── installer.sh              # One-line installer
├── scripts/                  # Deployment automation
│   ├── deploy-stack.sh      # Stack orchestrator
│   ├── lxc-manager.sh       # LXC lifecycle
│   └── helper-*.sh          # Utilities
├── docker-images/            # Custom images
│   └── desktop-workspace/   # Web-based desktop
├── docker/                   # Service stacks
│   ├── media/               # Jellyfin + Immich + GPU
│   ├── monitoring/          # Prometheus + Grafana + Loki
│   ├── files/               # Download managers
│   ├── webtools/            # Dashboard + tools
│   ├── proxy/               # Cloudflare tunnel
│   ├── backup/              # Backrest + rclone
│   └── gameservers/         # Game servers
└── stacks.yaml              # Central config
```

## 🔧 Requirements

- Proxmox VE 9.x with ZFS storage
- Network: `vmbr0` bridge, `192.168.1.x` range
- Optional: NVIDIA GPU for transcoding/ML

## 🔐 Security & Secrets

- **Unprivileged LXC** with UID/GID mapping (101000:101000 → 1000:1000)
- **Encrypted credentials**: AES-256-CBC with pbkdf2
- **Single master password** decrypts all secrets
- **Network isolation** per stack
- **Automated updates** via Watchtower

## 📄 License

MIT License - see [LICENSE](LICENSE) file for details.
