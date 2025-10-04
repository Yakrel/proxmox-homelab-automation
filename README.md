# Proxmox Homelab Automation

A simple, shell-based automation system for deploying containerized services in LXC containers on Proxmox VE.

## ⚠️ **IMPORTANT: Personal Homelab Setup**

**This is a highly specialized, personal homelab automation designed for a specific environment.** It is **NOT plug-and-play** and requires significant modifications for other setups:

### **Hardcoded Environment Requirements:**
- **Network**: `192.168.1.x` range with `vmbr0` bridge and `192.168.1.1` gateway
- **Storage**: ZFS pool named exactly `datapool` 
- **Location**: Timezone automatically set to `Europe/Istanbul` for all containers
- **User Mapping**: Specific UID/GID mappings (`101000:101000`, `PUID=1000`)
- **Passwords**: Pre-configured encrypted passwords for specific services and patterns

### **⚡ Zero Configurability by Design**
This follows the philosophy of "static/hardcoded values preferred over dynamic discovery." To use in your environment, you'll need to:
1. **Fork the repository**
2. **Modify hardcoded values** in scripts and config files
3. **Update network/storage/timezone** settings throughout
4. **Re-encrypt .env.enc files** with your own passwords and encryption key
5. **Test thoroughly** in your specific Proxmox environment

**This approach is intentional** - it prioritizes reliability and simplicity for THIS specific homelab over universal compatibility.

## 🎯 Design Philosophy

- **Idempotent & Fail-Fast**: Operations are safely re-runnable; failures stop immediately
- **Keep It Simple**: Direct approach over complex abstractions
- **Static Configuration**: Hardcoded values preferred over dynamic discovery
- **Latest Everything**: Always use newest versions (Debian, Alpine, Docker images)
- **Minimal Dependencies**: Bash built-ins and basic system tools only

## 🏗️ Architecture

Each service runs in its own LXC container with dedicated resources:

| Stack | ID | Purpose | Resources |
|-------|----|---------|---------  |
| **proxy** | 100 | Reverse proxy, monitoring agents | 2C/2GB/10GB |
| **media** | 101 | Media server (Jellyfin, Immich, Sonarr, Radarr) + GPU acceleration | 6C/10GB/20GB |
| **files** | 102 | File management services | 2C/3GB/15GB |
| **webtools** | 103 | Web-based utilities | 2C/6GB/15GB |
| **monitoring** | 104 | Prometheus, Grafana, Loki stack + auto dashboards | 4C/6GB/15GB |
| **gameservers** | 105 | Game servers (Satisfactory, Palworld) | 8C/16GB/50GB |
| **backup** | 106 | Proxmox Backup Server (native) | 4C/8GB/50GB |
| **development** | 107 | Development environment (Node.js, AI CLIs, dev tools) | 4C/6GB/15GB |

## 🚀 Quick Start

1. **Run on Proxmox host:**
   ```bash
   bash <(curl -s https://raw.githubusercontent.com/Yakrel/proxmox-homelab-automation/main/installer.sh)
   ```

2. **Select stack from menu**
3. **Enter encryption password when prompted** (decrypts `.env.enc` files)
4. **Wait for deployment** - all passwords and services configured automatically

### 🔑 **Password Setup**
- **Single Input**: Only the master encryption password is required during deployment
- **Web Access**: Use your pre-configured passwords to access web interfaces:
  - **Grafana**: `http://<lxc-ip>:3000` (admin / your-grafana-password)
  - **PBS**: `https://<lxc-ip>:8007` (root / your-pbs-password)

## 📁 Project Structure

