# Data Model: Proxmox PVE Zero-to-Production Automation

**Date**: 2025-09-26  
**Feature**: 001-proxmox-pve-s

## Core Entities

### ServiceStack
Represents a logical grouping of containerized services with deployment specifications.

**Attributes**:
- `name`: String - Stack identifier (proxy, media, monitoring, etc.)
- `vmid`: Integer - Proxmox LXC container ID (100-107 range)
- `description`: String - Human-readable stack purpose
- `cores`: Integer - CPU core allocation
- `memory`: Integer - RAM allocation in MB  
- `storage`: Integer - Disk storage allocation in GB
- `network`: String - Network configuration (hardcoded to vmbr0)
- `env_required`: Boolean - Whether .env.enc file is mandatory

**Relationships**:
- Contains multiple DockerService entities
- References single LXCContainer
- May have associated EnvironmentConfig

**Lifecycle States**:
1. `defined` - Stack configuration loaded from stacks.yaml
2. `container_creating` - LXC container being created
3. `container_ready` - LXC container operational
4. `services_deploying` - Docker services being deployed
5. `operational` - All services running successfully
6. `failed` - Deployment error occurred

### LXCContainer  
Represents Proxmox LXC container hosting service stack.

**Attributes**:
- `vmid`: Integer - Unique container identifier
- `hostname`: String - Container network name
- `template`: String - Base container template (debian-12-standard)
- `cores`: Integer - Allocated CPU cores
- `memory`: Integer - Allocated RAM in MB
- `rootfs`: String - Root filesystem specification
- `network`: String - Network interface configuration
- `startup`: String - Auto-start configuration
- `timezone`: String - Container timezone (hardcoded Europe/Istanbul)

**Identity Rules**:
- `vmid` must be unique across PVE cluster
- `hostname` derived from stack name
- Resource allocation cannot exceed host capacity

**State Transitions**:
- `stopped` → `starting` → `running` → `stopped`
- `nonexistent` → `creating` → `stopped`

### EnvironmentConfig
Represents encrypted environment configuration for service stacks.

**Attributes**:
- `stack_name`: String - Associated service stack
- `encrypted_file`: String - Path to .env.enc file
- `decrypted_file`: String - Path to temporary .env file  
- `fallback_file`: String - Path to .env.example template
- `encryption_method`: String - Always "aes-256-cbc"
- `requires_password`: Boolean - Always true for .env.enc files

**Security Rules**:
- Decrypted files never committed to version control
- Temporary .env files deleted after deployment
- Fallback to .env.example on decryption failure
- Single password used for all stacks (homelab simplicity)

**Lifecycle**:
1. `encrypted` - Only .env.enc exists
2. `decrypting` - Password provided, decryption in progress
3. `decrypted` - Plain .env available for use
4. `fallback` - Using .env.example due to decryption failure
5. `cleanup` - Temporary files removed

### DockerService
Represents individual containerized service within a stack.

**Attributes**:
- `name`: String - Service name from docker-compose.yml
- `image`: String - Docker image specification (always :latest)
- `stack`: String - Parent service stack name
- `ports`: Array[String] - Exposed port mappings
- `volumes`: Array[String] - Volume mount specifications
- `environment`: Array[String] - Environment variables
- `restart_policy`: String - Container restart behavior

**Dependencies**:
- Requires LXCContainer to be running
- Requires EnvironmentConfig to be available
- May depend on other DockerService instances

**Operational States**:
- `defined` - Service configuration loaded
- `starting` - Container being created/started
- `running` - Service operational and healthy
- `failed` - Service failed to start or crashed
- `stopped` - Service intentionally stopped

### GrafanaDashboard
Represents monitoring dashboard configuration.

**Attributes**:
- `dashboard_id`: Integer - Grafana community dashboard ID
- `title`: String - Dashboard display name
- `datasource`: String - Associated Prometheus datasource
- `category`: String - Dashboard grouping (system, docker, proxmox)
- `import_url`: String - Grafana.com JSON export URL

**Import Process**:
1. `pending` - Dashboard ID queued for import
2. `downloading` - Fetching JSON from Grafana community
3. `importing` - Posting to local Grafana instance  
4. `imported` - Successfully available in Grafana
5. `failed` - Import process failed

## Data Relationships

```
ServiceStack (1) ←→ (1) LXCContainer
ServiceStack (1) ←→ (0..1) EnvironmentConfig  
ServiceStack (1) ←→ (*) DockerService
ServiceStack (monitoring) ←→ (*) GrafanaDashboard
```

## Configuration Schema (Example)

**Note**: Current stacks.yaml is not mandatory - configuration structure can be redesigned as needed for this implementation.

```yaml
stacks:
  proxy:
    vmid: 100
    cores: 2
    memory: 2048
    storage: 10
    description: "Reverse proxy and SSL termination"
    env_required: true
  media:
    vmid: 101
    cores: 6  
    memory: 10240
    storage: 20
    description: "Media server stack (Jellyfin, Sonarr, Radarr)"
    env_required: true
    
grafana_dashboards:
  system:
    - id: 1860
      title: "Node Exporter Full" 
    - id: 3662
      title: "Prometheus 2.0 Overview"
  docker:
    - id: 893
      title: "Docker and System Monitoring"
```

## Data Validation Rules

### ServiceStack Validation
- `vmid` must be in range 100-199
- `cores` must be > 0 and ≤ host CPU count
- `memory` must be ≥ 512MB and ≤ host RAM
- `storage` must be ≥ 5GB for minimal operation

### LXCContainer Validation  
- Template must exist in PVE storage
- Network interface vmbr0 must exist
- Datapool storage must be available
- Container name must be valid hostname

### EnvironmentConfig Validation
- .env.enc file must exist for stacks with env_required=true
- .env.example must exist as fallback
- Decrypted .env must not be tracked in git

## Error Handling Strategy

**Principle**: Fail fast with clear error messages (Constitution I)

### Container Creation Failures
- Missing template → ERROR: "Template debian-12-standard not found"
- Insufficient resources → ERROR: "Not enough CPU/RAM available"  
- VMID conflict → ERROR: "Container ID already exists"

### Service Deployment Failures  
- Individual service failures logged but don't stop deployment
- Docker Compose errors passed through unchanged
- Missing environment variables → Use defaults from .env.example

### Configuration Failures
- Missing stacks.yaml → ERROR: "Configuration file required"
- Invalid YAML syntax → ERROR with line number
- Missing storage pool → ERROR: "Datapool ZFS not found"