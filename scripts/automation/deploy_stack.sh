#!/bin/bash

# Automated Stack Deployment Script
# Downloads latest docker-compose files from GitHub and deploys them

set -e

# Parse command line arguments for quiet mode
while [[ $# -gt 0 ]]; do
    case $1 in
        --quiet|-q)
            export QUIET_MODE=true
            shift
            ;;
        --*)
            echo "Unknown option: $1" >&2
            shift
            ;;
        *)
            # Non-option argument, break to handle positional args
            break
            ;;
    esac
done

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common.sh from utils directory with better error reporting
if [ -f "$SCRIPT_DIR/../utils/common.sh" ]; then
    source "$SCRIPT_DIR/../utils/common.sh"
elif [ -f "/tmp/common.sh" ]; then
    source "/tmp/common.sh"
else
    echo "ERROR: common.sh not found!" >&2
    ls -la "$SCRIPT_DIR/../utils/" 2>/dev/null || echo "Directory does not exist" >&2
    exit 1
fi

# Configuration
# Repository URL
GITHUB_REPO="https://raw.githubusercontent.com/Yakrel/proxmox-homelab-automation/main"
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

# Docker Compose command (Alpine Docker template uses V2 syntax)
DOCKER_COMPOSE_CMD="docker compose"



# Function to download files from GitHub
download_stack_files() {
    local stack_type=$1
    local target_dir=$2
    
    # Create target directory if it doesn't exist
    mkdir -p "$target_dir"
    
    # Download docker-compose.yml
    wget -q -O "$target_dir/docker-compose.yml" "$GITHUB_REPO/docker/$stack_type/docker-compose.yml"
    
    if [ $? -ne 0 ]; then
        print_error "Failed to download docker-compose.yml for $stack_type"
        return 1
    fi
    
    # Download .env.example
    wget -q -O "$target_dir/.env.example" "$GITHUB_REPO/docker/$stack_type/.env.example" 2>/dev/null || true
    
    # Download additional config files for monitoring stack
    if [ "$stack_type" = "monitoring" ]; then
        # Download template files for dynamic configuration
        wget -q -O "$target_dir/prometheus.yml.template" "$GITHUB_REPO/docker/monitoring/prometheus.yml.template" 2>/dev/null || true
        wget -q -O "$target_dir/alertmanager.yml.template" "$GITHUB_REPO/docker/monitoring/alertmanager.yml.template" 2>/dev/null || true
        wget -q -O "$target_dir/alerts.yml" "$GITHUB_REPO/docker/monitoring/alerts.yml" 2>/dev/null || true
        
        # Fallback to static files if templates don't exist
        if [ ! -f "$target_dir/prometheus.yml.template" ]; then
            wget -q -O "$target_dir/prometheus.yml" "$GITHUB_REPO/docker/monitoring/prometheus.yml" 2>/dev/null || true
        fi
        if [ ! -f "$target_dir/alertmanager.yml.template" ]; then
            wget -q -O "$target_dir/alertmanager.yml" "$GITHUB_REPO/docker/monitoring/alertmanager.yml" 2>/dev/null || true
        fi
    fi
    
    return 0
}

# Unified environment file setup - always refresh with backup and merge
setup_env_file() {
    local stack_dir=$1
    local stack_type=$2
    local lxc_id=$3
    
    print_info "Setting up .env file for $stack_type stack..."
    
    # 1. Always create backup if .env exists
    if pct exec "$lxc_id" -- test -f "$stack_dir/.env" 2>/dev/null; then
        pct exec "$lxc_id" -- cp "$stack_dir/.env" "$stack_dir/.env.backup" 2>/dev/null || true
        print_info "Backup created: $stack_dir/.env.backup"
    fi
    
    # 2. Download common.sh to LXC and create unified .env system
    pct exec "$lxc_id" -- wget -q -O /tmp/common.sh "$GITHUB_REPO/scripts/utils/common.sh"
    
    # 3. Create/update .env file directly in LXC using container-safe function
    # This preserves existing values and merges with latest .env.example
    if pct exec "$lxc_id" -- bash -c "
        source /tmp/common.sh
        # Download latest .env.example for template
        wget -q -O /tmp/.env.example '$GITHUB_REPO/docker/$stack_type/.env.example' 2>/dev/null || true
        
        # Create/update .env with container-safe merge functionality
        create_stack_env_file '$stack_dir/.env' '$stack_type' ''
    "; then
        print_info ".env file updated successfully"
        return 0
    else
        print_error "Environment file creation failed"
        return 1
    fi
}

