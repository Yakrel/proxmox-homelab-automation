# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Proxmox homelab automation project that deploys Docker-based services across multiple specialized LXC containers. The project uses a stack-based architecture with 6 main stacks:

- **Proxy Stack (LXC 100)**: Cloudflare tunnels for secure external access
- **Media Stack (LXC 101)**: Complete media automation (Sonarr, Radarr, Jellyfin, qBittorrent, etc.)
- **Files Stack (LXC 102)**: JDownloader2, MeTube, and Palmr for file management
- **Webtools Stack (LXC 103)**: Homepage dashboard, Firefox browser and administrative tools
- **Monitoring Stack (LXC 104)**: Prometheus, Grafana, and Alertmanager for system monitoring
- **Development Stack (LXC 150)**: Ubuntu environment with Claude Code and Node.js
- **Content Stack (LXC 105)**: Reserved for future content management (Immich, etc.)

## Key Commands

### Main Deployment
```bash
# Quick setup (downloads and runs setup.sh)
bash -c "$(wget -qO - https://raw.githubusercontent.com/Yakrel/proxmox-homelab-automation/main/setup.sh)"

# Deploy individual stacks
bash scripts/automation/create_alpine_lxc.sh <stack_type>
bash scripts/automation/deploy_stack.sh <stack_type>

# Deploy development environment
bash scripts/automation/create_development_lxc.sh development
```

### Stack Management
```bash
# Check LXC status
pct status <lxc_id>

# Enter LXC container
pct enter <lxc_id>

# Inside LXC: Manage Docker services
cd /opt/<stack_type>-stack
docker compose ps
docker compose logs <service_name>
docker compose pull && docker compose up -d
```

### Development Environment
```bash
# Access development LXC (150)
pct enter 150
ssh root@192.168.1.150

# Start Claude Code
cd /root/projects
claude-code
```

## Architecture & Structure

### File Organization
- `setup.sh`: Main entry point - interactive menu system
- `scripts/automation/`: LXC creation and stack deployment scripts
- `scripts/core/`: Core system setup (security, storage, timezone)
- `scripts/utils/common.sh`: Shared utility functions and constants
- `docker/*/`: Docker Compose configurations for each stack
- `config/homepage/`: Homepage dashboard configuration files

### LXC Container Specifications
- **Alpine-based containers**: Used for Docker stacks (100-104)
- **Ubuntu-based container**: Used for development (150)
- **Unprivileged LXCs**: All containers run as unprivileged for security
- **Datapool mount**: Shared storage at `/datapool` with ACL support
- **Standard IPs**: 192.168.1.x pattern (e.g., 192.168.1.101 for media stack)

### Permission System
- **Host-side ownership**: 101000:101000 (unprivileged LXC mapping)
- **Container-side**: PUID=1000, PGID=1000 for Docker services
- **LXC mapping**: 1000 (container) → 101000 (host)

### Common Patterns
- **Idempotent scripts**: All deployment scripts can be run multiple times safely
- **Environment validation**: Scripts check for required variables in .env files
- **Container readiness**: Wait loops ensure containers are ready before proceeding
- **Unified logging**: Standardized print functions (print_info, print_error, etc.)
- **Unified environment setup**: All stacks use shared functions from common.sh for consistent .env creation
- **Shared components**: Common functionality is centralized in common.sh to avoid code duplication

### Key Directories
- `/datapool/config/`: Configuration storage for all services
- `/datapool/media/`: Final media storage (movies, TV shows)
- `/datapool/torrents/`: Torrent download location
- `/opt/<stack>-stack/`: Docker Compose files inside each LXC

## Development Notes

### Shared Functions
The `scripts/utils/common.sh` file contains essential shared functions:
- `ensure_container_ready()`: Waits for LXC and Docker to be ready
- `ensure_datapool_mount()`: Adds /datapool mount to containers
- `ensure_datapool_permissions()`: Sets proper ownership for stack directories
- `print_*()`: Standardized logging functions
- `get_simple_password()`: Simple, reliable password input function (no complex retry logic)
- `create_stack_env_file()`: Unified .env file creation for all stacks
- `get_existing_env_value()`: Extract values from existing environment files
- `generate_encryption_key()`: Generate secure random keys for services

**IMPORTANT**: When improving any script functionality (like .env file creation or password input), apply the improvement to ALL LXC scripts using the shared functions in common.sh. This ensures consistency and prevents dead code.

### Stack Deployment Flow
1. Create LXC container with appropriate template
2. Configure datapool mount and permissions
3. Download latest Docker Compose files from GitHub
4. Run interactive setup for environment variables
5. Deploy services with `docker compose up -d`
6. Configure monitoring user (for monitoring stack)

