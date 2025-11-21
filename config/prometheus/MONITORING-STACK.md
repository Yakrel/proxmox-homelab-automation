# Monitoring Stack Configuration

This document provides details on the monitoring stack components and their configurations.

## Components Overview

### Prometheus
- **Version**: Latest
- **Port**: 9090
- **Retention**: 30 days
- **Scrape Interval**: 30 seconds
- **Configuration**: `/datapool/config/prometheus/prometheus.yml`

**Features:**
- Rule evaluation (alerts + recording rules)
- Admin API enabled for configuration reloads
- Web lifecycle API enabled
- TSDB storage with automatic cleanup

### Alertmanager
- **Version**: Latest
- **Port**: 9093
- **Configuration**: `/datapool/config/alertmanager/alertmanager.yml`

**Features:**
- Alert routing and grouping
- Inhibition rules (prevent duplicate notifications)
- Severity-based routing (critical vs warning)
- Extensible receivers (ready for email/slack/telegram)

### Grafana
- **Version**: Latest
- **Port**: 3000
- **Configuration**: Auto-provisioned datasources and dashboards
- **Dashboards**: 4 pre-configured dashboards

**Plugins:**
- grafana-clock-panel
- grafana-simple-json-datasource

### Loki
- **Version**: Latest
- **Port**: 3100
- **Retention**: 30 days
- **Schema**: v13 (TSDB-based)
- **Configuration**: `/datapool/config/loki/loki.yml`

**Features:**
- Filesystem-based storage
- Query result caching (256MB, 1h TTL)
- Automatic log compaction
- Rate limiting to prevent overload

### Promtail
- **Version**: Latest
- **Configuration**: `/etc/promtail/promtail.yml` (per LXC)

**Features:**
- Docker container log collection
- System log collection
- Position tracking for reliable log shipping

### Node Exporter
- **Version**: Latest
- **Port**: 9100 (host network mode)

**Collected Metrics:**
- CPU usage by mode (user, system, idle, etc.)
- Memory usage and available memory
- Disk I/O statistics
- Network interface statistics
- Filesystem usage
- System load averages

### cAdvisor
- **Version**: Latest
- **Port**: 8082 (per LXC)

**Collected Metrics:**
- Per-container CPU usage
- Per-container memory usage and limits
- Container filesystem I/O
- Container network I/O
- OOM events
- Container lifecycle events

### Prometheus PVE Exporter
- **Version**: Latest
- **Port**: 9221
- **Configuration**: `/datapool/config/prometheus-pve-exporter/pve.yml`

**Collected Metrics:**
- Proxmox host CPU and memory
- LXC container status and resources
- LXC CPU and memory usage
- LXC disk and network I/O
- VM metrics (if VMs are present)

---

## Alert Rules

Located in: `/datapool/config/prometheus/rules/homelab-alerts.yml`

### Critical Alerts (severity: critical)
1. **LXCContainerDown** - LXC container is not running (1m)
2. **ContainerOOMEvent** - Container killed due to OOM (1m)
3. **PrometheusTargetDown** - Monitoring target unreachable (2m)
4. **NodeExporterDown** - Node Exporter is down (2m)

### Warning Alerts (severity: warning)
1. **LXCHighCPUUsage** - LXC CPU above 90% (5m)
2. **LXCHighMemoryUsage** - LXC memory above 90% (5m)
3. **LXCDiskSpaceLow** - LXC disk usage above 85% (5m)
4. **ProxmoxHostHighCPU** - Host CPU above 85% (10m)
5. **ProxmoxHostHighMemory** - Host memory above 85% (10m)
6. **ContainerHighCPUUsage** - Container CPU above 90% (10m)
7. **ContainerRestarting** - Container restarting frequently (5m)
8. **ContainerScrapeErrors** - Metric collection failing (1m)
9. **HighNetworkErrors** - High network error rate (5m)
10. **HighFilesystemUsage** - Filesystem above 85% (5m)
11. **PrometheusStorageLow** - Prometheus storage < 10% (5m)
12. **TooManyAlertsFiring** - More than 10 alerts firing (5m)

