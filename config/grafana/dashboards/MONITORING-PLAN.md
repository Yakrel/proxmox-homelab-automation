# Available Metrics Reference

## cAdvisor Container Metrics

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

## Proxmox VE Exporter Metrics

### Host & Guest Metrics
- `pve_cpu_usage_ratio` - CPU usage (0.0-1.0)
- `pve_memory_usage_bytes` - Used memory in bytes
- `pve_memory_size_bytes` - Total memory in bytes
- `pve_disk_read_bytes` - Cumulative disk reads (counter)
- `pve_disk_write_bytes` - Cumulative disk writes (counter)
- `pve_network_receive_bytes` - Cumulative RX bytes (counter)
- `pve_network_transmit_bytes` - Cumulative TX bytes (counter)
- `pve_guest_info` - Guest metadata (name, type labels)
- `pve_up` - Guest status (1=running, 0=stopped)
