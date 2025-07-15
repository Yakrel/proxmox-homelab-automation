#!/bin/bash

# This script orchestrates the full deployment of a specific stack.

set -e

# --- Arguments and Setup ---
STACK_NAME=$1
WORK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)"
REPO_BASE_URL="https://raw.githubusercontent.com/Yakrel/proxmox-homelab-automation/main"

# --- Helper Functions ---
print_info() { echo -e "\033[36m[INFO]\033[0m $1"; }
print_success() { echo -e "\033[32m[SUCCESS]\033[0m $1"; }
print_error() { echo -e "\033[31m[ERROR]\033[0m $1"; }
print_warning() { echo -e "\033[33m[WARNING]\033[0m $1"; }

# --- Hardcoded Stack Configuration ---
get_stack_config() {
    local stack=$1
    case $stack in
        "proxy")
            CT_ID="100"; CT_HOSTNAME="lxc-proxy-01";
            ;;
        "media")
            CT_ID="101"; CT_HOSTNAME="lxc-media-01";
            ;;
        "files")
            CT_ID="102"; CT_HOSTNAME="lxc-files-01";
            ;;
        "webtools")
            CT_ID="103"; CT_HOSTNAME="lxc-webtools-01";
            ;;
        "monitoring")
            CT_ID="104"; CT_HOSTNAME="lxc-monitoring-01";
            ;;
        "development")
            CT_ID="150"; CT_HOSTNAME="lxc-development-01";
            ;;
        *)
            print_error "Unknown stack: $stack" >&2
            exit 1
            ;;
    esac
}

# --- Step 1: Host Preparation ---

prepare_host() {
    print_info "(1/5) Preparing Proxmox host..."
    mkdir -p /datapool/config
    mkdir -p /datapool/config/palmr/uploads
    if chown -R 101000:101000 /datapool/config 2>/dev/null; then
        print_success "Host prepared: /datapool/config ownership set to 101000."
    else
        print_warning "Could not set ownership to 101000:101000, proceeding anyway."
    fi
}

# --- Step 2: LXC Creation ---

create_lxc() {
    print_info "(2/5) Handing over to LXC Manager..."
    get_stack_config "$STACK_NAME"
    if pct status "$CT_ID" >/dev/null 2>&1; then
        print_warning "LXC container $CT_ID ($CT_HOSTNAME) already exists. Skipping creation."
    else
        bash "$WORK_DIR/scripts/lxc-manager.sh" "$STACK_NAME"
    fi
}

# --- Step 3: Environment Configuration (.env) ---

