#!/bin/bash

# =================================================================
#                     Monitoring Stack Module
# =================================================================
# Specialized deployment for monitoring stack - fail fast approach
set -euo pipefail

MONITORING_PVE_USER="pve-exporter@pve"
MONITORING_PVE_VERIFY_SSL="false"

read_env_value() {
    local key="$1"

    awk -v key="$key" 'index($0, key "=") == 1 { print substr($0, length(key) + 2); exit }'
}

normalize_monitoring_verify_ssl() {
    MONITORING_PVE_VERIFY_SSL="${MONITORING_PVE_VERIFY_SSL:-false}"
    MONITORING_PVE_VERIFY_SSL="${MONITORING_PVE_VERIFY_SSL,,}"

    case "$MONITORING_PVE_VERIFY_SSL" in
        true|false)
            ;;
        *)
            print_error "PVE_VERIFY_SSL must be true or false"
            exit 1
            ;;
    esac
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
    # Optimization: Read file once and parse variables to avoid multiple file reads
    local gf_admin_user gf_admin_password pve_url pve_user pve_verify_ssl
    local diun_telegram_token diun_telegram_chat_ids diun_telegram_template_body
    local env_content
    
    env_content=$(cat "$ENV_DECRYPTED_PATH")
    
    gf_admin_user=$(read_env_value GF_SECURITY_ADMIN_USER <<< "$env_content")
    gf_admin_password=$(read_env_value GF_SECURITY_ADMIN_PASSWORD <<< "$env_content")
    pve_url=$(read_env_value PVE_URL <<< "$env_content")
    pve_user=$(read_env_value PVE_USER <<< "$env_content")
    pve_verify_ssl=$(read_env_value PVE_VERIFY_SSL <<< "$env_content")
    diun_telegram_token=$(read_env_value DIUN_TELEGRAM_TOKEN <<< "$env_content")
    diun_telegram_chat_ids=$(read_env_value DIUN_TELEGRAM_CHAT_IDS <<< "$env_content")
    diun_telegram_template_body=$(read_env_value DIUN_TELEGRAM_TEMPLATE_BODY <<< "$env_content")
    MONITORING_PVE_USER="${pve_user:-pve-exporter@pve}"
    MONITORING_PVE_VERIFY_SSL="${pve_verify_ssl:-false}"
    normalize_monitoring_verify_ssl
    
    [[ -z "$gf_admin_password" ]] && {
        print_error "GF_SECURITY_ADMIN_PASSWORD not found in .env file"
        exit 1
    }
    
    # Create temporary file with static + dynamic values
    local temp_env="/tmp/monitoring_env_temp"
    cat > "$temp_env" << EOF
# Grafana configuration
GF_SECURITY_ADMIN_USER=$gf_admin_user
GF_SECURITY_ADMIN_PASSWORD=$gf_admin_password

# Prometheus configuration  
PVE_USER=$MONITORING_PVE_USER
PVE_PASSWORD=$PVE_MONITORING_PASSWORD
PVE_URL=${pve_url:-https://192.168.1.10:8006}
PVE_VERIFY_SSL=$MONITORING_PVE_VERIFY_SSL

# Timezone
TZ=Europe/Istanbul

# User mappings for containers
PUID=1000
PGID=1000

# Diun Telegram Notifications
DIUN_TELEGRAM_TOKEN=$diun_telegram_token
DIUN_TELEGRAM_CHAT_IDS=$diun_telegram_chat_ids
DIUN_TELEGRAM_TEMPLATE_BODY=$diun_telegram_template_body
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
    mkdir -p /datapool/config/prometheus/recording-rules
    mkdir -p /datapool/config/grafana/data
    mkdir -p /datapool/config/loki/data
    mkdir -p /datapool/config/grafana/provisioning/datasources
    mkdir -p /datapool/config/grafana/provisioning/dashboards
    mkdir -p /datapool/config/grafana/dashboards
    mkdir -p /datapool/config/prometheus-pve-exporter

    # Fresh deploy needs these user-mapped write roots owned by the LXC user.
    # Keep Loki shallow: chunks can contain thousands of small files.
    fix_path_owner /datapool/config/prometheus
    fix_path_owner /datapool/config/prometheus/data
    fix_path_owner /datapool/config/prometheus/recording-rules
    fix_path_owner /datapool/config/grafana
    fix_path_owner /datapool/config/grafana/data
    fix_path_owner /datapool/config/grafana/provisioning
    fix_path_owner /datapool/config/grafana/provisioning/datasources
    fix_path_owner /datapool/config/grafana/provisioning/dashboards
    fix_path_owner /datapool/config/grafana/dashboards
    fix_path_owner /datapool/config/loki
    fix_path_owner /datapool/config/loki/data
    fix_path_owner_recursive /datapool/config/prometheus-pve-exporter

    print_success "Monitoring directories created"
}

