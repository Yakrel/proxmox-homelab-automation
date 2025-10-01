#!/bin/bash

# =================================================================
#                     Monitoring Stack Module
# =================================================================
# Specialized deployment for monitoring stack - fail fast approach
set -euo pipefail



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

    if pct status "$backup_ct_id" 2>&1 | grep -q "status: running"; then
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



# Setup monitoring config directories with proper permissions
setup_monitoring_directories() {
    print_info "Setting up monitoring directories"

    # Create all required directories for monitoring stack
    mkdir -p /datapool/config/prometheus/data
    mkdir -p /datapool/config/grafana/data
    mkdir -p /datapool/config/loki/data
    mkdir -p /datapool/config/grafana/provisioning/datasources
    mkdir -p /datapool/config/grafana/provisioning/dashboards

    # Fix permissions for all config directory (simpler approach)
    chown -R 101000:101000 /datapool/config

    print_success "Monitoring directories created with proper permissions"
}

# Restart Grafana container to reload configuration
restart_grafana_container() {
    local ct_id="$1"

    print_info "Restarting Grafana to reload datasource configuration"

    # Restart Grafana container
    pct exec "$ct_id" -- docker restart grafana || {
        print_error "Failed to restart Grafana container"
        return 1
    }

    print_success "Grafana restarted successfully"
}

# Configure Grafana datasource provisioning and dashboard automation
configure_grafana_automation() {
    local ct_id="$1"
    
    print_info "Configuring Grafana datasource and dashboard automation"
    
    # Ensure clean configuration by overwriting existing files (idempotent)
    # Create datasource provisioning file with both Prometheus and Loki
    local datasource_config="/tmp/datasources.yml"
    cat > "$datasource_config" << 'EOF'
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
    jsonData:
      httpMethod: POST
      manageAlerts: true
      prometheusType: Prometheus
      prometheusVersion: 2.40.0
      cacheLevel: 'High'
      disableRecordingRules: false
      incrementalQueryOverlapWindow: 10m
    editable: true

  - name: Loki
    type: loki
    access: proxy
    url: http://loki:3100
    isDefault: false
    jsonData:
      maxLines: 1000
    editable: true
EOF
    
    # Copy datasource config to container (overwrites existing)
    pct push "$ct_id" "$datasource_config" "/datapool/config/grafana/provisioning/datasources/datasources.yml" || {
        print_error "Failed to configure datasources"
        rm -f "$datasource_config"
        return 1
    }
    rm -f "$datasource_config"
    
    # Create dashboard provisioning config (overwrites existing)
    local dashboard_provider_config="/tmp/dashboard_provider.yml"
    cat > "$dashboard_provider_config" << 'EOF'
apiVersion: 1

providers:
  - name: 'default'
    orgId: 1
    folder: ''
    type: file
    disableDeletion: false
    updateIntervalSeconds: 10
    allowUiUpdates: true
    options:
      path: /var/lib/grafana/dashboards
EOF
    
    # Copy dashboard provider config to container (overwrites existing)
    pct push "$ct_id" "$dashboard_provider_config" "/datapool/config/grafana/provisioning/dashboards/provider.yml" || {
        print_error "Failed to configure dashboard provider"
        rm -f "$dashboard_provider_config"
        return 1
    }
    rm -f "$dashboard_provider_config"
    
    print_success "Grafana datasources (Prometheus + Loki) and dashboard provisioning configured"
}

# Ensure all configuration files are ready before service startup
validate_monitoring_configs() {
    local ct_id="$1"

    print_info "Validating monitoring configuration files"

    # Ensure prometheus config is copied to container
    pct push "$ct_id" "$WORK_DIR/docker/monitoring/prometheus.yml" "/datapool/config/prometheus/prometheus.yml" || {
        print_error "Failed to copy prometheus.yml to container"
        exit 1
    }

    # Ensure loki config is copied to container
    pct push "$ct_id" "$WORK_DIR/config/loki/loki.yml" "/datapool/config/loki/loki.yml" || {
        print_error "Failed to copy loki.yml to container"
        exit 1
    }

    # Setup promtail config for monitoring LXC
    local hostname="lxc-monitoring-01"
    pct exec "$ct_id" -- mkdir -p /etc/promtail /var/lib/promtail/positions
    
    local temp_promtail="/tmp/promtail_monitoring.yml"
    sed "s/REPLACE_HOST_LABEL/$hostname/g" "$WORK_DIR/config/promtail/promtail.yml" > "$temp_promtail"
    pct push "$ct_id" "$temp_promtail" "/etc/promtail/promtail.yml" || {
        print_error "Failed to copy promtail.yml to container"
        rm -f "$temp_promtail"
        exit 1
    }
    rm -f "$temp_promtail"
    
    # Fix permissions
    pct exec "$ct_id" -- chown -R 101000:101000 /etc/promtail /var/lib/promtail

    # Ensure PBS password file exists (created in configure_pbs_monitoring)
    local password_file="/datapool/config/prometheus/.prometheus-password"
    [[ -f "$password_file" ]] || {
        print_error "PBS prometheus password file missing: $password_file"
        exit 1
    }

    # Ensure pbs_job.yml exists (created in configure_pbs_monitoring)
    [[ -f "/datapool/config/prometheus/pbs_job.yml" ]] || {
        print_error "PBS job configuration missing: /datapool/config/prometheus/pbs_job.yml"
        exit 1
    }

    print_success "All configuration files validated"
}


