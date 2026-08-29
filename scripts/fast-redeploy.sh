#!/bin/bash

# Fast Docker stack redeploy without LXC provisioning or package installation.
# Usage: fast-redeploy.sh [stack-name ...]
set -euo pipefail

WORK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)"

source "$WORK_DIR/scripts/helper-functions.sh"
source "$WORK_DIR/scripts/modules/docker-deployment.sh"
source "$WORK_DIR/scripts/modules/backrest-deployment.sh"
source "$WORK_DIR/scripts/modules/dev-terminal.sh"

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

    decrypt_openssl_file "$enc_file" "$output_file" "$ENV_ENC_KEY" || {
        rm -f "$output_file"
        print_error "Failed to decrypt docker/$stack/.env.enc"
        exit 1
    }
    if ! validate_env_file_schema "$output_file" "$WORK_DIR/docker/$stack/.env.example"; then
        rm -f "$output_file"
        print_error "Encrypted environment schema does not match docker/$stack/.env.example"
        exit 1
    fi

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
        bash "$WORK_DIR/scripts/lxc-manager.sh" dev
        deploy_dev_terminal "$CT_ID"
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

    # Reconcile host-side LXC configuration before applying the stack. This
    # also restarts an existing LXC when a bind mount or device changed.
    bash "$WORK_DIR/scripts/lxc-manager.sh" "$stack"

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

    deploy_docker_services "$stack" "$CT_ID"

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

    local stack needs_encryption=false
    for stack in "${stacks[@]}"; do
        if [[ -f "$WORK_DIR/docker/$stack/.env.enc" ]] || [[ "$stack" == "dev" && -f "$WORK_DIR/docker/ai/.env.enc" ]]; then
            needs_encryption=true
            break
        fi
    done

    if [[ "$needs_encryption" == true ]]; then
        ENV_ENC_KEY=$(get_or_prompt_env_passphrase)
        export ENV_ENC_KEY
    fi

    for stack in "${stacks[@]}"; do
        fast_redeploy_stack "$stack"
    done

    cleanup_fast_redeploy_secrets

    print_success "Fast redeploy completed"
}

main "$@"
