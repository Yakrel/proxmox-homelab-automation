# Grafana Dashboards

Homelab monitoring dashboards for Proxmox + Docker infrastructure.

## Dashboards

- **Infrastructure Overview** - LXC containers, Proxmox host metrics, and storage usage
- **Container Monitoring** - Docker container CPU, memory, network, disk I/O
- **Logs Monitoring** - Centralized log viewing with Loki
- **Alert Overview** - Active alerts and alert history

## Known Limitations

### Filesystem Usage by Container

The `container_fs_usage_bytes` metric may show no data. This is a known cAdvisor limitation:

- Docker uses overlay2 storage driver by default
- cAdvisor cannot accurately report per-container filesystem usage with overlay2
- This metric only works reliably with the older devicemapper storage driver

**Workaround:** Use Disk I/O metrics (`container_fs_reads_bytes_total`, `container_fs_writes_bytes_total`) which work correctly and show read/write activity per container. The Container Monitoring dashboard intentionally does not use `container_fs_usage_bytes` for capacity decisions.

**Alternative for LXC/storage capacity monitoring:** Use the Infrastructure Overview dashboard which shows LXC-level and storage-level disk usage via PVE exporter (`pve_disk_usage_bytes` / `pve_disk_size_bytes`).

## Available Metrics

### Container Metrics (cAdvisor)

| Metric | Description | Status |
|--------|-------------|--------|
| `container_cpu_usage_seconds_total` | CPU usage | ✅ Works |
| `container_memory_working_set_bytes` | Memory usage | ✅ Works |
| `container_network_*_bytes_total` | Network I/O | ✅ Works |
| `container_fs_reads_bytes_total` | Disk read I/O | ✅ Works |
| `container_fs_writes_bytes_total` | Disk write I/O | ✅ Works |
| `container_fs_usage_bytes` | Filesystem usage | ⚠️ Not used for capacity dashboards |
| `container_oom_events_total` | OOM events | ✅ Works |

### Proxmox Metrics (PVE Exporter)

| Metric | Description |
|--------|-------------|
| `pve_cpu_usage_ratio` | LXC/VM CPU usage |
| `pve_memory_usage_bytes` | LXC/VM memory usage |
| `pve_disk_usage_bytes` | LXC/VM disk usage |
| `pve_disk_size_bytes` | LXC/VM/storage disk size |
| `pve_network_*_bytes_total` | LXC/VM network I/O |
| `pve_up` | LXC/VM running status |

### Promtail Metrics

| Metric | Description |
|--------|-------------|
| `promtail_sent_entries_total` | Log entries sent to Loki |
| `promtail_sent_bytes_total` | Log bytes sent to Loki |
| `promtail_targets_active_total` | Active Promtail scrape targets |

### Log Metrics (Loki)

| Label | Description |
|-------|-------------|
| `host` | LXC hostname |
| `container_name` | Docker container name |
| `stream` | stdout/stderr |
| `job` | dockerlogs/systemlogs |