configure_env() {
    print_info "(3/5) Configuring .env file for [$STACK_NAME]..."
    get_stack_config "$STACK_NAME"
    local env_path="/root/.env"
    local example_env_url="$REPO_BASE_URL/docker/$STACK_NAME/.env.example"
    local temp_env_example="$WORK_DIR/.env.example"
    local temp_current_env="$WORK_DIR/.env.current"

    # Fetch the latest .env.example
    curl -sSL "$example_env_url" -o "$temp_env_example"
    if [ ! -s "$temp_env_example" ]; then
        print_warning "No .env.example found for stack [$STACK_NAME]. Skipping .env configuration."
        return
    fi

    # Get existing .env if it exists, to check for existing values
    if pct exec "$CT_ID" -- test -f "$env_path"; then
        pct pull "$CT_ID" "$env_path" "$temp_current_env"
    else
        touch "$temp_current_env" # Create an empty file if it doesn't exist
    fi

    print_info "Processing .env file configuration..."
    local new_env_content=""
    
    # Process each variable from .env.example
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Preserve comments and empty lines
        if [[ -z "$line" ]] || [[ "$line" == \#* ]]; then
            new_env_content+="$line\n"
            continue
        fi
        
        var_name=$(echo "$line" | cut -d '=' -f 1)
        
        # Check if the variable already exists and has a value in the current .env
        existing_value=$(grep "^$var_name=" "$temp_current_env" | cut -d '=' -f 2-)

        # --- Special Handling Logic ---
        
        # 1. Prompt for specific passwords/values if empty
        if [[ "$var_name" == "JDOWNLOADER_VNC_PASSWORD" ]] || \
           [[ "$var_name" == "FIREFOX_VNC_PASSWORD" ]] || \
           [[ "$var_name" == "CLOUDFLARED_TOKEN" ]] || \
           [[ "$var_name" == "GF_SECURITY_ADMIN_PASSWORD" ]] || \
           [[ "$var_name" == "PVE_PASSWORD" ]] || \
           [[ "$var_name" == "PVE_USER" ]] || \
           [[ "$var_name" == "PVE_URL" ]] || \
           [[ "$var_name" == "PVE_VERIFY_SSL" ]]; then
            if [[ -n "$existing_value" ]]; then
                new_env_content+="$var_name=$existing_value\n"
                print_info "  -> Kept existing $var_name."
            else
                read -p "Please enter value for $var_name: " user_input </dev/tty
                new_env_content+="$var_name=$user_input\n"
                print_info "  -> Set $var_name from user input."
            fi
        
        # 2. Generate Palmr encryption key if empty
        elif [[ "$var_name" == "PALMR_ENCRYPTION_KEY" ]]; then
            if [[ -n "$existing_value" ]]; then
                new_env_content+="$var_name=$existing_value\n"
                print_info "  -> Kept existing $var_name."
            else
                local generated_key=$(openssl rand -base64 32)
                new_env_content+="$var_name=$generated_key\n"
                print_info "  -> Generated new $var_name."
            fi

        # 3. For all other variables, preserve existing value or use .env.example
        else
            if [[ -n "$existing_value" ]]; then
                new_env_content+="$var_name=$existing_value\n"
                print_info "  -> Kept existing $var_name."
            else
                new_env_content+="$line\n" # Copy from .env.example (which might be empty)
                print_info "  -> Added $var_name from .env.example (new or empty)."
            fi
        fi
    done < "$temp_env_example"
    
    # Push the new .env file
    echo -e "$new_env_content" > "$WORK_DIR/.env.new"
    
    # Backup existing .env file before pushing the new one
    if pct exec "$CT_ID" -- test -f "$env_path"; then
        if pct exec "$CT_ID" -- cp "$env_path" "$env_path.backup" 2>/dev/null; then
            print_info "  -> Backup created: $env_path.backup"
        else
            print_warning "  -> Could not create backup, proceeding anyway..."
        fi
    fi
    
    pct push "$CT_ID" "$WORK_DIR/.env.new" "$env_path"
    print_success "Environment file configured successfully."
}

# --- Step 4: Configure Homepage Config (if applicable) ---

configure_homepage_config() {
    print_info "(4/5) Configuring Homepage config files for [$STACK_NAME]..."
    get_stack_config "$STACK_NAME"

    if [[ "$STACK_NAME" == "webtools" ]]; then
        local target_config_dir="/datapool/config/homepage"

        # Ensure the target directory exists in the LXC
        pct exec "$CT_ID" -- mkdir -p "$target_config_dir"

        print_info "  -> Downloading and pushing homepage config files..."

        local homepage_config_files=(
            "bookmarks.yaml"
            "docker.yaml"
            "services.yaml"
            "settings.yaml"
            "widgets.yaml"
        )

        for config_file in "${homepage_config_files[@]}"; do
            local remote_url="$REPO_BASE_URL/config/homepage/$config_file"
            local temp_file="$WORK_DIR/$config_file" # Use WORK_DIR (temp dir) for download

            print_info "    -> Downloading $config_file"
            curl -sSL "$remote_url" -o "$temp_file"

            print_info "    -> Pushing $config_file to LXC"
            pct push "$CT_ID" "$temp_file" "$target_config_dir/$config_file"
            # Clean up the temporary downloaded file
            rm "$temp_file"
        done

        print_success "Homepage config files configured successfully."
    else
        print_info "(4/5) No Homepage config to configure for stack [$STACK_NAME]. Skipping."
    fi
}

# --- Step 4.1: Configure Stack Specific Configs (if applicable) ---

configure_stack_configs() {
    print_info "(4.1/5) Configuring stack-specific config files for [$STACK_NAME]..."
    get_stack_config "$STACK_NAME"

    if [[ "$STACK_NAME" == "monitoring" ]]; then
        local prometheus_config_dir="/datapool/config/prometheus"
        local grafana_provisioning_dir="/datapool/config/grafana/provisioning"

        # Ensure target directories exist in the LXC
        pct exec "$CT_ID" -- mkdir -p "$prometheus_config_dir"
        pct exec "$CT_ID" -- mkdir -p "$grafana_provisioning_dir"

        print_info "  -> Downloading and pushing monitoring config files..."

        local monitoring_config_files=(
            "prometheus.yml:$prometheus_config_dir"
            "alertmanager.yml:$prometheus_config_dir"
            "alerts.yml:$prometheus_config_dir"
            "grafana-provisioning-dashboards.yml:$grafana_provisioning_dir"
            "grafana-provisioning-datasources.yml:$grafana_provisioning_dir"
        )

        for config_entry in "${monitoring_config_files[@]}"; do
            IFS=':' read -r config_file target_dir <<< "$config_entry"
            local remote_url="$REPO_BASE_URL/docker/$STACK_NAME/$config_file"
            local temp_file="$WORK_DIR/$config_file"

            print_info "    -> Downloading $config_file"
            curl -sSL "$remote_url" -o "$temp_file"

            print_info "    -> Pushing $config_file to LXC ($target_dir)"
            pct push "$CT_ID" "$temp_file" "$target_dir/$config_file"
            rm "$temp_file"
        done

        print_success "Monitoring config files configured successfully."
    else
        print_info "(4.1/5) No stack-specific config to configure for stack [$STACK_NAME]. Skipping."
    fi
}

# --- Step 5: Docker Compose Deployment ---

deploy_compose() {
    print_info "(5/5) Deploying Docker Compose stack for [$STACK_NAME]..."
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

# --- Stack-Specific Deployment ---

if [[ "$STACK_NAME" == "development" ]]; then
    print_info "Development environment setup is complete. No Docker deployment needed."
else
    # Proceed with standard Docker-based deployment
    configure_env

    if [[ "$STACK_NAME" == "webtools" ]]; then
        configure_homepage_config
    fi

    if [[ "$STACK_NAME" == "monitoring" ]]; then
        configure_stack_configs
    fi

    deploy_compose
fi

print_success "
-------------------------------------------------
Deployment for stack [$STACK_NAME] initiated successfully!
-------------------------------------------------
"