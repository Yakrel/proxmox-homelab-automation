# Monitoring Stack Cleanup & Optimization Plan

## 📊 Available cAdvisor Metrics Reference (DO NOT DELETE)

### CPU Metrics
- `container_cpu_usage_seconds_total` - Total CPU time consumed (counter)
- `container_cpu_system_seconds_total` - System CPU time (counter)
- `container_cpu_user_seconds_total` - User CPU time (counter)
- `container_cpu_load_average_10s` - Load average over 10 seconds (gauge)
- `container_spec_cpu_period` - CPU CFS period (gauge)
- `container_spec_cpu_shares` - CPU shares allocated (gauge)

### Memory Metrics
- `container_memory_usage_bytes` - Current memory usage (gauge)
- `container_memory_working_set_bytes` - Working set size (gauge) **[RECOMMENDED]**
- `container_memory_rss` - Resident set size (gauge)
- `container_memory_cache` - Page cache memory (gauge)
- `container_memory_swap` - Swap usage (gauge)
- `container_memory_max_usage_bytes` - Maximum memory usage recorded (gauge)
- `container_memory_failcnt` - Memory limit failures (counter)
- `container_memory_failures_total` - Memory allocation failures (counter)
- `container_memory_kernel_usage` - Kernel memory usage (gauge)
- `container_memory_mapped_file` - Memory mapped files (gauge)
- `container_spec_memory_limit_bytes` - Memory limit (gauge)
- `container_spec_memory_reservation_limit_bytes` - Memory soft limit (gauge)
- `container_spec_memory_swap_limit_bytes` - Swap limit (gauge)

### Network Metrics
- `container_network_receive_bytes_total` - Network bytes received (counter)
- `container_network_transmit_bytes_total` - Network bytes transmitted (counter)
- `container_network_receive_packets_total` - Packets received (counter)
- `container_network_transmit_packets_total` - Packets transmitted (counter)
- `container_network_receive_errors_total` - Receive errors (counter)
- `container_network_transmit_errors_total` - Transmit errors (counter)
- `container_network_receive_packets_dropped_total` - Dropped received packets (counter)
- `container_network_transmit_packets_dropped_total` - Dropped transmitted packets (counter)

### Filesystem Metrics
- `container_fs_usage_bytes` - Filesystem usage in bytes (gauge)
- `container_fs_limit_bytes` - Filesystem limit (gauge)
- `container_fs_reads_bytes_total` - Bytes read from filesystem (counter)
- `container_fs_writes_bytes_total` - Bytes written to filesystem (counter)
- `container_fs_reads_total` - Number of read operations (counter)
- `container_fs_writes_total` - Number of write operations (counter)
- `container_fs_read_seconds_total` - Time spent reading (counter)
- `container_fs_write_seconds_total` - Time spent writing (counter)
- `container_fs_reads_merged_total` - Merged read operations (counter)
- `container_fs_writes_merged_total` - Merged write operations (counter)
- `container_fs_sector_reads_total` - Sectors read (counter)
- `container_fs_sector_writes_total` - Sectors written (counter)
- `container_fs_io_current` - Current I/O operations (gauge)
- `container_fs_io_time_seconds_total` - Time spent doing I/Os (counter)
- `container_fs_io_time_weighted_seconds_total` - Weighted I/O time (counter)
- `container_fs_inodes_free` - Free inodes (gauge)
- `container_fs_inodes_total` - Total inodes (gauge)

### Block I/O Metrics
- `container_blkio_device_usage_total` - Block device usage (counter)

### Container State Metrics
- `container_last_seen` - Last time container was seen (timestamp)
- `container_start_time_seconds` - Container start time (timestamp)
- `container_tasks_state` - Number of tasks in various states (gauge)
- `container_oom_events_total` - Out of memory events (counter)
- `container_scrape_error` - Scrape error indicator (gauge)

---

## 📋 Current State Analysis

