#!/bin/bash

# =================================================================
#                 Main Stack Deployment Orchestrator
# =================================================================
# This script orchestrates the deployment of homelab stacks using
# specialized modules for different deployment types.
# Strict error handling
set -euo pipefail

WORK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)"

# --- Load Shared Functions ---
source "$WORK_DIR/scripts/helper-functions.sh"

# --- Arguments and Setup ---
if [[ $# -eq 0 ]]; then
    print_error "Usage: $0 <stack-name>"
    print_info "Available stacks: $(get_available_stacks | tr '\n' ' ')"
    exit 1
fi

STACK_NAME=$1

# --- Load Deployment Modules ---
source "$WORK_DIR/scripts/modules/docker-deployment.sh"
source "$WORK_DIR/scripts/modules/monitoring-deployment.sh"
source "$WORK_DIR/scripts/modules/backrest-deployment.sh"

# --- Global Variables ---
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

    print_info "Decrypting environment for $stack"

    local enc_file="$WORK_DIR/docker/$stack/.env.enc"
    local enc_tmp="$WORK_DIR/.env.enc"
    ENV_DECRYPTED_PATH="$WORK_DIR/.env"

    if [[ ! -f "$enc_file" ]]; then
        print_error "Encrypted environment file not found at $enc_file"
        exit 1
    fi

    cp "$enc_file" "$enc_tmp" || { print_error "Failed to copy .env.enc"; exit 1; }

    # Get passphrase and decrypt
    local pass
    pass=$(prompt_env_passphrase)

    # Export passphrase for use by deployment modules (e.g., backup stack needs it)
    ENV_ENC_KEY="$pass"
    export ENV_ENC_KEY

    # Decrypt
    printf '%s' "$pass" | openssl enc -d -aes-256-cbc -pbkdf2 -salt -pass stdin -in "$enc_tmp" -out "$ENV_DECRYPTED_PATH" || {
        print_error "Failed to decrypt .env.enc"
        rm -f "$enc_tmp" "$ENV_DECRYPTED_PATH"
        exit 1
    }
    rm -f "$enc_tmp"

    print_success "Environment decrypted"
}

# Prepare host environment
prepare_host() {
    print_info "Preparing host"
    
    # Ensure minimal required packages
    require_root
    ensure_packages curl yq
    
    print_success "Host ready"
}


# Create or verify LXC container
create_lxc() {
    print_info "Creating LXC for $STACK_NAME"
    
    # Use lxc-manager.sh to create and configure the container
    bash "$WORK_DIR/scripts/lxc-manager.sh" "$STACK_NAME" || { print_error "LXC setup failed"; exit 1; }
    
    print_success "LXC ready"
}

# Configure environment file for standard Docker stacks
configure_env() {
    # Copy decrypted .env to container
    pct push "$CT_ID" "$ENV_DECRYPTED_PATH" "/root/.env" || { print_error "Failed to configure environment"; exit 1; }

    print_success "Environment configured"
}

# Setup Promtail configuration for Docker stacks
configure_promtail_config() {
    local ct_id="$1"

    # Get hostname from stacks.yaml
    local hostname
    hostname=$(yq -r ".stacks.$STACK_NAME.hostname" "$WORK_DIR/stacks.yaml")
    [[ -n "$hostname" ]] || { print_error "Could not find hostname for $STACK_NAME"; exit 1; }

    setup_promtail_config "$ct_id" "$hostname"
}



echo
echo "═══════════════════════════════════════════"
print_info "Deploying stack: $STACK_NAME"
echo "═══════════════════════════════════════════"

# Load stack configuration
get_stack_config "$STACK_NAME"

# Step 1: Environment setup
if [[ "$STACK_NAME" == "dev" ]]; then
    : # No .env needed
elif [[ "$STACK_NAME" == "monitor" ]]; then
    decrypt_env_for_deploy "$STACK_NAME"
    PVE_MONITORING_PASSWORD=$(grep "^PVE_MONITORING_PASSWORD=" "$ENV_DECRYPTED_PATH" | cut -d'=' -f2-)
    [[ -z "$PVE_MONITORING_PASSWORD" ]] && { print_error "PVE_MONITORING_PASSWORD not found"; exit 1; }
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
    "dev")
        : # Setup completed by LXC manager
        ;;
    "utility")
        if deploy_backrest "$CT_ID"; then
            print_success "Backrest configured"
        else
            print_error "Backrest failed"
            exit 1
        fi
        
        configure_env
        configure_promtail_config "$CT_ID"
        deploy_docker_stack "$STACK_NAME" "$CT_ID" || { print_error "Deployment failed"; exit 1; }
        ;;
    "monitor")
        deploy_monitoring_stack "$STACK_NAME" "$CT_ID" || { print_error "Deployment failed"; exit 1; }
        ;;
    "desktop")
        setup_homepage_proxmox_token
        configure_env
        configure_promtail_config "$CT_ID"
        deploy_docker_stack "$STACK_NAME" "$CT_ID" || { print_error "Deployment failed"; exit 1; }
        ;;
    "gateway")
        configure_env
        configure_promtail_config "$CT_ID"
        deploy_docker_stack "$STACK_NAME" "$CT_ID" || { print_error "Deployment failed"; exit 1; }
        
        # Install and configure Tailscale on host (idempotent subnet router)
        if [[ -f "${ENV_DECRYPTED_PATH:-}" ]]; then
            ts_key=$(grep "^TAILSCALE_AUTH_KEY=" "$ENV_DECRYPTED_PATH" | cut -d'=' -f2- | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//")
            if [[ -n "$ts_key" ]]; then
                print_info "Configuring Tailscale on Proxmox host..."
                TAILSCALE_AUTH_KEY="$ts_key" bash "$WORK_DIR/scripts/setup-tailscale-host.sh"
            else
                print_info "TAILSCALE_AUTH_KEY not defined in gateway environment. Skipping Tailscale host setup."
            fi
        fi
        ;;
    *)
        configure_env
        configure_promtail_config "$CT_ID"
        deploy_docker_stack "$STACK_NAME" "$CT_ID" || { print_error "Deployment failed"; exit 1; }
        ;;
esac

# Step 5: Finalize permissions
# Fix permissions on /datapool globally after Docker creates volumes
fix_all_permissions

# Cleanup
rm -f "$ENV_DECRYPTED_PATH" 2>/dev/null || true

echo "═══════════════════════════════════════════"
print_success "Stack [$STACK_NAME] deployed successfully!"
echo "═══════════════════════════════════════════"
echo

# IMPORTANT: Keep this interactive prompt so errors and deployment output remain visible
# before the installer returns to the menu.
# DO NOT REMOVE - requested by @Yakrel
press_enter_to_continue
