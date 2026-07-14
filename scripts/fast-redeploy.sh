#!/bin/bash

# Fast Docker stack redeploy without LXC provisioning or package installation.
# Usage: fast-redeploy.sh [stack-name ...]
set -euo pipefail

WORK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)"

source "$WORK_DIR/scripts/helper-functions.sh"
source "$WORK_DIR/scripts/modules/docker-deployment.sh"
source "$WORK_DIR/scripts/modules/backrest-deployment.sh"

ENV_ENC_KEY=""
ENV_DECRYPTED_PATH=""

decrypt_stack_env() {
    local stack="$1"
    local enc_file="$WORK_DIR/docker/$stack/.env.enc"
    local output_file="/tmp/${stack}.fast-redeploy.env"

    [[ -f "$enc_file" ]] || {
        print_warning "No encrypted env found for $stack, skipping .env refresh"
        return 1
    }

    printf '%s' "$ENV_ENC_KEY" | openssl enc -d -aes-256-cbc -pbkdf2 -salt -pass stdin -in "$enc_file" -out "$output_file" || {
        rm -f "$output_file"
        print_error "Failed to decrypt docker/$stack/.env.enc"
        exit 1
    }

    ENV_DECRYPTED_PATH="$output_file"
    export ENV_DECRYPTED_PATH ENV_ENC_KEY
}



fast_redeploy_stack() {
    local stack="$1"

    [[ "$stack" != "dev" ]] || {
        print_info "Skipping dev stack (no Docker compose)"
        return 0
    }

    local compose_file="$WORK_DIR/docker/$stack/docker-compose.yml"
    [[ -f "$compose_file" ]] || {
        print_info "Skipping $stack (no docker-compose.yml)"
        return 0
    }

    get_stack_config "$stack"

    if ! check_container_running "$CT_ID"; then
        print_warning "Skipping $stack: LXC $CT_ID is not running"
        return 0
    fi

    verify_docker "$CT_ID"

    echo
    print_info "Fast redeploying [$stack] on LXC $CT_ID ($CT_HOSTNAME)"

    decrypt_stack_env "$stack"

    if [[ "$stack" == "desktop" ]]; then
        setup_desktop_permissions
        setup_homepage_config "$CT_ID"
        setup_couchdb_config "$CT_ID"
        setup_homepage_proxmox_token "$ENV_DECRYPTED_PATH"
        setup_guacamole_config "$CT_ID"
        setup_sshwifty_config "$CT_ID"
    elif [[ "$stack" == "utility" ]]; then
        setup_utility_permissions
        deploy_backrest "$CT_ID"
    elif [[ "$stack" == "gateway" ]]; then
        setup_gateway_permissions
    elif [[ "$stack" == "ai" ]]; then
        setup_ai_permissions
    fi

    pct push "$CT_ID" "$ENV_DECRYPTED_PATH" /root/.env
    pct push "$CT_ID" "$compose_file" /root/docker-compose.yml

    pct exec "$CT_ID" -- sh -c "cd /root && docker compose up -d --remove-orphans"

    rm -f "$ENV_DECRYPTED_PATH"
    ENV_DECRYPTED_PATH=""

    print_success "Fast redeployed: $stack"
}

main() {
    require_root

    local -a stacks=()

    if [[ $# -gt 0 ]]; then
        stacks=("$@")
    else
        while IFS= read -r stack; do
            stacks+=("$stack")
        done < <(get_available_stacks "$WORK_DIR/stacks.yaml")
    fi

    ENV_ENC_KEY=$(prompt_env_passphrase)
    export ENV_ENC_KEY

    for stack in "${stacks[@]}"; do
        fast_redeploy_stack "$stack"
    done

    rm -f /tmp/*.fast-redeploy.env

    print_success "Fast redeploy completed"
}

main "$@"