### ✅ What's Working
- **Proxmox VE Monitoring**: Dashboard ID 10347 working well
- **cAdvisor**: Successfully deployed in monitoring stack (LXC 104)
- **Container Metrics**: CPU, Memory, Network, Filesystem usage visible
- **Loki + Promtail**: Collecting logs from containers and system
- **Prometheus**: Scraping all targets successfully

### ❌ What's Not Working / Redundant
- **Docker Engine metrics (port 9323)**: Only provides daemon-level stats, NOT per-container metrics
- **Redundant metric collection**: Docker daemon metrics overlap with cAdvisor
- **cAdvisor only in monitoring LXC**: Other LXCs not monitored by cAdvisor

### 🎯 What We Need
- Per-container metrics from ALL LXC hosts (100-105)
- Remove Docker daemon metrics endpoint (port 9323)
- Centralized cAdvisor deployment strategy

---

## 🚀 Implementation Plan

### Phase 1: Deploy cAdvisor to All Docker LXCs
**Target LXCs:** 100 (proxy), 101 (media), 102 (files), 103 (webtools), 105 (gameservers)

**Tasks:**
1. Add cAdvisor service to each docker-compose.yml
2. Update Prometheus scrape config to collect from all cAdvisors
3. Configure cAdvisor with:
   - Alpine-compatible settings (no /dev/kmsg)
   - Port: 8080 (mapped uniquely per LXC in Prometheus)
   - Minimal metrics for performance

**Implementation:**
```yaml
# Add to each docker-compose.yml
cadvisor:
  image: gcr.io/cadvisor/cadvisor:latest
  container_name: cadvisor
  restart: unless-stopped
  ports:
    - "8080:8080"
  volumes:
    - /:/rootfs:ro
    - /var/run:/var/run:ro
    - /sys:/sys:ro
    - /var/lib/docker/:/var/lib/docker:ro
    - /dev/disk/:/dev/disk:ro
  privileged: true
  environment:
    - TZ=Europe/Istanbul
  command:
    - '--housekeeping_interval=10s'
    - '--docker_only=true'
    - '--store_container_labels=false'
  networks:
    - <network_name>
  logging:
    driver: "json-file"
    options:
      max-size: "10m"
      max-file: "3"
```

**Prometheus Config Update:**
```yaml
- job_name: 'cadvisor'
  static_configs:
    - targets:
      - '192.168.1.100:8080'  # proxy
      - '192.168.1.101:8080'  # media
      - '192.168.1.102:8080'  # files
      - '192.168.1.103:8080'  # webtools
      - '192.168.1.104:8080'  # monitoring
      - '192.168.1.105:8080'  # gameservers
  relabel_configs:
    - source_labels: [__address__]
      regex: '192.168.1.100:8080'
      target_label: instance
      replacement: 'lxc-proxy-01'
    - source_labels: [__address__]
      regex: '192.168.1.101:8080'
      target_label: instance
      replacement: 'lxc-media-01'
    - source_labels: [__address__]
      regex: '192.168.1.102:8080'
      target_label: instance
      replacement: 'lxc-files-01'
    - source_labels: [__address__]
      regex: '192.168.1.103:8080'
      target_label: instance
      replacement: 'lxc-webtools-01'
    - source_labels: [__address__]
      regex: '192.168.1.104:8080'
      target_label: instance
      replacement: 'lxc-monitoring-01'
    - source_labels: [__address__]
      regex: '192.168.1.105:8080'
      target_label: instance
      replacement: 'lxc-gameservers-01'
```

---

### Phase 2: Remove Docker Daemon Metrics (Port 9323)
**Reason:** Redundant - cAdvisor provides better per-container metrics

**Tasks:**
1. Remove `metrics-addr` from `/etc/docker/daemon.json` on all LXCs
2. Remove port 9323 expose from docker-compose files (if any)
3. Remove `docker_engine` job from Prometheus config
4. Restart Docker daemon on each LXC

**Files to modify:**
- `/etc/docker/daemon.json` on LXC 100-105
- `/datapool/config/prometheus/prometheus.yml`

