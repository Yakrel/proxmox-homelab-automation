# Script Interface Contracts

## main-menu.sh

**Purpose**: Interactive menu system for service stack selection and deployment

### Input Contract
```bash
# No command line arguments required
# Interactive user input via bash select
./scripts/main-menu.sh
```

### Output Contract
```bash
# Success: Exit code 0
# User cancellation: Exit code 1
# Error: Exit code >1 with stderr message

# Interactive menu display:
"Select service stack to deploy:"
"1) Proxy Stack (Traefik, Nginx)"
"2) Media Stack (Jellyfin, Sonarr, Radarr)" 
"3) Monitoring Stack (Prometheus, Grafana)"
"4) Files Stack (NextCloud, FTP)"
"5) WebTools Stack (Portainer, Heimdall)"
"6) GameServers Stack (Satisfactory, Palworld)"
"7) Backup Stack (Proxmox Backup Server)"
"8) Development Stack (VS Code Server, Git)"
"9) Exit"
```

### Error Conditions
- Invalid selection → Re-prompt user
- Deployment failure → Display error and return to menu
- Ctrl+C → Graceful exit with cleanup

## deploy-stack.sh

**Purpose**: Core orchestrator for individual stack deployment

### Input Contract
```bash
./scripts/deploy-stack.sh <stack_name> [--force] [--dry-run]

# Required:
# <stack_name>: One of [proxy, media, monitoring, files, webtools, gameservers, backup, development]

# Optional flags:
# --force: Skip idempotency checks, force redeploy
# --dry-run: Show deployment steps without executing
```

### Output Contract  
```bash
# Success: Exit code 0
echo "Stack '$stack_name' deployed successfully"

# Failure: Exit code >0  
echo "ERROR: Stack deployment failed: <reason>" >&2

# Progress output during deployment:
echo "Step 1/5: Loading configuration..."
echo "Step 2/5: Creating LXC container..."  
echo "Step 3/5: Decrypting environment..."
echo "Step 4/5: Deploying Docker services..."
echo "Step 5/5: Configuring monitoring..."
```

### Error Conditions
- Unknown stack name → Exit 1: "Unknown stack: $stack_name"
- Missing stacks.yaml → Exit 2: "Configuration file not found"  
- Container creation failure → Exit 3: "LXC creation failed"
- Environment decryption failure → Continue with .env.example
- Docker service failure → Log error, continue deployment

## lxc-manager.sh

**Purpose**: LXC container lifecycle management

### Input Contract
```bash
./scripts/lxc-manager.sh <action> <vmid> [options]

# Actions: create, start, stop, destroy, exec
# <vmid>: Integer container ID (100-199)

# Create options:
# --cores <n>: CPU core count
# --memory <mb>: RAM allocation  
# --storage <gb>: Disk storage
# --hostname <name>: Container hostname

# Exec options:
# --command <cmd>: Command to execute inside container
```

### Output Contract
```bash
# Success: Exit code 0
echo "LXC action completed: $action for container $vmid"

# Container status output:
echo "Container $vmid: running" | "stopped" | "nonexistent"

# Failure: Exit code >0
echo "ERROR: LXC $action failed for container $vmid: <pct_error>" >&2
```

### Idempotency Rules
- Create existing container → Skip, return success
- Start running container → Skip, return success  
- Stop stopped container → Skip, return success
- Destroy nonexistent container → Skip, return success

## encrypt-env.sh

**Purpose**: Environment file encryption and decryption management

### Input Contract  
```bash
./scripts/encrypt-env.sh <action> <stack_name> [password]

# Actions: encrypt, decrypt, validate
# <stack_name>: Service stack identifier
# [password]: Encryption password (prompt if not provided)

# File locations (hardcoded):
# Encrypted: .env/<stack_name>/.env.enc
# Decrypted: .env/<stack_name>/.env (temporary)
# Fallback: .env/<stack_name>/.env.example
```

### Output Contract
```bash
# Success: Exit code 0
echo "Environment $action completed for $stack_name"

# Decrypt success:  
echo "Decrypted .env file available at: $env_path"

# Decrypt failure (fallback):
echo "WARN: Decryption failed, using .env.example fallback"

# Failure: Exit code >0
echo "ERROR: Environment $action failed: <openssl_error>" >&2
```

### Security Requirements
- Temporary .env files deleted after use
- No plaintext passwords in logs or output
- .env files never committed to git (gitignore enforced)
- Fallback to .env.example on any decryption error

## monitoring-setup.sh

**Purpose**: Grafana dashboard and Prometheus configuration automation

### Input Contract
```bash
./scripts/monitoring-setup.sh <action> [options]

# Actions: setup-grafana, import-dashboards, configure-prometheus
# Options:
# --grafana-url <url>: Grafana instance URL (default: http://localhost:3000)  
# --api-key <key>: Grafana API key for authentication
# --dashboard-ids <id1,id2>: Comma-separated dashboard IDs to import
```

### Output Contract
```bash
# Success: Exit code 0
echo "Monitoring setup completed: $action"

# Dashboard import progress:
echo "Importing dashboard ID 1860: Node Exporter Full... ✓"
echo "Importing dashboard ID 893: Docker Monitoring... ✓"
echo "Configured Prometheus datasource: http://prometheus:9090"

# Failure: Exit code >0
echo "ERROR: Monitoring setup failed: <reason>" >&2
```

### Integration Requirements
- Grafana instance must be running and accessible
- Prometheus must be configured and running
- Dashboard IDs must exist in Grafana community
- API authentication must be configured

## Interface Consistency Rules

### Standard Exit Codes
- 0: Success
- 1: User error (invalid arguments, user cancellation)
- 2: Configuration error (missing files, invalid config)
- 3: Infrastructure error (LXC, Docker, network failure)
- 4: Authentication error (encryption, API access)

### Output Format Standards
- Progress messages to stdout
- Error messages to stderr  
- Structured logs: "TIMESTAMP [LEVEL] MESSAGE"
- No colored output (may redirect to files)

### Error Message Format
```bash
echo "ERROR: <component>: <specific_error>: <context>" >&2
# Examples:
echo "ERROR: LXC: Container creation failed: vmid 100 already exists" >&2
echo "ERROR: Docker: Service startup failed: media-jellyfin port conflict" >&2
echo "ERROR: Encryption: Decryption failed: invalid password provided" >&2
```