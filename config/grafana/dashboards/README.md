# Grafana Dashboards

Minimalist monitoring dashboards for Proxmox homelab with cAdvisor container metrics.

## Design Philosophy

- **Minimalist**: Only essential metrics that matter
- **Actionable**: Focus on data you actually use
- **Unified**: Complete system view in minimal dashboards
- **Clean**: Clear visual hierarchy, sorted by importance

## Available Dashboards

### 1. System Monitoring (`system-monitoring.json`)

**Unified monitoring dashboard** combining Proxmox LXC infrastructure + cAdvisor container metrics.

**Dashboard Structure:**

#### Top Section: Critical Metrics (First View)
- **Proxmox CPU/Memory**: Host resource gauges with color thresholds (green/yellow/red)
- **Running LXCs**: Total count of active containers
- **Total Containers**: Docker container count across all hosts
- **OOM Events**: Out-of-memory events in last 5 minutes

#### LXC Infrastructure
- **LXC Overview Table**: All LXCs with status, CPU %, Memory % (gradient gauges, sortable)
- **LXC CPU Usage**: Time series with mean/max in legend, sorted by max
- **LXC Memory Usage**: Time series with mean/max in legend, sorted by max
- **LXC Disk I/O**: Read (bottom) / Write (top) - sorted by max I/O
- **LXC Network I/O**: RX (bottom) / TX (top) - sorted by max throughput

#### Docker Containers (cAdvisor Metrics)
- **Container CPU Usage**: Per-container CPU with mean/max, sorted by max
- **Container Memory Usage**: Working set memory with mean/max, sorted by max
- **Container Disk I/O**: Read (bottom) / Write (top) - sorted by max I/O
- **Container Network I/O**: RX (bottom) / TX (top) - sorted by max throughput

**Key Features:**
- Auto-refresh every 30s
- 1-hour default time range
- Legend sorted by max values - **resource hogs appear at top**
- Monitoring containers excluded from Docker metrics (cadvisor, prometheus, grafana, loki, promtail, watchtower)

**Use Cases:**
- Quick system health check
- Identify CPU/memory/disk/network bottlenecks
- Track which LXC or container is causing issues
- Monitor OOM events

---

### 2. Logs Monitoring (`logs-monitoring.json`)

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

**Most Important Metrics Used:**

*Proxmox:*
- `pve_cpu_usage_ratio`, `pve_memory_usage_bytes`, `pve_memory_size_bytes`
- `pve_disk_read_bytes`, `pve_disk_write_bytes`
- `pve_network_receive_bytes`, `pve_network_transmit_bytes`
- `pve_up`, `pve_guest_info`

*cAdvisor:*
- `container_cpu_usage_seconds_total`
- `container_memory_working_set_bytes`
- `container_fs_reads_bytes_total`, `container_fs_writes_bytes_total`
- `container_network_receive_bytes_total`, `container_network_transmit_bytes_total`
- `container_oom_events_total`

---

## Contributing

To update dashboards:

1. Edit in Grafana UI
2. Export: Settings → JSON Model
3. Clean: remove `id`, set `"id": null`
4. Ensure datasource UIDs: `prometheus` and `loki`
5. Save to this repo
6. Update this README