### Environment Configuration
Each stack uses `.env` files for configuration:
- **Monitoring**: Requires GRAFANA_ADMIN_PASSWORD, PVE_PASSWORD, PVE_URL
- **Proxy**: Requires CLOUDFLARED_TOKEN
- **Utility/Downloads**: Require VNC passwords
- **Media**: Uses timezone and standard PUID/PGID


## Development Environment Notes

**IMPORTANT**: This repository is designed for Proxmox VE environments. When working in development/testing environments:

- **Proxmox commands unavailable**: Commands like `pct`, `pveum`, and other Proxmox-specific tools are not available outside of a Proxmox host
- **LXC operations**: Scripts that create, manage, or execute commands in LXC containers (`pct enter`, `pct exec`, etc.) will not work
- **Docker not available**: Docker is not installed in this development environment - cannot run `docker compose` commands
- **SSH operations**: Cannot SSH to Proxmox containers (192.168.1.x IPs) from this development environment
- **File permissions**: Host-side permission management (101000:101000) is specific to Proxmox unprivileged containers

### Development Workflow
This environment is for **development and testing only**:
1. Edit and update scripts, configuration files, and Docker Compose definitions
2. Test shell script syntax and logic (functions that don't require Proxmox/LXC/Docker)
3. Validate YAML syntax and configuration structure
4. **Deploy and test on actual Proxmox environment** for full functionality

### Testing Approach
- **Here**: Script development, syntax validation, configuration updates
- **Proxmox**: Actual deployment, Docker operations, LXC management, integration testing

## Tasarım Kuralları

Bu kurallar, projenin tüm geliştirme süreçlerinde göz önünde bulundurulmalıdır:

### 1. Tek ve Belirgin Senaryo
- Otomasyon yalnızca bu özel homelab yapısı için tasarlanmıştır
- LXC ID'leri, IP adresleri (192.168.1.x), depolama havuzu (`datapool`) sabit ve kod içinde belirtilmiştir
- Farklı ortamlar için esneklik aranmaz - bu basitlik ve anlaşılırlık sağlar

### 2. En Son LTS Sürümleri
- LXC konteynerleri için her zaman en güncel LTS sürümleri (Ubuntu LTS) kullanılır
- Proxmox tarafından otomatik indirilen şablonlar tercih edilir
- Manuel şablon güncellemesi ihtiyacını ortadan kaldırır

### 3. Merkezi Fonksiyonlar (`common.sh`)
- Tekrar eden görevler `scripts/utils/common.sh` dosyasında toplanır
- Loglama, durum kontrolü, komut kontrolü gibi yardımcı fonksiyonlar merkezi olarak yönetilir
- Kod tekrarını önler ve bakımı kolaylaştırır

### 4. Idempotent (Tekrarlanabilir) Scriptler
- Tüm scriptler birden çok kez çalıştırıldığında güvenli olmalıdır
- Mevcut yapılandırmalar ve veriler korunmalıdır
- Örnek: `.env` dosyasındaki şifreler script tekrar çalıştığında silinmemelidir

### 5. Güvenlik ve Erişim Modeli
- **Root Erişimi:** LXC konteynerlerine yalnızca Proxmox konsolu veya `pct enter` ile şifresiz erişim
- **SSH Kapalı:** LXC konteynerlerinde SSH servisi varsayılan olarak kapalıdır
- Harici erişim vektörlerini azaltır ve yönetimi merkezileştirir

### 6. Etkileşimli ve Otomatik Kurulum
- Hassas veriler (API anahtarları, şifreler) interactive script'ler ile alınır
- Mevcut değerler varsa tekrar sorulmaz
- **Monitoring Stack:** `monitoring@pve` kullanıcısı otomatik oluşturulur/güncellenir

### 7. Basitlik ve Odaklanmış Hata Kontrolü
- "Keep It Simple" prensibi uygulanır
- Karmaşık yan senaryolar yerine ana senaryo üzerinde odaklanılır
- Hata kontrolü basit ve etkili tutulur

### 8. Tam Otomatik Monitoring Stack
- Sıfırdan tam otomatik dağıtım hedeflenir
- Manuel işlemler tamamen ortadan kaldırılır
- Proxmox kullanıcı yönetimi, servis yapılandırmaları, `.env` dosyaları otomatik hazırlanır

## Important Instructions for Claude

**NEVER add "powered by Claude" or similar attribution messages to commit messages or code.** This includes:
- No "🤖 Generated with [Claude Code]" messages
- No "Co-Authored-By: Claude" lines
- No AI attribution in any form

Keep commit messages clean and professional without AI attribution.