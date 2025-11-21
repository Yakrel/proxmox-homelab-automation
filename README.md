# Proxmox Homelab Automation

Production homelab infrastructure running **40+ containerized services** across **8 specialized LXC containers** on Proxmox VE. Fully automated deployment with shell scripts, zero-touch configuration, and comprehensive monitoring.

## 🚀 Quick Start

**One-line installer on Proxmox host:**
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/Yakrel/proxmox-homelab-automation/main/installer.sh)"
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
Full monitoring infrastructure with auto-configured dashboards and alerting:
- **Prometheus** - Metrics collection with recording rules (30-day retention)
- **Alertmanager** - Alert routing and notification management
- **Grafana** - Visualization with 4 auto-imported dashboards
- **Loki** - Log aggregation (30-day retention)
- **Promtail** - Log collection from all LXC containers
- **PVE Exporter** - Proxmox host and LXC metrics
- **cAdvisor** - Per-container Docker metrics
- **Node Exporter** - OS-level system metrics

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
- **Backrest-Rclone** - Custom Docker image combining Backrest (restic web UI) + rclone
- Automated backups: `/datapool/config` + Immich media
- Post-backup hooks trigger Google Drive sync
- Encrypted offsite backups with OAuth2 authentication
- Auto-updates via Watchtower + CI/CD

### **Game Servers Stack** (LXC 105)
Dedicated game hosting:
- **Satisfactory** - Factory building game server
- **Palworld** - Multiplayer survival server

### **Development Stack** (LXC 107)
Development environment (extensible framework)

---

## 🛠️ Technical Highlights

### Custom Docker Images with CI/CD

Two custom Docker images built and maintained with automated CI/CD pipelines:

#### **Desktop Workspace** - Web-based development environment
- Multi-app integration: **Google Chrome** + **Obsidian** + **PCManFM**
- Web-based access via Selkies-GStreamer (WebRTC)
- GPU acceleration support for Chrome rendering
- **Source:** [`docker-images/desktop-workspace/`](docker-images/desktop-workspace/)

#### **Backrest-Rclone** - Backup solution with cloud sync
- Base: `garethgeorge/backrest:latest` (restic web UI)
- Custom layer: **rclone** for Google Drive sync hooks
- Automated post-backup cloud sync via rclone hooks
- **Source:** [`docker-images/backrest-rclone/`](docker-images/backrest-rclone/)

**CI/CD Pipeline:**
```
Trigger: Code changes OR Bi-weekly (Sunday & Wednesday 2 AM)
   ↓
Build: Docker Buildx with layer caching
   ↓
Tag: latest + YYYYMMDD-SHA (keep last 3 dated tags)
   ↓
Push: DockerHub (yakrel93/desktop-workspace, yakrel93/backrest-rclone)
   ↓
Deploy: Watchtower auto-updates containers in homelab
```

**Benefits:**
- Always-fresh base images (bi-weekly automatic rebuilds)
- Zero-downtime updates via Watchtower
- Rollback capability (3 previous versions retained)
- No manual image building required

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
- **Mixed LXC containers**: Alpine (default, lightweight) + Debian (GPU stacks with hardware acceleration)
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
- Custom Docker image with Backrest + rclone integration
- Post-backup hooks automatically sync to Google Drive
- OAuth2 authentication stored encrypted in `.env.enc`
- CI/CD pipeline ensures latest base image + rclone version
- Zero-downtime updates via Watchtower

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
├── docker-images/            # Custom Docker images with CI/CD
│   ├── desktop-workspace/   # Web-based desktop (Chrome + Obsidian)
│   └── backrest-rclone/     # Backup with cloud sync
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
