# CLAUDE.md

<!--
    CRITICAL: This file must be kept identical to AGENTS.md
    Both files need the same context and guidelines for all AI assistants.
    Any changes made to one file must be mirrored in the other exactly.
-->

AI coding agents guidance for this Proxmox homelab automation project.

**Always follow best practices and keep code clean.**

## Project Overview

Zero-to-production automation system for Proxmox VE homelab environments. Deploys 8 containerized service stacks (proxy, media, files, webtools, monitoring, gameservers, backup, development) in isolated LXC containers with interactive menu-driven deployment, encrypted environment management, and automatic monitoring dashboard imports.

## Architecture

### Core Components
- **Interactive Menu System**: `scripts/main-menu.sh` - Bash-based user interface for stack selection
- **LXC Container Management**: `scripts/lxc-manager.sh` - Automated container creation via `pct` commands
- **Environment Encryption**: `scripts/encrypt-env.sh` - OpenSSL AES-256-CBC encryption for configurations
- **Service Orchestration**: `scripts/deploy-stack.sh` - Docker Compose deployment within containers
- **Monitoring Integration**: `scripts/monitoring-setup.sh` - Automatic Grafana dashboard imports (#10347, #893, #12611)
- **Validation Tools**: `scripts/deployment-validation.sh` - Health checks and status verification
- **Maintenance Utilities**: `scripts/cleanup-maintenance.sh` - Container cleanup and system maintenance

### Resource Allocation (hardcoded in stacks.yaml)
- Proxy (100): 2C/2GB/10GB - Reverse proxy and SSL termination
- Media (101): 6C/10GB/20GB - Jellyfin, Sonarr, Radarr media services  
- Files (102): 2C/3GB/15GB - NextCloud file management
- WebTools (103): 2C/6GB/15GB - Portainer, utilities
- Monitoring (104): 4C/6GB/15GB - Prometheus, Grafana, Loki stack
- GameServers (105): 8C/16GB/50GB - Satisfactory, Palworld
- Backup (106): 4C/8GB/50GB - Proxmox Backup Server
- Development (107): 4C/6GB/15GB - VS Code Server, dev tools

## Core Principles (CRITICAL - Follow Exactly)

### **Fail Fast & Simple**
- Ensure idempotency (safe re-deployment)
- Let commands fail naturally with their original error messages
- **NEVER** use `>/dev/null 2>&1` - all output must be visible for debugging
- No retry logic, waiting loops, health checks, or error recovery
- Focus on main scenario - edge cases should fail fast
- Individual Docker service failures logged but don't stop deployment

### **Homelab-First Approach** 
- Static/hardcoded values for network (192.168.1.x), storage (datapool), timezone (Europe/Istanbul)
- LXC resource specifications in stacks.yaml configuration file
- No dynamic discovery or flexible configuration

### **Latest Everything**
- Always use `latest` for Docker images and system packages
- No version pinning allowed

### **Pure Bash Scripting**
- Use only Bash scripting for automation (no Ansible, Terraform, etc.)
- Minimal external dependencies: pct, docker-compose, openssl, jq, curl
- Bash 5.x features available on Debian Trixie

### **PVE-Exclusive Design**
- Code runs exclusively on Proxmox VE (Debian Trixie 13.1)
- Leverage PVE-specific features (pct commands, LXC containers)
- No cross-platform compatibility requirements

## Implementation Guidelines

### Script Structure
- **main-menu.sh**: Interactive menu system using bash `select`
- **deploy-stack.sh**: Core deployment orchestrator with progress output
- **lxc-manager.sh**: Container lifecycle management (create, start, stop, exec)
- **encrypt-env.sh**: Environment file encryption/decryption with OpenSSL
- **monitoring-setup.sh**: Grafana dashboard import via HTTP API

### Error Handling Pattern
```bash
# Standard error handling - fail fast with context
if ! command_that_might_fail; then
    echo "ERROR: Component: Specific failure: Additional context" >&2
    exit 3  # Infrastructure error code
fi

# Idempotency check pattern  
if pct status $VMID >/dev/null 2>&1; then
    echo "Container $VMID exists, skipping creation"
    # Continue with service deployment
else
    pct create $VMID ...
fi
```

### Environment File Management
- .env.enc files encrypted with single password (homelab simplicity)
- Fallback to .env.example on decryption failure (deployment continuity)
- Temporary .env files deleted after use (security)
- Never commit plaintext .env files to git

### Configuration Contracts
- stacks.yaml defines LXC resource allocation
- Grafana dashboard IDs for automatic import (#10347, #893, #12611)
- Docker Compose uses latest tags only
- Network hardcoded to vmbr0 bridge

### Implementation Patterns

#### Script Structure
```bash
#!/bin/bash
# Strict error handling
set -euo pipefail

# Load shared functions
WORK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)"
source "$WORK_DIR/scripts/helper-functions.sh"

# Configuration loading
get_stack_config "$STACK_NAME"  # Sets CT_ID, CT_IP, etc.
```

#### Logging Patterns
```bash
# Use consistent logging from helper-functions.sh
print_info "Starting operation"
print_success "Operation completed"  
print_warning "Non-critical issue"
print_error "Critical failure"
```

#### Validation Patterns
```bash
# Environment validation
./scripts/validate-environment.sh full

# Deployment validation  
./scripts/deployment-validation.sh stack monitoring

# Health checks
./scripts/deployment-validation.sh quick
```

#### Maintenance Operations
```bash
# Container cleanup
./scripts/cleanup-maintenance.sh stack media

# System maintenance
./scripts/cleanup-maintenance.sh maintenance

# Interactive cleanup
./scripts/cleanup-maintenance.sh interactive
```

## Git Guidelines

- **NEVER** use "Generated with [AI Tool]" in commits
- Commit as the actual developer (Yakrel), not as AI
- Check code to not commit secrets or passwords when committing
- .env files must be in .gitignore (only .env.enc and .env.example tracked)