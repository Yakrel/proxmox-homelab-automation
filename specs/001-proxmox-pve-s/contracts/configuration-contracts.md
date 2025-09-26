# Configuration File Contracts

## Configuration Structure Contract

**Purpose**: Define LXC container specifications and service stack configurations
**Note**: The existing stacks.yaml can be redesigned or replaced - this is a flexible design decision.

### Alternative Approaches:
- Keep existing stacks.yaml structure
- Create new configuration format
- Use multiple config files
- Embed configuration in scripts

### Schema Definition
```yaml
# Root configuration structure
stacks:
  <stack_name>:
    vmid: <integer>           # Unique LXC container ID (100-199)
    cores: <integer>          # CPU core allocation (1-32)  
    memory: <integer>         # RAM allocation in MB (512-32768)
    storage: <integer>        # Storage allocation in GB (5-500)
    description: <string>     # Human-readable stack description
    env_required: <boolean>   # Whether .env.enc file is mandatory
    network:                  # Network configuration (optional)
      bridge: <string>        # Default: "vmbr0"
      ip: <string>            # Static IP (optional, DHCP if omitted)
    services:                 # Service-specific overrides (optional)
      <service_name>:
        ports: [<string>]     # Port mappings override
        volumes: [<string>]   # Volume mounts override

# Grafana dashboard configuration  
grafana_dashboards:
  <category>:
    - id: <integer>           # Grafana.com dashboard ID
      title: <string>         # Dashboard display name
      datasource: <string>    # Target Prometheus datasource name

# Global settings
settings:
  default_template: <string>  # Default LXC template (debian-12-standard)
  storage_pool: <string>     # ZFS storage pool name (datapool)
  network_bridge: <string>   # Default network bridge (vmbr0)  
  timezone: <string>         # Container timezone (Europe/Istanbul)
```

### Validation Rules
```yaml
# VMID constraints
vmid:
  type: integer
  minimum: 100
  maximum: 199
  unique: true

# Resource constraints  
cores:
  type: integer
  minimum: 1
  maximum: 32

memory:
  type: integer
  minimum: 512
  maximum: 32768
  
storage:
  type: integer
  minimum: 5
  maximum: 500

# String constraints
stack_name:
  type: string
  pattern: "^[a-z][a-z0-9-]*$"  # lowercase, alphanumeric, hyphens
  maxLength: 20

description:
  type: string
  maxLength: 100
```

### Example Configuration
```yaml
stacks:
  proxy:
    vmid: 100
    cores: 2
    memory: 2048  
    storage: 10
    description: "Reverse proxy and SSL termination"
    env_required: true
    services:
      traefik:
        ports: ["80:80", "443:443", "8080:8080"]
        
  media:
    vmid: 101
    cores: 6
    memory: 10240
    storage: 20  
    description: "Media server stack (Jellyfin, Sonarr, Radarr)"
    env_required: true
    network:
      ip: "192.168.1.101"

  monitoring:
    vmid: 104
    cores: 4
    memory: 6144
    storage: 15
    description: "Prometheus, Grafana, Loki monitoring stack"  
    env_required: false

grafana_dashboards:
  system:
    - id: 1860
      title: "Node Exporter Full"
      datasource: "prometheus"
    - id: 3662  
      title: "Prometheus 2.0 Overview"
      datasource: "prometheus"
  docker:
    - id: 893
      title: "Docker and System Monitoring" 
      datasource: "prometheus"
  proxmox:
    - id: 10347
      title: "Proxmox VE"
      datasource: "prometheus"

settings:
  default_template: "debian-12-standard"
  storage_pool: "datapool"
  network_bridge: "vmbr0"
  timezone: "Europe/Istanbul"
```

## .env.example Template Contract

**Purpose**: Provide fallback environment configuration with placeholder values

### Structure Requirements
```bash
# Service-specific environment variables
# Format: UPPER_CASE with descriptive comments

# Database configuration
DB_HOST=localhost
DB_PORT=5432
DB_NAME=homelab_db
DB_USER=homelab_user
DB_PASS=changeme_database_password

# Authentication secrets  
JWT_SECRET=changeme_jwt_secret_key
API_KEY=changeme_api_key

# External service URLs
EXTERNAL_URL=https://your-domain.com
GRAFANA_URL=http://monitoring:3000

# User/Group IDs for file permissions
PUID=1000
PGID=1000

# Timezone setting
TZ=Europe/Istanbul

# Stack-specific variables (examples)
# Jellyfin media server
JELLYFIN_CACHE_DIR=/config/cache
JELLYFIN_CONFIG_DIR=/config

# Sonarr/Radarr media management  
MEDIA_ROOT=/media
DOWNLOADS_DIR=/downloads

# Traefik proxy configuration
TRAEFIK_DOMAIN=local.example.com
ACME_EMAIL=admin@example.com
```

### Placeholder Conventions
- Passwords: `changeme_<purpose>_password`
- URLs: `https://your-domain.com` or `http://service:port`  
- Paths: `/path/to/directory` (standard container paths)
- Secrets: `changeme_<type>_secret`
- Email: `admin@example.com`

### Security Requirements
- No actual passwords or secrets
- All values must be obviously placeholder
- Include comments explaining each variable purpose
- Group related variables with blank lines

## Docker Compose Integration Contract

**Purpose**: Define how .env files integrate with docker-compose.yml files

### Environment Variable Usage
```yaml
# docker-compose.yml structure expectations
version: '3.8'

services:
  service_name:
    image: image:latest           # Always use :latest (Constitution III)
    environment:
      - VAR_NAME=${VAR_NAME}     # Direct substitution from .env
      - PUID=${PUID:-1000}       # Default value if not set
      - TZ=${TZ:-Europe/Istanbul} # Hardcoded default (Constitution II)
    volumes:
      - ${CONFIG_DIR:-/config}:/config  # Path substitution
    ports:
      - "${PORT:-8080}:8080"     # Port mapping from .env
```

### Required Variables Per Stack
```bash
# Proxy stack requirements
TRAEFIK_DOMAIN=
ACME_EMAIL=  
BASIC_AUTH_USER=
BASIC_AUTH_PASS=

# Media stack requirements
PUID=
PGID=
TZ=
MEDIA_ROOT=
DOWNLOADS_DIR=

# Monitoring stack requirements  
GRAFANA_ADMIN_PASS=
PROMETHEUS_RETENTION=
LOKI_RETENTION=

# Files stack requirements
NEXTCLOUD_ADMIN_USER=
NEXTCLOUD_ADMIN_PASS=  
NEXTCLOUD_DOMAIN=
```

### Integration Behavior
- Missing variables use defaults from .env.example
- Docker Compose validates required variables before startup
- Fail fast if critical variables missing (no defaults possible)
- Log warnings for missing optional variables