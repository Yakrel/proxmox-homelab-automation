# Health Checks Implementation Guide

## Why Add Health Checks?

**Current Status:** 0 health checks across all containers  
**Impact:** No automatic failure detection or restart capabilities

### Benefits
- Automatic container restart on failures
- Better monitoring in dashboards
- Early problem detection
- Reduced manual intervention

### Performance Impact
- **Minimal** - typically <1% CPU overhead
- Simple HTTP/TCP checks every 30 seconds
- Negligible memory footprint

## Recommended Services for Health Checks

### Critical Services (High Priority)

These services are essential for homelab operation and should have health checks:

#### Monitoring Stack
```yaml
# Grafana
healthcheck:
  test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://localhost:3000/api/health"]
  interval: 30s
  timeout: 10s
  retries: 3
  start_period: 40s

# Prometheus
healthcheck:
  test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://localhost:9090/-/healthy"]
  interval: 30s
  timeout: 10s
  retries: 3
  start_period: 40s

# Loki
healthcheck:
  test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://localhost:3100/ready"]
  interval: 30s
  timeout: 10s
  retries: 3
  start_period: 40s
```

#### Media Stack
```yaml
# Plex
healthcheck:
  test: ["CMD", "curl", "-f", "http://localhost:32400/web/index.html"]
  interval: 30s
  timeout: 10s
  retries: 3
  start_period: 120s  # Plex takes longer to start

# Jellyfin
healthcheck:
  test: ["CMD", "curl", "-f", "http://localhost:8096/health"]
  interval: 30s
  timeout: 10s
  retries: 3
  start_period: 60s

# Sonarr/Radarr/Prowlarr/Bazarr
healthcheck:
  test: ["CMD", "curl", "-f", "http://localhost:8989/ping"]  # Adjust port per service
  interval: 30s
  timeout: 10s
  retries: 3
  start_period: 40s

# qBittorrent
healthcheck:
  test: ["CMD", "curl", "-f", "http://localhost:8080"]
  interval: 30s
  timeout: 10s
  retries: 3
  start_period: 40s
```

#### Proxy Stack
```yaml
# Nginx Proxy Manager
healthcheck:
  test: ["CMD", "curl", "-f", "http://localhost:81"]
  interval: 30s
  timeout: 10s
  retries: 3
  start_period: 60s

# Cloudflared
healthcheck:
  test: ["CMD", "cloudflared", "tunnel", "info"]
  interval: 30s
  timeout: 10s
  retries: 3
  start_period: 20s
```

### Optional Services (Medium Priority)

```yaml
# Homepage
healthcheck:
  test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://localhost:3000"]
  interval: 30s
  timeout: 10s
  retries: 3
  start_period: 40s

# Nextcloud
healthcheck:
  test: ["CMD", "curl", "-f", "http://localhost/status.php"]
  interval: 30s
  timeout: 10s
  retries: 3
  start_period: 120s
```

## Health Check Types

### 1. HTTP Check (Most Common)
```yaml
test: ["CMD", "curl", "-f", "http://localhost:PORT/health"]
```
- Requires `curl` in container
- Most reliable for web services
- Use `wget` if `curl` not available

### 2. TCP Check
```yaml
test: ["CMD-SHELL", "nc -z localhost PORT"]
```
- Simple port check
- Use when no HTTP endpoint available
- Requires `netcat` in container

### 3. Custom Script
```yaml
test: ["CMD", "/health-check.sh"]
```
- For complex checks
- Needs custom script in container

## Implementation Steps

1. **Add healthcheck to docker-compose.yml** for each service
2. **Restart the stack:**
   ```bash
   docker compose down
   docker compose up -d
   ```
3. **Verify health status:**
   ```bash
   docker ps
   # Look for "(healthy)" status
   ```
4. **Check Grafana dashboard** - Health check metrics should appear

## Common Issues

### Container Shows "unhealthy"
- Check logs: `docker logs <container>`
- Test healthcheck manually: 
  ```bash
  docker exec <container> curl -f http://localhost:PORT
  ```
- Increase `start_period` if service takes long to start
- Increase `retries` if service has intermittent issues

### Health Check Not Appearing in Dashboard
- Wait 1-2 minutes for metrics to populate
- Verify Prometheus is scraping: http://192.168.1.104:9090/targets
- Check `engine_daemon_health_checks_total` metric

## Recommendation

**Start with critical services only:**
1. Monitoring stack (Grafana, Prometheus, Loki)
2. Reverse proxy (Nginx Proxy Manager)
3. Main media servers (Plex/Jellyfin)

**Then expand to:**
4. *arr stack (Sonarr, Radarr, etc.)
5. Download clients (qBittorrent)
6. Other services

This staged approach lets you verify each addition works correctly.

## Next Steps

After implementing health checks, you can:
1. Set up alerts in Grafana for unhealthy containers
2. Monitor health check failure rates
3. Correlate failures with system issues
4. Use as early warning system for problems
