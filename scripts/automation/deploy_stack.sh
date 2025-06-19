#!/bin/bash

# Automated Stack Deployment Script
# Downloads latest docker-compose files from GitHub and deploys them

set -e

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../utils/common.sh"

# Configuration
# Repository URL - configurable branch
BRANCH="${HOMELAB_BRANCH:-main}"
GITHUB_REPO="https://raw.githubusercontent.com/Yakrel/proxmox-homelab-automation/$BRANCH"
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

# Docker Compose command (Alpine Docker template uses V2 syntax)
DOCKER_COMPOSE_CMD="docker compose"

# Function to validate environment file (idempotent helper)
validate_env_file() {
    local lxc_id=$1
    local env_file=$2
    local stack_type=$3
    
    # Check if file exists
    if ! pct exec "$lxc_id" -- test -f "$env_file" 2>/dev/null; then
        return 1
    fi
    
    # Define required variables per stack type
    local required_vars=""
    case "$stack_type" in
        "monitoring")
            required_vars="GRAFANA_ADMIN_PASSWORD PVE_PASSWORD PVE_URL"
            ;;
        "proxy")
            required_vars="CLOUDFLARED_TOKEN"
            ;;
        "downloads")
            required_vars="JDOWNLOADER_VNC_PASSWORD"
            ;;
        "utility")
            required_vars="FIREFOX_VNC_PASSWORD"
            ;;
        "media")
            # Media stack has optional vars, just check basic ones
            required_vars="TZ PUID PGID"
            ;;
        *)
            return 0  # Unknown stack, assume valid
            ;;
    esac
    
    # Check each required variable
    for var in $required_vars; do
        if ! pct exec "$lxc_id" -- grep -q "^${var}=" "$env_file" 2>/dev/null; then
            print_warning "Missing required variable: $var"
            return 1
        fi
        
        # Check if value is not empty
        local value=$(pct exec "$lxc_id" -- grep "^${var}=" "$env_file" 2>/dev/null | cut -d'=' -f2- | tr -d '"')
        if [ -z "$value" ]; then
            print_warning "Empty value for required variable: $var"
            return 1
        fi
    done
    
    return 0
}

# Function to backup existing env file
backup_env_file() {
    local lxc_id=$1
    local env_file=$2
    
    if pct exec "$lxc_id" -- test -f "$env_file" 2>/dev/null; then
        local backup_file="${env_file}.backup.$(date +%Y%m%d_%H%M%S)"
        pct exec "$lxc_id" -- cp "$env_file" "$backup_file" 2>/dev/null
        print_info "✓ Backed up existing .env to $(basename "$backup_file")"
    fi
}

# Function to ensure container and Docker are ready (idempotent)
ensure_container_ready() {
    local lxc_id=$1
    
    # Check if container exists
    if ! pct status "$lxc_id" >/dev/null 2>&1; then
        print_error "LXC $lxc_id does not exist!"
        return 1
    fi
    
    # Start container if not running
    if ! pct status "$lxc_id" | grep -q "running"; then
        print_info "Starting container $lxc_id..."
        pct start "$lxc_id"
    fi
    
    # Wait for container readiness
    local max_attempts=15
    local attempt=1
    
    print_info "Waiting for container to be ready..."
    while [ $attempt -le $max_attempts ]; do
        if pct exec "$lxc_id" -- echo "ready" >/dev/null 2>&1; then
            break
        fi
        sleep 3
        attempt=$((attempt + 1))
    done
    
    # Check Docker service
    attempt=1
    while [ $attempt -le $max_attempts ]; do
        if pct exec "$lxc_id" -- docker info >/dev/null 2>&1; then
            print_info "✓ Container and Docker ready"
            return 0
        fi
        
        if [ $attempt -eq 5 ]; then
            print_info "Docker not ready, restarting service..."
            pct exec "$lxc_id" -- rc-service docker restart >/dev/null 2>&1 || true
        fi
        
        sleep 3
        attempt=$((attempt + 1))
    done
    
    print_warning "Container readiness check timeout, continuing anyway..."
    return 0
}

# Function to ensure proper datapool permissions
ensure_datapool_permissions() {
    local stack_type=$1
    
    # Ensure base datapool config directory exists and has proper permissions
    mkdir -p /datapool/config 2>/dev/null || true
    chown -R 101000:101000 /datapool/config 2>/dev/null || {
        print_warning "Could not set ownership on /datapool/config"
        print_info "This may be normal if not running on Proxmox host"
    }
    
    # Create stack-specific config directories as needed
    case $stack_type in
        "media")
            mkdir -p /datapool/config/{sonarr,radarr,bazarr,jellyfin,jellyseerr,qbittorrent,prowlarr} 2>/dev/null || true
            mkdir -p /datapool/{torrents,media}/{movies,tv,other} 2>/dev/null || true
            ;;
        "monitoring")
            mkdir -p /datapool/config/monitoring/{grafana,prometheus,alertmanager} 2>/dev/null || true
            ;;
        "utility")
            mkdir -p /datapool/config/{homepage,firefox} 2>/dev/null || true
            ;;
        "downloads")
            mkdir -p /datapool/config/{jdownloader2,metube} 2>/dev/null || true
            ;;
        "proxy")
            mkdir -p /datapool/config/cloudflared 2>/dev/null || true
            ;;
    esac
    
    # Set consistent ownership
    chown -R 101000:101000 /datapool/config 2>/dev/null || true
    
    return 0
}

