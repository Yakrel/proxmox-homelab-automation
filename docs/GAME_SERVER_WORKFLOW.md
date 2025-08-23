# Game Server Management Workflow

This document explains the improved game server management workflow that addresses the issue of running multiple games and Watchtower conflicts.

## Architecture Overview

### Base Stack Architecture
The game servers use a **two-tier architecture**:

1. **Base Stack** (`docker-compose.yml`):
   - Contains only Watchtower and the shared network (`gameserver-net`)
   - Runs persistently and manages automatic updates
   - Creates the Docker network that game servers connect to

2. **Game-Specific Stacks** (e.g., `satisfactory.yml`, `palworld.yml`):
   - Contains only the game server service
   - Connects to the external network created by base stack
   - Can be started/stopped independently without affecting Watchtower

## Deployment Workflow

### Step 1: Deploy Base Infrastructure
```bash
# From the installer menu, choose option 9: Game Server Management
# Then choose option 1: Deploy Base Stack (LXC + Watchtower)
```

This will:
- Create LXC container 105 (`lxc-gameservers-01`) with 8 CPU cores, 16GB RAM, 50GB disk
- Install Docker and required dependencies
- Deploy the base stack with Watchtower and shared network
- Create persistent storage directories in `/datapool/config/`

### Step 2: Choose Your Game Server
After the base stack is deployed, you can deploy individual game servers:

```bash
# Option 2: Deploy Satisfactory Server
# Option 3: Deploy Palworld Server
```

## Game Management Features

### Individual Game Control
- **Deploy**: Start a specific game server
- **Switch**: Stop current game and start another (Option 5)
- **Stop All**: Stop all game servers but keep Watchtower running (Option 4)

### Automatic Game Switching
The system automatically:
1. Ensures the base stack (Watchtower + network) is running
2. Stops any currently running games before starting a new one
3. Prevents port conflicts and resource competition

### Example Workflows

#### Switch from Satisfactory to Palworld
```bash
# Method 1: Using Switch Menu (Option 5)
Game Server Management > Switch Game > Stop all games, start Palworld

# Method 2: Manual
Game Server Management > Stop All Game Servers
Game Server Management > Deploy Palworld Server
```

#### Run Only Watchtower (No Games)
```bash
Game Server Management > Stop All Game Servers
# Watchtower continues running for automatic updates
```

## Technical Details

### Docker Compose Files Structure
```
docker/gameservers/
├── docker-compose.yml     # Base: Watchtower + Network
├── satisfactory.yml       # Game: Satisfactory only
├── palworld.yml          # Game: Palworld only
├── .env.j2               # Environment template
└── .env.example          # Configuration example
```

### Network Configuration
- **Base Stack**: Creates `gameserver-net` bridge network
- **Game Stacks**: Connect to existing `gameserver-net` (external: true)
- **No Conflicts**: Only one Watchtower instance across all stacks

### Port Mappings
- **Satisfactory**: 7777 (UDP/TCP), 15000 (UDP), 15777 (UDP)
- **Palworld**: 8211 (UDP), 27015 (UDP)
- **Access**: `192.168.1.105:<PORT>` from LAN

## Benefits of This Architecture

1. **No Watchtower Conflicts**: Single Watchtower instance manages all containers
2. **Independent Game Management**: Start/stop games without affecting others
3. **Easy Game Switching**: Built-in workflow to switch between games
4. **Resource Efficiency**: Only run the games you're actively using
5. **Persistent Updates**: Watchtower continues running even when games are stopped
6. **Clean Separation**: Base infrastructure vs game-specific deployments

## Menu Navigation

```
Main Menu
└── 9) Game Server Management
    ├── 1) Deploy Base Stack (LXC + Watchtower)
    ├── 2) Deploy Satisfactory Server  
    ├── 3) Deploy Palworld Server
    ├── 4) Stop All Game Servers
    ├── 5) Switch Game (Stop Current, Start Another)
    │   ├── 1) Stop all games, start Satisfactory
    │   ├── 2) Stop all games, start Palworld
    │   └── 3) Just stop all games
    └── B) Back to Main Menu
```

This workflow addresses the original concerns about:
- ✅ Watchtower duplication and conflicts
- ✅ Running multiple games simultaneously 
- ✅ Easy game switching capabilities
- ✅ Clean separation of base infrastructure and games
- ✅ Efficient resource usage (run only what you need)