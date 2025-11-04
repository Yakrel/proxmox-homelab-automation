#!/bin/bash

# =================================================================
#                     Docker Deployment Module
# =================================================================
# Handles Docker-based stack deployments - fail fast approach
set -euo pipefail

# Setup homepage configuration files from repository
setup_homepage_config() {
    local ct_id="$1"

    print_info "Setting up Homepage configuration"

    # Ensure directory exists
    mkdir -p /datapool/config/homepage

    # List of homepage config files to copy
    local config_files=("services.yaml" "bookmarks.yaml" "widgets.yaml" "settings.yaml" "docker.yaml")

    # Download all files in parallel for better performance
    local pids=()
    for config_file in "${config_files[@]}"; do
        local config_url="$REPO_BASE_URL/config/homepage/$config_file"
        local temp_file="/tmp/homepage_${config_file}"
        
        # Launch background curl job with explicit error handling
        (
            if curl -sSL "$config_url" -o "$temp_file"; then
                if cp "$temp_file" "/datapool/config/homepage/$config_file"; then
                    rm -f "$temp_file"
                    exit 0
                fi
            fi
            rm -f "$temp_file"  # Clean up temp file on any failure
            exit 1
        ) &
        pids+=($!)
    done
    
    # Wait for all downloads to complete and check for failures
    local failed=0
    for pid in "${pids[@]}"; do
        if ! wait "$pid"; then
            failed=1
        fi
    done
    
    if [[ $failed -eq 1 ]]; then
        print_error "Failed to download homepage config files"
        exit 1
    fi

    # Fix permissions
    chown -R 101000:101000 /datapool/config/homepage

    print_success "Homepage configured"
}

# Setup CouchDB directories and configuration
setup_couchdb_config() {
    local ct_id="$1"

    print_info "Setting up CouchDB"

    # Create CouchDB directories
    mkdir -p /datapool/config/couchdb/data
    mkdir -p /datapool/config/couchdb/local.d

    # Copy CouchDB configuration file
    local config_url="$REPO_BASE_URL/config/couchdb-local.ini"
    local temp_file="/tmp/couchdb_local.ini"

    curl -sSL "$config_url" -o "$temp_file"
    cp "$temp_file" "/datapool/config/couchdb/local.d/local.ini"
    rm -f "$temp_file"

    # Fix permissions
    chown -R 101000:101000 /datapool/config/couchdb

    print_success "CouchDB configured"
}

# Setup Immich directories with correct ownership
setup_immich_directories() {
    print_info "Preparing Immich directories"

    # Create all required Immich directories
    mkdir -p /datapool/media/immich/{upload,library,thumbs,profile,backups,encoded-video}
    mkdir -p /datapool/config/immich/postgres

    # Set correct ownership (101000:101000 on host = 1000:1000 in LXC)
    chown -R 101000:101000 /datapool/media/immich
    chown -R 101000:101000 /datapool/config/immich

    # Set appropriate permissions
    chmod -R 755 /datapool/media/immich
    chmod -R 700 /datapool/config/immich/postgres

    print_success "Immich configured"
}

# Setup Promtail configuration for log aggregation
setup_promtail_config() {
    local ct_id="$1"
    local hostname="$2"

    print_info "Setting up Promtail for $hostname"

    # Create promtail directories in LXC
    pct exec "$ct_id" -- mkdir -p /etc/promtail /var/lib/promtail/positions

    # Create promtail config with correct hostname and Loki endpoint
    local temp_promtail="/tmp/promtail_${ct_id}.yml"
    sed "s/REPLACE_HOST_LABEL/$hostname/g" "$WORK_DIR/config/promtail/promtail.yml" > "$temp_promtail"

    # Copy to container
    pct push "$ct_id" "$temp_promtail" "/etc/promtail/promtail.yml" || {
        print_error "Failed to copy promtail config"
        rm -f "$temp_promtail"
        exit 1
    }
    rm -f "$temp_promtail"

    print_success "Promtail configured"
}

