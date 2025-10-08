# Grafana Dashboards

This directory contains pre-configured Grafana dashboards for the Proxmox homelab monitoring stack.

## Available Dashboards

### 1. Proxmox via Prometheus (`proxmox-dashboard.json`)

**Custom-built dashboard** with proper ZFS ARC memory accounting and comprehensive system monitoring.

**Required Data Sources:**
- Prometheus PVE Exporter (port 9221)
- Node Exporter on Proxmox host (port 9100)

**Required Metrics:**

*From PVE Exporter:*
- `pve_cpu_usage_limit` - CPU allocation limits
- `pve_cpu_usage_ratio` - CPU usage ratios
- `pve_memory_size_bytes` - Memory allocation
- `pve_memory_usage_bytes` - Memory usage
- `pve_disk_size_bytes` - Disk/storage sizes
- `pve_disk_usage_bytes` - Disk/storage usage
- `pve_disk_read_bytes` - Disk read statistics
- `pve_disk_write_bytes` - Disk write statistics
- `pve_network_receive_bytes` - Network receive statistics
- `pve_network_transmit_bytes` - Network transmit statistics
- `pve_node_info` - Node information (labels)
- `pve_guest_info` - Guest/container information (labels)
- `pve_storage_info` - Storage information (labels)
- `pve_up` - Resource up/down status

*From Node Exporter (ZFS-aware):*
- `node_memory_MemTotal_bytes` - Total system memory
- `node_memory_MemAvailable_bytes` - Available memory (accounts for reclaimable cache)
- `node_zfs_arc_size` - Current ZFS ARC size
- `node_zfs_arc_hits_total` - ZFS ARC cache hits
- `node_zfs_arc_misses_total` - ZFS ARC cache misses
- `node_cpu_seconds_total` - CPU usage by mode
- `node_load1/5/15` - System load averages
- `node_network_*_bytes_total` - Network statistics
- `node_boot_time_seconds` - System boot time

**Prometheus Configuration Required:**
```yaml
# Node Exporter for Proxmox host system metrics
- job_name: 'node_exporter'
  static_configs:
    - targets:
      - '192.168.1.10:9100'
  relabel_configs:
    - source_labels: [__address__]
      regex: '192.168.1.10:9100'
      target_label: instance
      replacement: 'proxmox-host'

# Proxmox VE Exporter for guest metrics
- job_name: 'proxmox'
  static_configs:
    - targets:
      - '192.168.1.10'
  metrics_path: /pve
  params:
    module: [default]
  relabel_configs:
    - source_labels: [__address__]
      target_label: __param_target
    - source_labels: [__param_target]
      target_label: instance
    - target_label: __address__
      replacement: prometheus-pve-exporter:9221
```

**Features:**
- **ZFS-Aware Memory Monitoring**: Properly accounts for ZFS ARC as reclaimable cache
- **System Overview**: Guest status, uptime, CPU/Memory gauges
- **Detailed System Metrics**: CPU by mode, memory breakdown with ZFS ARC visibility
- **ZFS Monitoring**: ARC size, hit rate, and efficiency tracking
- **Storage Usage**: All storage pools with usage percentage
- **Network I/O**: Host network throughput on bridge interface
- **Guest Resources**: Per-LXC/VM CPU, memory, disk I/O, and network I/O
- **Best Practice Design**: Organized layout with row separators and clear visualizations

**ZFS ARC Memory Accounting:**

Traditional memory monitoring shows ZFS ARC as "used" memory, which is misleading because ARC is reclaimable cache. This dashboard uses `node_memory_MemAvailable_bytes` which properly accounts for reclaimable memory including ZFS ARC.

**Memory calculation:**
- **Actual Used Memory** = `MemTotal - MemAvailable`
- **Available Memory** = `MemAvailable` (includes reclaimable ARC)
- **ZFS ARC Size** = Displayed separately for visibility

This gives accurate representation of actual memory pressure vs cache usage.

**Setup Requirements:**

1. Install node_exporter on Proxmox host:
   ```bash
   # Use helper menu option 9, or manually:
   apt install prometheus-node-exporter
   systemctl enable --now prometheus-node-exporter
   ```

2. Configure Prometheus to scrape both exporters (see configuration above)

3. Dashboard will auto-load when placed in `/datapool/config/grafana/dashboards/`

---

### 2. Docker Engine Metrics (`docker-engine-dashboard.json`)

**Custom dashboard** designed for Docker Engine's native metrics endpoint.

**Required Metrics:**
- `engine_daemon_container_states_containers` - Container states (running/paused/stopped)
- `engine_daemon_container_actions_seconds_*` - Container action durations (create/start/stop/delete)
- `engine_daemon_health_checks_total` - Total health checks
- `engine_daemon_health_checks_failed_total` - Failed health checks
- `engine_daemon_health_check_start_duration_seconds_*` - Health check durations
- `engine_daemon_events_total` - Total Docker events
- `engine_daemon_image_actions_seconds_*` - Image operations (pull/push/delete)
- `engine_daemon_network_actions_seconds_*` - Network operations
- `engine_daemon_engine_cpus_cpus` - Available CPUs
- `engine_daemon_engine_memory_bytes` - Available memory