---

## Recording Rules

Located in: `/datapool/config/prometheus/recording-rules/homelab-recording-rules.yml`

Recording rules pre-compute expensive queries to improve dashboard performance.

### Container Recording Rules (30s interval)
- `container:cpu_usage:rate5m` - Pre-computed CPU percentage
- `container:network_receive:rate5m` - Network receive rate
- `container:network_transmit:rate5m` - Network transmit rate
- `container:fs_read:rate5m` - Disk read rate
- `container:fs_write:rate5m` - Disk write rate

**Note**: Container memory percentage recording rule is disabled because Docker containers in LXC don't have memory limits set, which would cause division by zero errors. Use LXC-level memory monitoring instead.

### LXC Recording Rules (30s interval)
- `lxc:memory_usage:percent` - LXC memory percentage
- `lxc:disk_read:rate5m` - LXC disk read rate
- `lxc:disk_write:rate5m` - LXC disk write rate
- `lxc:network_receive:rate5m` - LXC network receive rate
- `lxc:network_transmit:rate5m` - LXC network transmit rate

### Node Recording Rules (30s interval)
- `node:cpu_usage:percent` - Node CPU usage percentage
- `node:memory_usage:percent` - Node memory usage percentage
- `node:disk_usage:percent` - Node disk usage percentage

---

## Prometheus Scrape Jobs

### 1. prometheus (self-monitoring)
- **Target**: localhost:9090
- **Metrics**: Prometheus internal metrics

### 2. cadvisor (container metrics)
- **Targets**: All Docker LXC containers (192.168.1.100-106:8082)
- **Metrics**: Per-container resource usage
- **Labels**: Relabeled with friendly LXC names

### 3. proxmox (PVE metrics)
- **Target**: 192.168.1.10 (Proxmox host)
- **Exporter**: prometheus-pve-exporter:9221
- **Metrics**: Host and LXC/VM metrics

### 4. loki (log system)
- **Target**: loki:3100
- **Metrics**: Loki internal metrics

### 5. node-exporter (OS metrics)
- **Target**: 192.168.1.104:9100
- **Metrics**: Operating system metrics
- **Labels**: lxc-monitoring-01

---

## Data Flow

```
Container Logs → Promtail → Loki → Grafana (Logs Dashboard)
                                ↓
Container Metrics → cAdvisor → Prometheus → Grafana (Container Dashboard)
                                ↓
OS Metrics → Node Exporter → Prometheus → Grafana (Infrastructure Dashboard)
                                ↓
Proxmox Metrics → PVE Exporter → Prometheus → Grafana (Infrastructure Dashboard)
                                ↓
Alert Rules → Alertmanager → (Email/Slack/etc.)
                                ↓
Recording Rules → Pre-computed metrics → Faster dashboard queries
```

---

## Storage Locations

All monitoring data is stored on the Proxmox host at `/datapool/config/`:

```
/datapool/config/
├── prometheus/
│   ├── prometheus.yml              # Main Prometheus config
│   ├── data/                       # Time-series data (30d retention)
│   ├── rules/
│   │   └── homelab-alerts.yml     # Alert rules
│   └── recording-rules/
│       └── homelab-recording-rules.yml  # Recording rules
├── alertmanager/
│   ├── alertmanager.yml           # Alertmanager config
│   └── data/                      # Alert state persistence
├── grafana/
│   ├── data/                      # Grafana database
│   ├── provisioning/
│   │   ├── datasources/           # Auto-configured datasources
│   │   └── dashboards/            # Dashboard provider config
│   └── dashboards/                # Dashboard JSON files
├── loki/
│   ├── loki.yml                   # Loki config
│   └── data/                      # Log storage (30d retention)
└── prometheus-pve-exporter/
    └── pve.yml                    # PVE credentials
```

---

## Best Practices Implemented

### 1. **Separation of Concerns**
- Infrastructure metrics (PVE + Node Exporter)
- Container metrics (cAdvisor)
- Application logs (Loki)
- Alert management (Alertmanager)