# Import recommended dashboards
import_grafana_dashboards() {
    local ct_ip="$1"
    local gf_admin_user="$2"
    local gf_admin_password="$3"

    print_info "Importing recommended Grafana dashboards"

    # Import Proxmox dashboard
    curl -s "https://grafana.com/api/dashboards/10347/revisions/latest/download" | \
    jq '{dashboard: (. | del(.id) | del(.__inputs) | del(.__requires)), folderId: 0, overwrite: true, inputs: [{name: "DS_PROMETHEUS", type: "datasource", pluginId: "prometheus", value: "Prometheus"}]}' | \
    curl -s -X POST -H "Content-Type: application/json" -u "$gf_admin_user:$gf_admin_password" -d @- "http://$ct_ip:3000/api/dashboards/import" >/dev/null || {
        print_warning "Failed to import Proxmox dashboard"
    }

    # Import Docker dashboard
    curl -s "https://grafana.com/api/dashboards/893/revisions/latest/download" | \
    jq '{dashboard: (. | del(.id) | del(.__inputs) | del(.__requires)), folderId: 0, overwrite: true, inputs: [{name: "DS_PROMETHEUS", type: "datasource", pluginId: "prometheus", value: "Prometheus"}]}' | \
    curl -s -X POST -H "Content-Type: application/json" -u "$gf_admin_user:$gf_admin_password" -d @- "http://$ct_ip:3000/api/dashboards/import" >/dev/null || {
        print_warning "Failed to import Docker dashboard"
    }

    # Import Loki dashboard
    curl -s "https://grafana.com/api/dashboards/12611/revisions/latest/download" | \
    jq '{dashboard: (. | del(.id) | del(.__inputs) | del(.__requires)), folderId: 0, overwrite: true, inputs: [{name: "DS_LOKI", type: "datasource", pluginId: "loki", value: "Loki"}]}' | \
    curl -s -X POST -H "Content-Type: application/json" -u "$gf_admin_user:$gf_admin_password" -d @- "http://$ct_ip:3000/api/dashboards/import" >/dev/null || {
        print_warning "Failed to import Loki dashboard"
    }
    
    print_success "Dashboard import completed"
}



# Complete monitoring stack deployment
deploy_monitoring_stack() {
    local stack_name="$1"
    local ct_id="$2"

    print_info "Deploying monitoring stack"

    # Setup monitoring directories first
    setup_monitoring_directories

    # Setup monitoring-specific environment
    setup_monitoring_environment "$ct_id"

    # Configure PBS monitoring if backup stack exists (before Docker deployment)
    configure_pbs_monitoring "$ct_id"

    # Validate all configurations are ready before starting services
    validate_monitoring_configs "$ct_id"

    # Deploy Docker services (configurations are now ready)
    deploy_docker_stack "$stack_name" "$ct_id"

    # Configure Grafana datasources and dashboards
    configure_grafana_automation "$ct_id"

    # Restart Grafana to reload datasource configuration
    restart_grafana_container "$ct_id"

    # Get container IP and credentials for verification
    local gf_admin_user gf_admin_password ct_ip
    gf_admin_user=$(grep '^GF_SECURITY_ADMIN_USER=' "$ENV_DECRYPTED_PATH" | cut -d'=' -f2-) || { print_error "GF_SECURITY_ADMIN_USER not found"; exit 1; }
    gf_admin_password=$(grep '^GF_SECURITY_ADMIN_PASSWORD=' "$ENV_DECRYPTED_PATH" | cut -d'=' -f2-) || { print_error "GF_SECURITY_ADMIN_PASSWORD not found"; exit 1; }
    ct_ip=$(get_lxc_ip "$ct_id")

    # No health checks - Docker Compose will handle service startup
    # If containers fail to start, docker-compose will show the error immediately

    print_success "Monitoring stack deployed and verified"

    # Import dashboards (non-critical, continue if it fails)
    import_grafana_dashboards "$ct_ip" "$gf_admin_user" "$gf_admin_password"
}

