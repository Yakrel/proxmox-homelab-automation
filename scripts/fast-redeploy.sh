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
TEMP_DIR=""

cleanup_fast_redeploy_secrets() {
    cleanup_runtime_temp_files
    if [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then
        rm -rf -- "${TEMP_DIR:?}"
        TEMP_DIR=""
    fi
    ENV_DECRYPTED_PATH=""
    unset ENV_ENC_KEY
}

trap cleanup_fast_redeploy_secrets EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

decrypt_stack_env() {
    local stack="$1"
    local enc_file="$WORK_DIR/docker/$stack/.env.enc"
    local output_file="$TEMP_DIR/${stack}.env"

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

    get_stack_config "$stack"

    [[ "$stack" != "dev" ]] || {
        if ! check_container_running "$CT_ID"; then
            print_warning "Skipping $stack: LXC $CT_ID is not running"
            return 0
        fi

        print_info "Fast redeploying dev CLI applications"
        decrypt_stack_env ai
        AGENTMEMORY_ENV_FILE="$ENV_DECRYPTED_PATH" \
            bash "$WORK_DIR/scripts/lxc-manager.sh" dev
        rm -f "$ENV_DECRYPTED_PATH"
        ENV_DECRYPTED_PATH=""
        print_success "Fast redeployed: dev"
        return 0
    }

    [[ -f "$WORK_DIR/docker/$stack/docker-compose.yml" ]] || {
        print_error "docker-compose.yml not found for $stack"
        return 1
    }

    if ! check_container_running "$CT_ID"; then
        print_warning "Skipping $stack: LXC $CT_ID is not running"
        return 0
    fi

    echo
    print_info "Fast redeploying [$stack] on LXC $CT_ID ($CT_HOSTNAME)"

    decrypt_stack_env "$stack"

    if [[ "$stack" == "desktop" ]]; then
        setup_homepage_proxmox_token "$ENV_DECRYPTED_PATH"
    elif [[ "$stack" == "utility" ]]; then
        deploy_backrest "$CT_ID"
    fi

    prepare_docker_stack "$stack"

    pct push "$CT_ID" "$ENV_DECRYPTED_PATH" /root/.env
    pct exec "$CT_ID" -- chmod 0600 /root/.env
    setup_docker_compose "$stack" "$CT_ID"

    local compose_build_flag=""
    local compose_wait_flags=""
    if [[ "$stack" == "ai" ]]; then
        compose_build_flag="--build"
        compose_wait_flags="--wait --wait-timeout 120"
    fi

    pct exec "$CT_ID" -- sh -c \
        "cd /root && docker compose up -d $compose_build_flag $compose_wait_flags --remove-orphans"

    rm -f "$ENV_DECRYPTED_PATH"
    ENV_DECRYPTED_PATH=""

    print_success "Fast redeployed: $stack"
}

main() {
    require_root
    umask 077
    TEMP_DIR=$(mktemp -d /tmp/fast-redeploy.XXXXXX)

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

    cleanup_fast_redeploy_secrets

    print_success "Fast redeploy completed"
}

main "$@"
