# Monitoring System Documentation

## Overview

The monitoring stack provides comprehensive observability for the entire Proxmox homelab infrastructure using:
- **Prometheus** - Metrics collection and storage
- **Grafana** - Visualization and dashboards
- **Loki** - Log aggregation
- **Promtail** - Log shipping from all LXC containers
- **Proxmox VE Exporter** - Proxmox metrics
- **PBS Integration** - Proxmox Backup Server metrics

## Architecture

### Network Topology
```
Proxmox Host (192.168.1.10)
├── LXC 100 (proxy)      - 192.168.1.100
├── LXC 101 (media)      - 192.168.1.101
├── LXC 102 (files)      - 192.168.1.102
├── LXC 103 (webtools)   - 192.168.1.103
├── LXC 104 (monitoring) - 192.168.1.104 ⭐ Main monitoring stack
├── LXC 105 (gameservers)- 192.168.1.105
└── LXC 106 (backup/PBS) - 192.168.1.106
```

### Data Flow

```
┌─────────────────────────────────────────────────────────────┐
│                    Monitoring LXC (104)                      │
│  ┌──────────┐  ┌──────────┐  ┌──────┐  ┌────────────────┐  │
│  │Prometheus│◄─┤   Loki   │◄─┤ PBS  │  │  Grafana       │  │
│  │  :9090   │  │  :3100   │  │:8007 │  │  :3000         │  │
│  └────▲─────┘  └────▲─────┘  └──────┘  └────────────────┘  │
│       │             │                                         │
└───────┼─────────────┼─────────────────────────────────────────┘
        │             │
        │             │  Logs via Promtail
        │             │
    ┌───┴─────────────┴────────────────────────┐
    │  Metrics via Prometheus scraping         │
    │  - Docker Engine (:9323)                  │
    │  - PVE Exporter (:9221)                   │
    │  - PBS API (:8007/api2/prometheus)        │
    └───────────────────────────────────────────┘
         │
         │
    ┌────┴──────────────────────────────────────┐
    │  All Docker LXCs (100-105)                 │
    │  - Promtail container in each              │
    │  - Docker daemon metrics enabled           │
    │  - Container logs shipped to Loki          │
    └────────────────────────────────────────────┘
```

## Components

### 1. Prometheus (Metrics)

**Service**: `prometheus:9090`
**Storage**: `/datapool/config/prometheus/data`
**Retention**: 30 days

**Monitored Targets**:
- Self-monitoring (localhost:9090)
- Docker Engine metrics from all LXCs (192.168.1.100-105:9323)
- Proxmox VE via PVE Exporter (192.168.1.10)
- Proxmox Backup Server via API (192.168.1.106:8007)
- Loki (loki:3100)
- Promtail (promtail-monitoring:9080)

**Configuration**: `docker/monitoring/prometheus.yml`

### 2. Grafana (Visualization)

**Service**: `grafana:3000`
**Storage**: `/datapool/config/grafana/data`
**Admin**: Configured via `.env.enc` (GF_SECURITY_ADMIN_USER/PASSWORD)

**Features**:
- Auto-provisioned datasources (Prometheus + Loki)
- Auto-provisioned dashboards (Proxmox, Docker, Loki)
- Dashboard files: `/datapool/config/grafana/dashboards/`

**Pre-loaded Dashboards**:
1. **Proxmox Dashboard** - Host and VM/LXC metrics
2. **Docker Dashboard** - Container resource usage
3. **Loki Dashboard** - Log exploration and analysis

### 3. Loki (Log Aggregation)

**Service**: `loki:3100`
**Storage**: `/datapool/config/loki/data`
**Retention**: 30 days (with compaction)

**Configuration**: `config/loki/loki.yml`
- Retention enabled with automatic cleanup
- Compaction runs every 10 minutes
- Filesystem storage backend

### 4. Promtail (Log Shipping)

**Deployment**: One instance in each Docker LXC
**Configuration**: `/etc/promtail/promtail.yml` (per LXC)

**Log Sources**:
- Docker container logs (`/var/lib/docker/containers`)
- System logs (`/var/log/messages`)

**Labels**:
- `host`: LXC hostname (e.g., lxc-media-01)
- `container_name`: Docker container name
- `job`: containerlogs or systemlogs

### 5. Proxmox VE Exporter

**Service**: `prometheus-pve-exporter:9221`
**Authentication**: Uses `pve-exporter@pve` user with PVEAuditor role

**Metrics**:
- Host CPU, memory, disk usage
- VM/LXC resource utilization
- Cluster status (if applicable)

### 6. PBS Monitoring

**Integration**: File-based service discovery
**Configuration**: `/datapool/config/prometheus/pbs_job.yml`
**Authentication**: `prometheus@pbs` user with password file

**Dynamic Behavior**:
- If PBS stack (LXC 106) is running → metrics scraped
- If PBS stack is not running → empty targets (no errors)

## Environment Variables

