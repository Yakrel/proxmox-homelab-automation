# GEMINI.md

<!-- 
    CRITICAL: This file must be kept identical to CLAUDE.md
    Both AI assistants need the same context and guidelines for this project.
    Any changes made to CLAUDE.md must be mirrored here exactly.
-->

This file provides guidance when working with code in this repository.

## Development Philosophy (CRITICAL - Follow Exactly)

This homelab automation follows these core principles:

### 1. **Idempotent & Fail-Fast**
- All operations must be safely re-runnable
- When something fails, stop immediately - don't try to recover
- Minimal error handling - let failures bubble up for quick manual fixes
- Exception: Critical services (like PBS) may have retry logic with proper timeouts
- The system should work perfectly in THIS homelab, not handle every edge case

### 2. **Keep It Simple & Short**
- Prefer short, direct code over complex abstractions
- No unnecessary error handling or complex logic
- Static/hardcoded values are PREFERRED over dynamic discovery
- If code is getting long, we're probably over-engineering

### 3. **DRY (Don't Repeat Yourself)**
- Avoid duplicating the same logic across scripts
- Use shared functions for common functionality
- Single source of truth for configuration (stacks.yaml)

### 4. **Latest Everything**
- Always use latest versions: Debian, Alpine, Docker images, etc.
- No version pinning - we want the newest features and security updates
- This is intentional - we accept the risk for a homelab environment

### 5. **Minimal Dependencies**
- Keep external dependencies to minimum
- Prefer bash built-ins over external tools where possible
- Direct approach over complex abstractions

## Project Overview

This is a shell-based automation system for deploying containerized services in LXC containers on Proxmox VE. Everything is designed to be simple, direct, and maintainable.

## Key Architecture

- **Single Entry Point**: `installer.sh` downloads latest scripts and runs menu
- **Shell Scripts**: All logic in bash scripts (no complex frameworks)
- **LXC Containers**: Each service stack runs in dedicated container
- **Docker Compose**: Services defined in docker-compose files
- **Static Configuration**: All settings in `stacks.yaml`

## File Structure

```
├── installer.sh          # Entry point - downloads and runs scripts
├── scripts/              # Core automation scripts
│   ├── main-menu.sh     # Interactive stack selection
│   ├── deploy-stack.sh  # Stack deployment orchestrator  
│   ├── lxc-manager.sh   # LXC container operations
│   ├── helper-menu.sh   # Additional utilities
│   ├── gaming-menu.sh   # Game server management
│   ├── game-manager.sh  # Game server operations
│   ├── encrypt-env.sh   # Environment encryption
│   └── fail2ban-manager.sh # Fail2ban configuration
├── docker/              # Docker compose per stack
│   ├── proxy/
│   ├── media/
│   ├── files/
│   ├── webtools/
│   ├── monitoring/
│   └── gameservers/
├── stacks.yaml         # Central configuration
└── config/             # Service config templates
```

## Stack Architecture

Each stack follows this pattern:
1. **Create LXC container** using `pct create`
2. **Set feature flags** with `pct set --features keyctl=1,nesting=1`
3. **Install Docker** if docker-compose.yml exists
4. **Deploy services** with docker-compose
5. **Configure networking** and storage mounts

## Available Stacks

| Stack | ID | Purpose |
|-------|----|---------| 
| proxy | 100 | Reverse proxy, monitoring agents |
| media | 101 | Jellyfin, Sonarr, Radarr |
| files | 102 | File management services |
| webtools | 103 | Web utilities, dashboards |
| monitoring | 104 | Prometheus, Grafana |
| gameservers | 105 | Game servers |
| backup | 150 | Proxmox Backup Server (native, no Docker) |
| development | 151 | Development tools (no Docker, minimal setup) |

## Key Implementation Notes

### LXC Container Management
- All containers are unprivileged for security
- Feature flags (keyctl=1, nesting=1) set after creation for Docker support
- Static IP assignment based on container ID
- ZFS storage with datapool mount points

### Docker Integration
- Only install Docker if docker-compose.yml exists in stack
- Use latest Alpine/Debian base images for Docker stacks
- Use latest Debian for native services (PBS)
- No version pinning - always pull latest
- Persistent data in `/datapool/config/STACK_NAME/`

### Special Stack Handling
- **backup**: Uses Debian + native Proxmox Backup Server (no Docker)
- **development**: Uses Alpine + Node.js/npm (no Docker)  
- **All others**: Use Alpine + Docker Compose

### Network Configuration
- Bridge: vmbr0
- IP Range: 192.168.1.x
- Gateway: 192.168.1.1
- Container IP = 192.168.1.<container_id>

### Common Commands

```bash
# Deploy a stack
./installer.sh

# Check container status
pct list

# Access container
pct exec <id> -- bash

# View docker services
pct exec <id> -- docker ps

# Check logs
pct exec <id> -- docker logs <service>
```

### Development Guidelines
- Test all changes on actual Proxmox environment
- Ensure idempotency - scripts should be re-runnable
- Keep error messages clear and actionable
- Document any assumptions or requirements
- Use descriptive variable names
- Comment complex logic only when necessary

### Security Considerations
- Never commit secrets or passwords
- Use unprivileged containers when possible
- Set minimal required feature flags
- Regular updates via latest image pulls
- Network isolation between stacks where needed

### Git Commit Guidelines
- **NEVER** use "Generated with Claude Code" or similar AI attribution in commits
- **ALWAYS** commit as the actual developer (Yakrel), not as Claude
- Keep commit messages professional and focused on the actual changes
- Author should always be the human developer, not the AI assistant