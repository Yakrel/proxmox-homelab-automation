# Grafana Dashboards

Comprehensive monitoring dashboards for Proxmox homelab with cAdvisor container metrics.

## Design Philosophy

- **Comprehensive**: Cover all important metrics across infrastructure and applications
- **Organized**: Separate dashboards for different concerns (infrastructure vs containers vs logs)
- **Actionable**: Focus on metrics you actually use for troubleshooting and monitoring
- **Clean**: Clear visual hierarchy, sorted by importance with color-coded thresholds

## Available Dashboards

### 1. Infrastructure Overview (`infrastructure-overview.json`)

**Proxmox host and LXC container monitoring** - Focus on virtualization infrastructure health.

**Dashboard Structure:**

#### Top Section: Critical Host Metrics
- **Proxmox CPU/Memory**: Host resource gauges with color thresholds (green/yellow/red)
- **Running LXCs**: Total count of active LXC containers
- **Total Containers**: Docker container count across all hosts
- **OOM Events**: Out-of-memory events in last 5 minutes

#### LXC Infrastructure
- **LXC Overview Table**: All LXCs with status, CPU %, Memory % (gradient gauges, sortable)
- **LXC CPU Usage**: Time series with mean/max in legend, sorted by max
- **LXC Memory Usage**: Time series with mean/max in legend, sorted by max
- **LXC Disk I/O**: Read (bottom) / Write (top) - sorted by max I/O to identify storage bottlenecks
- **LXC Network I/O**: RX (bottom) / TX (top) - sorted by max throughput

**Key Features:**
- Auto-refresh every 30s
- 1-hour default time range
- Legend sorted by max values - **resource hogs appear at top**
- Color-coded thresholds (green < 70% < yellow < 85% < red)

**Use Cases:**
- Infrastructure health monitoring
- Identify which LXC is consuming resources
- Track Proxmox host capacity
- Spot disk/network bottlenecks at the LXC level

---

### 2. Container Monitoring (`container-monitoring.json`)

**Detailed Docker container metrics from cAdvisor** - Deep dive into application container performance.

**Dashboard Structure:**

#### Top Section: Container Health Metrics
- **Total Containers**: Count of running Docker containers
- **OOM Events (5m)**: Out-of-memory events with color thresholds
- **Scrape Errors**: cAdvisor metric collection errors
- **Network Errors (5m)**: Network receive/transmit errors across all containers

#### Container Overview Table
- All containers with Host, Name, CPU %, Memory, Memory %, Memory Limit
- Gradient gauges for CPU and Memory usage with color thresholds
- Sortable by any column to quickly find resource hogs

#### Detailed Container Metrics
- **CPU Usage**: Per-container CPU percentage with mean/max stats
- **Memory Usage**: Working set memory (actual memory used)
- **Disk I/O**: Filesystem read/write rates (bytes per second)
- **Network I/O**: Network transmit/receive rates (bytes per second)
- **Filesystem Usage**: Total filesystem usage per container
- **Network Packet Drops**: Dropped packets indicating network issues

**Key Features:**
- All metrics have mean/max calculations in legend
- Legend sorted by max values - highest usage at top
- Color-coded thresholds (green < 70% < yellow < 90% < red for CPU/Memory)
- Excludes monitoring infrastructure containers (cadvisor, prometheus, grafana, loki, promtail, watchtower)

**Use Cases:**
- Application performance monitoring
- Container resource optimization
- Identify memory leaks (check memory trends)
- Network troubleshooting (errors, drops, bandwidth)
- Filesystem usage tracking

---

### 3. Logs Monitoring (`logs-monitoring.json`)

**Real-time log viewer** with advanced filtering for Docker container logs via Loki.

**Dashboard Structure:**

#### Log Volume Chart
- Stacked histogram showing log volume per container over time
- Helps identify log spikes and chatty containers

#### Container Logs Panel
- Live log streaming with syntax highlighting
- Full log details on expansion
- Sorted by newest first

**Filtering Variables:**
- **Host**: Select LXC host (dropdown, All by default)
- **Container**: Multi-select container names (All by default)
- **Stream**: stdout, stderr, or All
- **Search**: Free-text regex search box

**Key Features:**
- Auto-refresh every 10s
- 1-hour default time range
- Live mode enabled
- Dynamic container list based on selected host

**Use Cases:**
- Real-time container troubleshooting
- Filter errors only (stream=stderr)
- Search for specific events across all containers
- Track log volume spikes

---

## Dashboard Organization

The 3-dashboard structure provides **separation of concerns**:

1. **Infrastructure Overview** → For infrastructure/ops team monitoring LXC health
2. **Container Monitoring** → For application/dev team monitoring container performance
3. **Logs Monitoring** → For troubleshooting and debugging

**Benefits:**
- Faster dashboard loading (smaller JSON files, less data per view)
- Clearer context per dashboard
- Easier to share specific views with different teams
- Better performance with focused queries

