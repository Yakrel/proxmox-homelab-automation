#!/bin/bash

# =================================================================
#                 Main Stack Deployment Orchestrator
# =================================================================
# This script orchestrates the deployment of homelab stacks using
# specialized modules for different deployment types.
# Strict error handling
set -euo pipefail

# --- Arguments and Setup ---
if [[ $# -eq 0 ]]; then
    print_error "Usage: $0 <stack-name>"
    print_info "Available stacks: $(get_available_stacks | tr '\n' ' ')"
    exit 1
fi

STACK_NAME=$1
WORK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)"

# --- Load Shared Functions ---
source "$WORK_DIR/scripts/helper-functions.sh"

# --- Load Deployment Modules ---
source "$WORK_DIR/scripts/modules/docker-deployment.sh"
source "$WORK_DIR/scripts/modules/monitoring-deployment.sh"
source "$WORK_DIR/scripts/modules/backup-deployment.sh"

# --- Global Variables ---
REPO_BASE_URL=$(get_repo_base_url)
PVE_MONITORING_PASSWORD=""
ENV_DECRYPTED_PATH=""

# --- Early Validation ---
# Validate stack name
get_available_stacks | grep -q "^$STACK_NAME$" || {
    print_error "Invalid stack name: $STACK_NAME"
    print_info "Available stacks: $(get_available_stacks | tr '\n' ' ')"
    exit 1
}

# --- Core Deployment Functions ---

# Decrypt environment file for stacks that need it
decrypt_env_for_deploy() {
    local stack="$1"
    
    print_info "Decrypting environment file for $stack"
    
    local enc_url="$REPO_BASE_URL/docker/$stack/.env.enc"
    local enc_tmp="$WORK_DIR/.env.enc"
    ENV_DECRYPTED_PATH="$WORK_DIR/.env"

    curl -sSL "$enc_url" -o "$enc_tmp" || { print_error "Failed to download .env.enc"; exit 1; }
    
    # Single passphrase prompt
    local pass
    pass=$(prompt_env_passphrase)
    
    # Decrypt - fail fast
    printf '%s' "$pass" | openssl enc -d -aes-256-cbc -pbkdf2 -pass stdin -in "$enc_tmp" -out "$ENV_DECRYPTED_PATH" 2>/dev/null || {
        print_error "Failed to decrypt .env.enc"
        rm -f "$enc_tmp" "$ENV_DECRYPTED_PATH"
        exit 1
    }
    rm -f "$enc_tmp"
    
    print_success "Environment file decrypted"
}

# Prepare host environment
prepare_host() {
    print_info "Preparing host environment"
    
    # Ensure minimal required packages
    require_root
    ensure_packages curl yq
    
    print_success "Host environment ready"
}

# Setup Proxmox monitoring user (for monitoring stack)
setup_proxmox_monitoring_user() {
    print_info "Setting up Proxmox monitoring user"
    
    local pve_user="pve-exporter@pve"
    
    # Check if user already exists
    if pveum user list | grep -q "$pve_user"; then
        print_info "Updating PVE monitoring user password"
        pveum user modify "$pve_user" --password "$PVE_MONITORING_PASSWORD"
    else
        print_info "Creating PVE monitoring user: $pve_user"
        pveum user add "$pve_user" --password "$PVE_MONITORING_PASSWORD" --comment "Prometheus monitoring user"
        pveum acl modify / --user "$pve_user" --role PVEAuditor
    fi
    
    print_success "PVE monitoring user configured"
}

# Create LXC container
create_lxc() {
    print_info "Creating LXC container for $STACK_NAME"
    
    # Use lxc-manager.sh to create and configure the container
    bash "$WORK_DIR/scripts/lxc-manager.sh" "$STACK_NAME" || { print_error "LXC creation failed"; exit 1; }
    
    print_success "LXC container created"
}

# Configure environment file for standard Docker stacks
configure_env() {
    print_info "Configuring environment for $STACK_NAME"
    
    # Copy decrypted .env to container
    pct push "$CT_ID" "$ENV_DECRYPTED_PATH" "/root/.env" || { print_error "Failed to configure environment"; exit 1; }
    
    print_success "Environment configured"
}



print_info "Starting deployment: $STACK_NAME"
print_info "============================================"

# Load stack configuration
get_stack_config "$STACK_NAME"

# Step 1: Environment setup
if [[ "$STACK_NAME" == "development" || "$STACK_NAME" == "backup" ]]; then
    print_info "No .env file needed for $STACK_NAME"
elif [[ "$STACK_NAME" == "monitoring" ]]; then
    decrypt_env_for_deploy "$STACK_NAME"
    PVE_MONITORING_PASSWORD=$(openssl rand -base64 16 | tr -d "=+/" | cut -c1-12)
    print_info "Generated PVE monitoring password"
    setup_proxmox_monitoring_user
else
    decrypt_env_for_deploy "$STACK_NAME"
fi

# Step 2: Prepare host
prepare_host

# Step 3: Create LXC container
create_lxc

# Step 4: Stack-specific deployment
case "$STACK_NAME" in
    "development")
        print_info "Development stack setup completed by LXC manager"
        ;;
    "backup")
        print_info "Starting PBS configuration..."
        
        if configure_pbs "$CT_ID"; then
            print_success "PBS configuration completed successfully"
            
            if configure_pve_backup_job; then
                print_success "PVE backup job configuration completed"
            else
                print_warning "PVE backup job configuration failed - you can configure it manually later"
                print_info "This does not affect PBS functionality"
                press_enter_to_continue
            fi
        else
            print_error "PBS configuration failed!"
            print_info "Check container logs: pct exec $CT_ID -- journalctl -u proxmox-backup"
            exit 1
        fi
        ;;
    "monitoring")
        deploy_monitoring_stack "$STACK_NAME" "$CT_ID" || { print_error "Monitoring deployment failed"; exit 1; }
        ;;
    *)
        configure_env
        configure_promtail_config "$CT_ID"
        deploy_docker_stack "$STACK_NAME" "$CT_ID" || { print_error "Docker deployment failed"; exit 1; }
        ;;
esac

# Cleanup
rm -f "$ENV_DECRYPTED_PATH" 2>/dev/null || true

print_success "Deployment completed: $STACK_NAME"
print_success "============================================"

# Show stack information
case "$STACK_NAME" in
    "monitoring")
        show_monitoring_info "$CT_ID" "$CT_IP"
        ;;
    "backup")
        show_backup_info "$CT_ID" "$CT_IP"
        ;;
    "proxy")
        print_info "Proxy Stack: http://$CT_IP"
        ;;
    *)
        print_info "Stack deployed at: http://$CT_IP"
        print_info "Container ID: $CT_ID | Hostname: $CT_HOSTNAME"
        print_info "Access: pct exec $CT_ID -- bash"
        ;;
esac

print_success "Stack [$STACK_NAME] ready!"

# Give user time to review the deployment results
echo
print_info "Deployment completed successfully!"
case "$STACK_NAME" in
    "backup")
        print_info "Your PBS server is ready. Take note of the connection details above."
        ;;
    "monitoring")
        print_info "Your monitoring stack is ready. Access the web interfaces using the URLs above."
        ;;
    *)
        print_info "Your $STACK_NAME stack is ready and running."
        ;;
esac

press_enter_to_continue