### 2. **Performance Optimization**
- Recording rules for expensive queries
- Query result caching in Loki
- Proper scrape intervals (30s)
- Efficient label filtering

### 3. **Data Retention**
- 30-day retention for metrics and logs
- Automatic compaction and cleanup
- Balanced between disk space and historical data

### 4. **Monitoring Coverage**
- Host-level metrics (Proxmox + OS)
- Container-level metrics (Docker)
- Application logs (all containers)
- System health (alerts)

### 5. **Alert Design**
- Clear severity levels (critical vs warning)
- Appropriate thresholds and durations
- Actionable descriptions
- Alert inhibition to reduce noise

### 6. **Observability**
- Multiple dashboard perspectives
- Real-time log viewing
- Alert visualization
- Metric pre-aggregation

### 7. **Reliability**
- Persistent storage for all components
- Health checks for all services
- Automatic restarts
- Container user mapping (1000:1000)

### 8. **Security**
- Read-only configuration mounts
- User-level container execution
- Password-protected Grafana
- Configurable authentication

---

## Accessing Services

- **Grafana**: http://192.168.1.104:3000
- **Prometheus**: http://192.168.1.104:9090
- **Alertmanager**: http://192.168.1.104:9093
- **Loki**: http://192.168.1.104:3100

Default Grafana credentials are set via environment variables in the encrypted `.env` file.

---

## Maintenance

### Reload Prometheus Configuration
```bash
curl -X POST http://192.168.1.104:9090/-/reload
```

### Reload Alertmanager Configuration
```bash
curl -X POST http://192.168.1.104:9093/-/reload
```

### Check Prometheus Targets
```bash
curl http://192.168.1.104:9090/api/v1/targets
```

### Check Alertmanager Status
```bash
curl http://192.168.1.104:9093/api/v2/status
```

### View Active Alerts
```bash
curl http://192.168.1.104:9093/api/v2/alerts
```

---

## Extending the Monitoring Stack

### Adding a New Scrape Target
1. Edit `/datapool/config/prometheus/prometheus.yml`
2. Add new scrape config with target address
3. Reload Prometheus: `curl -X POST http://192.168.1.104:9090/-/reload`

### Adding a New Alert Rule
1. Edit `/datapool/config/prometheus/rules/homelab-alerts.yml`
2. Add new alert rule with appropriate severity
3. Reload Prometheus: `curl -X POST http://192.168.1.104:9090/-/reload`

### Adding Alert Notifications
1. Edit `/datapool/config/alertmanager/alertmanager.yml`
2. Configure receiver (email, Slack, Telegram, etc.)
3. Reload Alertmanager: `curl -X POST http://192.168.1.104:9093/-/reload`

### Adding a New Dashboard
1. Create dashboard in Grafana UI
2. Export as JSON (Settings → JSON Model)
3. Clean JSON (remove `id`, set to `null`)
4. Save to `config/grafana/dashboards/`
5. Grafana will auto-load within 10 seconds

---

## Troubleshooting

### No Data in Grafana
1. Check Prometheus targets: http://192.168.1.104:9090/targets
2. Verify all targets show "UP" status
3. Check container logs: `docker logs prometheus`

### Alerts Not Firing
1. Verify alert rules loaded: http://192.168.1.104:9090/rules
2. Check alert evaluation: http://192.168.1.104:9090/alerts
3. Review Alertmanager: http://192.168.1.104:9093

### Missing Metrics
1. Verify exporter is running: `docker ps | grep <exporter>`
2. Check exporter endpoint: `curl http://<ip>:<port>/metrics`
3. Review Prometheus scrape errors in logs

### High Memory Usage
1. Consider reducing retention period
2. Add more recording rules to pre-aggregate data
3. Optimize dashboard queries
4. Increase scrape intervals if needed

---

## References

- [Prometheus Documentation](https://prometheus.io/docs/)
- [Grafana Documentation](https://grafana.com/docs/)
- [Loki Documentation](https://grafana.com/docs/loki/)
- [Alertmanager Documentation](https://prometheus.io/docs/alerting/latest/alertmanager/)