# Function to deploy Homepage dashboard configuration
deploy_homepage_configs() {
    local lxc_id=$1
    
    
    # Create homepage config directory
    pct exec "$lxc_id" -- mkdir -p /datapool/config/homepage 2>/dev/null
    
    # Download and deploy each config file
    local config_files=("bookmarks.yaml" "docker.yaml" "services.yaml" "settings.yaml" "widgets.yaml")
    local success_count=0
    
    for config_file in "${config_files[@]}"; do
        local temp_file="$TEMP_DIR/$config_file"
        local target_path="/datapool/config/homepage/$config_file"
        
        # Download and deploy config file (simplified for homelab)
        if wget -q -O "$temp_file" "$GITHUB_REPO/config/homepage/$config_file" 2>/dev/null; then
            # Simply copy new file to container (overwrite existing)
            if pct push "$lxc_id" "$temp_file" "$target_path" 2>/dev/null; then
                success_count=$((success_count + 1))
            else
                print_warning "Failed to deploy $config_file"
            fi
        else
            print_warning "Failed to download $config_file"
        fi
    done
    
    # Set proper permissions (homelab hardcoded values)
    # Unprivileged LXC mapping: 1000 (container) → 101000 (host)
    if [ -w "/datapool/config" ]; then
        chown -R 101000:101000 /datapool/config/homepage 2>/dev/null || {
            print_warning "Could not set ownership for homepage config (may already be correct)"
        }
    else
        print_warning "Cannot access /datapool/config for permission setup"
    fi
    chmod -R 644 /datapool/config/homepage/*.yaml 2>/dev/null || true
    
    if [ $success_count -eq ${#config_files[@]} ]; then
        return 0
    elif [ $success_count -gt 0 ]; then
        print_warning "Partially deployed Homepage configs ($success_count/${#config_files[@]} files)"
        return 0
    else
        print_error "Failed to deploy Homepage configuration files"
        return 1
    fi
}


# Function to deploy monitoring stack specific configs (simplified)
deploy_monitoring_configs() {
    local lxc_id=$1
    
    # Create monitoring config directories with data subdirectories
    pct exec "$lxc_id" -- mkdir -p /datapool/config/monitoring/{prometheus/{rules,data},alertmanager/data,grafana/{provisioning/{datasources,dashboards},dashboards}} 2>/dev/null
    
    return 0
}








# Function to update existing stack
update_existing_stack() {
    local lxc_id=$1
    local stack_dir=$2
    local stack_type=$3
    
    
    # Download latest compose files from GitHub
    print_long_operation "📥 Downloading latest compose files..."
    download_stack_files "$stack_type" "$TEMP_DIR/$stack_type"
    
    # Update compose files in LXC
    pct push "$lxc_id" "$TEMP_DIR/$stack_type/docker-compose.yml" "$stack_dir/docker-compose.yml"
    
    # Copy additional config files for monitoring stack
    if [ "$stack_type" = "monitoring" ]; then
        if [ -f "$TEMP_DIR/$stack_type/prometheus.yml" ]; then
            pct push "$lxc_id" "$TEMP_DIR/$stack_type/prometheus.yml" "$stack_dir/prometheus.yml"
        fi
        if [ -f "$TEMP_DIR/$stack_type/alertmanager.yml" ]; then
            pct push "$lxc_id" "$TEMP_DIR/$stack_type/alertmanager.yml" "$stack_dir/alertmanager.yml"
        fi
        # Static monitoring configurations are used from repository
    fi
    
    # Update Docker images and restart services
    print_long_operation "🔄 Pulling latest images..."
    pct exec "$lxc_id" -- bash -c "cd '$stack_dir' && docker compose pull"
    print_long_operation "🚀 Starting services..."
    pct exec "$lxc_id" -- bash -c "cd '$stack_dir' && docker compose up -d"
    
}


# Function to deploy complete stack
deploy_complete_stack() {
    local stack_type=$1
    local lxc_id=$2
    
    print_long_operation "🚀 Deploying $stack_type stack to LXC $lxc_id..."
    
    # Set target directory inside LXC
    local target_dir="/opt/$stack_type"
    
    # Create directory structure inside LXC
    pct exec "$lxc_id" -- mkdir -p "$target_dir"
    
    # Download stack files to temp directory
    download_stack_files "$stack_type" "$TEMP_DIR/$stack_type"
    
    # Copy files to LXC
    pct push "$lxc_id" "$TEMP_DIR/$stack_type/docker-compose.yml" "$target_dir/docker-compose.yml"
    
    if [ -f "$TEMP_DIR/$stack_type/.env.example" ]; then
        pct push "$lxc_id" "$TEMP_DIR/$stack_type/.env.example" "$target_dir/.env.example"
    fi
    
    # Ensure proper datapool permissions for new deployment
    ensure_datapool_permissions "$stack_type"
    
    # Set proper ownership for stack files after copying (fixes permission issues)
    # Stack files need proper ownership for Docker containers to access them
    if [ -d "$target_dir" ] && [ -w "$(dirname "$target_dir")" ]; then
        chown -R $HOMELAB_HOST_UID:$HOMELAB_HOST_GID "$target_dir" 2>/dev/null || {
            print_warning "Could not set ownership for stack files (may already be correct)"
        }
    fi
    
    # Copy monitoring config files to proper locations for monitoring stack
    if [ "$stack_type" = "monitoring" ]; then
        
        # Ensure monitoring config directories exist (including data directories)
        pct exec "$lxc_id" -- mkdir -p /datapool/config/monitoring/{prometheus/{rules,data},alertmanager/data,grafana} 2>/dev/null
        
        # Copy template and static files to LXC first
        if [ -f "$TEMP_DIR/$stack_type/prometheus.yml.template" ]; then
            pct push "$lxc_id" "$TEMP_DIR/$stack_type/prometheus.yml.template" "$target_dir/prometheus.yml.template"
        fi
        if [ -f "$TEMP_DIR/$stack_type/alertmanager.yml.template" ]; then
            pct push "$lxc_id" "$TEMP_DIR/$stack_type/alertmanager.yml.template" "$target_dir/alertmanager.yml.template"
        fi
        if [ -f "$TEMP_DIR/$stack_type/prometheus.yml" ]; then
            pct push "$lxc_id" "$TEMP_DIR/$stack_type/prometheus.yml" "$target_dir/prometheus.yml"
        fi
        if [ -f "$TEMP_DIR/$stack_type/alertmanager.yml" ]; then
            pct push "$lxc_id" "$TEMP_DIR/$stack_type/alertmanager.yml" "$target_dir/alertmanager.yml"
        fi
        if [ -f "$TEMP_DIR/$stack_type/alerts.yml" ]; then
            pct push "$lxc_id" "$TEMP_DIR/$stack_type/alerts.yml" "$target_dir/alerts.yml"
        fi
        
    fi
    
    # Interactive configuration for the stack
    setup_env_file "$target_dir" "$stack_type" "$lxc_id"
    
    # For monitoring stack, deploy config files
    if [ "$stack_type" = "monitoring" ]; then
        if pct exec "$lxc_id" -- test -f "$target_dir/prometheus.yml" 2>/dev/null; then
            pct exec "$lxc_id" -- cp "$target_dir/prometheus.yml" "/datapool/config/monitoring/prometheus/prometheus.yml"
        fi
        if pct exec "$lxc_id" -- test -f "$target_dir/alertmanager.yml" 2>/dev/null; then
            pct exec "$lxc_id" -- cp "$target_dir/alertmanager.yml" "/datapool/config/monitoring/alertmanager/alertmanager.yml"
        fi
        if pct exec "$lxc_id" -- test -f "$target_dir/alerts.yml" 2>/dev/null; then
            pct exec "$lxc_id" -- cp "$target_dir/alerts.yml" "/datapool/config/monitoring/prometheus/rules/alerts.yml"
        fi
        if pct exec "$lxc_id" -- test -f "$target_dir/grafana-provisioning-datasources.yml" 2>/dev/null; then
            pct exec "$lxc_id" -- cp "$target_dir/grafana-provisioning-datasources.yml" "/datapool/config/monitoring/grafana/provisioning/datasources/datasources.yml"
        fi
        if pct exec "$lxc_id" -- test -f "$target_dir/grafana-provisioning-dashboards.yml" 2>/dev/null; then
            pct exec "$lxc_id" -- cp "$target_dir/grafana-provisioning-dashboards.yml" "/datapool/config/monitoring/grafana/provisioning/dashboards/dashboards.yml"
        fi
        
    fi
    
    # For webtools stack, deploy homepage configurations
    if [ "$stack_type" = "webtools" ]; then
        print_long_operation "📋 Deploying Homepage configurations..."
        if deploy_homepage_configs "$lxc_id"; then
            print_info "✅ Homepage configurations deployed successfully"
        else
            print_warning "⚠️  Homepage configurations deployment had issues (continuing with stack deployment)"
        fi
    fi
    
    # Deploy with docker compose (Alpine Docker template uses V2 syntax)
    print_long_operation "🔄 Pulling Docker images..."
    pct exec "$lxc_id" -- sh -c "cd $target_dir && docker compose pull"
    print_long_operation "🚀 Starting services..."
    pct exec "$lxc_id" -- sh -c "cd $target_dir && docker compose up -d"
    
    if [ $? -eq 0 ]; then
        print_long_operation "✅ $stack_type stack deployed successfully!"
        
        # Show status
        pct exec "$lxc_id" -- sh -c "cd $target_dir && docker compose ps"
        
        # Clean up .env.example file
        pct exec "$lxc_id" -- sh -c "cd $target_dir && rm -f .env.example" 2>/dev/null || true
        
        return 0
    else
        print_error "Failed to deploy $stack_type stack"
        return 1
    fi
}


# Validate stack type
case "$1" in
    media|proxy|files|webtools|monitoring)
        # Valid stack type
        ;;
    *)
        print_error "Invalid stack type: $1"
        print_error "Available stack types: media, proxy, files, webtools, monitoring"
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


# Determine LXC ID if not provided
if [ -z "$LXC_ID" ]; then
    LXC_ID=$(get_stack_lxc_id "$STACK_TYPE")
    if [ $? -ne 0 ]; then
        print_error "Unknown stack type: $STACK_TYPE"
        exit 1
    fi
fi

# Check if LXC exists and has existing stack
if pct status "$LXC_ID" &>/dev/null && pct exec "$LXC_ID" -- test -d "/opt/$STACK_TYPE-stack"; then
    update_existing_stack "$LXC_ID" "/opt/$STACK_TYPE-stack" "$STACK_TYPE"
else
    deploy_complete_stack "$STACK_TYPE" "$LXC_ID"
fi

if [ $? -ne 0 ]; then
    print_error "Deployment failed!"
    exit 1
fi