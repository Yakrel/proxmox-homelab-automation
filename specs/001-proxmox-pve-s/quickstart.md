# Quickstart Guide: Proxmox PVE Zero-to-Production Automation

**Version**: 1.0.0 | **Date**: 2025-09-26  
**Target**: Proxmox VE (Debian Trixie 13.1) homelab environments

## Prerequisites

### Hardware/Infrastructure
- [ ] Proxmox VE 8.x installed and running
- [ ] Minimum 32GB RAM, 8 CPU cores available
- [ ] ZFS storage pool named `datapool` created and mounted
- [ ] Network bridge `vmbr0` configured with internet access
- [ ] SSH access to PVE host as root

### Required Software (Pre-installed on Debian Trixie)
- [ ] `bash` 5.x
- [ ] `pct` (Proxmox Container Toolkit)  
- [ ] `docker` and `docker-compose`
- [ ] `openssl` for encryption
- [ ] `jq` for JSON parsing
- [ ] `curl` for API calls

### Configuration Files
- [ ] LXC template available: `debian-12-standard` 
- [ ] DNS resolution working (for downloading containers/images)
- [ ] Encryption password prepared for .env.enc files

## Installation

### 1. Clone Repository
```bash
cd /root
git clone https://github.com/Yakrel/proxmox-homelab-automation.git
cd proxmox-homelab-automation
```

### 2. Verify Environment
```bash
# Check ZFS pool exists
zpool status datapool

# Check network bridge
ip link show vmbr0  

# Check PVE container functionality
pct list

# Check Docker is available
docker --version
docker-compose --version
```

### 3. Configure Stack Specifications
```bash
# Verify stacks.yaml exists and is valid
cat stacks.yaml

# Validate YAML syntax
python3 -c "import yaml; yaml.safe_load(open('stacks.yaml'))"
```

### 4. Prepare Environment Files
```bash
# Create .env.enc files from examples (optional)
# Each stack directory should contain either:
# - .env.enc (encrypted, preferred)  
# - .env.example (fallback template)

# Example: Create encrypted environment for proxy stack
cd docker/proxy/
cp .env.example .env
# Edit .env with actual values
../../../scripts/encrypt-env.sh encrypt proxy
rm .env  # Remove plaintext version
cd ../../..
```

## First Deployment

### Interactive Menu Method (Recommended)
```bash
# Launch interactive deployment system
bash scripts/main-menu.sh

# Follow prompts:
# 1. Select service stack from menu
# 2. Provide encryption password when requested  
# 3. Monitor deployment progress
# 4. Verify services are running
```

### Direct Deployment Method
```bash
# Deploy specific stack directly
bash scripts/deploy-stack.sh monitoring

# Deploy with options
bash scripts/deploy-stack.sh proxy --dry-run   # Preview only
bash scripts/deploy-stack.sh media --force     # Force redeploy
```

### Verify Deployment
```bash
# Check LXC containers created
pct list | grep -E "(100|101|104)"

# Check containers are running
pct status 100  # Proxy
pct status 101  # Media  
pct status 104  # Monitoring

# Check Docker services inside containers
pct exec 104 -- docker-compose -f /opt/monitoring/docker-compose.yml ps
```

## Service Stack Overview

| Stack | VMID | Purpose | Default Access |
|-------|------|---------|----------------|
| **Proxy** | 100 | Reverse proxy, SSL termination | http://192.168.1.100 |
| **Media** | 101 | Jellyfin, Sonarr, Radarr | http://192.168.1.101:8096 |
| **Monitoring** | 104 | Prometheus, Grafana, Loki | http://192.168.1.104:3000 |
| **Files** | 102 | NextCloud, file management | http://192.168.1.102:8080 |
| **WebTools** | 103 | Portainer, utilities | http://192.168.1.103:9000 |
| **GameServers** | 105 | Satisfactory, Palworld | Game-specific ports |
| **Backup** | 106 | Proxmox Backup Server | https://192.168.1.106:8007 |
| **Development** | 107 | VS Code Server, dev tools | http://192.168.1.107:8443 |

