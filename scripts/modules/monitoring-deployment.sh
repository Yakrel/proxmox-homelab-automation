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
    
    # Read Grafana configuration from .env.enc (already decrypted)
    local gf_admin_user gf_admin_password
    gf_admin_user=$(grep '^GF_SECURITY_ADMIN_USER=' "$ENV_DECRYPTED_PATH" | cut -d'=' -f2-)
    gf_admin_password=$(grep '^GF_SECURITY_ADMIN_PASSWORD=' "$ENV_DECRYPTED_PATH" | cut -d'=' -f2-)
    [[ -z "$gf_admin_password" ]] && {
        print_error "GF_SECURITY_ADMIN_PASSWORD not found in .env file"
        exit 1
    }
    
    # Read additional config values from .env
    local pve_url pve_user pve_verify_ssl
    pve_url=$(grep '^PVE_URL=' "$ENV_DECRYPTED_PATH" | cut -d'=' -f2-)
    pve_user=$(grep '^PVE_USER=' "$ENV_DECRYPTED_PATH" | cut -d'=' -f2-)
    pve_verify_ssl=$(grep '^PVE_VERIFY_SSL=' "$ENV_DECRYPTED_PATH" | cut -d'=' -f2-)
    
    # Create temporary file with static + dynamic values
    local temp_env="/tmp/monitoring_env_temp"
    cat > "$temp_env" << EOF
# Grafana configuration
GF_SECURITY_ADMIN_USER=$gf_admin_user
GF_SECURITY_ADMIN_PASSWORD=$gf_admin_password

# Prometheus configuration  
PVE_USER=${pve_user:-pve-exporter@pve}
PVE_PASSWORD=$PVE_MONITORING_PASSWORD
PVE_URL=${pve_url:-https://192.168.1.10:8006}
PVE_VERIFY_SSL=${pve_verify_ssl:-false}

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

    # Read PBS prometheus password from .env file using parameter expansion for robust parsing
    local pbs_prometheus_password
    local pbs_line
    pbs_line=$(grep '^PBS_PROMETHEUS_PASSWORD=' "$ENV_DECRYPTED_PATH")
    [[ -z "$pbs_line" ]] && {
        print_error "PBS_PROMETHEUS_PASSWORD not found in .env file"
        return 1
    }
    # Use parameter expansion to handle passwords containing '=' characters
    pbs_prometheus_password="${pbs_line#*=}"
    [[ -z "$pbs_prometheus_password" ]] && {
        print_error "PBS_PROMETHEUS_PASSWORD value is empty"
        return 1
    }

    # Create PBS prometheus password file on host datapool (accessible to monitoring container)
    print_info "Creating PBS prometheus password file"
    mkdir -p /datapool/config/prometheus/

    # Create password file securely with restricted permissions from the start
    local password_file="/datapool/config/prometheus/.prometheus-password"

    # Set umask to ensure secure file creation, then restore original
    local original_umask
    original_umask=$(umask)
    umask 077

    printf '%s' "$pbs_prometheus_password" > "$password_file" || {
        umask "$original_umask"
        print_error "Failed to create PBS prometheus password file"
        return 1
    }

    # Restore original umask
    umask "$original_umask"

    # Set correct ownership for container access (unprivileged LXC mapping: 1000 -> 101000)
    chown 101000:101000 "$password_file"

    # Check if backup stack is running for PBS target configuration
    local backup_ct_id
    backup_ct_id=$(yq -r ".stacks.backup.ct_id" "$WORK_DIR/stacks.yaml")

    if pct status "$backup_ct_id" >/dev/null 2>&1; then
        # Cache network values to avoid repeated yq calls
        local ip_base ip_octet pbs_ip_address
        ip_base=$(yq -r ".network.ip_base" "$WORK_DIR/stacks.yaml")
        ip_octet=$(yq -r ".stacks.backup.ip_octet" "$WORK_DIR/stacks.yaml")
        pbs_ip_address="${ip_base}.${ip_octet}"

        # Create PBS targets configuration for file service discovery (array format required)
        local pbs_job_config_temp="$WORK_DIR/pbs_targets.yml"
        cat > "$pbs_job_config_temp" << EOF
[
  {
    "targets": ["$pbs_ip_address:8007"],
    "labels": {
      "instance": "proxmox-backup-server"
    }
  }
]
EOF

        # Copy PBS targets to monitoring container datapool (prometheus file_sd_configs will read this)
        pct push "$monitoring_ct_id" "$pbs_job_config_temp" "/datapool/config/prometheus/pbs_job.yml" || {
            print_error "Failed to configure PBS targets"
            return 1
        }
        rm -f "$pbs_job_config_temp"

        print_success "PBS monitoring configured with target: $pbs_ip_address:8007"
    else
        # Create empty targets file so prometheus doesn't fail (consistent with pct push pattern)
        local empty_targets_temp="$WORK_DIR/pbs_empty_targets.yml"
        echo "[]" > "$empty_targets_temp"
        pct push "$monitoring_ct_id" "$empty_targets_temp" "/datapool/config/prometheus/pbs_job.yml" || {
            print_error "Failed to create empty PBS targets file"
            rm -f "$empty_targets_temp"
            return 1
        }
        rm -f "$empty_targets_temp"
        print_info "PBS stack not running - PBS monitoring disabled (empty targets)"
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

    # Check PBS monitoring status
    local backup_ct_id
    backup_ct_id=$(yq -r ".stacks.backup.ct_id" "$WORK_DIR/stacks.yaml")
    local pbs_status="Disabled (PBS stack not found)"

    if pct status "$backup_ct_id" >/dev/null 2>&1; then
        # Use cached network values for consistency
        local ip_base ip_octet
        ip_base=$(yq -r ".network.ip_base" "$WORK_DIR/stacks.yaml")
        ip_octet=$(yq -r ".stacks.backup.ip_octet" "$WORK_DIR/stacks.yaml")
        pbs_status="Active (monitoring PBS at ${ip_base}.${ip_octet}:8007)"
    fi

    print_info ""
    print_info "=== Monitoring Stack ==="
    print_info "Grafana:     http://$ct_ip:3000 (admin/check .grafana-admin-password)"
    print_info "Prometheus:  http://$ct_ip:9090"
    print_info "Loki:        http://$ct_ip:3100"
    print_info "PBS Monitor: $pbs_status"
    print_info ""
    print_info "Container: pct exec $ct_id -- bash"
    print_info "Services:  pct exec $ct_id -- docker compose ps"
    print_info "Config:    /datapool/config/prometheus/"
    print_info ""
}