---

## Data Sources

### Prometheus (UID: `prometheus`)
- **Proxmox VE Exporter** (port 9221): LXC/VM metrics
- **cAdvisor** (port 8080): Per-container metrics from all Docker hosts

### Loki (UID: `loki`)
- **Promtail agents**: Log shipping from all Docker hosts
- 30-day retention

---

## Prometheus Configuration

Required scrape configs in `prometheus.yml`:

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

  # cAdvisor - Per-container metrics
  - job_name: 'cadvisor'
    static_configs:
      - targets:
        - '192.168.1.100:8080'  # lxc-proxy-01
        - '192.168.1.101:8080'  # lxc-media-01
        - '192.168.1.102:8080'  # lxc-files-01
        - '192.168.1.103:8080'  # lxc-webtools-01
        - '192.168.1.104:8080'  # lxc-monitoring-01
        - '192.168.1.105:8080'  # lxc-gameservers-01
    relabel_configs:
      - source_labels: [__address__]
        regex: '192.168.1.100:8080'
        target_label: instance
        replacement: 'lxc-proxy-01'
      - source_labels: [__address__]
        regex: '192.168.1.101:8080'
        target_label: instance
        replacement: 'lxc-media-01'
      # ... (remaining relabel configs for other LXCs)
```

**Note:** Old Docker daemon metrics (port 9323) removed - cAdvisor provides better per-container data.

---

## Deployment

Dashboards are automatically deployed:

```bash
./installer.sh
# Select: Deploy monitoring stack
```

The script:
1. Downloads dashboard JSONs to `/datapool/config/grafana/dashboards/`
2. Grafana auto-loads via provisioning
3. Datasource UIDs pre-configured

---

## Manual Installation

To manually import:

1. Grafana UI → Dashboards → Import
2. Upload JSON file or paste contents
3. Select datasources: `prometheus` and `loki`
4. Click Import

---

## Troubleshooting

### "No data" in panels

**Check Prometheus targets:**
```bash
curl http://192.168.1.104:9090/api/v1/targets
```
All should show `"health":"up"`.

**Verify cAdvisor metrics:**
```bash
curl -s http://192.168.1.104:9090/api/v1/label/__name__/values | jq -r '.data[]' | grep "^container_"
```

**Verify Proxmox metrics:**
```bash
curl -s http://192.168.1.104:9090/api/v1/label/__name__/values | jq -r '.data[]' | grep "^pve_"
```

### Loki logs not showing

**Check Promtail:**
```bash
docker ps | grep promtail
```

**Verify Loki labels:**
```bash
curl -s http://192.168.1.104:3100/loki/api/v1/labels | jq
```
Should see: `host`, `container_name`, `stream`, `job`.

### Container metrics missing from some hosts

Ensure cAdvisor is deployed to all Docker LXCs. Check if running:
```bash
ssh root@192.168.1.100 "docker ps | grep cadvisor"
```

---

## Metrics Reference

See `MONITORING-PLAN.md` for complete metric definitions.

**Metrics Used by Dashboard:**

### Infrastructure Overview Dashboard
*Proxmox VE Metrics:*
- `pve_cpu_usage_ratio` - Host and LXC CPU usage (0.0-1.0)
- `pve_memory_usage_bytes`, `pve_memory_size_bytes` - Memory usage and capacity
- `pve_disk_read_bytes`, `pve_disk_write_bytes` - Cumulative disk I/O (use rate())
- `pve_network_receive_bytes`, `pve_network_transmit_bytes` - Cumulative network I/O (use rate())
- `pve_up` - LXC status (1=running, 0=stopped)
- `pve_guest_info` - LXC metadata (name, type)

### Container Monitoring Dashboard
*cAdvisor Metrics:*
- `container_cpu_usage_seconds_total` - Total CPU time (use rate() for percentage)
- `container_memory_working_set_bytes` - Active memory usage **[PRIMARY METRIC]**
- `container_spec_memory_limit_bytes` - Memory limit for percentage calculation
- `container_fs_usage_bytes` - Filesystem space used
- `container_fs_reads_bytes_total`, `container_fs_writes_bytes_total` - Disk I/O (use rate())
- `container_network_receive_bytes_total`, `container_network_transmit_bytes_total` - Network I/O (use rate())
- `container_network_receive_errors_total`, `container_network_transmit_errors_total` - Network errors
- `container_network_receive_packets_dropped_total`, `container_network_transmit_packets_dropped_total` - Packet drops
- `container_oom_events_total` - Out of memory events
- `container_scrape_error` - Metric collection errors
- `container_last_seen` - Container presence indicator

---

## Contributing

To update dashboards:

1. Edit in Grafana UI
2. Export: Settings → JSON Model
3. Clean: remove `id`, set `"id": null`
4. Ensure datasource UIDs: `prometheus` and `loki`
5. Save to this repo
6. Update this README
