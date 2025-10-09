# Grafana Dashboards

This directory contains minimalist, practical Grafana dashboards for the Proxmox homelab monitoring stack.

## Design Philosophy

- **Minimalist**: Only essential metrics that matter
- **Practical**: Focused on real homelab monitoring needs
- **Unified**: Single dashboard for infrastructure + workloads
- **Clean**: Well-organized with clear visual hierarchy

## Available Dashboards

### 1. System Overview (`system-overview-dashboard.json`)

**Unified dashboard** combining Proxmox infrastructure and Docker workload metrics.

**Dashboard Structure:**

#### Section 1: Host Health (Stat Panels)
- **Node CPU/Memory**: Proxmox host resource gauges with color thresholds
- **Running Guests**: Total count of running LXC/VMs
- **Docker Containers**: Total running containers across all hosts
- **Failed Health Checks**: Docker health check failures (5m window)

#### Section 2: LXC Resources
- **Guest Overview Table**:
  - All LXC/VM with status (Running/Stopped)
  - CPU and Memory usage as gradient gauges
  - Sortable by resource usage
- **Guest CPU Usage**: Time series per LXC/VM with mean/max in legend
- **Guest Memory Usage**: Time series per LXC/VM with mean/max in legend

#### Section 3: Disk & Network I/O ⭐
- **Guest Disk I/O**: Read (negative) and Write (positive) per LXC/VM
  - Sorted by max I/O in legend - **instantly see which LXC is hammering the disk**
- **Guest Network I/O**: RX (negative) and TX (positive) per LXC/VM
  - Sorted by max throughput - **identify network bottlenecks**

#### Section 4: Docker Containers
- **Container States**: Running/stopped over time (stacked area chart)
- **Container Actions**: Start/stop/restart rates per Docker host

**Required Metrics:**

*Proxmox VE Exporter (PVE):*
- `pve_cpu_usage_ratio` - CPU usage
- `pve_memory_usage_bytes` / `pve_memory_size_bytes` - Memory
- `pve_disk_read_bytes` / `pve_disk_write_bytes` - Disk I/O (rate)
- `pve_network_receive_bytes` / `pve_network_transmit_bytes` - Network I/O (rate)
- `pve_guest_info` - Guest metadata (names, types)
- `pve_up` - Guest status

*Docker Engine Metrics:*
- `engine_daemon_container_states_containers` - Container states (running/stopped)
- `engine_daemon_container_actions_seconds_count` - Container action rates
- `engine_daemon_health_checks_failed_total` - Failed health checks

**Why Disk I/O matters:**
When an LXC freezes or becomes unresponsive, it's often disk-related. This dashboard shows:
- Which LXC is doing heavy disk writes (backup/download/build)
- Which LXC is reading excessively (database/media streaming)
- Legend sorted by max values - culprit is at the top

**Use Cases:**
- Quick system health check in one view
- Identify resource hogs (CPU/Memory/Disk/Network)
- Monitor Docker container lifecycle
- Track health check failures

---

### 2. Logs Monitor (`logs-dashboard.json`)

**Improved log viewer** with better filtering and search capabilities.

**Features:**
- **Log Volume Chart**: Stacked histogram showing log volume per container
- **Real-time Log Panel**: Live log streaming with filtering
- **Advanced Filtering**:
  - **Host**: Select which LXC host
  - **Container**: Filter by Docker container name
  - **Stream**: stdout/stderr selection
  - **Level**: Quick filter by log level (info/warn/error/debug)
  - **Search**: Free-text regex search
- **Auto-refresh**: 10s interval for live monitoring

**Required Setup:**
- Loki datasource configured in Grafana
- Promtail scraping Docker logs from all hosts

**Use Cases:**
- Troubleshoot container issues in real-time
- Filter logs by severity (errors only)
- Search across all containers for specific events
- Monitor log volume spikes

---

## Data Sources

### Prometheus (UID: `prometheus`)
Collects metrics from:
- **Proxmox VE Exporter** (port 9221): Host and guest metrics
- **Docker Engine** (port 9323): Native Docker daemon metrics from 6 LXC hosts

### Loki (UID: `loki`)
Centralized log aggregation:
- **Promtail agents** on each Docker host shipping container logs
- 30-day retention policy

---

## Prometheus Configuration

The monitoring stack requires these scrape configs:

```yaml
scrape_configs:
  # Proxmox VE Exporter
  - job_name: 'proxmox'
    static_configs:
      - targets: ['192.168.1.10']
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

  # Docker Engine metrics
  - job_name: 'docker_engine'
    static_configs:
      - targets:
        - '192.168.1.100:9323'  # lxc-proxy-01
        - '192.168.1.101:9323'  # lxc-media-01
        - '192.168.1.102:9323'  # lxc-files-01
        - '192.168.1.103:9323'  # lxc-webtools-01
        - '192.168.1.104:9323'  # lxc-monitoring-01
        - '192.168.1.105:9323'  # lxc-gameservers-01
    relabel_configs:
      - source_labels: [__address__]
        regex: '192.168.1.(\d+):9323'
        target_label: instance
        replacement: 'lxc-${1}'
```