# Download and configure Docker Compose files
setup_docker_compose() {
    local stack_name="$1"
    local ct_id="$2"
    
    print_info "Setting up Docker Compose for $stack_name"
    
    # Download compose file
    local compose_url="$REPO_BASE_URL/docker/$stack_name/docker-compose.yml"
    local temp_compose="/tmp/docker-compose.yml"
    
    if ! curl -sSL "$compose_url" -o "$temp_compose"; then
        print_error "Failed to download docker-compose.yml"
        exit 1
    fi
    
    # Verify downloaded file is not empty
    if [[ ! -s "$temp_compose" ]]; then
        print_error "Downloaded docker-compose.yml is empty"
        rm -f "$temp_compose"
        exit 1
    fi
    
    # Copy to container root directory directly
    pct push "$ct_id" "$temp_compose" "/root/docker-compose.yml" || { print_error "Failed to push compose file"; exit 1; }
    rm -f "$temp_compose"
    
    print_success "Docker Compose configured"
}

# Verify Docker is available in container (already installed during LXC provisioning)
install_docker() {
    local ct_id="$1"
    
    # Docker is already installed during LXC provisioning in lxc-manager.sh
    # Just verify it's available
    if ! pct exec "$ct_id" -- docker --version >/dev/null 2>&1; then
        print_error "Docker not found in container"
        exit 1
    fi
    
    print_success "Docker verified"
}

# Deploy Docker Compose services - pull latest images
deploy_docker_services() {
    local stack_name="$1"
    local ct_id="$2"

    print_info "Deploying services for $stack_name"

    # Pull images and deploy in one command
    pct exec "$ct_id" -- sh -c "cd /root && docker compose up -d --pull always --remove-orphans" || {
        print_error "Failed to deploy services"
        exit 1
    }

    print_success "Services deployed"
}

# Full Docker deployment workflow
deploy_docker_stack() {
    local stack_name="$1"
    local ct_id="$2"
    
    # Check if docker-compose.yml exists for this stack
    local compose_url="$REPO_BASE_URL/docker/$stack_name/docker-compose.yml"
    local http_code
    http_code=$(curl -sSL -w "%{http_code}" -o /dev/null "$compose_url" || echo "000")
    
    if [[ "$http_code" != "200" ]]; then
        print_info "No docker-compose.yml found for $stack_name, skipping"
        return 0
    fi
    
    install_docker "$ct_id"
    
    # Setup Promtail for log aggregation (all Docker stacks except monitoring)
    if [[ "$stack_name" != "monitoring" ]]; then
        local hostname
        hostname=$(yq -r ".stacks.${stack_name}.hostname" "$WORK_DIR/stacks.yaml")
        setup_promtail_config "$ct_id" "$hostname"
    fi

    # Setup Homepage config files for webtools stack
    if [[ "$stack_name" == "webtools" ]]; then
        setup_homepage_config "$ct_id"
        setup_couchdb_config "$ct_id"
    fi

    # Setup Immich directories for media stack
    if [[ "$stack_name" == "media" ]]; then
        setup_immich_directories
    fi

    setup_docker_compose "$stack_name" "$ct_id"
    deploy_docker_services "$stack_name" "$ct_id"
    
    print_success "Stack deployed: $stack_name"
}

# Update Docker services
update_docker_services() {
    local ct_id="$1"
    
    print_info "Updating services"
    
    # Pull latest images and recreate containers
    pct exec "$ct_id" -- sh -c "cd /root && docker compose pull" || { print_error "Failed to pull images"; exit 1; }
    pct exec "$ct_id" -- sh -c "cd /root && docker compose up -d --remove-orphans" || { print_error "Failed to recreate containers"; exit 1; }
    
    # Clean up old images
    pct exec "$ct_id" -- docker image prune -f
    
    print_success "Services updated"
}

# Remove Docker services
remove_docker_services() {
    local ct_id="$1"
    
    print_info "Removing services"
    
    # Stop and remove containers
    if pct exec "$ct_id" -- test -f /root/docker-compose.yml; then
        pct exec "$ct_id" -- sh -c "cd /root && docker-compose down -v --remove-orphans"
    fi
    
    # Remove all containers, networks, and volumes
    pct exec "$ct_id" -- docker system prune -af --volumes 2>/dev/null || true
    
    print_success "Services removed"
}