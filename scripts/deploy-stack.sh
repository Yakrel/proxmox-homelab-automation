#!/bin/bash

# This script orchestrates the full deployment of a specific stack.

set -e

# --- Arguments and Setup ---
STACK_NAME=$1
WORK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)"
REPO_BASE_URL="https://raw.githubusercontent.com/Yakrel/proxmox-homelab-automation/main"

source "$WORK_DIR/scripts/stack-config.sh"

# --- Helper Functions (re-defined for standalone execution if needed) ---
print_info() { echo -e "\033[36m[INFO]\033[0m $1"; }
print_success() { echo -e "\033[32m[SUCCESS]\033[0m $1"; }
print_error() { echo -e "\033[31m[ERROR]\033[0m $1"; }
print_warning() { echo -e "\033[33m[WARNING]\033[0m $1"; }

# --- Step 1: Host Preparation ---

prepare_host() {
    print_info "(1/4) Preparing Proxmox host..."
    mkdir -p /datapool/config
    chown -R 101000:101000 /datapool/config
    print_success "Host prepared: /datapool/config ownership set to 101000."
}

# --- Step 2: LXC Creation ---

create_lxc() {
    print_info "(2/4) Handing over to LXC Manager..."
    get_stack_config "$STACK_NAME"
    if pct status "$CT_ID" >/dev/null 2>&1; then
        print_warning "LXC container $CT_ID ($CT_HOSTNAME) already exists. Skipping creation."
    else
        bash "$WORK_DIR/scripts/lxc-manager.sh" "$STACK_NAME"
    fi
}

# --- Step 3: Environment Configuration (.env) ---

configure_env() {
    print_info "(3/4) Configuring .env file for [$STACK_NAME]..."
    get_stack_config "$STACK_NAME"
    local env_path="/root/.env"
    local example_env_url="$REPO_BASE_URL/docker/$STACK_NAME/.env.example"
    local temp_env_example="$WORK_DIR/.env.example"

    # Fetch the latest .env.example
    curl -sSL "$example_env_url" -o "$temp_env_example"
    if [ ! -s "$temp_env_example" ]; then
        print_warning "No .env.example found for stack [$STACK_NAME]. Skipping .env configuration."
        return
    fi

    # Check if .env already exists in the container
    if pct exec "$CT_ID" -- test -f "$env_path"; then
        print_info ".env file exists. Merging new variables..."
        local temp_current_env="$WORK_DIR/.env.current"
        pct pull "$CT_ID" "$env_path" "$temp_current_env"
        
        # Merge logic
        while IFS= read -r line || [[ -n "$line" ]]; do
            var_name=$(echo "$line" | cut -d '=' -f 1)
            if ! grep -q "^$var_name=" "$temp_current_env"; then
                echo "$line" >> "$temp_current_env"
                print_info "  -> Added new variable: $var_name"
            fi
        done < "$temp_env_example"
        pct push "$CT_ID" "$temp_current_env" "$env_path"
        print_success "Merge complete."
    else
        print_info ".env file does not exist. Creating from scratch..."
        local new_env_content=""
        while IFS= read -r line || [[ -n "$line" ]]; do
            var_name=$(echo "$line" | cut -d '=' -f 1)
            var_value=$(echo "$line" | cut -d '=' -f 2-)
            if [[ -z "$var_value" && "$var_name" != *"_COMMENT" ]]; then
                if [[ "$var_name" == "PALMR_ENCRYPTION_KEY" ]]; then
                    user_input=$(head /dev/urandom | tr -dc A-Za-z0-9_ | head -c 32)
                    print_info "  -> Generated random key for PALMR_ENCRYPTION_KEY"
                elif [[ "$var_name" == "JDOWNLOADER_VNC_PASSWORD" ]]; then
                    user_input=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 12)
                    print_info "  -> Generated random password for JDOWNLOADER_VNC_PASSWORD"
                else
                    read -p "Please enter value for $var_name: " user_input </dev/tty
                fi
                new_env_content+="$var_name=$user_input\n"
            else
                new_env_content+="$line\n"
            fi
        done < "$temp_env_example"
        # Push the new .env file
        echo -e "$new_env_content" > "$WORK_DIR/.env.new"
        pct push "$CT_ID" "$WORK_DIR/.env.new" "$env_path"
        print_success "New .env file created and configured."
    fi
}

# --- Step 4: Docker Compose Deployment ---

deploy_compose() {
    print_info "(4/4) Deploying Docker Compose stack for [$STACK_NAME]..."
    get_stack_config "$STACK_NAME"
    local compose_url="$REPO_BASE_URL/docker/$STACK_NAME/docker-compose.yml"
    local temp_compose="$WORK_DIR/docker-compose.yml"

    # Fetch the latest docker-compose.yml
    curl -sSL "$compose_url" -o "$temp_compose"
    if [ ! -s "$temp_compose" ]; then
        print_error "Failed to download docker-compose.yml for stack [$STACK_NAME]."
        exit 1
    fi

    # Push and deploy
    pct push "$CT_ID" "$temp_compose" "/root/docker-compose.yml"
    print_info "Starting docker-compose up -d..."
    pct exec "$CT_ID" -- docker compose -f /root/docker-compose.yml up -d
    print_success "Docker Compose stack for [$STACK_NAME] is deploying in the background."
}

# --- Main Execution ---

prepare_host
create_lxc
configure_env
deploy_compose

print_success "
-------------------------------------------------
Deployment for stack [$STACK_NAME] initiated successfully!
-------------------------------------------------
"
