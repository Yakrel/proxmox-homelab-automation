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
    
    # Get passphrase and decrypt
    local pass
    pass=$(prompt_env_passphrase)

    # Decrypt
    printf '%s' "$pass" | openssl enc -d -aes-256-cbc -pbkdf2 -salt -pass stdin -in "$enc_tmp" -out "$ENV_DECRYPTED_PATH" || {
        print_error "Failed to decrypt .env.enc - wrong passphrase or corrupted file?"
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
    
    # Check if user already exists (idempotent)
    if pveum user list | grep -qw "$pve_user"; then
        print_info "PVE monitoring user exists, updating password"
        pveum passwd "$pve_user" --password "$PVE_MONITORING_PASSWORD"
    else
        print_info "Creating PVE monitoring user: $pve_user"
        pveum user add "$pve_user" --password "$PVE_MONITORING_PASSWORD" --comment "Prometheus monitoring user"
    fi
    
    # Grant PVEAuditor role (idempotent - command handles existing ACLs)
    pveum acl modify / --user "$pve_user" --role PVEAuditor
    
    print_success "PVE monitoring user configured"
}

# Setup Proxmox API token for Homepage widget
# Always regenerates token to ensure .env has correct secret
setup_homepage_proxmox_token() {
    print_info "Setting up Homepage Proxmox API token"

    local pve_user="homepage@pve"
    local token_name="homepage-token"
    local token_id="$pve_user!$token_name"

    # Create user if not exists (idempotent)
    if ! pveum user list | grep -qw "$pve_user"; then
        print_info "Creating Homepage Proxmox user: $pve_user"
        pveum user add "$pve_user" --comment "Homepage dashboard monitoring"
    fi

    # Grant PVEAuditor role (idempotent - command handles existing ACLs)
    pveum acl modify / --user "$pve_user" --role PVEAuditor

    # Remove old token if exists, then create fresh one
    pveum user token remove "$pve_user" "$token_name" 2>/dev/null || true

    # Create new API token and capture secret
    print_info "Generating fresh API token: $token_id"
    local token_output
    token_output=$(pveum user token add "$pve_user" "$token_name" --privsep 0 --output-format=json)

    # Extract secret value from JSON output
    local token_secret
    token_secret=$(echo "$token_output" | grep -o '"value":"[^"]*"' | cut -d'"' -f4)

    if [[ -z "$token_secret" ]]; then
        print_error "Failed to extract token secret"
        return 1
    fi

    # Replace placeholder with real secret in .env file
    sed -i "s/placeholder_will_be_set_on_deploy/$token_secret/g" "$ENV_DECRYPTED_PATH"

    print_success "Homepage API token configured in .env"
}

# Create or verify LXC container
create_lxc() {
    print_info "Creating LXC container for $STACK_NAME"
    
    # Use lxc-manager.sh to create and configure the container (now idempotent)
    bash "$WORK_DIR/scripts/lxc-manager.sh" "$STACK_NAME" || { print_error "LXC setup failed"; exit 1; }
    
    print_success "LXC container ready"
}

# Configure environment file for standard Docker stacks
configure_env() {
    print_info "Configuring environment for $STACK_NAME"

    # Copy decrypted .env to container
    pct push "$CT_ID" "$ENV_DECRYPTED_PATH" "/root/.env" || { print_error "Failed to configure environment"; exit 1; }

    print_success "Environment configured"
}

# Setup Promtail configuration for Docker stacks
configure_promtail_config() {
    local ct_id="$1"

    print_info "Configuring Promtail for $STACK_NAME"

    # Get hostname from stacks.yaml
    local hostname
    hostname=$(yq -r ".stacks.$STACK_NAME.hostname" "$WORK_DIR/stacks.yaml")
    [[ -n "$hostname" ]] || { print_error "Could not find hostname for $STACK_NAME in stacks.yaml"; exit 1; }

    # Ensure the target directories exist inside the container
    pct exec "$ct_id" -- mkdir -p /etc/promtail /var/lib/promtail/positions || { print_error "Failed to create Promtail directories in container"; exit 1; }

    # Create a temporary, customized promtail config from the template
    local temp_promtail="/tmp/promtail_${hostname}.yml"
    sed "s/REPLACE_HOST_LABEL/$hostname/g" "$WORK_DIR/config/promtail/promtail.yml" > "$temp_promtail"

    # Copy to container
    pct push "$ct_id" "$temp_promtail" "/etc/promtail/promtail.yml" || { print_error "Failed to push Promtail config for $hostname"; rm -f "$temp_promtail"; exit 1; }
    rm -f "$temp_promtail"

    # Note: No chown needed inside LXC - files pushed with pct push get correct ownership from root context
    # Promtail container runs without specific user requirements

    print_success "Promtail configured for $hostname"
}



print_info "Starting deployment: $STACK_NAME"
print_info "============================================"

# Load stack configuration
get_stack_config "$STACK_NAME"

# Step 1: Environment setup
if [[ "$STACK_NAME" == "development" ]]; then
    print_info "No .env file needed for $STACK_NAME"
elif [[ "$STACK_NAME" == "monitoring" ]]; then
    decrypt_env_for_deploy "$STACK_NAME"
    PVE_MONITORING_PASSWORD=$(grep "^PVE_MONITORING_PASSWORD=" "$ENV_DECRYPTED_PATH" | cut -d'=' -f2-)
    [[ -z "$PVE_MONITORING_PASSWORD" ]] && { print_error "PVE_MONITORING_PASSWORD not found in .env file"; exit 1; }
    print_info "Using fixed PVE monitoring password from .env"
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
        print_info "Starting Backrest configuration..."
        
        if deploy_backrest "$CT_ID"; then
            print_success "Backrest deployment completed successfully"
        else
            print_error "Backrest configuration failed!"
            exit 1
        fi
        
        # Deploy docker-compose stack
        configure_env
        configure_promtail_config "$CT_ID"
        deploy_docker_stack "$STACK_NAME" "$CT_ID" || { print_error "Docker deployment failed"; exit 1; }
        ;;
    "monitoring")
        deploy_monitoring_stack "$STACK_NAME" "$CT_ID" || { print_error "Monitoring deployment failed"; exit 1; }
        ;;
    "webtools")
        # Setup Homepage Proxmox API token (idempotent)
        setup_homepage_proxmox_token

        # Standard deployment flow
        configure_env
        configure_promtail_config "$CT_ID"
        deploy_docker_stack "$STACK_NAME" "$CT_ID" || { print_error "Docker deployment failed"; exit 1; }
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
print_success "Stack [$STACK_NAME] ready!"

# IMPORTANT: Keep this interactive prompt - allows user to review deployment results
# and see any error messages before returning to main menu. This is a desired feature.
# DO NOT REMOVE - requested by @Yakrel
press_enter_to_continue