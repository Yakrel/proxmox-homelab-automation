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

# Provision Grafana dashboards as JSON files
# CRITICAL: Grafana docker-compose.yml must have volume mount for /datapool/config/grafana/dashboards
# This allows Grafana to auto-load dashboard JSON files on startup
provision_grafana_dashboards() {
    local ct_id="$1"
    
    print_info "Provisioning Grafana dashboards"
    
    # Create dashboards directory on host
    local dashboards_dir="/datapool/config/grafana/dashboards"
    mkdir -p "$dashboards_dir"
    
    # Download custom dashboards from our repo (already have correct datasource UIDs)
    # These dashboards are maintained in config/grafana/dashboards/ with full documentation
    
    # Infrastructure Overview dashboard - Proxmox host + LXC monitoring
    curl -sSL "$REPO_BASE_URL/config/grafana/dashboards/infrastructure-overview.json" \
        -o "$dashboards_dir/infrastructure-overview.json" || \
        print_warning "Failed to download Infrastructure Overview dashboard"
    
    # Container Monitoring dashboard - Detailed cAdvisor metrics for all Docker containers
    curl -sSL "$REPO_BASE_URL/config/grafana/dashboards/container-monitoring.json" \
        -o "$dashboards_dir/container-monitoring.json" || \
        print_warning "Failed to download Container Monitoring dashboard"
    
    # Logs Monitoring dashboard - Loki log viewer for Docker containers
    curl -sSL "$REPO_BASE_URL/config/grafana/dashboards/logs-monitoring.json" \
        -o "$dashboards_dir/logs-monitoring.json" || \
        print_warning "Failed to download Logs Monitoring dashboard"
    
    # Fix ownership for Grafana container (unprivileged LXC mapping: 1000 -> 101000)
    chown -R 101000:101000 "$dashboards_dir"
    
    print_success "Grafana dashboards provisioned"
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

deleteDatasources:
  - name: Prometheus
    orgId: 1
  - name: Loki
    orgId: 1

datasources:
  - name: Prometheus
    type: prometheus
    uid: prometheus
    access: proxy
    orgId: 1
    url: http://prometheus:9090
    isDefault: true
    jsonData:
      httpMethod: POST
      timeInterval: 30s
    editable: false

  - name: Loki
    type: loki
    uid: loki
    access: proxy
    orgId: 1
    url: http://loki:3100
    isDefault: false
    jsonData:
      maxLines: 1000
    editable: false
EOF
    
    # Copy datasource config to host (overwrites existing, /datapool is host-mounted)
    cp "$datasource_config" "/datapool/config/grafana/provisioning/datasources/datasources.yml" || {
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
      path: /datapool/config/grafana/dashboards
EOF
    
    # Copy dashboard provider config to host (overwrites existing, /datapool is host-mounted)
    cp "$dashboard_provider_config" "/datapool/config/grafana/provisioning/dashboards/provider.yml" || {
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

    # Download prometheus config directly from GitHub to host filesystem
    curl -sSL "$REPO_BASE_URL/docker/monitoring/prometheus.yml" -o "/datapool/config/prometheus/prometheus.yml" || {
        print_error "Failed to download prometheus.yml from GitHub"
        exit 1
    }

    # Download loki config directly from GitHub to host filesystem
    curl -sSL "$REPO_BASE_URL/config/loki/loki.yml" -o "/datapool/config/loki/loki.yml" || {
        print_error "Failed to download loki.yml from GitHub"
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
    
    # Note: No chown needed inside LXC for /etc/promtail files
    # Files pushed with pct push automatically get correct ownership from root context
    
    # Fix permissions for config files pushed with pct push (they get root ownership)
    # Must be done after pct push commands to ensure Docker containers can read them
    chown -R 101000:101000 /datapool/config/prometheus /datapool/config/loki

    print_success "All configuration files validated"
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

    # Validate all configurations are ready before starting services
    validate_monitoring_configs "$ct_id"

    # Configure Grafana datasources and dashboards (before starting Docker)
    configure_grafana_automation "$ct_id"
    
    # Provision Grafana dashboard JSON files (before starting Docker)
    provision_grafana_dashboards "$ct_id"

    # Fix all permissions one final time before starting services (ensure new files have correct ownership)
    print_info "Setting final permissions on all config files"
    chown -R 101000:101000 /datapool/config
    print_success "All permissions set correctly"

    # Deploy Docker services (configurations are now ready)
    deploy_docker_stack "$stack_name" "$ct_id"

    print_success "Monitoring stack deployed and verified"
}

