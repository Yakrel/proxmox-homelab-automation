# Proxmox Homelab Automation Development Guidelines

Auto-generated from all feature plans. Last updated: [DATE]

## Core Technologies
- **Scripting**: Bash 5.x (pure shell scripting)
- **Platform**: Proxmox VE (Debian Trixie 13.1)
- **Containerization**: LXC containers
- **Services**: Docker Compose stacks
- **Monitoring**: Prometheus, Grafana, Loki

## Project Structure
```
scripts/           # Main automation scripts
docker/           # Docker compose configurations  
config/          # Service configuration templates
.specify/        # Specification and planning files
```

## Development Commands
- `bash scripts/main-menu.sh` - Main automation interface
- `bash scripts/deploy-stack.sh [stack]` - Deploy service stack
- `bash scripts/lxc-manager.sh` - LXC container management
- `pct create` - Create LXC containers (PVE command)
- `docker-compose up -d` - Start services in containers

## Code Style (Bash)
- Use `#!/bin/bash` shebang
- Prefer built-in commands over external tools
- Hardcode PVE-specific values (192.168.1.x, datapool, Europe/Istanbul)
- No error recovery - let commands fail naturally  
- Always use `latest` versions
- Clear variable names with UPPER_CASE for constants

## Recent Changes
[LAST 3 FEATURES AND WHAT THEY ADDED]

<!-- MANUAL ADDITIONS START -->
<!-- MANUAL ADDITIONS END -->