**Docker Configuration Required:**

Each Docker host must expose metrics. Add to `/etc/docker/daemon.json`:
```json
{
  "metrics-addr": "0.0.0.0:9323",
  "experimental": true
}
```

---

## Deployment

Dashboards are automatically deployed by the monitoring stack:

```bash
./installer.sh
# Select: Deploy monitoring stack
```

The deployment script:
1. Places dashboard JSONs in `/datapool/config/grafana/dashboards/`
2. Grafana auto-loads them via provisioning
3. Datasource UIDs are pre-configured (`prometheus` and `loki`)

---

## Manual Installation

To manually import a dashboard:

1. Open Grafana UI → Dashboards → Import
2. Upload the JSON file or paste contents
3. Select datasources: `prometheus` and `loki`
4. Click Import

---

## Troubleshooting

### "No data" in panels

**Check Prometheus targets:**
```bash
curl http://192.168.1.104:9090/api/v1/targets
```

All targets should show `"health":"up"`.

**Verify metrics availability:**
```bash
# Check PVE metrics
curl -s http://192.168.1.104:9090/api/v1/label/__name__/values | jq -r '.data[]' | grep "^pve_"

# Check Docker metrics
curl -s http://192.168.1.104:9090/api/v1/label/__name__/values | jq -r '.data[]' | grep "^engine_"
```

### Loki logs not showing

**Check Promtail is running:**
```bash
docker ps | grep promtail
```

**Verify log labels in Loki:**
```bash
curl -s http://192.168.1.104:3100/loki/api/v1/labels | jq
```

You should see labels: `host`, `container_name`, `stream`, `job`.

### Disk I/O shows zero

If disk I/O graphs are flat:
1. Ensure PVE exporter is scraping successfully
2. Check that `pve_disk_read_bytes` and `pve_disk_write_bytes` metrics exist
3. Verify the `rate()` function window (5m) - may need more data points

---

## Customization

All dashboards are editable in Grafana UI:

1. Open dashboard → Settings (gear icon)
2. Make changes in edit mode
3. To preserve changes:
   - Click dashboard settings → JSON Model
   - Copy JSON
   - Save to this repo: `config/grafana/dashboards/`

**Tips:**
- Add more panels by duplicating existing ones
- Adjust time ranges and thresholds as needed
- Customize colors and legends

---

## Metrics Reference

### Proxmox VE Exporter Metrics (Used)

```
pve_cpu_usage_ratio          - CPU usage (0.0-1.0)
pve_memory_usage_bytes       - Used memory in bytes
pve_memory_size_bytes        - Total memory in bytes
pve_disk_read_bytes          - Cumulative disk reads (counter)
pve_disk_write_bytes         - Cumulative disk writes (counter)
pve_network_receive_bytes    - Cumulative RX bytes (counter)
pve_network_transmit_bytes   - Cumulative TX bytes (counter)
pve_guest_info               - Guest metadata (name, type labels)
pve_up                       - Guest status (1=running, 0=stopped)
```

**Note:** Disk and network metrics are counters - use `rate()` to get per-second rates.

### Docker Engine Metrics (Used)

```
engine_daemon_container_states_containers           - Container count by state (running/stopped)
engine_daemon_container_actions_seconds_count       - Container action counts (start/stop/restart)
engine_daemon_health_checks_failed_total            - Failed health check counter
```

**Full list available:** https://docs.docker.com/config/daemon/prometheus/

---

## Removed Metrics (From Old Dashboards)

To keep dashboards minimal, we removed:
- ❌ Docker action duration histograms (rarely needed)
- ❌ Docker events rate (too noisy)
- ❌ Image/network operation metrics (advanced use only)
- ❌ Storage pool details table (Proxmox UI better for this)

**Focus:** Only metrics you actually look at regularly.

---

## Contributing

If you improve these dashboards:

1. Export JSON from Grafana (Settings → JSON Model)
2. Clean up: remove `id`, set `"id": null`
3. Ensure datasource UIDs are `prometheus` and `loki`
4. Update this README with changes
5. Commit to repo

---

## Migration from Old Dashboards

If upgrading from previous dashboard version:

**Old dashboards (removed):**
- `proxmox-dashboard.json` → Merged into `system-overview-dashboard.json`
- `docker-engine-dashboard.json` → Merged into `system-overview-dashboard.json`
- `loki-logs-dashboard.json` → Replaced by `logs-dashboard.json`

**What changed:**
- 3 dashboards → 2 dashboards (less context switching)
- Proxmox + Docker unified in one view
- Added critical Disk & Network I/O metrics
- Improved log filtering with search textbox
- Removed unnecessary advanced metrics

**No configuration changes needed** - datasources and metrics are the same.