## Common Operations

### Re-deploy Existing Stack
```bash
# Safe re-deployment (idempotent)
bash scripts/deploy-stack.sh monitoring

# The system will:
# 1. Skip LXC creation if container exists
# 2. Update Docker services  
# 3. Refresh configurations
# 4. Continue with any failed services
```

### Update Service Configurations
```bash
# 1. Modify docker-compose.yml or .env files
# 2. Re-deploy the stack
bash scripts/deploy-stack.sh <stack_name>

# 3. Services will be updated automatically
```

### Add New Dashboard to Monitoring
```bash
# 1. Add dashboard ID to stacks.yaml under grafana_dashboards
# 2. Re-deploy monitoring stack
bash scripts/deploy-stack.sh monitoring

# Dashboards will be imported automatically
```

### Backup/Restore Environment Files
```bash
# Backup encrypted environments  
tar czf homelab-env-backup.tar.gz docker/*/.env.enc

# Restore encrypted environments
tar xzf homelab-env-backup.tar.gz
```

## Troubleshooting

### Container Creation Failures
```bash
# Check PVE resources
pvesh get /nodes/localhost/status

# Check storage availability  
pvesh get /storage/datapool

# Verify template availability
pveam list local | grep debian-12-standard

# Manual container creation test
pct create 999 /var/lib/vz/template/cache/debian-12-standard_12.2-1_amd64.tar.zst \
  --cores 1 --memory 512 --rootfs datapool:2 --hostname test
pct destroy 999
```

### Environment Decryption Issues
```bash
# Test decryption manually
bash scripts/encrypt-env.sh decrypt <stack_name>

# Check .env.example fallback
ls -la docker/<stack_name>/.env.example

# Verify encryption format  
file docker/<stack_name>/.env.enc
```

### Service Startup Failures
```bash
# Check Docker logs inside container
pct exec <vmid> -- docker-compose -f /opt/<stack>/docker-compose.yml logs

# Check container network connectivity
pct exec <vmid> -- ping google.com

# Verify environment variables
pct exec <vmid> -- docker-compose -f /opt/<stack>/docker-compose.yml config
```

### Network Access Issues
```bash
# Check container IP assignment
pct exec <vmid> -- ip addr show

# Test connectivity from PVE host
ping 192.168.1.<vmid>

# Check firewall (if enabled)
iptables -L | grep <vmid>
```

## Performance Optimization

### Resource Tuning
```bash
# Monitor container resource usage
pct exec <vmid> -- htop

# Adjust CPU/memory allocation in stacks.yaml
# Re-deploy to apply changes
```

### Storage Performance  
```bash  
# Monitor ZFS pool performance
zpool iostat datapool 1

# Check container disk usage
pct exec <vmid> -- df -h
```

## Security Considerations

### Environment File Security
- Never commit .env or decrypted files to git
- Use strong encryption passwords (store in password manager)  
- Regularly rotate secrets in .env.enc files
- Backup encrypted files separately from repository

### Container Security
- Containers run as unprivileged (safer than privileged)
- Network isolation through LXC containers
- Services bound to container IPs only
- Use strong passwords for web interfaces

### Access Control
- Change default passwords in deployed services
- Configure firewall rules if external access needed
- Use VPN for remote access to homelab
- Enable 2FA where supported by services

## Next Steps

1. **Configure Service Integrations**: Set up monitoring dashboards, media library scanning, etc.
2. **Backup Strategy**: Configure automated backups of container data
3. **SSL Certificates**: Set up Let's Encrypt through proxy stack  
4. **External Access**: Configure VPN or secure external access
5. **Monitoring Alerts**: Set up Grafana alerting for system issues

For advanced configuration and troubleshooting, refer to the individual service documentation and Proxmox VE guides.