**Prometheus Configuration Required:**
```yaml
- job_name: 'docker_engine'
  static_configs:
    - targets: 
        - '192.168.1.100:9323'  # LXC 100
        - '192.168.1.101:9323'  # LXC 101
        # Add all Docker hosts
```

**Docker Configuration Required:**

Each Docker host must expose metrics on port 9323. Add to `/etc/docker/daemon.json`:
```json
{
  "metrics-addr": "0.0.0.0:9323",
  "experimental": true
}
```

**Features:**
- Container state tracking over time
- Container action rates and durations
- Health check monitoring
- Image and network operation rates
- Per-host breakdown

**Why not cAdvisor?**

This dashboard uses Docker Engine's native metrics instead of cAdvisor because:
- cAdvisor has compatibility issues with Alpine Linux in LXC containers
- Docker Engine metrics are simpler and built-in (no extra container needed)
- Sufficient for homelab monitoring needs

---

### 3. Docker Logs via Loki (`loki-logs-dashboard.json`)

**Custom simple log viewer** for Docker container logs.

**Required Setup:**
- Loki datasource configured
- Promtail scraping Docker logs

**Promtail Configuration:**

The deployment script automatically configures Promtail to scrape Docker container logs from `/var/lib/docker/containers`.

**Features:**
- Real-time log streaming
- Searchable and filterable
- Shows all Docker containers on the host
- Auto-refresh every 10 seconds

**Usage:**
- Use Grafana's built-in log panel filters to search
- Click on log lines to expand details
- Adjust time range as needed

---

## Deployment

These dashboards are automatically deployed by the monitoring stack deployment script:

```bash
./installer.sh
# Select option 5: Deploy monitoring stack
```

The script will:
1. Download dashboard JSONs from this repo
2. Fix datasource UIDs to match your setup (`prometheus` and `loki`)
3. Place them in `/datapool/config/grafana/dashboards/`
4. Grafana auto-loads them via provisioning

## Manual Installation

If you want to manually import a dashboard:

1. Copy the JSON file to the Grafana host
2. Open Grafana UI → Dashboards → Import
3. Upload the JSON file or paste its contents
4. Select the appropriate datasources (Prometheus/Loki)

## Customization

All dashboards are editable in Grafana. After making changes:

1. Click the dashboard settings (gear icon)
2. Go to "JSON Model"
3. Copy the JSON
4. Save it back to this repo to preserve changes

## Metrics Reference

### Proxmox VE Exporter

Metrics are collected by `prometheus-pve-exporter` which queries the Proxmox VE API.

- **Documentation:** https://github.com/prometheus-pve/prometheus-pve-exporter
- **Metrics exposed:** All PVE API metrics for nodes, guests, and storage

### Docker Engine Metrics

Metrics are native to Docker Engine when experimental features are enabled.

- **Documentation:** https://docs.docker.com/config/daemon/prometheus/
- **Port:** 9323 (default)
- **Requires:** `"experimental": true` in daemon.json

## Troubleshooting

### "No data" in panels

1. **Check datasources:**
   ```bash
   # In Grafana UI: Configuration → Data Sources
   # Test each datasource connection
   ```

2. **Verify Prometheus targets:**
   ```bash
   curl http://192.168.1.104:9090/api/v1/targets
   ```

3. **Check metric availability:**
   ```bash
   # List all PVE metrics
   curl -s http://192.168.1.104:9090/api/v1/label/__name__/values | jq -r '.data[]' | grep "^pve_"
   
   # List all Docker metrics
   curl -s http://192.168.1.104:9090/api/v1/label/__name__/values | jq -r '.data[]' | grep "^engine_"
   ```

### Datasource UID mismatch

If you see "Datasource not found" errors, the dashboard's datasource UID doesn't match your setup.

**Fix:**
```bash
# Replace datasource UIDs in dashboard JSON
sed -i 's/"uid": "${DS_PROMETHEUS}"/"uid": "prometheus"/g' dashboard.json
sed -i 's/"uid": "${DS_LOKI}"/"uid": "loki"/g' dashboard.json
```

### Loki logs not showing

1. **Check Promtail is running:**
   ```bash
   docker ps | grep promtail
   ```

2. **Verify Promtail config:**
   ```bash
   cat /etc/promtail/promtail.yml
   ```

3. **Check Loki targets in Promtail:**
   ```bash
   curl http://192.168.1.104:9080/targets
   ```

## Contributing

If you improve these dashboards or create new ones:

1. Export the JSON from Grafana
2. Clean up the JSON (remove `id`, `__inputs`, `__requires`)
3. Add documentation comments at the top of the JSON
4. Update this README with metrics required and features
5. Commit to the repo

