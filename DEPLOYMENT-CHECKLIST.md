# Deployment Verification Checklist
# =================================
# Complete validation guide for Proxmox PVE homelab automation deployments
# Use this checklist to verify successful deployment and troubleshoot issues

## Pre-Deployment Environment Checks

### Proxmox VE Host Requirements
- [ ] **Proxmox VE 8.x** installed and running
- [ ] **Root access** available via SSH or console
- [ ] **Network bridge `vmbr0`** configured and active
- [ ] **Gateway `192.168.1.1`** reachable from host
- [ ] **Storage pool `datapool`** exists and is active
- [ ] **Minimum 4GB RAM** available on host
- [ ] **Minimum 2 CPU cores** available on host
- [ ] **Minimum 50GB free** space on datapool

### Host Validation Commands
```bash
# Validate environment prerequisites
./scripts/validate-environment.sh full

# Quick environment check
./scripts/validate-environment.sh quick

# Individual component checks
./scripts/validate-environment.sh storage
./scripts/validate-environment.sh network
```

### Required Tools Available
- [ ] **pct** command available (`which pct`)
- [ ] **pvesm** command available (`which pvesm`) 
- [ ] **curl** available for downloads (`which curl`)
- [ ] **openssl** available for encryption (`which openssl`)

## Deployment Process Validation

### Initial Setup
- [ ] **Repository cloned** to `/root/proxmox-homelab-automation`
- [ ] **Scripts executable** (`chmod +x scripts/*.sh`)
- [ ] **stacks.yaml** present and valid
- [ ] **Environment files** encrypted (`.env.enc` files exist)

### Stack Deployment Steps
- [ ] **Stack selected** from main menu
- [ ] **Encryption password** provided successfully
- [ ] **LXC container created** without errors
- [ ] **Container started** and responding to ping
- [ ] **Services deployed** within container
- [ ] **Health checks passed** for deployed services

### Deployment Validation Commands
```bash
# Validate specific stack deployment
./scripts/deployment-validation.sh stack <stack-name>

# Validate all deployed stacks
./scripts/deployment-validation.sh all

# Quick health check
./scripts/deployment-validation.sh quick
```

## Post-Deployment Validation

### Container-Level Checks
For each deployed stack, verify:

- [ ] **Container Status**: `pct status <ct-id>` shows "running"
- [ ] **Network Connectivity**: `ping <ct-ip>` responds successfully  
- [ ] **Storage Mount**: Datapool mounted at `/datapool` in container
- [ ] **Service Processes**: Expected services running inside container
- [ ] **Resource Usage**: CPU and memory usage within expected ranges

### Stack-Specific Validation

#### Proxy Stack (CT 100)
- [ ] **Container IP**: `192.168.1.100` responding
- [ ] **Cloudflared**: Tunnel active (if configured)
- [ ] **Watchtower**: Container update service running
- [ ] **Promtail**: Log shipping to monitoring stack

#### Media Stack (CT 101) 
- [ ] **Container IP**: `192.168.1.101` responding
- [ ] **Jellyfin**: Web interface at `http://192.168.1.101:8096`
- [ ] **Sonarr**: Web interface at `http://192.168.1.101:8989`
- [ ] **Radarr**: Web interface at `http://192.168.1.101:7878`
- [ ] **Transmission**: Web interface at `http://192.168.1.101:9091`

#### Files Stack (CT 102)
- [ ] **Container IP**: `192.168.1.102` responding
- [ ] **Filebrowser**: Web interface at `http://192.168.1.102:8080`
- [ ] **Nextcloud**: Web interface at `http://192.168.1.102:8000`

#### Webtools Stack (CT 103)
- [ ] **Container IP**: `192.168.1.103` responding  
- [ ] **Homepage**: Dashboard at `http://192.168.1.103:3000`
- [ ] **Portainer**: Container management at `http://192.168.1.103:9000`

#### Monitoring Stack (CT 104)
- [ ] **Container IP**: `192.168.1.104` responding
- [ ] **Grafana**: Dashboard at `http://192.168.1.104:3000`
  - [ ] Admin login working with configured password
  - [ ] Prometheus datasource configured and working
  - [ ] Loki datasource configured and working  
  - [ ] Dashboard #10347 (Proxmox) imported successfully
  - [ ] Dashboard #893 (Docker) imported successfully
  - [ ] Dashboard #12611 (Loki) imported successfully
- [ ] **Prometheus**: Metrics at `http://192.168.1.104:9090`
  - [ ] PVE exporter targets up and collecting data
  - [ ] Docker metrics from all containers collecting
- [ ] **Loki**: Log aggregation at `http://192.168.1.104:3100`
  - [ ] Logs from all containers being collected

#### Gameservers Stack (CT 105)
- [ ] **Container IP**: `192.168.1.105` responding
- [ ] **Game Services**: Selected games running and accessible
- [ ] **Resource Usage**: High CPU/memory usage expected and acceptable