```
├── installer.sh           # Main entry point (downloads latest scripts)
├── scripts/               # Core deployment scripts
│   ├── main-menu.sh      # Interactive main menu
│   ├── deploy-stack.sh   # Stack deployment orchestrator
│   ├── lxc-manager.sh    # LXC container management
│   ├── helper-functions.sh # Shared utility functions (DRY principle)
│   ├── helper-menu.sh    # Additional utility menu
│   ├── gaming-menu.sh    # Game server selection menu
│   ├── game-manager.sh   # Game server operations
│   ├── encrypt-env.sh    # Environment file encryption
│   └── fail2ban-manager.sh # Fail2ban configuration
├── docker/               # Docker compose files per stack
│   ├── proxy/
│   ├── media/
│   ├── files/
│   ├── webtools/
│   ├── monitoring/
│   └── gameservers/
├── stacks.yaml          # Central configuration
├── config/              # Service configurations
├── CLAUDE.md            # AI assistant development guidelines
└── GEMINI.md            # AI assistant development guidelines (kept identical to CLAUDE.md)
```

## 🔧 Requirements

- **Proxmox VE 8.x**
- **ZFS pool named `datapool`**
- **Network bridge `vmbr0`**
- **IP range `192.168.1.x`**
- **NVIDIA GPU** (optional, for Jellyfin hardware transcoding)

## 🎮 GPU Support (NVIDIA)

For enhanced media transcoding performance in Jellyfin:

### Supported Hardware
- **NVIDIA GTX 970** (tested configuration)
- Other NVIDIA GPUs with similar driver support

### Automatic Setup
The helper scripts provide automated GPU passthrough configuration:
1. **`7) Setup GPU Passthrough (NVIDIA)`** - Configures host system for GPU passthrough
2. **`8) Configure Media Container GPU`** - Maps GPU devices to media LXC container  
3. **`9) Install NVIDIA Drivers in Container`** - Installs required drivers inside container
4. **Automatic NVIDIA toolkit tuning** - Container provisioning now forces `no-cgroups = true` and enables unprivileged device visibility so Docker GPU workloads run cleanly in unprivileged LXC environments (fixes `nvidia-container-cli` device filter errors)
5. **Targeted Jellyfin runtime** - Docker keeps `runc` as the default runtime while Jellyfin explicitly requests the `nvidia` runtime with GPU env vars, so only the media server touches the GPU stack

### Manual Verification
After setup, verify GPU is accessible in Jellyfin:
- Navigate to Jellyfin Admin → Playback → Transcoding
- Select **NVIDIA NVENC** for hardware acceleration
- Monitor GPU usage during transcoding operations

## 📋 Stack Details

### Proxy Stack (LXC 100)
- Cloudflared tunnel
- Promtail log shipping
- Watchtower for updates

### Media Stack (LXC 101)
**GPU-Accelerated Media Services with NVIDIA GTX 970:**

#### 🎬 **Media Streaming & Management:**
- **Jellyfin**: Media server with GPU-accelerated video transcoding
- **Immich**: Self-hosted Google Photos with AI-powered features
- **Sonarr/Radarr/Bazarr**: Automated media management
- **Jellyseerr**: Media request management
- **qBittorrent**: Torrent client
- **Prowlarr**: Indexer management

#### 🚀 **GPU Hardware Acceleration:**
- **Video Transcoding (Jellyfin, Immich):**
  - NVIDIA CUVID decoding (h264, hevc)
  - CUDA scaling and filters
  - NVIDIA NVENC encoding
  - 11-15x real-time transcoding speed
  
- **AI/ML Processing (Immich):**
  - CUDA-accelerated machine learning
  - Face detection & recognition (5-10x faster)
  - Smart object search
  - Semantic image search (CLIP embeddings)
  - GTX 970 Compute Capability 5.2 ✅

#### 📊 **Services & Ports:**
| Service | Port | Description |
|---------|------|-------------|
| Jellyfin | 8096 | Media streaming |
| Immich | 2283 | Photo/video management |
| Sonarr | 8989 | TV show automation |
| Radarr | 7878 | Movie automation |
| Jellyseerr | 5055 | Media requests |
| qBittorrent | 8080 | Torrent client |
| Prowlarr | 9696 | Indexer manager |

