# 🎮 Game Servers Stack Documentation

## Overview

The Game Servers stack provides a dedicated LXC container (ID: 105) for hosting multiple game servers using Docker containers. It includes automatic updates via Watchtower and persistent storage in `/datapool/config/`.

## Supported Games

### 🏗️ Satisfactory Server
- **Docker Image**: `wolveix/satisfactory-server:latest`
- **Ports**: 7777 (game), 15000 (query), 15777 (beacon)
- **Config Location**: `/datapool/config/satisfactory/`
- **Default Settings**: 10 players, private server, password: `homelab123`

### 🌴 Palworld Server
- **Docker Image**: `jammsen/docker-palworld-dedicated-server:latest`
- **Ports**: 8211 (game), 27015 (query)
- **Config Location**: `/datapool/config/palworld/`
- **Default Settings**: 32 players, private server, admin password: `homelab123`

## Deployment Options

### Option 9: Base Stack Only
```bash
# Deploys only Watchtower service for updates
bash installer.sh # Select option 9
```

### Option 10: Satisfactory Server
```bash
# Deploys Watchtower + Satisfactory Server
bash installer.sh # Select option 10
```

### Option 11: Palworld Server
```bash
# Deploys Watchtower + Palworld Server
bash installer.sh # Select option 11
```

## Running Multiple Games

You can run both games simultaneously by deploying them separately:
1. First deploy Satisfactory (option 10)
2. Then deploy Palworld (option 11) - this will add Palworld to the existing stack

## Configuration

### Environment Variables
Copy `.env.example` to `.env` in the LXC container and modify:
```bash
# In LXC 105
cp /root/.env.example /root/.env
nano /root/.env
```

### Server Settings
- **Satisfactory**: Modify environment variables in `satisfactory.yml`
- **Palworld**: Modify environment variables in `palworld.yml`

### Persistent Data
All game data is stored in `/datapool/config/`:
- Satisfactory: `/datapool/config/satisfactory/`
- Palworld: `/datapool/config/palworld/`

## Network Access

### From LAN
- Satisfactory: `192.168.1.105:7777`
- Palworld: `192.168.1.105:8211`

### Port Forwarding (if needed)
Configure your router to forward:
- Satisfactory: TCP/UDP 7777, UDP 15000, UDP 15777
- Palworld: UDP 8211, UDP 27015

## Automatic Updates

Watchtower checks for image updates every hour and automatically:
- Pulls new images
- Recreates containers with new images
- Removes old images
- Maintains zero-downtime where possible

## Troubleshooting

### Check Container Status
```bash
pct exec 105 -- docker ps
pct exec 105 -- docker logs satisfactory-server
pct exec 105 -- docker logs palworld-server
```

### Restart Services
```bash
pct exec 105 -- docker compose restart satisfactory-server
pct exec 105 -- docker compose restart palworld-server
```

### View Game Logs
```bash
pct exec 105 -- docker logs -f satisfactory-server
pct exec 105 -- docker logs -f palworld-server
```

## Resource Requirements

- **CPU**: 8 cores (shared between games)
- **RAM**: 16GB (each game can use 4-8GB)
- **Storage**: 50GB container + persistent volumes
- **Network**: Gigabit recommended for multiplayer