All sensitive configuration is stored in `.env.enc` (encrypted).

### Required Variables

```bash
# User Passwords (set by you)
GF_SECURITY_ADMIN_PASSWORD=<your-grafana-password>
PBS_ADMIN_PASSWORD=<your-pbs-password>

# System Passwords (fixed for idempotency)
PVE_MONITORING_PASSWORD=<fixed-random>
PBS_PROMETHEUS_PASSWORD=<fixed-random>

# Configuration
GF_SECURITY_ADMIN_USER=admin
PVE_USER=pve-exporter@pve
PVE_URL=https://192.168.1.10:8006
PVE_VERIFY_SSL=false
TZ=Europe/Istanbul
```

### Decryption

The `.env.enc` file is decrypted using:
1. **Interactive deployment**: User prompted for passphrase
2. **CI/CD**: `ENV_ENC_KEY` environment variable

```bash
# Manual decryption
printf '%s' "$ENV_ENC_KEY" | openssl enc -d -aes-256-cbc -pbkdf2 -pass stdin \
  -in docker/monitoring/.env.enc -out /tmp/.env
```

## Deployment Flow

### Automated Deployment

The monitoring stack deploys fully automatically via `deploy-stack.sh`:

```bash
./scripts/deploy-stack.sh monitoring
```

**Steps Executed**:
1. Decrypt `.env.enc` using ENV_ENC_KEY or user prompt
2. Create monitoring directories on host
3. Setup PVE monitoring user (pve-exporter@pve)
4. Configure PBS monitoring (password file + targets)
5. Configure Grafana datasources (Prometheus + Loki)
6. Download and provision Grafana dashboards
7. Configure Promtail for monitoring LXC
8. Validate all configuration files
9. Deploy Docker Compose stack

### Idempotency

The deployment is fully idempotent:
- Configuration files are **overwritten** on each run
- Docker Compose updates services without destroying data
- Re-running deployment is safe and will fix configuration drift

### Manual Validation

Run the validation script to check the monitoring system:

```bash
./scripts/validate-monitoring.sh
```

This performs 100+ checks including:
- Environment variable validation
- Configuration file existence
- Inter-stack connectivity
- PBS integration
- Dashboard provisioning
- Network topology

## Configuration Files

### Host Files (Proxmox)
```
/datapool/config/
├── prometheus/
│   ├── prometheus.yml           # Main Prometheus config
│   ├── .prometheus-password     # PBS password (secure)
│   ├── pbs_job.yml              # PBS targets (dynamic)
│   └── data/                    # Metrics storage
├── grafana/
│   ├── data/                    # Grafana database
│   ├── provisioning/
│   │   ├── datasources/
│   │   │   └── datasources.yml  # Auto-provisioned datasources
│   │   └── dashboards/
│   │       └── provider.yml     # Dashboard provider config
│   └── dashboards/              # Dashboard JSON files
│       ├── proxmox-dashboard.json
│       ├── docker-dashboard.json
│       └── loki-dashboard.json
└── loki/
    ├── loki.yml                 # Loki configuration
    └── data/                    # Log storage
```

### Container Files (LXC)
```
/root/.env                       # Environment variables
/etc/promtail/promtail.yml       # Per-LXC Promtail config
/var/lib/promtail/positions/     # Log position tracking
```

## Monitoring Stack Connections

### To Other Stacks

| Stack       | Connection Type | Port/Protocol | Purpose |
|-------------|----------------|---------------|---------|
| All Docker  | Prometheus     | 9323/TCP      | Docker Engine metrics |
| All Docker  | Loki           | 3100/TCP      | Log aggregation via Promtail |
| Proxmox     | PVE Exporter   | 8006/HTTPS    | Host & VM/LXC metrics |
| Backup (PBS)| Prometheus     | 8007/HTTPS    | Backup metrics & jobs |

### From Other Stacks

Each Docker stack includes:
- **Promtail container** - Ships logs to `192.168.1.104:3100`
- **Docker daemon metrics** - Exposed on port 9323

## Security

### Password Management

- **User passwords**: Set by administrator (Grafana, PBS admin panels)
- **System passwords**: Fixed random values for service-to-service auth
- **Encryption**: All passwords in `.env.enc` encrypted with AES-256-CBC
- **PBS password file**: Stored with 600 permissions, owned by container user

### Network Security

- All communication within private network (192.168.1.0/24)
- PBS uses HTTPS with `insecure_skip_verify` (private network)
- No external exposure required (access via Cloudflare tunnel if needed)

### User Permissions

**Proxmox**:
- `pve-exporter@pve` - PVEAuditor role (read-only)

**PBS**:
- `prometheus@pbs` - Datastore.Audit permission (metrics only)

## Maintenance

### Log Retention

- **Loki**: 30 days automatic retention with compaction
- **Prometheus**: 30 days storage (configurable)
- **Docker logs**: 10MB max size, 3 files rotation

### Updates

