# Playground Stack

GPU-enabled test environment for development and testing GPU workloads.

## Overview

LXC 108 (`lxc-playground-01`) provides a Debian-based testing environment with:
- **NVIDIA GTX 970 GPU passthrough** - Full GPU acceleration support
- **Docker + docker-compose** - Container runtime for testing containerized GPU workloads
- **Claude Code CLI** - AI assistant for development tasks
- **Manual configuration** - No automated docker-compose deployment

## Purpose

This stack is designed for:
- GPU passthrough testing and validation
- Chrome GPU acceleration testing
- General development and experimentation
- Repository development and testing new features

## Configuration

### Resources
- **CPU**: 6 cores
- **Memory**: 6 GB
- **Disk**: 30 GB
- **Network**: 192.168.1.108
- **GPU**: NVIDIA GTX 970 (passthrough configured)

### Installed Software
- Debian Trixie (latest)
- Docker CE + docker-compose plugin
- NVIDIA drivers + container toolkit
- Node.js + npm
- Claude Code CLI (`@anthropic-ai/claude-code`)

## Usage

Unlike other stacks, this environment does **not** automatically deploy docker-compose services.

### Manual Setup Required
1. Create your own `docker-compose.yml` files for testing
2. Configure services as needed
3. Test GPU workloads manually

### GPU Testing
The NVIDIA GPU is already configured with:
- Device passthrough (`/dev/nvidia*`)
- NVIDIA container toolkit
- Docker runtime configured for GPU support

To use GPU in a container, add to your docker-compose.yml:
```yaml
services:
  your-service:
    runtime: nvidia
    environment:
      - NVIDIA_VISIBLE_DEVICES=all
      - NVIDIA_DRIVER_CAPABILITIES=all
```

Or using docker-compose v2 syntax:
```yaml
services:
  your-service:
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]
```

## Access

Console access via Proxmox VE:
```bash
pct enter 108
```

Or from Proxmox host:
```bash
pct exec 108 -- bash
```

## Notes

- No `.env` file encryption/decryption - configure manually as needed
- No Promtail logging - add manually if needed
- This is a test environment - breaking changes are expected
