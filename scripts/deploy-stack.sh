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
    if chown -R 101000:101000 /datapool/config 2>/dev/null; then
        print_success "Host prepared: /datapool/config ownership set to 101000."
    else
        print_warning "Could not set ownership to 101000:101000, proceeding anyway."
    fi
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

    # Always prompt for password variables and create/update .env file
    print_info "Processing .env file configuration..."
    local temp_current_env="$WORK_DIR/.env.current"
    local new_env_content=""
    
    # Get existing .env if it exists
    if pct exec "$CT_ID" -- test -f "$env_path"; then
        print_info ".env file exists. Will update with new values..."
        pct pull "$CT_ID" "$env_path" "$temp_current_env"
    else
        print_info ".env file does not exist. Creating from scratch..."
        touch "$temp_current_env"
    fi
    
    # Process each variable from .env.example
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Skip empty lines and comments
        if [[ -z "$line" ]] || [[ "$line" == \#* ]]; then
            new_env_content+="$line\n"
            continue
        fi
        
        var_name=$(echo "$line" | cut -d '=' -f 1)
        var_value=$(echo "$line" | cut -d '=' -f 2-)
        
        # Skip comment lines
        if [[ "$var_name" == *"_COMMENT" ]]; then
            new_env_content+="$line\n"
            continue
        fi
        
        # Handle variables that need values
        if [[ -z "$var_value" ]]; then
            if [[ "$var_name" == "PALMR_ENCRYPTION_KEY" ]]; then
                # Check if already exists and has value
                existing_value=$(grep "^$var_name=" "$temp_current_env" 2>/dev/null | cut -d '=' -f 2-)
                if [[ -n "$existing_value" ]]; then
                    user_input="$existing_value"
                    print_info "  -> Using existing PALMR_ENCRYPTION_KEY"
                else
                    user_input=$(head /dev/urandom | tr -dc A-Za-z0-9_ | head -c 32)
                    print_info "  -> Generated random key for PALMR_ENCRYPTION_KEY"
                fi
            elif [[ "$var_name" == "GRAFANA_ADMIN_PASSWORD" ]] || [[ "$var_name" == "JDOWNLOADER_VNC_PASSWORD" ]] || [[ "$var_name" == "FIREFOX_VNC_PASSWORD" ]]; then
                # Always prompt for password variables
                read -p "Please enter value for $var_name: " user_input </dev/tty
                print_info "  -> Updated $var_name"
            elif [[ "$var_name" == "CLOUDFLARED_TOKEN" ]]; then
                read -p "Please enter value for $var_name: " user_input </dev/tty
                print_info "  -> Updated $var_name"
            else
                read -p "Please enter value for $var_name: " user_input </dev/tty
                print_info "  -> Updated $var_name"
            fi
            new_env_content+="$var_name=$user_input\n"
        else
            new_env_content+="$line\n"
        fi
    done < "$temp_env_example"
    
    # Push the new .env file
    echo -e "$new_env_content" > "$WORK_DIR/.env.new"
    pct push "$CT_ID" "$WORK_DIR/.env.new" "$env_path"
    print_success "Environment file configured successfully."
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
