#!/bin/bash

# =================================================================
#                     Grafana Dashboard Import Module
# =================================================================
# Specialized Grafana dashboard import utility - standalone module
# Used by monitoring-deployment.sh for dashboard automation
set -euo pipefail

WORK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)"

# --- Load Shared Functions ---
source "$WORK_DIR/scripts/helper-functions.sh"

# Import Grafana dashboards via HTTP API
import_grafana_dashboards() {
    local ct_ip="$1"
    local gf_admin_user="$2" 
    local gf_admin_password="$3"
    
    print_info "Importing recommended Grafana dashboards"
    
    # Dashboard #10347: Proxmox via Prometheus (most popular Proxmox dashboard)
    print_info "Importing dashboard #10347 (Proxmox via Prometheus)"
    curl -s "https://grafana.com/api/dashboards/10347/revisions/latest/download" | \
        jq '.dashboard' | \
    curl -s -X POST -H "Content-Type: application/json" -u "$gf_admin_user:$gf_admin_password" -d @- "http://$ct_ip:3000/api/dashboards/import" >/dev/null || {
        print_warning "Failed to import dashboard #10347 - continuing deployment"
    }
    
    # Dashboard #893: Docker and System Monitoring (comprehensive container metrics)  
    print_info "Importing dashboard #893 (Docker and System Monitoring)"
    curl -s "https://grafana.com/api/dashboards/893/revisions/latest/download" | \
        jq '.dashboard' | \
    curl -s -X POST -H "Content-Type: application/json" -u "$gf_admin_user:$gf_admin_password" -d @- "http://$ct_ip:3000/api/dashboards/import" >/dev/null || {
        print_warning "Failed to import dashboard #893 - continuing deployment"
    }
    
    # Dashboard #12611: Logging Dashboard via Loki (official log dashboard)
    print_info "Importing dashboard #12611 (Logging Dashboard via Loki)"
    curl -s "https://grafana.com/api/dashboards/12611/revisions/latest/download" | \
        jq '.dashboard' | \
    curl -s -X POST -H "Content-Type: application/json" -u "$gf_admin_user:$gf_admin_password" -d @- "http://$ct_ip:3000/api/dashboards/import" >/dev/null || {
        print_warning "Failed to import dashboard #12611 - continuing deployment"
    }
    
    print_success "Dashboard import completed"
}

# Configure Prometheus datasource in Grafana  
configure_prometheus_datasource() {
    local ct_ip="$1"
    local gf_admin_user="$2"
    local gf_admin_password="$3"
    
    print_info "Configuring Prometheus datasource"
    
    # Create Prometheus datasource
    local datasource_config=$(cat << 'EOF'
{
  "name": "Prometheus",
  "type": "prometheus", 
  "url": "http://prometheus:9090",
  "access": "proxy",
  "isDefault": true,
  "basicAuth": false
}
EOF
)
    
    echo "$datasource_config" | curl -s -X POST -H "Content-Type: application/json" -u "$gf_admin_user:$gf_admin_password" -d @- "http://$ct_ip:3000/api/datasources" >/dev/null || {
        print_warning "Failed to configure Prometheus datasource - may already exist"
    }
    
    print_success "Prometheus datasource configured"
}

# Configure Loki datasource in Grafana
configure_loki_datasource() {
    local ct_ip="$1"
    local gf_admin_user="$2" 
    local gf_admin_password="$3"
    
    print_info "Configuring Loki datasource"
    
    # Create Loki datasource
    local datasource_config=$(cat << 'EOF'
{
  "name": "Loki",
  "type": "loki",
  "url": "http://loki:3100", 
  "access": "proxy",
  "isDefault": false,
  "basicAuth": false
}
EOF
)
    
    echo "$datasource_config" | curl -s -X POST -H "Content-Type: application/json" -u "$gf_admin_user:$gf_admin_password" -d @- "http://$ct_ip:3000/api/datasources" >/dev/null || {
        print_warning "Failed to configure Loki datasource - may already exist"
    }
    
    print_success "Loki datasource configured"
}

# Main function for complete Grafana setup
setup_grafana_monitoring() {
    local ct_ip="$1"
    local gf_admin_user="${2:-admin}"
    local gf_admin_password="$3"
    
    [[ -z "$gf_admin_password" ]] && {
        print_error "Grafana admin password required"
        exit 1
    }
    
    print_info "Setting up Grafana monitoring dashboards and datasources"
    
    # Wait for Grafana to be ready
    local max_wait=60
    local wait_count=0
    while ! curl -s "http://$ct_ip:3000/api/health" >/dev/null 2>&1; do
        sleep 2
        wait_count=$((wait_count + 2))
        if [[ $wait_count -ge $max_wait ]]; then
            print_error "Grafana not responding after ${max_wait}s"
            exit 1
        fi
    done
    
    print_success "Grafana is ready"
    
    # Configure datasources
    configure_prometheus_datasource "$ct_ip" "$gf_admin_user" "$gf_admin_password"
    configure_loki_datasource "$ct_ip" "$gf_admin_user" "$gf_admin_password"
    
    # Import dashboards
    import_grafana_dashboards "$ct_ip" "$gf_admin_user" "$gf_admin_password"
    
    print_success "Grafana monitoring setup completed"
    print_info "Access Grafana at: http://$ct_ip:3000 (${gf_admin_user}/${gf_admin_password})"
}

# Allow script to be called directly for testing
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [[ $# -lt 3 ]]; then
        print_error "Usage: $0 <ct_ip> <admin_user> <admin_password>"
        print_info "Example: $0 192.168.1.104 admin mypassword"
        exit 1
    fi
    
    setup_grafana_monitoring "$@"
fi