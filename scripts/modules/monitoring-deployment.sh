#!/bin/bash

# =================================================================
#                     Monitoring Stack Module
# =================================================================
# Specialized deployment for monitoring stack - fail fast approach
set -euo pipefail

# Download Grafana dashboards
download_grafana_dashboards() {
    local dashboards_dir="$WORK_DIR/dashboards"
    mkdir -p "$dashboards_dir"
    
    print_info "Downloading Grafana dashboards"
    
    # Dashboard configurations: ID:filename
    local -A dashboards=(
        ["10347"]="proxmox-dashboard.json"
        ["893"]="docker-monitoring.json"
        ["12611"]="loki-dashboard.json"
    )
    
    for dashboard_id in "${!dashboards[@]}"; do
        local filename="${dashboards[$dashboard_id]}"
        local dashboard_url="https://grafana.com/api/dashboards/$dashboard_id/revisions/latest/download"
        
        print_info "Downloading dashboard $dashboard_id -> $filename"
        curl -sSL "$dashboard_url" -o "$dashboards_dir/$filename" || {
            print_error "Failed to download dashboard $dashboard_id"
            exit 1
        }
    done
    
    print_success "Dashboards downloaded"
}

# Setup monitoring environment variables
setup_monitoring_environment() {
    local ct_id="$1"
    
    print_info "Setting up monitoring environment"
    
    # Use already decrypted .env from main flow
    [[ -z "${ENV_DECRYPTED_PATH:-}" || ! -s "$ENV_DECRYPTED_PATH" ]] && {
        print_error ".env file not decrypted"
        exit 1
    }
    
    # PVE_MONITORING_PASSWORD should already be set from main execution
    [[ -z "${PVE_MONITORING_PASSWORD:-}" ]] && { 
        print_error "PVE_MONITORING_PASSWORD not set"
        exit 1
    }
    
    # Read Grafana admin password from .env.enc (already decrypted)
    local gf_admin_password
    gf_admin_password=$(grep '^GF_ADMIN_PASSWORD=' "$ENV_DECRYPTED_PATH" | cut -d'=' -f2)
    [[ -z "$gf_admin_password" ]] && {
        print_error "GF_ADMIN_PASSWORD not found in .env file"
        exit 1
    }
    
    # Create temporary file with static + dynamic values
    local temp_env="/tmp/monitoring_env_temp"
    cat > "$temp_env" << EOF
# Grafana configuration
GF_ADMIN_PASSWORD=$gf_admin_password

# Prometheus configuration  
PVE_USER=pve-exporter@pve
PVE_PASSWORD=$PVE_MONITORING_PASSWORD
PVE_VERIFY_SSL=false

# Timezone
TZ=Europe/Istanbul

# User mappings for containers
PUID=1000
PGID=1000
EOF
    
    # Copy to container
    pct push "$ct_id" "$temp_env" "/root/.env" || { print_error "Failed to configure environment"; exit 1; }
    rm -f "$temp_env"
    
    print_success "Monitoring environment configured"
}

# Configure Prometheus for PBS monitoring
configure_pbs_monitoring() {
    local monitoring_ct_id="$1"
    
    print_info "Configuring Prometheus for PBS monitoring"
    
    local backup_ct_id
    backup_ct_id=$(yq -r ".stacks.backup.ct_id" "$WORK_DIR/stacks.yaml")
    
    if pct status "$backup_ct_id" >/dev/null 2>&1; then
        local pbs_job_config_temp="$WORK_DIR/pbs_job.yml"
        local pbs_ip_address
        pbs_ip_address="$(yq -r ".network.ip_base" "$WORK_DIR/stacks.yaml").$(yq -r ".stacks.backup.ip_octet" "$WORK_DIR/stacks.yaml")"
        
        cat > "$pbs_job_config_temp" << EOF
  - job_name: 'proxmox-backup-server'
    static_configs:
      - targets: ['$pbs_ip_address:8007']
    metrics_path: '/api2/prometheus'
    scheme: https
    tls_config:
      insecure_skip_verify: true
    basic_auth:
      username: 'prometheus@pbs'
      password_file: '/etc/prometheus/.prometheus-password'
EOF
        
        # Copy PBS job config to monitoring container
        pct push "$monitoring_ct_id" "$pbs_job_config_temp" "/tmp/pbs_job.yml" || { print_error "Failed to configure PBS monitoring"; exit 1; }
        rm -f "$pbs_job_config_temp"
        
        # Read current prometheus config and append PBS job
        pct exec "$monitoring_ct_id" -- sh -c 'cat /etc/prometheus/prometheus.yml /tmp/pbs_job.yml > /tmp/prometheus_new.yml && mv /tmp/prometheus_new.yml /etc/prometheus/prometheus.yml'
        pct exec "$monitoring_ct_id" -- rm -f /tmp/pbs_job.yml
        
        print_success "PBS monitoring configured"
    else
        print_info "Backup stack not running, skipping PBS monitoring"
    fi
}

# Setup Promtail configuration
configure_promtail_config() {
    local ct_id="$1"
    
    print_info "Configuring Promtail"
    
    # Create Promtail configuration
    local promtail_config="/tmp/promtail_config.yml"
    cat > "$promtail_config" << 'EOF'
server:
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: /tmp/positions.yaml

clients:
  - url: http://loki:3100/loki/api/v1/push

scrape_configs:
  - job_name: containers
    static_configs:
      - targets:
          - localhost
        labels:
          job: containerlogs
          __path__: /var/lib/docker/containers/*/*log

  - job_name: syslog
    static_configs:
      - targets:
          - localhost
        labels:
          job: syslog
          __path__: /var/log/*log
EOF
    
    # Copy to container
    pct push "$ct_id" "$promtail_config" "/datapool/config/promtail/promtail.yml" || { print_error "Failed to configure Promtail"; exit 1; }
    rm -f "$promtail_config"
    
    print_success "Promtail configured"
}

# Complete monitoring stack deployment
deploy_monitoring_stack() {
    local stack_name="$1"
    local ct_id="$2"
    
    print_info "Deploying monitoring stack"
    
    # Download dashboards before deployment
    download_grafana_dashboards
    
    # Setup monitoring-specific environment
    setup_monitoring_environment "$ct_id"
    
    # Deploy Docker services
    deploy_docker_stack "$stack_name" "$ct_id"
    
    # Configure Promtail
    configure_promtail_config "$ct_id"
    
    # Configure PBS monitoring if backup stack exists
    configure_pbs_monitoring "$ct_id"
    
    print_success "Monitoring stack deployed"
}

# Show monitoring stack information
show_monitoring_info() {
    local ct_id="$1"
    local ct_ip="$2"
    
    print_info ""
    print_info "=== Monitoring Stack ==="
    print_info "Grafana:    http://$ct_ip:3000 (admin/check .grafana-admin-password)"
    print_info "Prometheus: http://$ct_ip:9090"
    print_info "Loki:       http://$ct_ip:3100"
    print_info ""
    print_info "Container: pct exec $ct_id -- bash"
    print_info "Services:  pct exec $ct_id -- docker compose ps"
    print_info ""
}