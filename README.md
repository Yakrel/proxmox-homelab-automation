# Proxmox Homelab Automation

A simple, shell-based automation system for deploying containerized services in LXC containers on Proxmox VE.

## ⚠️ **IMPORTANT: Personal Homelab Setup**

**This is a highly specialized, personal homelab automation designed for a specific environment.** It is **NOT plug-and-play** and requires significant modifications for other setups:

### **Hardcoded Environment Requirements:**
- **Network**: `192.168.1.x` range with `vmbr0` bridge and `192.168.1.1` gateway
- **Storage**: ZFS pool named exactly `datapool` 
- **Location**: Timezone automatically set to `Europe/Istanbul` for all containers
- **User Mapping**: Specific UID/GID mappings (`101000:101000`, `PUID=1000`)

### **⚡ Zero Configurability by Design**
This follows the philosophy of "static/hardcoded values preferred over dynamic discovery." To use in your environment, you'll need to:
1. **Fork the repository**
2. **Modify hardcoded values** in scripts and config files
3. **Update network/storage/timezone** settings throughout
4. **Test thoroughly** in your specific Proxmox environment

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
| **media** | 101 | Media server (Jellyfin, Sonarr, Radarr) | 6C/10GB/20GB |
| **files** | 102 | File management services | 2C/3GB/15GB |
| **webtools** | 103 | Web-based utilities | 2C/6GB/15GB |
| **monitoring** | 104 | Prometheus, Grafana, Loki stack + auto dashboards | 4C/6GB/15GB |
| **gameservers** | 105 | Game servers (Satisfactory, Palworld) | 8C/16GB/50GB |
| **backup** | 106 | Proxmox Backup Server (native) | 4C/8GB/50GB |
| **development** | 107 | Development tools (minimal) | 4C/6GB/15GB |

## 🚀 Quick Start

1. **Run on Proxmox host:**
   ```bash
   bash <(curl -s https://raw.githubusercontent.com/Yakrel/proxmox-homelab-automation/main/installer.sh)
   ```

2. **Select stack from menu**
3. **Wait for deployment**

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

## 📋 Stack Details

### Proxy Stack (LXC 100)
- Cloudflared tunnel
- Promtail log shipping
- Watchtower for updates

### Media Stack (LXC 101)
- Jellyfin media server
- Sonarr/Radarr for automation
- Transmission torrent client

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
- **Auto-installed Dashboards** (latest 2025 versions):
  - **#10347**: Proxmox via Prometheus (most popular Proxmox dashboard)
  - **#893**: Docker and System Monitoring (comprehensive container metrics)
  - **#12611**: Logging Dashboard via Loki (official log dashboard)

#### 📝 **Log Aggregation:**
- **Loki**: Central log storage with 30-day retention
- **Promtail**: Automatic log collection from all Docker containers and system logs
- **Log Pipeline**: Container logs + system logs with proper labeling and parsing

#### ⚙️ **Automated Setup:**
- **PVE User**: Auto-creates `pve-exporter@pve` with `PVEAuditor` role and random password
- **Environment**: All credentials auto-generated and configured
- **Dashboard Provisioning**: Downloads latest dashboards from grafana.com during deployment
- **Idempotent**: Re-runnable deployment with password updates

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