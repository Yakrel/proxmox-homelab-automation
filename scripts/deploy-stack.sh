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

# Source central configuration
if [ -f "$SCRIPT_DIR/../config.sh" ]; then
    source "$SCRIPT_DIR/../config.sh"
else
    echo "ERROR: config.sh not found!" >&2
    exit 1
fi

# Source utils from new location
if [ -f "$SCRIPT_DIR/utils.sh" ]; then
    source "$SCRIPT_DIR/utils.sh"
else
    echo "ERROR: utils.sh not found!" >&2
    exit 1
fi

# Configuration
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
    wget -q -O "$target_dir/docker-compose.yml" "$GITHUB_REPO_URL/docker/$stack_type/docker-compose.yml"
    
    if [ $? -ne 0 ]; then
        print_error "Failed to download docker-compose.yml for $stack_type"
        return 1
    fi
    
    # Download additional config files for monitoring stack
    if [ "$stack_type" = "monitoring" ]; then
        # Download template files for dynamic configuration
        wget -q -O "$target_dir/prometheus.yml.template" "$GITHUB_REPO_URL/docker/monitoring/prometheus.yml.template" 2>/dev/null || true
        wget -q -O "$target_dir/alertmanager.yml.template" "$GITHUB_REPO_URL/docker/monitoring/alertmanager.yml.template" 2>/dev/null || true
        wget -q -O "$target_dir/alerts.yml" "$GITHUB_REPO_URL/docker/monitoring/alerts.yml" 2>/dev/null || true
        
        # Fallback to static files if templates don't exist
        if [ ! -f "$target_dir/prometheus.yml.template" ]; then
            wget -q -O "$target_dir/prometheus.yml" "$GITHUB_REPO_URL/docker/monitoring/prometheus.yml" 2>/dev/null || true
        fi
        if [ ! -f "$target_dir/alertmanager.yml.template" ]; then
            wget -q -O "$target_dir/alertmanager.yml" "$GITHUB_REPO_URL/docker/monitoring/alertmanager.yml" 2>/dev/null || true
        fi
    fi
    
    return 0
}

# Function for interactive setup
interactive_setup() {
    local stack_type=$1

    case "$stack_type" in
        "files")
            get_user_password "Enter JDownloader VNC Password" JDOWNLOADER_VNC_PASSWORD
            PALMR_ENCRYPTION_KEY=$(generate_random_key)
            print_info "Generated random encryption key for Palmr."
            ;;
        "proxy")
            get_user_input "Enter Cloudflared Tunnel Token" CLOUDFLARED_TOKEN
            ;;
        "webtools")
            get_user_password "Enter Firefox VNC Password" FIREFOX_VNC_PASSWORD
            ;;
    esac
}

# Unified environment file setup - always refresh with backup and merge
setup_env_file() {
    local stack_dir=$1
    local stack_type=$2
    local lxc_id=$3
    local jdownloader_password=$4
    local palmr_key=$5
    local cloudflared_token=$6
    local firefox_password=$7

    print_info "Setting up .env file for $stack_type stack..."

    # 1. Get the content of the .env.example file from the repository
    local env_example_content
    env_example_content=$(curl -sL "$GITHUB_REPO_URL/docker/$stack_type/.env.example")

    # 2. Create a string of variables to pass to the LXC
    local extra_vars=""
    [ -n "$jdownloader_password" ] && extra_vars+="JDOWNLOADER_VNC_PASSWORD=$jdownloader_password\n"
    [ -n "$palmr_key" ] && extra_vars+="PALMR_ENCRYPTION_KEY=$palmr_key\n"
    [ -n "$cloudflared_token" ] && extra_vars+="CLOUDFLARED_TOKEN=$cloudflared_token\n"
    [ -n "$firefox_password" ] && extra_vars+="FIREFOX_VNC_PASSWORD=$firefox_password\n"

    # 3. Push the updated utils.sh script to the LXC
    pct push "$lxc_id" "$SCRIPT_DIR/utils.sh" "/tmp/utils.sh" -perms 755

    # 4. Execute the create_stack_env_file function inside the LXC
    if pct exec "$lxc_id" -- bash -c "
        source /tmp/utils.sh
        # Append extra vars to the example content before processing
        env_example_content=\$(echo -e \"\$1\n\$2\")
        create_stack_env_file '$stack_dir/.env' '$stack_type' \"\$env_example_content\"
    " -- "$env_example_content" "$extra_vars"; then
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
    
    print_info "Deploying Homepage configuration..."
    
    # Create homepage config directory
    pct exec "$lxc_id" -- mkdir -p /datapool/config/homepage 2>/dev/null
    
    # Download and deploy each config file
    local config_files=("bookmarks.yaml" "docker.yaml" "services.yaml" "settings.yaml" "widgets.yaml")
    local essential_files=("settings.yaml" "widgets.yaml" "services.yaml")
    local deployed_files=()
    
    for config_file in "${config_files[@]}"; do
        local temp_file="$TEMP_DIR/$config_file"
        local target_path="/datapool/config/homepage/$config_file"
        
        if wget -q -O "$temp_file" "$GITHUB_REPO_URL/config/homepage/$config_file"; then
            if pct push "$lxc_id" "$temp_file" "$target_path" >/dev/null 2>&1; then
                deployed_files+=("$config_file")
            else
                print_warning "Failed to push $config_file to LXC."
            fi
        else
            print_warning "Failed to download $config_file from repository."
        fi
    done
    
    # Verify that essential files were deployed
    for essential in "${essential_files[@]}"; do
        if ! [[ " ${deployed_files[@]} " =~ " ${essential} " ]]; then
            print_error "Essential Homepage config file '$essential' could not be deployed. Aborting."
            return 1
        fi
    done

    # Set proper permissions
    if [ -w "/datapool/config" ]; then
        chown -R "$HOMELAB_HOST_UID:$HOMELAB_HOST_GID" /datapool/config/homepage 2>/dev/null
        chmod -R 644 /datapool/config/homepage/*.yaml 2>/dev/null
    else
        print_warning "Cannot access /datapool/config to set permissions."
    fi
    
    print_success "Homepage configuration deployed successfully."
    return 0
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
    
    print_long_operation "🔄 Updating $stack_type stack in LXC $lxc_id..."
    
    # Download latest compose files from GitHub
    print_long_operation "📥 Downloading latest compose files..."
    download_stack_files "$stack_type" "$TEMP_DIR/$stack_type"
    
    # Update compose files in LXC
    pct push "$lxc_id" "$TEMP_DIR/$stack_type/docker-compose.yml" "$stack_dir/docker-compose.yml"
    
    # Run interactive setup and update .env file
    interactive_setup "$stack_type"
    setup_env_file "$stack_dir" "$stack_type" "$lxc_id" "$JDOWNLOADER_VNC_PASSWORD" "$PALMR_ENCRYPTION_KEY" "$CLOUDFLARED_TOKEN" "$FIREFOX_VNC_PASSWORD"

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
    print_long_operation "🚀 Restarting services..."
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
    interactive_setup "$stack_type"
    
    # Pass the collected variables to the setup_env_file function
    setup_env_file "$target_dir" "$stack_type" "$lxc_id" "$JDOWNLOADER_VNC_PASSWORD" "$PALMR_ENCRYPTION_KEY" "$CLOUDFLARED_TOKEN" "$FIREFOX_VNC_PASSWORD"
    
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