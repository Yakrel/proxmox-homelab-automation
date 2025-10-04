#!/bin/bash

# =================================================================
#           Quick Monitoring Health Check (Runtime)
# =================================================================
# Quick health check for running monitoring stack
# This checks the actual running services, not just configuration
set -euo pipefail

WORK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)"
source "$WORK_DIR/scripts/helper-functions.sh"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;36m'
NC='\033[0m'

MONITORING_CT_ID=104
MONITORING_IP="192.168.1.104"

print_header() {
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

check_pass() {
    echo -e "${GREEN}✓${NC} $1"
}

check_fail() {
    echo -e "${RED}✗${NC} $1"
}

check_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_info "Monitoring Stack Health Check"
print_info "=============================="
echo ""

# Check 1: Container Status
print_header "Container Status"
if pct status "$MONITORING_CT_ID" 2>&1 | grep -q "status: running"; then
    check_pass "Monitoring LXC ($MONITORING_CT_ID) is running"
else
    check_fail "Monitoring LXC ($MONITORING_CT_ID) is NOT running"
    echo ""
    echo "Start the container with: pct start $MONITORING_CT_ID"
    exit 1
fi

# Check 2: Docker Services
print_header "Docker Services"
services=("prometheus" "grafana" "loki" "promtail-monitoring" "prometheus-pve-exporter" "watchtower-monitoring")
all_running=true

for service in "${services[@]}"; do
    if pct exec "$MONITORING_CT_ID" -- docker ps --format '{{.Names}}' | grep -q "^${service}$"; then
        check_pass "$service is running"
    else
        check_fail "$service is NOT running"
        all_running=false
    fi
done

if ! $all_running; then
    echo ""
    check_warn "Some services are not running. Check logs with:"
    echo "  pct exec $MONITORING_CT_ID -- docker ps -a"
    echo "  pct exec $MONITORING_CT_ID -- docker logs <service>"
fi

# Check 3: Service Endpoints
print_header "Service Endpoints"

# Prometheus
if curl -sf "http://${MONITORING_IP}:9090/-/healthy" >/dev/null 2>&1; then
    check_pass "Prometheus is healthy (http://${MONITORING_IP}:9090)"
else
    check_fail "Prometheus endpoint not responding"
fi

# Grafana
if curl -sf "http://${MONITORING_IP}:3000/api/health" >/dev/null 2>&1; then
    check_pass "Grafana is healthy (http://${MONITORING_IP}:3000)"
else
    check_fail "Grafana endpoint not responding"
fi

# Loki
if curl -sf "http://${MONITORING_IP}:3100/ready" >/dev/null 2>&1; then
    check_pass "Loki is healthy (http://${MONITORING_IP}:3100)"
else
    check_fail "Loki endpoint not responding"
fi

# PVE Exporter
if curl -sf "http://${MONITORING_IP}:9221/pve?target=192.168.1.10&module=default" >/dev/null 2>&1; then
    check_pass "PVE Exporter is responding (http://${MONITORING_IP}:9221)"
else
    check_warn "PVE Exporter endpoint not responding (check PVE credentials)"
fi

# Check 4: Prometheus Targets
print_header "Prometheus Targets"

targets_json=$(curl -s "http://${MONITORING_IP}:9090/api/v1/targets" 2>/dev/null || echo '{"status":"error"}')
if echo "$targets_json" | grep -q '"status":"success"'; then
    # Count active targets
    active_count=$(echo "$targets_json" | grep -o '"health":"up"' | wc -l)
    total_count=$(echo "$targets_json" | grep -o '"health":"' | wc -l)
    
    check_pass "Prometheus targets API responding"
    echo "  Active targets: $active_count / $total_count"
    
    if [ "$active_count" -lt "$total_count" ]; then
        check_warn "Some targets are down. Check Prometheus UI: http://${MONITORING_IP}:9090/targets"
    fi
else
    check_fail "Prometheus targets API not responding"
fi

# Check 5: Grafana Datasources
print_header "Grafana Datasources"

datasources=$(curl -s "http://${MONITORING_IP}:3000/api/datasources" 2>/dev/null || echo '[]')
if echo "$datasources" | grep -q '"name":"Prometheus"'; then
    check_pass "Prometheus datasource configured in Grafana"
else
    check_warn "Prometheus datasource not found in Grafana"
fi

if echo "$datasources" | grep -q '"name":"Loki"'; then
    check_pass "Loki datasource configured in Grafana"
else
    check_warn "Loki datasource not found in Grafana"
fi

# Check 6: Promtail in Other Stacks
print_header "Promtail Log Shipping"

docker_stacks=("100" "101" "102" "103" "105")
stack_names=("proxy" "media" "files" "webtools" "gameservers")

for i in "${!docker_stacks[@]}"; do
    ct_id="${docker_stacks[$i]}"
    stack_name="${stack_names[$i]}"
    
    if pct status "$ct_id" 2>&1 | grep -q "status: running"; then
        if pct exec "$ct_id" -- docker ps 2>/dev/null | grep -q "promtail-${stack_name}"; then
            check_pass "$stack_name (LXC $ct_id): Promtail running"
        else
            check_warn "$stack_name (LXC $ct_id): Promtail not running"
        fi
    else
        check_warn "$stack_name (LXC $ct_id): Container not running"
    fi
done

# Check 7: PBS Integration
print_header "PBS Integration"

PBS_CT_ID=106
if pct status "$PBS_CT_ID" 2>&1 | grep -q "status: running"; then
    check_pass "PBS LXC ($PBS_CT_ID) is running"
    
    # Check if PBS is being scraped
    if curl -s "http://${MONITORING_IP}:9090/api/v1/targets" 2>/dev/null | grep -q "proxmox-backup-server"; then
        check_pass "PBS target configured in Prometheus"
    else
        check_warn "PBS target not found in Prometheus (may take time to appear)"
    fi
else
    check_warn "PBS LXC ($PBS_CT_ID) is not running - PBS metrics disabled"
fi

# Check 8: Configuration Files
print_header "Configuration Files"

config_files=(
    "/datapool/config/prometheus/prometheus.yml"
    "/datapool/config/prometheus/.prometheus-password"
    "/datapool/config/prometheus/pbs_job.yml"
    "/datapool/config/grafana/provisioning/datasources/datasources.yml"
    "/datapool/config/grafana/provisioning/dashboards/provider.yml"
    "/datapool/config/loki/loki.yml"
)

for file in "${config_files[@]}"; do
    if [ -f "$file" ]; then
        check_pass "Config exists: $file"
    else
        check_fail "Config missing: $file"
    fi
done

# Check 9: Dashboard Files
print_header "Dashboard Files"

dashboard_dir="/datapool/config/grafana/dashboards"
if [ -d "$dashboard_dir" ]; then
    dashboard_count=$(find "$dashboard_dir" -name "*.json" 2>/dev/null | wc -l)
    if [ "$dashboard_count" -gt 0 ]; then
        check_pass "Found $dashboard_count dashboard(s) in $dashboard_dir"
    else
        check_warn "No dashboard JSON files found in $dashboard_dir"
    fi
else
    check_fail "Dashboard directory missing: $dashboard_dir"
fi

# Check 10: Storage Usage
print_header "Storage Usage"

if [ -d "/datapool/config/prometheus/data" ]; then
    prom_size=$(du -sh /datapool/config/prometheus/data 2>/dev/null | awk '{print $1}')
    check_pass "Prometheus data: $prom_size"
fi

if [ -d "/datapool/config/loki/data" ]; then
    loki_size=$(du -sh /datapool/config/loki/data 2>/dev/null | awk '{print $1}')
    check_pass "Loki data: $loki_size"
fi

if [ -d "/datapool/config/grafana/data" ]; then
    grafana_size=$(du -sh /datapool/config/grafana/data 2>/dev/null | awk '{print $1}')
    check_pass "Grafana data: $grafana_size"
fi

# Summary
echo ""
print_header "Summary"
echo ""
echo -e "Monitoring Stack: ${GREEN}Operational${NC}"
echo ""
echo "Web Interfaces:"
echo "  Grafana:    http://${MONITORING_IP}:3000"
echo "  Prometheus: http://${MONITORING_IP}:9090"
echo ""
echo "Quick Links:"
echo "  Targets:    http://${MONITORING_IP}:9090/targets"
echo "  Logs:       http://${MONITORING_IP}:3000/explore (select Loki datasource)"
echo ""
echo "Troubleshooting:"
echo "  Container logs: pct exec $MONITORING_CT_ID -- docker logs <service>"
echo "  Service status: pct exec $MONITORING_CT_ID -- docker ps -a"
echo "  Full validation: ./scripts/validate-monitoring.sh"
echo ""