fix_monitoring_config_ownership() {
    fix_path_owner /datapool/config/prometheus/prometheus.yml
    fix_path_owner_recursive /datapool/config/prometheus/rules
    fix_path_owner_recursive /datapool/config/prometheus/recording-rules
    fix_path_owner /datapool/config/loki/loki.yml
    fix_path_owner /datapool/config/grafana/provisioning/datasources/datasources.yml
    fix_path_owner /datapool/config/grafana/provisioning/dashboards/provider.yml
    fix_path_owner_recursive /datapool/config/grafana/dashboards
    fix_path_owner_recursive /datapool/config/prometheus-pve-exporter
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
    
    # Copy custom dashboards from our local workspace (already have correct datasource UIDs)
    # These dashboards are maintained in config/grafana/dashboards/ with full documentation
    
    local dashboards=("infrastructure-overview" "container-monitoring" "logs-monitoring")
    local failed_dashboards=()
    
    for dashboard in "${dashboards[@]}"; do
        local source_file="$WORK_DIR/config/grafana/dashboards/${dashboard}.json"
        local dest_file="$dashboards_dir/${dashboard}.json"
        
        if [[ -f "$source_file" ]]; then
            cp "$source_file" "$dest_file" || failed_dashboards+=("${dashboard}")
        else
            print_warning "Dashboard file not found: $source_file"
            failed_dashboards+=("${dashboard}")
        fi
    done
    
    # Report warnings for failed dashboards after all complete
    for dashboard in "${failed_dashboards[@]}"; do
        print_warning "Failed to copy ${dashboard} dashboard"
    done
    
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

    # Copy prometheus config directly from local workspace to host filesystem
    local prom_source="$WORK_DIR/docker/monitor/prometheus.yml"
    if [[ -f "$prom_source" ]]; then
        cp "$prom_source" "/datapool/config/prometheus/prometheus.yml" || {
            print_error "Failed to copy prometheus.yml"
            exit 1
        }
    else
        print_error "prometheus.yml not found at $prom_source"
        exit 1
    fi

    # Copy loki config directly from local workspace to host filesystem
    local loki_source="$WORK_DIR/config/loki/loki.yml"
    if [[ -f "$loki_source" ]]; then
        cp "$loki_source" "/datapool/config/loki/loki.yml" || {
            print_error "Failed to copy loki.yml"
            exit 1
        }
    else
        print_error "loki.yml not found at $loki_source"
        exit 1
    fi

    # Copy prometheus rules and recording rules
    if [[ -d "$WORK_DIR/config/prometheus/rules" ]]; then
        cp -r "$WORK_DIR/config/prometheus/rules" /datapool/config/prometheus/ || {
            print_error "Failed to copy prometheus rules"
            exit 1
        }
    else
        print_error "Prometheus rules directory not found"
        exit 1
    fi

    if [[ -d "$WORK_DIR/config/prometheus/recording-rules" ]]; then
        cp -r "$WORK_DIR/config/prometheus/recording-rules" /datapool/config/prometheus/ || {
            print_error "Failed to copy prometheus recording rules"
            exit 1
        }
    else
        print_error "Prometheus recording-rules directory not found"
        exit 1
    fi

    # Create PVE exporter config using credentials from .env
    mkdir -p /datapool/config/prometheus-pve-exporter
    cat > /datapool/config/prometheus-pve-exporter/pve.yml << EOF
default:
  user: ${MONITORING_PVE_USER}
  password: ${PVE_MONITORING_PASSWORD}
  verify_ssl: ${MONITORING_PVE_VERIFY_SSL}
EOF

    # Setup promtail config for monitor LXC
    local hostname="lxc-monitor"
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

    fix_monitoring_config_ownership

    # Deploy Docker services (configurations are now ready)
    deploy_docker_stack "$stack_name" "$ct_id"

    print_success "Monitoring stack deployed and verified"
}