# Function to download files from GitHub
download_stack_files() {
    local stack_type=$1
    local target_dir=$2
    
    print_step "Downloading $stack_type stack files from GitHub..."
    
    # Create target directory if it doesn't exist
    mkdir -p "$target_dir"
    
    # Download docker-compose.yml
    print_info "Downloading docker-compose.yml..."
    wget -q -O "$target_dir/docker-compose.yml" "$GITHUB_REPO/docker/$stack_type/docker-compose.yml"
    
    if [ $? -ne 0 ]; then
        print_error "Failed to download docker-compose.yml for $stack_type"
        return 1
    fi
    
    # Download .env.example
    print_info "Downloading .env.example..."
    wget -q -O "$target_dir/.env.example" "$GITHUB_REPO/docker/$stack_type/.env.example"
    
    if [ $? -ne 0 ]; then
        print_warning "Failed to download .env.example for $stack_type (may not exist)"
    fi
    
    # Download additional config files for monitoring stack
    if [ "$stack_type" = "monitoring" ]; then
        print_info "Downloading monitoring configuration files..."
        wget -q -O "$target_dir/prometheus.yml" "$GITHUB_REPO/docker/monitoring/prometheus.yml"
        wget -q -O "$target_dir/alertmanager.yml" "$GITHUB_REPO/docker/monitoring/alertmanager.yml"
        
        if [ $? -ne 0 ]; then
            print_warning "Failed to download some monitoring config files"
        fi
    fi
    
    print_info "✓ Stack files downloaded successfully"
    return 0
}

# Function to setup environment file with validation (idempotent)
setup_env_file() {
    local stack_dir=$1
    local stack_type=$2
    local lxc_id=$3
    
    print_step "Setting up environment file..."
    
    # Check if .env exists and is valid
    if validate_env_file "$lxc_id" "$stack_dir/.env" "$stack_type"; then
        print_info "✓ Existing .env file is valid, preserving configuration"
        return 0
    fi
    
    # If .env exists but invalid, back it up
    if pct exec "$lxc_id" -- test -f "$stack_dir/.env" 2>/dev/null; then
        print_warning "Existing .env file is incomplete, backing up and recreating..."
        backup_env_file "$lxc_id" "$stack_dir/.env"
    else
        print_info "No .env file found, creating new configuration..."
    fi
    
    # Download and run interactive setup script
    local interactive_script="$TEMP_DIR/interactive_setup.sh"
    if [ ! -f "$interactive_script" ]; then
        wget -q -O "$interactive_script" "$GITHUB_REPO/scripts/automation/interactive_setup.sh"
        chmod +x "$interactive_script"
    fi
    
    # Run interactive setup for this stack type
    bash "$interactive_script" "$stack_type" "$(dirname $stack_dir)"
    
    # Validate the newly created .env file
    if validate_env_file "$lxc_id" "$stack_dir/.env" "$stack_type"; then
        print_info "✓ Environment configuration completed successfully"
        return 0
    else
        print_error "Failed to create valid .env file"
        return 1
    fi
}

# Function to deploy stack with Docker Compose
deploy_with_compose() {
    local stack_dir=$1
    local stack_type=$2
    
    print_step "Deploying $stack_type stack with Docker Compose..."
    
    cd "$stack_dir"
    
    # Pull latest images
    print_info "Pulling latest Docker images..."
    $DOCKER_COMPOSE_CMD pull
    
    if [ $? -ne 0 ]; then
        print_warning "Some images failed to pull, continuing anyway..."
    fi
    
    # Start services
    print_info "Starting services..."
    $DOCKER_COMPOSE_CMD up -d
    
    if [ $? -eq 0 ]; then
        print_info "✓ $stack_type stack deployed successfully!"
        
        # Show running containers
        print_info "Running containers:"
        $DOCKER_COMPOSE_CMD ps
        
        return 0
    else
        print_error "Failed to deploy $stack_type stack"
        return 1
    fi
}

# Function to ensure datapool mount exists (idempotent)
ensure_datapool_mount() {
    local lxc_id=$1
    
    # Check if mount point is already configured
    if pct config "$lxc_id" | grep -q "/datapool"; then
        print_info "✓ /datapool mount point already configured"
        
        # Verify accessibility if container is running
        if pct status "$lxc_id" | grep -q "running"; then
            if pct exec "$lxc_id" -- test -d /datapool 2>/dev/null; then
                print_info "✓ /datapool is accessible"
            else
                print_warning "/datapool mount configured but not accessible, container may need restart"
            fi
        fi
        return 0
    fi
    
    print_info "Adding /datapool mount point..."
    
    # Use the create_alpine_lxc.sh mount function
    local script_dir="$(dirname "$0")"
    local create_script="$script_dir/create_alpine_lxc.sh"
    
    if [ -f "$create_script" ]; then
        # Verify script integrity before sourcing
        if ! bash -n "$create_script" 2>/dev/null; then
            print_error "Syntax error in create_alpine_lxc.sh, using fallback method"
        else
            # Safely source the function from create_alpine_lxc.sh
            source "$create_script"
            ensure_datapool_mount "$lxc_id"
            return $?
        fi
    fi
    
    # Fallback to simple mount add if source fails or file doesn't exist
    local was_running=false
    if pct status "$lxc_id" | grep -q "running"; then
        was_running=true
        pct shutdown "$lxc_id" 2>/dev/null || pct stop "$lxc_id"
        sleep 5
    fi
    
    local next_mp_index=$(pct config "$lxc_id" | grep -o 'mp[0-9]\+' | sort -V | tail -n 1 | grep -o '[0-9]\+' | awk '{print $1+1}' 2>/dev/null)
    next_mp_index=${next_mp_index:-0}
    
    if pct set "$lxc_id" -mp${next_mp_index} /datapool,mp=/datapool,acl=1; then
        if [ "$was_running" = true ]; then
            pct start "$lxc_id"
            sleep 5
        fi
        print_info "✓ Datapool mount added successfully"
    else
        print_error "Failed to add datapool mount"
        return 1
    fi
    
    return 0
}



