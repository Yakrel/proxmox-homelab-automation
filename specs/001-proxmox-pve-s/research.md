# Research: Proxmox PVE Zero-to-Production Automation

**Date**: 2025-09-26  
**Feature**: 001-proxmox-pve-s

## Research Questions & Findings

### 1. LXC Container Management via Proxmox API
**Question**: How to programmatically create and manage LXC containers on Proxmox VE?

**Decision**: Use `pct` command-line interface directly  
**Rationale**: 
- Native PVE tool, no additional dependencies
- Direct access to all LXC functionality
- Aligns with constitution principle IV (Pure Bash Scripting)
- Fail-fast behavior with clear error messages

**Key Commands**:
```bash
pct create <vmid> <template> --hostname <name> --cores <cpu> --memory <ram> --rootfs <storage>
pct start <vmid>
pct exec <vmid> -- <command>
```

### 2. Environment File Encryption Strategy
**Question**: How to securely handle .env.enc files for homelab automation?

**Decision**: OpenSSL symmetric encryption with AES-256-CBC  
**Rationale**:
- Available by default on Debian Trixie
- Single password for all stacks (homelab simplicity)
- Fallback to .env.example ensures deployment continuity
- No GPG complexity needed for homelab use case

**Implementation**:
```bash
# Encrypt
openssl enc -aes-256-cbc -salt -in .env -out .env.enc -pass pass:$PASSWORD

# Decrypt  
openssl enc -d -aes-256-cbc -in .env.enc -out .env -pass pass:$PASSWORD
```

### 3. Grafana Dashboard Auto-Import Mechanism
**Question**: How to automatically import Grafana dashboards from community?

**Decision**: Grafana HTTP API with dashboard ID-based imports  
**Rationale**:
- Community dashboards have stable IDs
- HTTP API available in all Grafana versions
- Can be scripted with curl (no additional tools)
- Supports bulk import operations

**Implementation**:
```bash
curl -X POST "http://grafana:3000/api/dashboards/db" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"dashboard": {...}, "overwrite": true}'
```

### 4. Service Stack Resource Allocation
**Question**: How to determine appropriate resource allocation per service stack?

**Decision**: Static YAML configuration with predefined specifications  
**Rationale**:
- Homelab environments have known resource constraints  
- Static allocation prevents resource conflicts
- YAML format allows structured configuration
- Aligns with constitution principle II (Homelab-First Approach)

**Configuration Structure**:
```yaml
stacks:
  proxy:
    vmid: 100
    cores: 2
    memory: 2048
    storage: 10
  media:
    vmid: 101  
    cores: 6
    memory: 10240
    storage: 20
```

### 5. Idempotent Deployment Strategy
**Question**: How to ensure safe re-deployment of existing stacks?

**Decision**: Pre-flight checks with graceful skipping  
**Rationale**:
- Check LXC container existence before `pct create`
- Validate Docker services before `docker-compose up`
- Skip creation steps, continue with updates
- Log all actions for transparency

**Check Pattern**:
```bash
if pct status $VMID >/dev/null 2>&1; then
    echo "Container $VMID exists, skipping creation"
    # Continue with service deployment
else
    pct create $VMID ...
fi
```

## Alternatives Considered

### Rejected: Ansible/Terraform Orchestration
- **Reason**: Violates constitution principle IV (Pure Bash Scripting)
- **Trade-off**: Less declarative configuration for simpler dependency management

### Rejected: Dynamic Resource Discovery  
- **Reason**: Violates constitution principle II (Homelab-First Approach)
- **Trade-off**: Less flexibility for predictable homelab behavior

### Rejected: Configuration File Auto-Generation
- **Reason**: Adds complexity without homelab benefit
- **Trade-off**: Manual config maintenance for simpler automation logic

## Technical Decisions Summary

| Component | Technology | Justification |
|-----------|------------|---------------|
| **Container Management** | Proxmox `pct` CLI | Native, fail-fast, no dependencies |
| **Encryption** | OpenSSL AES-256-CBC | Built-in, simple, homelab-appropriate |  
| **Dashboard Import** | Grafana HTTP API | Community standard, curl-compatible |
| **Resource Config** | Static YAML | Predictable, homelab-optimized |
| **Orchestration** | Pure Bash Scripts | Constitution compliance, minimal dependencies |
| **Menu System** | Bash `select` | Interactive, built-in, no external tools |

## Implementation Constraints

1. **No Testing Framework**: Live PVE environment required (constitution principle)
2. **Hardcoded Network**: 192.168.1.x range assumed throughout
3. **Single Storage Pool**: datapool ZFS pool must exist
4. **Timezone Fixed**: Europe/Istanbul hardcoded for all containers
5. **Latest Versions**: No version pinning allowed for any component