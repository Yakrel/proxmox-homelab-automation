# Loki Connection Issue Fix

## Problem

Promtail containers on LXCs (except monitoring LXC) cannot reach Loki at `192.168.1.104:3100`.

**Error:**
```
error sending batch, will retry" status=-1 tenant= error="Post \"http://192.168.1.104:3100/loki/api/v1/push\": dial tcp 192.168.1.104:3100: connect: no route to host
```

## Root Cause

Promtail containers are running in isolated Docker bridge networks. They cannot reach the host IP `192.168.1.104` from inside the container because:
1. Docker bridge networks are isolated
2. Host IP is not accessible from container's network namespace without `network_mode: host` or port publishing

## Solutions

### Solution 1: Use Host Network Mode for Promtail (RECOMMENDED)

**Pros:**
- Simple configuration
- Direct access to all network interfaces
- No port mapping needed

**Cons:**
- Less network isolation (acceptable for logging agent)

**Implementation:**
Add `network_mode: "host"` to Promtail containers in all docker-compose.yml files.

### Solution 2: Use Docker Internal DNS

**Pros:**
- Maintains network isolation
- Uses Docker's internal networking

**Cons:**
- Requires all Promtails to join monitoring network
- More complex setup

**Not viable** - Promtail containers are on different hosts, cannot join same Docker network.

### Solution 3: Use Loki via Reverse Proxy

**Pros:**
- Centralized access via domain name
- Can add authentication

**Cons:**
- Requires Nginx Proxy Manager setup
- Additional complexity

## Recommended Fix: Host Network Mode

Update each stack's Promtail container to use host networking.

### Files to Modify

1. `docker/proxy/docker-compose.yml` - Add Promtail with host network
2. `docker/media/docker-compose.yml` - Add Promtail with host network
3. `docker/files/docker-compose.yml` - Add Promtail with host network
4. `docker/webtools/docker-compose.yml` - Fix existing Promtail network mode
5. `docker/gameservers/docker-compose.yml` - Add Promtail with host network

### Promtail Service Template

```yaml
  promtail:
    image: grafana/promtail:latest
    container_name: promtail-STACKNAME
    restart: unless-stopped
    network_mode: "host"  # Use host network to access Loki
    volumes:
      - /var/lib/docker/containers:/var/lib/docker/containers:ro
      - /var/log:/var/log:ro
      - /etc/promtail:/etc/promtail:ro
      - /var/lib/promtail/positions:/var/lib/promtail/positions:rw
    command: -config.file=/etc/promtail/promtail.yml
    environment:
      - TZ=${TZ:-Europe/Istanbul}
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
```

**Note:** With `network_mode: "host"`, you cannot use `ports:` directive. Port 9080 will be automatically available.

### Deployment Script Changes

The monitoring deployment script needs to:
1. Add Promtail to all stacks (except monitoring - already has it)
2. Use host network mode
3. Ensure `/etc/promtail/promtail.yml` is created with correct host label

This is already partially implemented in `scripts/modules/monitoring-deployment.sh`.

## Verification After Fix

On each LXC, check Promtail logs:
```bash
docker logs promtail-STACKNAME --tail 50
```

Should see:
```
level=info ts=... msg="Successfully sent batch"
```

Instead of:
```
level=warn ts=... msg="error sending batch, will retry"
```

In Grafana Loki dashboard, you should start seeing logs from all LXCs.