# Function to deploy Homepage dashboard configuration
deploy_homepage_configs() {
    local lxc_id=$1
    
    print_info "Deploying Homepage dashboard configuration..."
    
    # Create homepage config directory
    pct exec "$lxc_id" -- mkdir -p /datapool/config/homepage 2>/dev/null
    
    # Download and deploy each config file
    local config_files=("bookmarks.yaml" "docker.yaml" "services.yaml" "settings.yaml" "widgets.yaml")
    local success_count=0
    
    for config_file in "${config_files[@]}"; do
        local temp_file="$TEMP_DIR/$config_file"
        local target_path="/datapool/config/homepage/$config_file"
        
        # Download config file
        if wget -q -O "$temp_file" "$GITHUB_REPO/config/homepage/$config_file" 2>/dev/null; then
            # Check if file already exists and is identical
            if pct exec "$lxc_id" -- test -f "$target_path" 2>/dev/null; then
                # Compare files to avoid unnecessary overwrites
                if pct exec "$lxc_id" -- md5sum "$target_path" 2>/dev/null | cut -d' ' -f1 | \
                   { read existing_md5; [ "$(md5sum "$temp_file" | cut -d' ' -f1)" = "$existing_md5" ]; }; then
                    print_info "✓ $config_file already up-to-date"
                    success_count=$((success_count + 1))
                    continue
                fi
                
                # Backup existing file
                local backup_name="${config_file}.backup.$(date +%Y%m%d_%H%M%S)"
                pct exec "$lxc_id" -- cp "$target_path" "/datapool/config/homepage/$backup_name" 2>/dev/null
                print_info "Backed up existing $config_file to $backup_name"
            fi
            
            # Copy new file to container
            if pct push "$lxc_id" "$temp_file" "$target_path" 2>/dev/null; then
                print_info "✓ Deployed $config_file"
                success_count=$((success_count + 1))
            else
                print_warning "Failed to deploy $config_file"
            fi
        else
            print_warning "Failed to download $config_file"
        fi
    done
    
    # Set proper permissions (consistent with other stack setup scripts)
    # All LXC setup scripts use host-side 101000:101000 for unprivileged containers
    # Docker containers use PUID=1000, LXC mapping: 1000 → 101000
    chown -R 101000:101000 /datapool/config/homepage 2>/dev/null || {
        print_warning "Failed to set ownership to 101000:101000"
        print_info "Ensure /datapool is accessible and you have proper permissions"
    }
    chmod -R 644 /datapool/config/homepage/*.yaml 2>/dev/null || true
    
    if [ $success_count -eq ${#config_files[@]} ]; then
        print_info "✓ All Homepage configuration files deployed successfully"
        return 0
    elif [ $success_count -gt 0 ]; then
        print_warning "Partially deployed Homepage configs ($success_count/${#config_files[@]} files)"
        return 0
    else
        print_error "Failed to deploy Homepage configuration files"
        return 1
    fi
}

# Function to deploy monitoring stack specific configs
deploy_monitoring_configs() {
    local lxc_id=$1
    
    print_info "Deploying monitoring configuration files..."
    
    # Create monitoring config directories
    pct exec "$lxc_id" -- mkdir -p /datapool/config/monitoring/alertmanager 2>/dev/null
    pct exec "$lxc_id" -- mkdir -p /datapool/config/monitoring/grafana 2>/dev/null
    pct exec "$lxc_id" -- mkdir -p /datapool/config/monitoring/prometheus 2>/dev/null
    
    # These files are already handled by download_stack_files function
    print_info "✓ Monitoring config directories prepared"
    
    return 0
}




# Function to ensure PVE monitoring user exists (idempotent)
ensure_pve_monitoring_user() {
    local pve_user=$1
    local pve_password=$2
    
    print_info "Ensuring Proxmox monitoring user exists..."
    
    # Always try to set password (works for both existing and new users)
    if pveum user list | grep -q "^$pve_user:"; then
        print_info "User $pve_user exists, updating password..."
        if pveum passwd "$pve_user" --password "$pve_password" >/dev/null 2>&1; then
            print_info "✓ Password updated successfully"
        else
            print_warning "Password update failed, continuing..."
        fi
    else
        print_info "Creating user $pve_user..."
        if pveum user add "$pve_user" --password "$pve_password" --comment "Monitoring user for Prometheus PVE exporter" >/dev/null 2>&1; then
            print_info "✓ User created successfully"
        else
            # Try to update password in case user was created by another process
            if pveum passwd "$pve_user" --password "$pve_password" >/dev/null 2>&1; then
                print_info "✓ User existed, password updated"
            else
                print_error "Failed to create or update user $pve_user"
                return 1
            fi
        fi
    fi
    
    # Ensure PVEAuditor role is assigned (idempotent)
    if pveum acl list | grep -q "$pve_user.*PVEAuditor"; then
        print_info "✓ PVEAuditor role already assigned"
    else
        print_info "Assigning PVEAuditor role..."
        if pveum acl modify / --users "$pve_user" --roles PVEAuditor >/dev/null 2>&1; then
            print_info "✓ Role assigned successfully"
        else
            print_warning "Failed to assign role, but continuing..."
        fi
    fi
    
    print_info "✓ PVE monitoring user ready"
    return 0
}


# Function to generate monitoring configuration files with environment variables
generate_monitoring_configs() {
    local lxc_id=$1
    local stack_dir=$2
    
    print_info "Generating monitoring configuration files..."
    
    # Read network configuration from .env file
    local network_base=$(pct exec "$lxc_id" -- grep "^NETWORK_BASE=" "$stack_dir/.env" 2>/dev/null | cut -d'=' -f2 || echo "192.168.1")
    local grafana_url=$(pct exec "$lxc_id" -- grep "^GRAFANA_URL=" "$stack_dir/.env" 2>/dev/null | cut -d'=' -f2 || echo "http://192.168.1.104:3000")
    
    print_info "Using network base: $network_base"
    print_info "Using Grafana URL: $grafana_url"
    
    # Generate prometheus.yml with dynamic IPs
    cat > "/tmp/prometheus.yml" <<EOF
# Prometheus Configuration - Generated automatically
# Network Base: $network_base

global:
  scrape_interval: 15s
  evaluation_interval: 15s

rule_files:
  - "/etc/prometheus/rules/*.yml"

alerting:
  alertmanagers:
    - static_configs:
        - targets:
          - alertmanager:9093

scrape_configs:
  # Prometheus itself
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  # Node Exporter - Monitoring LXC (104)
  - job_name: 'node-exporter-monitoring'
    static_configs:
      - targets: ['node-exporter:9100']
        labels:
          instance: 'monitoring-lxc-104'

  # Node Exporter - Proxy LXC (100)
  - job_name: 'node-exporter-proxy'
    static_configs:
      - targets: ['192.168.1.100:9100']
        labels:
          instance: 'proxy-lxc-100'

  # Node Exporter - Media LXC (101)
  - job_name: 'node-exporter-media'
    static_configs:
      - targets: ['192.168.1.101:9100']
        labels:
          instance: 'media-lxc-101'

  # Node Exporter - Downloads LXC (102)
  - job_name: 'node-exporter-downloads'
    static_configs:
      - targets: ['192.168.1.102:9100']
        labels:
          instance: 'downloads-lxc-102'

  # Node Exporter - Utility LXC (103)
  - job_name: 'node-exporter-utility'
    static_configs:
      - targets: ['192.168.1.103:9100']
        labels:
          instance: 'utility-lxc-103'

  # cAdvisor - Container metrics from Monitoring LXC
  - job_name: 'cadvisor'
    static_configs:
      - targets: ['cadvisor:8081']

  # Proxmox VE Exporter
  - job_name: 'proxmox'
    static_configs:
      - targets: ['prometheus-pve-exporter:9221']
    metrics_path: /pve
    params:
      cluster: ['1']
      node: ['1']
    relabel_configs:
      - source_labels: [__address__]
        target_label: __param_target
      - source_labels: [__param_target]
        target_label: instance
      - target_label: __address__
        replacement: prometheus-pve-exporter:9221
EOF

    # Generate alertmanager.yml with dynamic Grafana URL
    cat > "/tmp/alertmanager.yml" <<EOF
global:
  smtp_smarthost: 'smtp.gmail.com:587'
  smtp_from: '\${GMAIL_ADDRESS}'
  smtp_auth_username: '\${GMAIL_ADDRESS}'
  smtp_auth_password: '\${GMAIL_APP_PASSWORD}'

route:
  group_by: ['alertname', 'severity']
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 12h
  receiver: 'default'
  routes:
    # Route critical alerts to immediate notification
    - match:
        severity: 'critical'
      receiver: 'critical-alerts'
      repeat_interval: 1h
    # Route all other alerts to standard notification
    - match_re:
        severity: '.*'
      receiver: 'email-notifications'

receivers:
  - name: 'default'
    email_configs:
      - to: '\${GMAIL_ADDRESS}'
        subject: '[HOMELAB] System Alert'
        body: |
          🚨 HOMELAB ALERT 🚨
          
          {{ range .Alerts }}
          Alert: {{ .Annotations.summary }}
          Description: {{ .Annotations.description }}
          Instance: {{ .Labels.instance | default "N/A" }}
          Severity: {{ .Labels.severity | default "unknown" }}
          Time: {{ .StartsAt.Format "2006-01-02 15:04:05 UTC" }}
          {{ end }}
          
          Dashboard: $grafana_url

  - name: 'email-notifications'
    email_configs:
      - to: '\${GMAIL_ADDRESS}'
        subject: '[HOMELAB] {{ .GroupLabels.alertname }} Alert'
        body: |
          🚨 HOMELAB ALERT 🚨
          
          {{ range .Alerts }}
          Alert: {{ .Annotations.summary }}
          Description: {{ .Annotations.description }}
          Instance: {{ .Labels.instance | default "N/A" }}
          Severity: {{ .Labels.severity | default "unknown" }}
          Time: {{ .StartsAt.Format "2006-01-02 15:04:05 UTC" }}
          {{ end }}
          
          Dashboard: $grafana_url
        html: |
          <h2>🚨 HOMELAB ALERT</h2>
          {{ range .Alerts }}
          <p><strong>Alert:</strong> {{ .Annotations.summary }}</p>
          <p><strong>Description:</strong> {{ .Annotations.description }}</p>
          <p><strong>Instance:</strong> {{ .Labels.instance | default "N/A" }}</p>
          <p><strong>Severity:</strong> <span style="color: orange;">{{ .Labels.severity | default "unknown" }}</span></p>
          <p><strong>Time:</strong> {{ .StartsAt.Format "2006-01-02 15:04:05 UTC" }}</p>
          <hr>
          {{ end }}
          <p><a href="$grafana_url">Go to Grafana Dashboard</a></p>

  - name: 'critical-alerts'
    email_configs:
      - to: '\${GMAIL_ADDRESS}'
        subject: '🔥 [CRITICAL] {{ .GroupLabels.alertname }} - Immediate Action Required'
        body: |
          🔥 CRITICAL ALERT 🔥
          
          {{ range .Alerts }}
          Alert: {{ .Annotations.summary }}
          Description: {{ .Annotations.description }}
          Instance: {{ .Labels.instance | default "N/A" }}
          Time: {{ .StartsAt.Format "2006-01-02 15:04:05 UTC" }}
          {{ end }}
          
          ⚠️  This requires IMMEDIATE attention!
          Dashboard: $grafana_url
        html: |
          <h2 style="color: red;">🔥 CRITICAL ALERT</h2>
          {{ range .Alerts }}
          <p><strong>Alert:</strong> {{ .Annotations.summary }}</p>
          <p><strong>Description:</strong> {{ .Annotations.description }}</p>
          <p><strong>Instance:</strong> {{ .Labels.instance | default "N/A" }}</p>
          <p><strong>Time:</strong> {{ .StartsAt.Format "2006-01-02 15:04:05 UTC" }}</p>
          <hr>
          {{ end }}
          <p style="color: red;"><strong>⚠️ This requires IMMEDIATE attention!</strong></p>
          <p><a href="$grafana_url">Go to Grafana Dashboard</a></p>

inhibit_rules:
  - source_match:
      severity: 'critical'
    target_match:
      severity: 'warning'
    equal: ['alertname', 'instance']
EOF

    # Copy generated configs to datapool
    cp "/tmp/prometheus.yml" "/datapool/config/monitoring/prometheus/prometheus.yml"
    cp "/tmp/alertmanager.yml" "/datapool/config/monitoring/alertmanager/alertmanager.yml"
    
    # Cleanup temporary files
    rm -f "/tmp/prometheus.yml" "/tmp/alertmanager.yml"
    
    print_info "✓ Monitoring configuration files generated successfully"
}

# Function to download and setup Grafana dashboards
setup_grafana_dashboards() {
    local lxc_id=$1
    
    print_info "📊 Downloading Grafana dashboards from GitHub..."
    
    # Ensure dashboard directory exists
    mkdir -p "/datapool/config/grafana/dashboards"
    
    # Dashboard URLs from GitHub repo
    local dashboard_urls=(
        "https://raw.githubusercontent.com/Yakrel/proxmox-homelab-automation/$BRANCH/docker/monitoring/dashboards/proxmox-dashboard-10347.json"
        "https://raw.githubusercontent.com/Yakrel/proxmox-homelab-automation/$BRANCH/docker/monitoring/dashboards/node-exporter-full-1860.json"
        "https://raw.githubusercontent.com/Yakrel/proxmox-homelab-automation/$BRANCH/docker/monitoring/dashboards/docker-containers-193.json"
    )
    
    # Dashboard filenames
    local dashboard_files=(
        "proxmox-dashboard-10347.json"
        "node-exporter-full-1860.json"
        "docker-containers-193.json"
    )
    
    # Download each dashboard
    for i in "${!dashboard_urls[@]}"; do
        local url="${dashboard_urls[$i]}"
        local filename="${dashboard_files[$i]}"
        local output_path="/datapool/config/grafana/dashboards/$filename"
        
        print_info "Downloading $filename..."
        
        if wget -q --timeout=10 --tries=3 -O "$output_path" "$url"; then
            print_info "✓ Downloaded $filename successfully"
            # Set proper ownership
            chown 101000:101000 "$output_path" 2>/dev/null || true
        else
            print_warning "Failed to download $filename from GitHub"
            print_info "Dashboard will need to be imported manually with ID: ${filename##*-}"
        fi
    done
    
    # Also create dashboard provider config if it doesn't exist
    local provider_dir="/datapool/config/grafana/provisioning/dashboards"
    mkdir -p "$provider_dir"
    
    if [ ! -f "$provider_dir/dashboard-provider.yml" ]; then
        print_info "Creating dashboard provider configuration..."
        cat > "$provider_dir/dashboard-provider.yml" <<EOF
apiVersion: 1

providers:
  - name: 'homelab-dashboards'
    orgId: 1
    folder: 'Homelab'
    type: file
    disableDeletion: false
    updateIntervalSeconds: 30
    allowUiUpdates: true
    options:
      path: /var/lib/grafana/dashboards
EOF
        chown 101000:101000 "$provider_dir/dashboard-provider.yml" 2>/dev/null || true
        print_info "✓ Dashboard provider configured"
    fi
    
    print_info "✓ Grafana dashboard setup completed"
    print_info "📋 Dashboards will be available in Grafana under 'Homelab' folder after container startup"
}

# Function to update existing stack
update_existing_stack() {
    local lxc_id=$1
    local stack_dir=$2
    
    print_info "Generating monitoring configuration files..."
    
    # Read network configuration from .env file
    local network_base=$(pct exec "$lxc_id" -- grep "^NETWORK_BASE=" "$stack_dir/.env" 2>/dev/null | cut -d'=' -f2 || echo "192.168.1")
    local grafana_url=$(pct exec "$lxc_id" -- grep "^GRAFANA_URL=" "$stack_dir/.env" 2>/dev/null | cut -d'=' -f2 || echo "http://192.168.1.104:3000")
    
    print_info "Using network base: $network_base"
    print_info "Using Grafana URL: $grafana_url"
    
    # Generate prometheus.yml with dynamic IPs
    cat > "/tmp/prometheus.yml" <<EOF
# Prometheus Configuration - Generated automatically
# Network Base: $network_base

global:
  scrape_interval: 15s
  evaluation_interval: 15s

rule_files:
  - "/etc/prometheus/rules/*.yml"

alerting:
  alertmanagers:
    - static_configs:
        - targets:
          - alertmanager:9093

scrape_configs:
  # Prometheus itself
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  # Node Exporter - Monitoring LXC (104)
  - job_name: 'node-exporter-monitoring'
    static_configs:
      - targets: ['node-exporter:9100']
        labels:
          instance: 'monitoring-lxc-104'

  # Node Exporter - Proxy LXC (100)
  - job_name: 'node-exporter-proxy'
    static_configs:
      - targets: ['192.168.1.100:9100']
        labels:
          instance: 'proxy-lxc-100'

  # Node Exporter - Media LXC (101)
  - job_name: 'node-exporter-media'
    static_configs:
      - targets: ['192.168.1.101:9100']
        labels:
          instance: 'media-lxc-101'

  # Node Exporter - Downloads LXC (102)
  - job_name: 'node-exporter-downloads'
    static_configs:
      - targets: ['192.168.1.102:9100']
        labels:
          instance: 'downloads-lxc-102'

  # Node Exporter - Utility LXC (103)
  - job_name: 'node-exporter-utility'
    static_configs:
      - targets: ['192.168.1.103:9100']
        labels:
          instance: 'utility-lxc-103'

  # cAdvisor - Container metrics from Monitoring LXC
  - job_name: 'cadvisor'
    static_configs:
      - targets: ['cadvisor:8081']

  # Proxmox VE Exporter
  - job_name: 'proxmox'
    static_configs:
      - targets: ['prometheus-pve-exporter:9221']
    metrics_path: /pve
    params:
      cluster: ['1']
      node: ['1']
    relabel_configs:
      - source_labels: [__address__]
        target_label: __param_target
      - source_labels: [__param_target]
        target_label: instance
      - target_label: __address__
        replacement: prometheus-pve-exporter:9221
EOF

    # Generate alertmanager.yml with dynamic Grafana URL
    cat > "/tmp/alertmanager.yml" <<EOF
global:
  smtp_smarthost: 'smtp.gmail.com:587'
  smtp_from: '\${GMAIL_ADDRESS}'
  smtp_auth_username: '\${GMAIL_ADDRESS}'
  smtp_auth_password: '\${GMAIL_APP_PASSWORD}'

route:
  group_by: ['alertname', 'severity']
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 12h
  receiver: 'default'
  routes:
    # Route critical alerts to immediate notification
    - match:
        severity: 'critical'
      receiver: 'critical-alerts'
      repeat_interval: 1h
    # Route all other alerts to standard notification
    - match_re:
        severity: '.*'
      receiver: 'email-notifications'

receivers:
  - name: 'default'
    email_configs:
      - to: '\${GMAIL_ADDRESS}'
        subject: '[HOMELAB] System Alert'
        body: |
          🚨 HOMELAB ALERT 🚨
          
          {{ range .Alerts }}
          Alert: {{ .Annotations.summary }}
          Description: {{ .Annotations.description }}
          Instance: {{ .Labels.instance | default "N/A" }}
          Severity: {{ .Labels.severity | default "unknown" }}
          Time: {{ .StartsAt.Format "2006-01-02 15:04:05 UTC" }}
          {{ end }}
          
          Dashboard: $grafana_url

  - name: 'email-notifications'
    email_configs:
      - to: '\${GMAIL_ADDRESS}'
        subject: '[HOMELAB] {{ .GroupLabels.alertname }} Alert'
        body: |
          🚨 HOMELAB ALERT 🚨
          
          {{ range .Alerts }}
          Alert: {{ .Annotations.summary }}
          Description: {{ .Annotations.description }}
          Instance: {{ .Labels.instance | default "N/A" }}
          Severity: {{ .Labels.severity | default "unknown" }}
          Time: {{ .StartsAt.Format "2006-01-02 15:04:05 UTC" }}
          {{ end }}
          
          Dashboard: $grafana_url
        html: |
          <h2>🚨 HOMELAB ALERT</h2>
          {{ range .Alerts }}
          <p><strong>Alert:</strong> {{ .Annotations.summary }}</p>
          <p><strong>Description:</strong> {{ .Annotations.description }}</p>
          <p><strong>Instance:</strong> {{ .Labels.instance | default "N/A" }}</p>
          <p><strong>Severity:</strong> <span style="color: orange;">{{ .Labels.severity | default "unknown" }}</span></p>
          <p><strong>Time:</strong> {{ .StartsAt.Format "2006-01-02 15:04:05 UTC" }}</p>
          <hr>
          {{ end }}
          <p><a href="$grafana_url">Go to Grafana Dashboard</a></p>

  - name: 'critical-alerts'
    email_configs:
      - to: '\${GMAIL_ADDRESS}'
        subject: '🔥 [CRITICAL] {{ .GroupLabels.alertname }} - Immediate Action Required'
        body: |
          🔥 CRITICAL ALERT 🔥
          
          {{ range .Alerts }}
          Alert: {{ .Annotations.summary }}
          Description: {{ .Annotations.description }}
          Instance: {{ .Labels.instance | default "N/A" }}
          Time: {{ .StartsAt.Format "2006-01-02 15:04:05 UTC" }}
          {{ end }}
          
          ⚠️  This requires IMMEDIATE attention!
          Dashboard: $grafana_url
        html: |
          <h2 style="color: red;">🔥 CRITICAL ALERT</h2>
          {{ range .Alerts }}
          <p><strong>Alert:</strong> {{ .Annotations.summary }}</p>
          <p><strong>Description:</strong> {{ .Annotations.description }}</p>
          <p><strong>Instance:</strong> {{ .Labels.instance | default "N/A" }}</p>
          <p><strong>Time:</strong> {{ .StartsAt.Format "2006-01-02 15:04:05 UTC" }}</p>
          <hr>
          {{ end }}
          <p style="color: red;"><strong>⚠️ This requires IMMEDIATE attention!</strong></p>
          <p><a href="$grafana_url">Go to Grafana Dashboard</a></p>

inhibit_rules:
  - source_match:
      severity: 'critical'
    target_match:
      severity: 'warning'
    equal: ['alertname', 'instance']
EOF

    # Copy generated configs to datapool
    cp "/tmp/prometheus.yml" "/datapool/config/monitoring/prometheus/prometheus.yml"
    cp "/tmp/alertmanager.yml" "/datapool/config/monitoring/alertmanager/alertmanager.yml"
    
    # Cleanup temporary files
    rm -f "/tmp/prometheus.yml" "/tmp/alertmanager.yml"
    
    print_info "✓ Monitoring configuration files generated successfully"
}

# Function to update existing stack
update_existing_stack() {
    local stack_type=$1
    local lxc_id=$2
    local target_dir="/opt/$stack_type-stack"
    
    print_info "🔄 Updating existing $stack_type stack in LXC $lxc_id"
    
    # Check if LXC exists and is running
    if ! pct status "$lxc_id" &>/dev/null; then
        print_error "LXC $lxc_id does not exist!"
        return 1
    fi
    
    # Ensure container and Docker are ready
    ensure_container_ready "$lxc_id"
    
    # Ensure datapool mount exists
    ensure_datapool_mount "$lxc_id"
    
    # Check if stack directory exists
    if ! pct exec "$lxc_id" -- test -d "$target_dir"; then
        print_warning "Stack directory $target_dir doesn't exist, creating new deployment..."
        deploy_complete_stack "$stack_type" "$lxc_id"
        return $?
    fi
    
    # Check if .env exists and validate it
    if pct exec "$lxc_id" -- test -f "$target_dir/.env"; then
        print_info "Environment file found, validating..."
        
        # For monitoring stack, validate required variables
        if [ "$stack_type" = "monitoring" ]; then
            local missing_vars=()
            for var in "GRAFANA_ADMIN_PASSWORD" "PVE_PASSWORD" "PVE_URL"; do
                if ! pct exec "$lxc_id" -- grep -q "^${var}=" "$target_dir/.env"; then
                    missing_vars+=("$var")
                fi
            done
            
            if [ ${#missing_vars[@]} -gt 0 ]; then
                print_warning "Missing required variables in .env: ${missing_vars[*]}"
                print_warning "Will recreate environment configuration"
                skip_env_setup=false
            else
                print_info "✓ Environment file is valid, skipping configuration prompts"
                skip_env_setup=true
            fi
        else
            print_info "✓ Environment file exists, skipping configuration prompts"
            skip_env_setup=true
        fi
    else
        print_warning "No .env file found, will need configuration setup"
        skip_env_setup=false
    fi
    
    # Download latest stack files
    download_stack_files "$stack_type" "$TEMP_DIR/$stack_type"
    
    # Copy updated docker-compose.yml to LXC
    print_info "Updating docker-compose.yml..."
    pct push "$lxc_id" "$TEMP_DIR/$stack_type/docker-compose.yml" "$target_dir/docker-compose.yml"
    
    # Update monitoring config files if needed (permissions already set by ensure_datapool_permissions)
    if [ "$stack_type" = "monitoring" ]; then
        if [ -f "$TEMP_DIR/$stack_type/prometheus.yml" ]; then
            cp "$TEMP_DIR/$stack_type/prometheus.yml" "/datapool/config/prometheus/prometheus.yml"
        fi
        if [ -f "$TEMP_DIR/$stack_type/alertmanager.yml" ]; then
            cp "$TEMP_DIR/$stack_type/alertmanager.yml" "/datapool/config/alertmanager/alertmanager.yml"
        fi
    fi
    
    # Setup environment if .env doesn't exist
    if [ "$skip_env_setup" = false ]; then
        print_info "Setting up environment configuration..."
        setup_env_file "$target_dir" "$stack_type" "$lxc_id"
    fi
    
    # Ensure proper datapool permissions (always run for existing stacks)
    ensure_datapool_permissions "$stack_type"
    
    # Download additional monitoring configuration files if needed
    if [ "$stack_type" = "monitoring" ]; then
        # Download monitoring configuration files from GitHub
        if wget -q -O "/datapool/config/grafana/provisioning/datasources/prometheus.yml" "$GITHUB_REPO/docker/monitoring/grafana-datasource.yml"; then
            print_info "✓ Grafana datasource configuration downloaded"
        else
            print_warning "Could not download Grafana datasource configuration"
        fi
        
        if wget -q -O "/datapool/config/prometheus/rules/alerts.yml" "$GITHUB_REPO/docker/monitoring/alerts.yml"; then
            print_info "✓ Prometheus alerts configuration downloaded"
        else
            print_warning "Could not download Prometheus alerts configuration"
        fi
    fi
    
    # Update stack with latest compose file
    print_info "Updating services with latest configuration..."
    pct exec "$lxc_id" -- sh -c "cd $target_dir && docker compose pull && docker compose up -d"
    
    if [ $? -eq 0 ]; then
        print_info "✅ $stack_type stack updated successfully!"
        
        # Show status
        print_info "Container status:"
        pct exec "$lxc_id" -- sh -c "cd $target_dir && docker compose ps"
        
        return 0
    else
        print_error "Failed to update $stack_type stack"
        return 1
    fi
}

# Function to deploy complete stack
deploy_complete_stack() {
    local stack_type=$1
    local lxc_id=$2
    
    print_info "🚀 Starting complete deployment for $stack_type stack (LXC $lxc_id)"
    
    # Set target directory inside LXC
    local target_dir="/opt/$stack_type-stack"
    
    # Create directory structure inside LXC
    print_info "Creating directory structure in LXC..."
    pct exec "$lxc_id" -- mkdir -p "$target_dir"
    
    # Download stack files to temp directory
    download_stack_files "$stack_type" "$TEMP_DIR/$stack_type"
    
    # Copy files to LXC
    print_info "Copying files to LXC..."
    pct push "$lxc_id" "$TEMP_DIR/$stack_type/docker-compose.yml" "$target_dir/docker-compose.yml"
    
    if [ -f "$TEMP_DIR/$stack_type/.env.example" ]; then
        pct push "$lxc_id" "$TEMP_DIR/$stack_type/.env.example" "$target_dir/.env.example"
    fi
    
    # Ensure proper datapool permissions for new deployment
    ensure_datapool_permissions "$stack_type"
    
    # Generate monitoring config files with dynamic network configuration
    if [ "$stack_type" = "monitoring" ]; then
        # Generate configuration files after .env is set up
        generate_monitoring_configs "$lxc_id" "$target_dir"
    fi
    
    # Setup environment inside LXC with interactive configuration
    print_info "Setting up environment in LXC..."
    
    # Interactive configuration for the stack
    setup_env_file "$target_dir" "$stack_type" "$lxc_id"
    
    # For monitoring stack, create PVE monitoring user on host using credentials from .env
    if [ "$stack_type" = "monitoring" ]; then
        print_info "Setting up Proxmox monitoring user on host..."
        
        # Read PVE password from .env file (set by interactive_setup.sh)
        local pve_password
        if pct exec "$lxc_id" -- test -f "$target_dir/.env" 2>/dev/null; then
            pve_password=$(pct exec "$lxc_id" -- grep "^PVE_PASSWORD=" "$target_dir/.env" 2>/dev/null | cut -d'=' -f2)
        fi
        
        if [ -z "$pve_password" ]; then
            print_warning "PVE password not found in .env file, monitoring user setup will be skipped"
            print_info "You can manually create the user later: pveum user add monitoring@pve --password <password>"
            print_info "Then assign PVEAuditor role: pveum acl modify / --users monitoring@pve --roles PVEAuditor"
        else
            print_info "Using PVE password from environment configuration"
            ensure_pve_monitoring_user "monitoring@pve" "$pve_password"
        fi
    fi
    
    # Deploy stack inside LXC
    print_info "Deploying stack inside LXC..."
    
    # Deploy with docker compose (Alpine Docker template uses V2 syntax)
    pct exec "$lxc_id" -- sh -c "cd $target_dir && docker compose pull && docker compose up -d"
    
    if [ $? -eq 0 ]; then
        print_info "🎉 $stack_type stack deployed successfully in LXC $lxc_id!"
        
        # Show status
        print_info "Container status:"
        pct exec "$lxc_id" -- sh -c "cd $target_dir && docker compose ps"
        
        # Clean up .env.example file
        print_info "Cleaning up temporary files..."
        pct exec "$lxc_id" -- sh -c "cd $target_dir && rm -f .env.example"
        
        # Show important notes
        print_info "Stack deployed successfully to $target_dir"
        
        # Add stack-specific configuration notes
        if [ "$stack_type" = "media" ]; then
            print_warning "⚠️  Configure Cleanuperr API keys via service web interfaces after deployment"
        fi
        
        return 0
    else
        print_error "Failed to deploy $stack_type stack"
        return 1
    fi
}


# Validate stack type
case "$1" in
    media|proxy|downloads|utility|monitoring)
        # Valid stack type
        ;;
    *)
        print_error "Invalid stack type: $1"
        print_error "Available stack types: media, proxy, downloads, utility, monitoring"
        exit 1
        ;;
esac

# Validate LXC ID if provided
if [ $# -eq 2 ]; then
    if ! [[ "$2" =~ ^[0-9]+$ ]] || [ "$2" -lt 100 ] || [ "$2" -gt 999 ]; then
        print_error "Invalid LXC ID: $2 (must be a number between 100-999)"
        exit 1
    fi
fi

# Check if running as root
check_root

STACK_TYPE=$1
LXC_ID=$2

print_info "Starting deployment process for $STACK_TYPE stack..."

# Determine LXC ID if not provided
if [ -z "$LXC_ID" ]; then
    case $STACK_TYPE in
        "media") LXC_ID=101 ;;
        "proxy") LXC_ID=100 ;;
        "downloads") LXC_ID=102 ;;
        "utility") LXC_ID=103 ;;
        "monitoring") LXC_ID=104 ;;
        *) 
            print_error "Unknown stack type: $STACK_TYPE"
            exit 1
            ;;
    esac
fi

# Check if LXC exists and has existing stack
if pct status "$LXC_ID" &>/dev/null && pct exec "$LXC_ID" -- test -d "/opt/$STACK_TYPE-stack"; then
    print_info "🔍 Found existing $STACK_TYPE stack in LXC $LXC_ID - updating compose files..."
    update_existing_stack "$STACK_TYPE" "$LXC_ID"
else
    deploy_complete_stack "$STACK_TYPE" "$LXC_ID"
fi

if [ $? -eq 0 ]; then
    print_info "✅ Deployment completed successfully!"
else
    print_error "❌ Deployment failed!"
    exit 1
fi