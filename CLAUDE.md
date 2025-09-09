# CLAUDE.md

<!-- 
    CRITICAL: This file must be kept identical to GEMINI.md
    Both AI assistants need the same context and guidelines for this project.
    Any changes made to GEMINI.md must be mirrored here exactly.
-->

This file provides guidance when working with code in this repository.

## Development Philosophy (CRITICAL - Follow Exactly)

This homelab automation follows these core principles:

### 1. **Fail Fast & Simple**
- All operations must be safely re-runnable
- When something fails, show basic error message and exit immediately
- No retry logic anywhere in the codebase - everything works first time or fails fast
- No complex error recovery - just fail and let user fix the issue
- Focus on THIS homelab's main scenario, not edge cases

### 2. **Homelab-First Approach**
- Prefer short, direct code over complex abstractions
- Minimal error handling - just enough to know what failed
- Static/hardcoded values are PREFERRED over dynamic discovery
- If code is getting long, we're probably over-engineering
- Edge cases cause failures - this is acceptable for homelab use

### 3. **DRY (Don't Repeat Yourself)**
- Avoid duplicating the same logic across scripts
- Use shared functions for common functionality

### 4. **Latest Everything**
- Always use latest versions: Debian, Alpine, Docker images, etc.
- No version pinning - we want the newest features and security updates
- This is intentional - we accept the risk for a homelab environment

### 5. **Minimal Dependencies**
- Keep external dependencies to minimum
- Prefer bash built-ins over external tools where possible
- Direct approach over complex abstractions

### 6. **Fail Fast Philosophy**
- Use `latest` tags for all container images and software packages
- Pre-defined network topology: Proxmox at 192.168.1.10, LXCs at 192.168.1.{lxc_id}
- Pre-configured storage pool (datapool) - no discovery needed
- Minimal interactivity: Only prompt for .env.enc decryption passphrase
- Manual version rollback when needed (homelab tolerance for breakage)
- Centralized configuration without complex discovery mechanisms
- **Scripts optimize for single main scenario - edge cases should fail fast**

## Project Overview

This is a shell-based automation system for deploying containerized services in LXC containers on Proxmox VE. Everything is designed to be simple, direct, and maintainable.

## Key Architecture

- **Single Entry Point**: `installer.sh` downloads latest scripts and runs menu
- **Shell Scripts**: All logic in bash scripts (no complex frameworks)
- **LXC Containers**: Each service stack runs in dedicated container
- **Docker Compose**: Services defined in docker-compose files
- **Static Configuration**: All settings in `stacks.yaml`
- **Modular Structure**: Specialized modules for different deployment types

## Stack Architecture

Each stack follows this pattern:
1. **Create LXC container** using `pct create`
2. **Set feature flags** with `pct set --features keyctl=1,nesting=1`
3. **Install Docker** if docker-compose.yml exists
4. **Deploy services** with docker-compose
5. **Configure networking** and storage mounts

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
- **backup**: Uses latest stable Debian + native Proxmox Backup Server (no Docker)
- **development**: Uses Alpine + Node.js/npm (no Docker)  
- **All others**: Use Alpine + Docker Compose

### Modular Deployment
- **modules/config-validator.sh**: Basic configuration validation - fail fast on critical errors only
- **modules/docker-deployment.sh**: Standard Docker stack deployment - fail immediately on errors
- **modules/monitoring-deployment.sh**: Monitoring specialization (Grafana + Prometheus)
- **modules/backup-deployment.sh**: PBS specialization

### Error Handling Pattern
```bash
# Homelab fail-fast approach - simple and direct
function deploy_something() {
    local step="$1"
    
    print_info "Starting: $step"
    
    # Fail fast - no recovery attempts
    if ! some_command; then
        print_error "Failed: $step"
        exit 1
    fi
    
    print_success "Completed: $step"
}
```

### Development Guidelines
- Test all changes on actual Proxmox environment
- Ensure idempotency - scripts should be re-runnable
- Use fail-fast approach - scripts exit immediately on errors
- No retry loops, waiting loops, or recovery attempts in any function
- Basic error messages sufficient for homelab debugging
- Use `set -euo pipefail` for automatic error detection and exit
- Document any assumptions or requirements
- Use descriptive variable names
- Optimize for main scenario - edge cases should fail fast

### Security Considerations
- Never commit secrets or passwords
- Use unprivileged containers
- Set minimal required feature flags
- Regular updates via latest image pulls
- Network isolation between stacks where needed

### Working Environment Notes
- **Current Context**: Claude Code runs in an LXC container (`/root/proxmox-homelab-automation`), NOT on the Proxmox host
- **Proxmox Host Commands**: When commands need to be run on Proxmox host (pvesm, pveum, zfs, etc.), ask the user to run them and provide the output
- **Host vs Container**: Always be aware of execution context - scripts run on host but Claude debugging happens in container

### Command Usage Guidelines
- **No user approval required** for: git commands, bash operations, find, grep, curl, yq, systemctl, docker commands, file operations (read/write/edit)
- **Use freely without asking**: Standard development tools and utilities for analysis, debugging, and code modifications
- **Direct execution preferred** over asking permission for routine development tasks

### Git Commit Guidelines
- **NEVER** use "Generated with Claude Code" or similar AI attribution in commits
- **ALWAYS** commit as the actual developer (Yakrel), not as Claude
- Keep commit messages professional and focused on the actual changes
- Author should always be the human developer, not the AI assistant