Watchtower handles automatic updates:
- Schedule: `0 0 2,8,14,20 * * *` (4x daily at 02:00, 08:00, 14:00, 20:00)
- Cleanup: Old images removed automatically
- Restart: Containers restarted with new images

### Dashboard Updates

Dashboards are downloaded automatically during deployment:
- Source: Grafana.com dashboard repository
- Cleaned: `id`, `__inputs`, `__requires` removed for auto-provisioning
- Location: `/datapool/config/grafana/dashboards/`

To update dashboards, redeploy the monitoring stack:
```bash
./scripts/deploy-stack.sh monitoring
```

## Troubleshooting

### Grafana Not Showing Data

1. Check Prometheus is running and scraping:
   ```bash
   curl http://192.168.1.104:9090/targets
   ```

2. Verify datasource in Grafana:
   - Navigate to Configuration → Data Sources
   - Test Prometheus and Loki connections

3. Check container logs:
   ```bash
   pct exec 104 -- docker logs grafana
   pct exec 104 -- docker logs prometheus
   ```

### Missing Metrics from LXC

1. Verify Docker metrics enabled:
   ```bash
   pct exec <ct_id> -- cat /etc/docker/daemon.json
   # Should contain: "metrics-addr": "0.0.0.0:9323"
   ```

2. Test metric endpoint:
   ```bash
   curl http://192.168.1.<ct_id>:9323/metrics
   ```

3. Check Prometheus targets:
   ```bash
   curl http://192.168.1.104:9090/api/v1/targets | jq
   ```

### Promtail Not Sending Logs

1. Check Promtail is running:
   ```bash
   pct exec <ct_id> -- docker ps | grep promtail
   ```

2. Verify Promtail configuration:
   ```bash
   pct exec <ct_id> -- cat /etc/promtail/promtail.yml
   # Should contain: url: http://192.168.1.104:3100/loki/api/v1/push
   ```

3. Check Promtail logs:
   ```bash
   pct exec <ct_id> -- docker logs promtail-<stack>
   ```

4. Test Loki endpoint:
   ```bash
   curl http://192.168.1.104:3100/ready
   ```

### PBS Metrics Not Available

1. Check PBS stack is running:
   ```bash
   pct status 106
   ```

2. Verify PBS prometheus user exists:
   ```bash
   pct exec 106 -- proxmox-backup-manager user list
   # Should show: prometheus@pbs
   ```

3. Check PBS targets file:
   ```bash
   cat /datapool/config/prometheus/pbs_job.yml
   ```

4. Test PBS metrics endpoint:
   ```bash
   curl -k -u prometheus@pbs:$(cat /datapool/config/prometheus/.prometheus-password) \
     https://192.168.1.106:8007/api2/prometheus/metrics
   ```

### Dashboards Not Loading

1. Check dashboard files exist:
   ```bash
   ls -la /datapool/config/grafana/dashboards/
   ```

2. Verify dashboard provider configuration:
   ```bash
   cat /datapool/config/grafana/provisioning/dashboards/provider.yml
   ```

3. Check file permissions:
   ```bash
   ls -la /datapool/config/grafana/
   # Should be owned by 101000:101000 (unprivileged LXC mapping)
   ```

4. Restart Grafana to reload:
   ```bash
   pct exec 104 -- docker restart grafana
   ```

## Design Principles (per CLAUDE.md)

### Fail Fast & Simple
- Let commands fail naturally with original error messages
- No retry logic or waiting loops
- All output visible for debugging (no `/dev/null`)

### Homelab-First Approach
- Static/hardcoded values (IPs, ports)
- Manual intervention accepted for edge cases
- Simple solutions over complex error recovery

### Latest Everything
- All images use `:latest` tag
- Version pinning only if compatibility requires

### Idempotency
- Safe to re-run deployment
- Configuration files overwritten
- No duplicate resources created

## Validation Results

Last validation: All 106 checks passed ✓

Key validations:
- ENV_ENC_KEY decryption working
- All required environment variables present
- Prometheus scrape configs complete
- Grafana datasources and dashboards automated
- Loki retention and compaction configured
- Promtail deployed to all Docker stacks
- PBS integration dynamic and fail-safe
- Network topology consistent (192.168.1.{ct_id})
- Watchtower auto-updates enabled

## References

- **Prometheus**: https://prometheus.io/docs/
- **Grafana**: https://grafana.com/docs/grafana/latest/
- **Loki**: https://grafana.com/docs/loki/latest/
- **Promtail**: https://grafana.com/docs/loki/latest/clients/promtail/
- **PVE Exporter**: https://github.com/prometheus-pve/prometheus-pve-exporter
- **Proxmox VE**: https://pve.proxmox.com/wiki/
- **Proxmox Backup Server**: https://pbs.proxmox.com/docs/

---

**Note**: This monitoring system is specifically designed for this homelab environment with hardcoded IPs and configuration. Adaptation for other environments requires modifications to network addresses, authentication, and deployment scripts.
