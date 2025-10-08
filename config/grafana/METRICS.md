# Available Metrics in Homelab

**Last Updated:** 2025-10-08  
**Purpose:** This document tracks all available metrics from our monitoring stack to avoid re-checking every time.

## Prometheus Targets Status

### ✅ Active Targets
- `prometheus` (localhost:9090) - UP
- `lxc-proxy-01` (192.168.1.100:9323) - UP
- `lxc-media-01` (192.168.1.101:9323) - UP
- `lxc-files-01` (192.168.1.102:9323) - UP
- `lxc-webtools-01` (192.168.1.103:9323) - UP
- `lxc-monitoring-01` (192.168.1.104:9323) - UP
- `lxc-gameservers-01` (192.168.1.105:9323) - DOWN (no route to host)
- `loki` (loki:3100) - UP
- `promtail` (promtail-monitoring:9080) - UP
- `proxmox` (192.168.1.10 via pve-exporter:9221) - UP

## Available Metrics

### 1. Proxmox VE Metrics (via PVE Exporter)

**Source:** `prometheus-pve-exporter` container  
**Endpoint:** Port 9221  
**Total Metrics:** 20

```
pve_cpu_usage_limit
pve_cpu_usage_ratio
pve_disk_read_bytes
pve_disk_size_bytes          # Used for storage capacity
pve_disk_usage_bytes         # Used for storage usage
pve_disk_write_bytes
pve_guest_info               # Labels: name, type (lxc/qemu), node
pve_ha_state
pve_lock_state
pve_memory_size_bytes
pve_memory_usage_bytes
pve_network_receive_bytes
pve_network_transmit_bytes
pve_node_info
pve_onboot_status
pve_storage_info             # NOT USED - use pve_disk_* instead
pve_storage_shared
pve_up
pve_uptime_seconds
pve_version_info
```

**Important Notes:**
- Storage metrics use `pve_disk_*` NOT `pve_storage_*`
- Filter storage with: `id=~"storage/.*"`
- Example storage query: `pve_disk_usage_bytes{id=~"storage/.*"}`

### 2. Docker Engine Metrics

**Source:** Docker daemon native metrics endpoint  
**Endpoint:** Port 9323 on each LXC  
**Total Metrics:** 21 (grouped by operation type)

```
engine_daemon_container_states_containers           # States: running, paused, stopped
engine_daemon_container_actions_seconds_bucket      # Histogram buckets
engine_daemon_container_actions_seconds_count       # Action counts: create, start, stop, delete
engine_daemon_container_actions_seconds_sum         # Action durations
engine_daemon_engine_cpus_cpus                      # Available CPUs
engine_daemon_engine_info                           # Engine version/platform info
engine_daemon_engine_memory_bytes                   # Available memory
engine_daemon_events_subscribers_total              # Event subscribers
engine_daemon_events_total                          # Total events
engine_daemon_health_checks_failed_total            # Failed health checks
engine_daemon_health_check_start_duration_seconds_bucket
engine_daemon_health_check_start_duration_seconds_count
engine_daemon_health_check_start_duration_seconds_sum
engine_daemon_health_checks_total                   # Total health checks (usually 0 if no healthchecks defined)
engine_daemon_host_info_functions_seconds_bucket
engine_daemon_host_info_functions_seconds_count
engine_daemon_host_info_functions_seconds_sum
engine_daemon_image_actions_seconds_bucket
engine_daemon_image_actions_seconds_count           # Image operations: pull, push, delete
engine_daemon_image_actions_seconds_sum
engine_daemon_network_actions_seconds_bucket
engine_daemon_network_actions_seconds_count         # Network operations: create, remove, connect
engine_daemon_network_actions_seconds_sum
```

**Current Container Counts (2025-10-08):**
- lxc-proxy-01: 3 running
- lxc-media-01: 16 running
- lxc-files-01: 5 running
- lxc-webtools-01: 4 running
- lxc-monitoring-01: 6 running
- lxc-gameservers-01: DOWN

**Health Checks:** Currently showing 0 because no containers have healthchecks defined.

### 3. Loki & Promtail Metrics

**Loki Endpoint:** Port 3100  
**Promtail Endpoint:** Port 9080

**Status:** 
- ⚠️ **KNOWN ISSUE:** Promtail on non-monitoring LXCs cannot reach Loki (192.168.1.104:3100)
- Error: `dial tcp 192.168.1.104:3100: connect: no route to host` or `connection refused`
- Root cause: Promtail containers are in separate Docker networks, cannot reach Loki's host IP
- **Solution needed:** Either use host network mode for Promtail or use a shared network

**Promtail Locations:**
- lxc-monitoring-01: ✅ Working (same host as Loki)
- lxc-webtools-01: ❌ Cannot reach Loki
- lxc-proxy-01: ❌ Not deployed
- lxc-media-01: ? Unknown
- lxc-files-01: ? Unknown
- lxc-gameservers-01: ? Unknown

## Missing Metrics / Gaps

### 1. Container Resource Usage
- **Missing:** Per-container CPU, memory, network, disk I/O
- **Why:** Not using cAdvisor (incompatible with Alpine LXC)
- **Alternative:** Docker engine metrics only show daemon-level stats, not per-container

### 2. Health Checks
- **Current:** 0 health checks across all containers
- **Impact:** `engine_daemon_health_checks_total` always shows 0
- **Recommendation:** Add basic healthchecks to critical services (see below)

### 3. Detailed Storage Metrics
- **Available:** Only basic size/usage
- **Missing:** IOPS, latency, read/write breakdown per storage pool
- **Impact:** Limited storage performance monitoring

## Recommendations

### Should We Add Health Checks?

**Pros:**
- Better monitoring and alerting
- Automatic container restart on failures
- Dashboard metrics will be more useful

**Cons:**
- Slight overhead (typically negligible)
- Need to configure for each service

**Recommendation:** Yes, add healthchecks to critical services only:

**Critical services that should have healthchecks:**
- Nginx Proxy Manager (HTTP check on :81)
- Grafana (HTTP check on :3000)
- Prometheus (HTTP check on :9090)
- Loki (HTTP check on :3100)
- Plex (HTTP check on :32400)
- Jellyfin (HTTP check on :8096)
- Sonarr/Radarr/etc (HTTP checks on respective ports)

**Format:**
```yaml
healthcheck:
  test: ["CMD", "curl", "-f", "http://localhost:PORT/health"]
  interval: 30s
  timeout: 10s
  retries: 3
  start_period: 40s
```

**System Impact:** Minimal - a simple HTTP GET every 30s is negligible overhead.

## How to Update This Document

When metrics change:
1. Run the verification commands (see below)
2. Update the metric lists above
3. Update the "Last Updated" date
4. Commit changes

### Verification Commands

```bash
# Check Prometheus targets
curl -s http://192.168.1.104:9090/api/v1/targets | jq '.data.activeTargets[] | {job: .labels.job, instance: (.labels.instance // .scrapeUrl), health: .health}'

# List PVE metrics
curl -s http://192.168.1.104:9090/api/v1/label/__name__/values | jq -r '.data[]' | grep "^pve_" | sort

# List Docker engine metrics
curl -s http://192.168.1.104:9090/api/v1/label/__name__/values | jq -r '.data[]' | grep "^engine_" | sort

# Check container counts
curl -s http://192.168.1.104:9090/api/v1/query?query=engine_daemon_container_states_containers | jq '.data.result[] | {instance: .metric.instance, state: .metric.state, count: .value[1]}'

# Check Loki status
curl http://192.168.1.104:3100/ready

# Check Promtail status (on monitoring LXC)
curl http://192.168.1.104:9080/ready
```
