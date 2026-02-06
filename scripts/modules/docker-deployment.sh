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

    # Copy all files from local workspace
    for config_file in "${config_files[@]}"; do
        local source_file="$WORK_DIR/config/homepage/$config_file"
        local dest_file="/datapool/config/homepage/$config_file"
        
        if [[ -f "$source_file" ]]; then
            cp "$source_file" "$dest_file" || {
                print_error "Failed to copy $config_file"
                exit 1
            }
        else
            print_error "Source file not found: $source_file"
            exit 1
        fi
    done

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
    local source_file="$WORK_DIR/config/couchdb-local.ini"
    local dest_file="/datapool/config/couchdb/local.d/local.ini"

    if [[ -f "$source_file" ]]; then
        cp "$source_file" "$dest_file" || {
            print_error "Failed to copy couchdb-local.ini"
            exit 1
        }
    else
        print_error "Source file not found: $source_file"
        exit 1
    fi

    print_success "CouchDB configured"
}

# Setup Immich directories with correct ownership
setup_immich_directories() {
    print_info "Preparing Immich directories"

    # Create all required Immich directories
    mkdir -p /datapool/media/immich/{upload,library,thumbs,profile,backups,encoded-video}
    mkdir -p /datapool/config/immich/postgres

    # Permissions are handled globally by fix_all_permissions

    # Set appropriate permissions (chmod only, ownership handled globally)
    chmod -R 755 /datapool/media/immich
    chmod -R 700 /datapool/config/immich/postgres

    print_success "Immich configured"
}

# Setup Tdarr directories
setup_tdarr_directories() {
    print_info "Preparing Tdarr directories"

    # Create config and temp directories
    mkdir -p /datapool/config/tdarr/{server,configs,logs}
    mkdir -p /datapool/temp/tdarr

    # Ensure correct ownership for LXC user (101000 mapping for user 1000)
    chown -R 101000:101000 /datapool/config/tdarr
    chown -R 101000:101000 /datapool/temp/tdarr

    # Ensure correct permissions for the temp directory (transcoding needs write access)
    chmod -R 777 /datapool/temp/tdarr

    print_success "Tdarr configured"
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
    
    # Copy compose file from local workspace
    local source_file="$WORK_DIR/docker/$stack_name/docker-compose.yml"
    
    if [[ -f "$source_file" ]]; then
        # Copy to container root directory directly
        pct push "$ct_id" "$source_file" "/root/docker-compose.yml" || { 
            print_error "Failed to push compose file"
            exit 1 
        }
    else
        print_error "docker-compose.yml not found at $source_file"
        exit 1
    fi
    
    print_success "Docker Compose configured"
}

# Verify Docker is available in container (already installed during LXC provisioning)
verify_docker() {
    local ct_id="$1"

    # Docker should already be installed by lxc-manager.sh
    # This verification will fail-fast with visible error if missing
    pct exec "$ct_id" -- docker --version

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

# Setup aliases and MOTD for game servers
setup_gameserver_aliases() {
    local ct_id="$1"
    print_info "Configuring Game Server aliases"

    # Define the marker used to identify our block
    local start_marker="# --- Game Server Manager Aliases ---"
    local end_marker="# --- End Game Server Manager ---"

    # Create the alias content locally
    local alias_file="/tmp/gameserver_aliases.sh"
    cat <<EOF > "$alias_file"

$start_marker
# Aliases for Game Server Management
# Core services (cadvisor, promtail, watchtower) always run via base compose
# Game servers are managed separately via profiles

# Ensure core services are always running, then start/stop game containers
alias start-palworld='cd /root && echo "Starting Palworld..." && docker stop satisfactory-server 2>/dev/null || true && docker compose up -d && docker compose --profile palworld up -d --pull always'
alias start-satisfactory='cd /root && echo "Starting Satisfactory..." && docker stop palworld-server 2>/dev/null || true && docker compose up -d && docker compose --profile satisfactory up -d --pull always'
alias stop-games='cd /root && echo "Stopping all game servers..." && docker stop palworld-server satisfactory-server 2>/dev/null || true'
alias game-status='cd /root && docker compose ps -a'

# --- Game Server MOTD (Login Message) ---
# Display only on interactive shell login
if [ -t 0 ]; then
    echo -e "\033[1;36m=====================================================\033[0m"
    echo -e "\033[1;32m       Proxmox Homelab Game Server Manager           \033[0m"
    echo -e "\033[1;36m=====================================================\033[0m"
    echo -e " Available Commands:"
    echo -e "  \033[1;33mstart-palworld\033[0m      : Start Palworld (stops others)"
    echo -e "  \033[1;33mstart-satisfactory\033[0m  : Start Satisfactory (stops others)"
    echo -e "  \033[1;33mstop-games\033[0m          : Stop all running games"
    echo -e "  \033[1;33mgame-status\033[0m         : Show running containers"
    echo -e "\033[1;36m=====================================================\033[0m"
    echo
fi
$end_marker
EOF

    # Target files for aliases (Alpine uses .profile by default, Bash uses .bashrc)
    local target_files=("/root/.bashrc" "/root/.profile")
    
    # Push the alias file to the container
    pct push "$ct_id" "$alias_file" "/tmp/aliases.sh"

    # Loop through targets and apply changes
    for target in "${target_files[@]}"; do
        # Create file if it doesn't exist
        pct exec "$ct_id" -- touch "$target"
        
        # Clean existing block if present (Idempotency) using sed
        pct exec "$ct_id" -- sh -c "if grep -qF '$start_marker' '$target'; then sed -i '/$start_marker/,/$end_marker/d' '$target'; fi"
        
        # Append new block
        pct exec "$ct_id" -- sh -c "cat /tmp/aliases.sh >> '$target'"
    done

    # Cleanup
    pct exec "$ct_id" -- rm -f "/tmp/aliases.sh"
    rm -f "$alias_file"

    print_success "Game Server aliases configured"
}

# Full Docker deployment workflow
deploy_docker_stack() {
    local stack_name="$1"
    local ct_id="$2"
    
    # Check if docker-compose.yml exists for this stack locally
    local compose_file="$WORK_DIR/docker/$stack_name/docker-compose.yml"
    
    if [[ ! -f "$compose_file" ]]; then
        print_info "No docker-compose.yml found for $stack_name at $compose_file, skipping"
        return 0
    fi
    
    verify_docker "$ct_id"
    
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
        setup_tdarr_directories
        
        # Setup secure vault infrastructure requirements
        print_info "Installing security tools for media stack"
        pct exec "$ct_id" -- apt-get update
        pct exec "$ct_id" -- apt-get install -y gocryptfs
    fi

    setup_docker_compose "$stack_name" "$ct_id"
    deploy_docker_services "$stack_name" "$ct_id"

    # Setup aliases for gameservers stack
    if [[ "$stack_name" == "gameservers" ]]; then
        setup_gameserver_aliases "$ct_id"
    fi
    
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