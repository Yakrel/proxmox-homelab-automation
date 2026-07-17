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
    print_info "Stack names are defined in $WORK_DIR/stacks.yaml"
    exit 1
fi

STACK_NAME=$1

# --- Load Deployment Modules ---
source "$WORK_DIR/scripts/modules/docker-deployment.sh"
source "$WORK_DIR/scripts/modules/backrest-deployment.sh"

# --- Global Variables ---
ENV_DECRYPTED_PATH=""

cleanup_deploy_secrets() {
    cleanup_runtime_temp_files
    if [[ -n "${ENV_DECRYPTED_PATH:-}" ]]; then
        rm -f -- "$ENV_DECRYPTED_PATH"
        ENV_DECRYPTED_PATH=""
    fi
    unset ENV_ENC_KEY
}

trap cleanup_deploy_secrets EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

# --- Core Deployment Functions ---

# Decrypt environment file for stacks that need it
decrypt_env_for_deploy() {
    local stack="$1"

    print_info "Decrypting environment for $stack"

    local enc_file="$WORK_DIR/docker/$stack/.env.enc"
    ENV_DECRYPTED_PATH="$WORK_DIR/.env"

    if [[ ! -f "$enc_file" ]]; then
        print_error "Encrypted environment file not found at $enc_file"
        exit 1
    fi

    # Get passphrase and decrypt
    local pass
    pass=$(prompt_env_passphrase)

    # Export passphrase for use by deployment modules (e.g., backup stack needs it)
    ENV_ENC_KEY="$pass"
    export ENV_ENC_KEY

    (
        umask 077
        printf '%s' "$pass" | openssl enc -d -aes-256-cbc -pbkdf2 -salt -pass stdin -in "$enc_file" -out "$ENV_DECRYPTED_PATH"
    ) || {
        print_error "Failed to decrypt .env.enc"
        rm -f "$ENV_DECRYPTED_PATH"
        exit 1
    }

    print_success "Environment decrypted"
}

# Prepare host environment
prepare_host() {
    print_info "Preparing host"
    
    # Ensure minimal required packages
    require_root
    ensure_packages curl python3 yq
    
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
    pct exec "$CT_ID" -- chmod 0600 /root/.env

    print_success "Environment configured"
}




echo
echo "═══════════════════════════════════════════"
print_info "Deploying stack: $STACK_NAME"
echo "═══════════════════════════════════════════"

# Step 1: Prepare the host before decrypting secrets.
prepare_host
get_stack_config "$STACK_NAME"

# Step 2: Environment setup
if [[ "$STACK_NAME" == "dev" ]]; then
    : # No .env needed
else
    decrypt_env_for_deploy "$STACK_NAME"
fi

# Step 3: Create LXC container
create_lxc

# Step 4: Stack-specific pre-deployment
case "$STACK_NAME" in
    "utility")
        deploy_backrest "$CT_ID"
        ;;
    "desktop")
        setup_homepage_proxmox_token "$ENV_DECRYPTED_PATH"
        ;;
esac

if [[ "$STACK_NAME" != "dev" ]]; then
    configure_env
    deploy_docker_stack "$STACK_NAME" "$CT_ID"
fi

if [[ "$STACK_NAME" == "gateway" ]]; then
    ts_key=$(get_env_value "TAILSCALE_AUTH_KEY")
    if [[ -n "$ts_key" ]]; then
        print_info "Configuring Tailscale on Proxmox host..."
        TAILSCALE_AUTH_KEY="$ts_key" bash "$WORK_DIR/scripts/setup-tailscale-host.sh"
    else
        print_info "TAILSCALE_AUTH_KEY not defined in gateway environment. Skipping Tailscale host setup."
    fi
fi

# Remove the host-side plaintext environment before returning to the menu.
cleanup_deploy_secrets

echo "═══════════════════════════════════════════"
print_success "Stack [$STACK_NAME] deployed successfully!"
echo "═══════════════════════════════════════════"
echo

# IMPORTANT: Keep this interactive prompt so errors and deployment output remain visible
# before the installer returns to the menu.
# DO NOT REMOVE - requested by @Yakrel
press_enter_to_continue
