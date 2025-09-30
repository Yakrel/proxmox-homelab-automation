#!/bin/bash

# =================================================================
#                     Docker Deployment Module
# =================================================================
# Handles Docker-based stack deployments - fail fast approach
set -euo pipefail

# Download and configure Docker Compose files
setup_docker_compose() {
    local stack_name="$1"
    local ct_id="$2"
    
    print_info "Setting up Docker Compose for $stack_name"
    
    # Download compose file
    local compose_url="$REPO_BASE_URL/docker/$stack_name/docker-compose.yml"
    local temp_compose="/tmp/docker-compose.yml"
    
    curl -sSL "$compose_url" -o "$temp_compose" || { print_error "Failed to download docker-compose.yml"; exit 1; }
    
    # Copy to container root directory directly
    pct push "$ct_id" "$temp_compose" "/root/docker-compose.yml" || { print_error "Failed to push compose file"; exit 1; }
    rm -f "$temp_compose"
    
    print_success "Docker Compose ready"
}

# Install latest Docker in container
install_docker() {
    local ct_id="$1"
    
    print_info "Installing Docker"
    
    # Update and install Docker
    pct exec "$ct_id" -- apk update
    pct exec "$ct_id" -- apk add --no-cache docker docker-compose docker-cli-compose
    
    # Start Docker service
    pct exec "$ct_id" -- service docker start || { print_error "Failed to start Docker"; exit 1; }
    pct exec "$ct_id" -- rc-update add docker default
    
    # Verify Docker is ready - fail fast
    pct exec "$ct_id" -- docker info || { print_error "Docker failed to start"; exit 1; }
    
    print_success "Docker installed"
}

# Deploy Docker Compose services - pull latest images
deploy_docker_services() {
    local stack_name="$1"
    local ct_id="$2"
    
    print_info "Deploying Docker services for $stack_name"
    
    # Deploy services
    pct exec "$ct_id" -- sh -c "cd /root && docker-compose pull --quiet && docker-compose up -d --remove-orphans" || {
        print_error "Failed to deploy Docker services"
        exit 1
    }
    
    print_success "Docker services deployed"
}

# Full Docker deployment workflow
deploy_docker_stack() {
    local stack_name="$1"
    local ct_id="$2"
    
    print_info "Deploying Docker stack: $stack_name"
    
    # Check if docker-compose.yml exists for this stack
    local compose_url="$REPO_BASE_URL/docker/$stack_name/docker-compose.yml"
    if ! curl -sSf --head "$compose_url" 2>&1 | grep -q "200 OK"; then
        print_info "No docker-compose.yml found for $stack_name, skipping Docker deployment"
        return 0
    fi
    
    if [[ "$stack_name" != "media" ]]; then
        install_docker "$ct_id"
    else
        print_info "Docker is pre-installed for stack '$stack_name'. Verifying..."
        pct exec "$ct_id" -- docker info >/dev/null || { print_error "Docker verification failed for $stack_name"; exit 1; }
        print_success "Docker verification passed for $stack_name"
    fi
    setup_docker_compose "$stack_name" "$ct_id"
    deploy_docker_services "$stack_name" "$ct_id"
    
    print_success "Docker deployment completed: $stack_name"
}

# Check Docker container health
check_docker_health() {
    local ct_id="$1"
    
    print_info "Checking Docker health"
    
    # Check if Docker daemon is running
    pct exec "$ct_id" -- docker info || { print_error "Docker daemon not running"; exit 1; }
    
    # Check running containers
    local container_count
    container_count=$(pct exec "$ct_id" -- docker ps -q | wc -l)
    
    print_info "Docker daemon: Running"
    print_info "Active containers: $container_count"
    
    # Show container status
    if [[ $container_count -gt 0 ]]; then
        print_info "Container status:"
        pct exec "$ct_id" -- docker ps --format "table {{.Names}}\t{{.Status}}"
    fi
}

# Update Docker services
update_docker_services() {
    local ct_id="$1"
    
    print_info "Updating Docker services"
    
    # Pull latest images and recreate containers
    pct exec "$ct_id" -- sh -c "cd /root && docker-compose pull" || { print_error "Failed to pull images"; exit 1; }
    pct exec "$ct_id" -- sh -c "cd /root && docker-compose up -d --remove-orphans" || { print_error "Failed to recreate containers"; exit 1; }
    
    # Clean up old images
    pct exec "$ct_id" -- docker image prune -f
    
    print_success "Docker services updated"
}

# Remove Docker services
remove_docker_services() {
    local ct_id="$1"
    
    print_info "Removing Docker services"
    
    # Stop and remove containers
    if pct exec "$ct_id" -- test -f /root/docker-compose.yml; then
        pct exec "$ct_id" -- sh -c "cd /root && docker-compose down -v --remove-orphans"
    fi
    
    # Remove all containers, networks, and volumes
    pct exec "$ct_id" -- docker system prune -af --volumes 2>/dev/null || true
    
    print_success "Docker services removed"
}