> ℹ️ The media stack automatically patches the NVIDIA container runtime to skip cgroup manipulations inside unprivileged LXCs. If you previously hit `nvidia-container-cli: mount error: failed to add device rules`, redeploy with the updated scripts to pick up the fix.

### Files Stack (LXC 102)
- Filebrowser web interface
- Nextcloud personal cloud
- File management tools

### Web Tools Stack (LXC 103)
- Homepage dashboard
- Portainer container management
- Various web utilities

### Monitoring Stack (LXC 104)
**Fully automated monitoring with modern observability stack:**

#### 🔍 **Metrics Collection:**
- **Prometheus**: Scrapes Docker daemon metrics (port 9323) from all LXC containers
- **PVE Exporter**: Proxmox host and VM/LXC metrics with auto-generated credentials
- **Docker Engine Metrics**: Native Docker daemon API (no cAdvisor needed)

#### 📊 **Visualization:**
- **Grafana**: Auto-configured with pre-defined admin credentials
- **Automated Dashboard Management**: Pre-configured Prometheus datasource and auto-imported dashboards

#### 📈 **Auto-Imported Dashboards:**
- **#10347**: Proxmox via Prometheus (most popular Proxmox dashboard)
- **#893**: Docker and System Monitoring (comprehensive container metrics)
- **#12611**: Logging Dashboard via Loki (official log dashboard)

> **Resilient Import**: Prometheus datasource is always configured. Dashboard imports are attempted automatically but failures won't stop deployment - monitoring stack remains fully functional

#### 📝 **Log Aggregation:**
- **Loki**: Central log storage with 30-day retention
- **Promtail**: Automatic log collection from all Docker containers and system logs
- **Log Pipeline**: Container logs + system logs with proper labeling and parsing

#### ⚙️ **Automated Setup:**
- **PVE User**: Auto-creates `pve-exporter@pve` with `PVEAuditor` role and fixed password
- **PBS User**: Auto-creates `prometheus@pbs` with monitoring permissions and fixed password
- **Grafana Setup**: Auto-configures Prometheus datasource and imports recommended dashboards
- **Credentials**: All passwords loaded from encrypted `.env.enc` files
- **Idempotent**: Re-runnable deployment with consistent passwords

### Game Servers Stack (LXC 105)
- Satisfactory dedicated server
- Palworld server
- Extensible for more games

### Backup Stack (LXC 106)
- Proxmox Backup Server
- Automated backup schedules
- Data verification

## 🛡️ Security

- **Unprivileged LXC containers** for security isolation
- **Feature flags** (nesting, keyctl) set post-creation
- **Network isolation** with dedicated VLANs
- **Regular security updates** via automated processes

### 🔐 **Password Management**

**Single Interaction Security Model**: Only one password required from you.

#### User Passwords (You Set These):
```bash
Encryption Master: <your-master-password>  # Decrypts all .env.enc files
Grafana Admin:     <your-grafana-password> # Web dashboard access  
PBS Admin:         <your-pbs-password>     # Backup server web access
```

#### System Passwords (Automated):
- **PVE Monitoring**: Fixed random password for Prometheus → PVE API access
- **PBS Prometheus**: Fixed random password for Prometheus → PBS API access  
- **Service Keys**: All API keys and inter-service credentials managed automatically

#### Implementation:
- **Encrypted Storage**: All passwords stored in `.env.enc` files using AES-256-CBC
- **Idempotent**: Same passwords every deployment, re-runnable and predictable
- **No Secrets in Code**: Zero hardcoded passwords or keys in repository
- **Fail-Fast**: Missing passwords cause immediate deployment failure

## 📝 Configuration

All configuration is centralized in `stacks.yaml`:

```yaml
network:
  gateway: 192.168.1.1
  bridge: vmbr0
  ip_base: 192.168.1

storage:
  pool: datapool

stacks:
  proxy:
    ct_id: 100
    hostname: lxc-proxy-01
    ip_octet: 100
    cpu_cores: 2
    memory_mb: 2048
    disk_gb: 10
```

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.