**Docker daemon.json cleanup:**
```bash
# On each LXC, edit /etc/docker/daemon.json
# Remove this line:
"metrics-addr": "0.0.0.0:9323",

# Restart Docker
rc-service docker restart
```

---

### Phase 3: Optimize Grafana Dashboards

**Keep:**
- Dashboard ID **10347**: Proxmox VE monitoring (working well)
- **Custom cAdvisor Dashboard**: `/datapool/config/grafana/dashboards/cadvisor-docker-monitoring.json`

**Remove:**
- Dashboard ID 1229 (Docker Engine Metrics - redundant)
- Dashboard ID 893 (incomplete data)
- Dashboard ID 19792 (too complex, incomplete)
- Any other imported dashboards that don't show data

**Enhance Custom Dashboard:**
- Add per-LXC filtering (instance variable)
- Add Datapool disk usage panel
- Fix remaining "No Data" panels

---

### Phase 4: Loki Dashboard Improvements

**Current Issue:** Dashboard ID 13186 expects Kubernetes labels

**Solution Options:**
1. Use simpler dashboard: ID **12611** (Logging Dashboard via Loki)
2. Create custom Loki dashboard for container logs with:
   - Filter by host (LXC)
   - Filter by container name
   - Filter by log level (detected_level)
   - Search functionality

---

### Phase 5: Final Cleanup & Testing

**Tasks:**
1. Verify all cAdvisors are up and reporting
2. Verify Prometheus targets are healthy
3. Remove unused dashboards from Grafana
4. Test dashboard with all container metrics visible
5. Document final architecture in README.md

**Health Check Commands:**
```bash
# Check all cAdvisor endpoints
for ip in 100 101 102 103 104 105; do
  echo "=== LXC 192.168.1.$ip ==="
  curl -s http://192.168.1.$ip:8080/metrics | head -5
done

# Check Prometheus targets
curl -s http://192.168.1.104:9090/api/v1/targets | jq '.data.activeTargets[] | select(.job=="cadvisor") | {instance: .labels.instance, health: .health}'

# Check container metrics
curl -s 'http://192.168.1.104:9090/api/v1/query?query=container_cpu_usage_seconds_total{name!=""}' | jq '.data.result | length'
```

---

## 📊 Expected Results

### Before
- ❌ Only monitoring LXC has detailed container metrics
- ❌ Docker daemon metrics provide minimal value
- ❌ Incomplete dashboards with "No Data"
- ❌ 6 targets for docker_engine job (port 9323)

### After
- ✅ All 6 LXC hosts report per-container metrics via cAdvisor
- ✅ Single unified cAdvisor job in Prometheus
- ✅ Clean dashboard showing all container CPU/Memory/Network/Disk
- ✅ No redundant metrics collection
- ✅ Reduced Docker daemon overhead (no port 9323 exposure)

---

## 🔧 Implementation Order

1. **Phase 1** - Deploy cAdvisor to all LXCs (non-breaking, additive)
2. **Phase 3** - Update custom dashboard for all instances (verify metrics)
3. **Phase 2** - Remove Docker daemon metrics (after verifying cAdvisor works)
4. **Phase 4** - Fix Loki dashboard
5. **Phase 5** - Final cleanup and documentation

---

## 📝 Notes

- **Backward Compatible:** Phase 1 can be done without breaking existing monitoring
- **Rollback Plan:** Keep docker_engine metrics until cAdvisor fully verified
- **Performance:** cAdvisor uses ~50-100MB RAM per instance
- **Network:** Port 8080 only exposed on host network, not external

---

## 🎯 Next Steps

**Ready to start?**
1. Confirm plan looks good
2. Start with Phase 1: Deploy cAdvisor to one non-monitoring LXC first (test)
3. If successful, deploy to remaining LXCs
4. Update Prometheus config and custom dashboard
5. Remove redundant docker_engine metrics

**Estimated Time:** 30-45 minutes total