#### Backup Stack (CT 106) 
- [ ] **Container IP**: `192.168.1.106` responding
- [ ] **PBS Interface**: Web interface at `https://192.168.1.106:8007`  
- [ ] **Datastore**: Backup datastore configured and accessible
- [ ] **PVE Integration**: Backup storage configured in Proxmox host
- [ ] **Backup Jobs**: Scheduled backup jobs created (if configured)

#### Development Stack (CT 107)
- [ ] **Container IP**: `192.168.1.107` responding
- [ ] **Node.js**: Latest version installed and working
- [ ] **AI CLI Tools**: Claude/Gemini CLI tools installed
- [ ] **Development Tools**: Git, editors, and utilities available

### Network Connectivity Matrix
Verify network connectivity between components:

- [ ] **Host → All Containers**: Can ping all deployed container IPs
- [ ] **Container → Gateway**: Each container can reach `192.168.1.1`
- [ ] **Container → Internet**: Each container has internet access
- [ ] **Container → Container**: Inter-container communication working
- [ ] **Monitoring → Targets**: Prometheus can scrape all configured targets

## Performance Benchmarks

### Expected Resource Usage
| Stack | CPU Cores | Memory | Disk | Network |
|-------|-----------|--------|------|---------|
| proxy | 1-2 cores | 1-2GB | <5GB | Low |
| media | 2-4 cores | 4-8GB | 10-15GB | Medium-High |
| files | 1-2 cores | 2-3GB | 5-10GB | Medium |
| webtools | 1-2 cores | 3-5GB | 5-10GB | Low |
| monitoring | 2-3 cores | 4-6GB | 10-15GB | Medium |
| gameservers | 4-8 cores | 8-16GB | 20-40GB | High |
| backup | 2-4 cores | 4-8GB | Variable | Medium |
| development | 2-4 cores | 3-6GB | 5-10GB | Low |

### Response Time Expectations
- [ ] **Web Interfaces**: Load within 3 seconds
- [ ] **API Endpoints**: Respond within 1 second
- [ ] **Container Startup**: Ready within 30 seconds
- [ ] **Service Startup**: Functional within 60 seconds

## Troubleshooting Guide

### Common Issues and Solutions

#### Container Creation Failures
```bash
# Check storage availability
pvesm status

# Check network configuration  
ip link show vmbr0

# Validate template availability
pveam available | grep alpine
```

#### Network Connectivity Issues
```bash
# Test container network
pct exec <ct-id> -- ping 8.8.8.8

# Check bridge configuration
brctl show vmbr0

# Verify routing
ip route show
```

#### Service Startup Failures
```bash
# Check container logs
pct exec <ct-id> -- journalctl -u docker
pct exec <ct-id> -- docker-compose logs

# Check resource usage
pct exec <ct-id> -- top
pct exec <ct-id> -- df -h
```

#### Monitoring Issues
```bash
# Verify Grafana configuration
curl -s http://192.168.1.104:3000/api/health

# Check Prometheus targets
curl -s http://192.168.1.104:9090/api/v1/targets

# Validate dashboard imports
curl -s http://192.168.1.104:3000/api/search
```

### Log Locations
- **Host Logs**: `/var/log/pve/` and `journalctl`
- **Container Logs**: `pct exec <id> -- journalctl`
- **Docker Logs**: `pct exec <id> -- docker-compose logs`
- **Service Logs**: Container-specific locations

### Support Commands
```bash
# Complete system validation
./scripts/deployment-validation.sh all

# Environment health check
./scripts/validate-environment.sh full

# Quick stack status
./scripts/deployment-validation.sh quick

# Manual container inspection
pct list
pct status <ct-id>
pct exec <ct-id> -- systemctl status
```

## Success Criteria

### Deployment Considered Successful When:
- [ ] **All containers running** and responding to network pings
- [ ] **All web interfaces accessible** without errors  
- [ ] **Monitoring dashboards populated** with data from all stacks
- [ ] **Log aggregation working** with logs from all containers
- [ ] **No critical errors** in any container or service logs
- [ ] **Resource usage within limits** across all containers
- [ ] **Backup integration functional** (if backup stack deployed)

### Maintenance Readiness:
- [ ] **Cleanup scripts working** for container management
- [ ] **Validation scripts functional** for health checking
- [ ] **Monitoring alerts configured** for system health
- [ ] **Documentation updated** with deployment specifics
- [ ] **Recovery procedures tested** for critical services

---

**Deployment Date**: ___________  
**Validated By**: ___________  
**Environment**: Proxmox VE ___ on ___________  
**Deployed Stacks**: ___________  

**Notes**: 
_Use this space to record any deployment-specific configuration, known issues, or special considerations for this environment._