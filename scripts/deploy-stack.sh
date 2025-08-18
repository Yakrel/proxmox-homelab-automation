
#!/bin/bash

# This script orchestrates the full deployment of a specific stack.

set -e

# --- Arguments and Setup ---
STACK_NAME=$1
WORK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)"
REPO_BASE_URL="https://raw.githubusercontent.com/Yakrel/proxmox-homelab-automation/main"

# Global variables for monitoring setup
PVE_MONITORING_PASSWORD=""
ENV_ENC_NAME=".env.enc"    # Encrypted env filename expected in repo per stack
ENV_DECRYPTED_PATH=""
ENV_PASSPHRASE_CACHE=""

prompt_env_passphrase() {
    local pass
    while true; do
        echo -n "Enter .env decryption passphrase: " >&2
        read -s pass
        echo >&2
        if [ -z "$pass" ]; then
            print_warning "Passphrase cannot be empty."
        else
            printf '%s' "$pass"  # Secure output without newline
            return 0
        fi
    done
}

decrypt_repo_env_to_temp() {
    # Downloads encrypted .env.enc from repo for the stack and decrypts it to a temp file.
    # Expects OpenSSL available on host (present by default on Proxmox).
    local stack="$1"
    local enc_url="$REPO_BASE_URL/docker/$stack/$ENV_ENC_NAME"
    local enc_tmp="$WORK_DIR/$ENV_ENC_NAME"
    ENV_DECRYPTED_PATH="$WORK_DIR/.env.new"

    print_info "  -> Downloading encrypted env ($ENV_ENC_NAME) for [$stack] from repo..."
    mkdir -p "$WORK_DIR/docker/$stack"
    curl -sSL "$enc_url" -o "$enc_tmp"
    if [ ! -s "$enc_tmp" ]; then
        print_error "Encrypted env not found for stack [$stack] at $enc_url"
        return 1
    fi

    # Ask passphrase and try to decrypt; allow up to 3 attempts
    local attempts=0
    while [ $attempts -lt 3 ]; do
        attempts=$((attempts+1))
        local pass
        if [ -n "$ENV_PASSPHRASE_CACHE" ]; then
            pass="$ENV_PASSPHRASE_CACHE"
        else
            pass=$(prompt_env_passphrase)
            ENV_PASSPHRASE_CACHE="$pass"
        fi
        
    # Pass the passphrase to openssl via stdin to avoid writing it to disk
    if printf '%s' "$pass" | openssl enc -d -aes-256-cbc -pbkdf2 -pass stdin -in "$enc_tmp" -out "$ENV_DECRYPTED_PATH" 2>/dev/null; then
            print_success ".env decrypted successfully."
            rm -f "$enc_tmp"
            return 0
        else
            print_warning "Decryption failed (attempt $attempts/3). Check passphrase or file integrity."
            # Clear cached passphrase on first failure to force re-entry
            if [ $attempts -eq 1 ]; then
                ENV_PASSPHRASE_CACHE=""
            fi
        fi
    done
    rm -f "$enc_tmp" "$ENV_DECRYPTED_PATH" 2>/dev/null || true
    print_error "Failed to decrypt .env after 3 attempts."
    return 1
}

# --- Helper Functions ---
print_info() { echo -e "\033[36m[INFO]\033[0m $1"; }
print_success() { echo -e "\033[32m[SUCCESS]\033[0m $1"; }
print_error() { echo -e "\033[31m[ERROR]\033[0m $1"; }
print_warning() { echo -e "\033[33m[WARNING]\033[0m $1"; }

# --- Stack Configuration (YAML-driven only) ---
get_stack_config() {
    local stack=$1
    local stacks_file="$WORK_DIR/stacks.yaml"
    
    # Ensure yq is installed only if missing (faster, less network usage)
    if ! command -v yq >/dev/null 2>&1; then
        apt-get update -y >/dev/null 2>&1 || true
        apt-get install -y yq >/dev/null 2>&1 || true
    fi
    
    if [ ! -f "$stacks_file" ]; then
        print_error "Stacks file not found: $stacks_file. Ensure stacks.yaml is placed there."
        exit 1
    fi
    
    CT_ID=$(yq -r ".stacks.$stack.ct_id" "$stacks_file")
    CT_HOSTNAME=$(yq -r ".stacks.$stack.hostname" "$stacks_file")
    if [ -z "$CT_ID" ] || [ "$CT_ID" = "null" ]; then
        print_error "Stack '$stack' not found or incomplete in $stacks_file"
        exit 1
    fi
}

# --- Step 1: Host Preparation ---

prepare_host() {
    print_info "(1/5) Preparing Proxmox host..."
    
    # Create all necessary directories (consolidated)
    local -a dirs=(
        /datapool/config/prometheus
        /datapool/config/grafana/provisioning
        /datapool/config/loki/data
        /datapool/config/promtail
        /datapool/config/promtail/positions
        /datapool/config/homepage
        /datapool/config/palmr/uploads
    )
    
    # Add PBS datastore directory for backup stack
    if [[ "$STACK_NAME" == "backup" ]]; then
        dirs+=(/datapool/backups)
    fi
    
    mkdir -p "${dirs[@]}"
    
    # Set ownership to 101000. This is intentional and crucial.
    # It maps the Proxmox host UID to the container's UID for user 1000.
    # This allows Docker containers running as PUID/PGID=1000 inside the LXC
    # to have the correct permissions on the mounted /datapool/config volume.
    if chown -R 101000:101000 /datapool/config 2>/dev/null; then
        print_success "Host prepared: /datapool/config ownership set to 101000."
    else
        print_warning "Could not set ownership to 101000:101000, proceeding anyway."
    fi
    
    # Set ownership for PBS datastore
    if [[ "$STACK_NAME" == "backup" ]]; then
        if chown -R 101000:101000 /datapool/backups 2>/dev/null; then
            print_success "PBS datastore prepared: /datapool/backups ownership set to 101000."
        else
            print_warning "Could not set ownership to 101000:101000 for backups, proceeding anyway."
        fi
    fi

    
}

# --- Step 1.1: Proxmox User Management (for monitoring stack) ---

setup_proxmox_monitoring_user() {
    print_info "(1.1/5) Setting up Proxmox monitoring user..."
    
    local PVE_MONITORING_USER="pve-exporter@pve"
    local PVE_MONITORING_ROLE="PVEAuditor"
    
    # Check if user already exists
    if pveum user list | grep -q "$PVE_MONITORING_USER"; then
        print_info "  -> Proxmox user '$PVE_MONITORING_USER' already exists."
    else
        print_info "  -> Creating Proxmox user '$PVE_MONITORING_USER'..."
        pveum user add "$PVE_MONITORING_USER" --comment "Monitoring user for PVE Exporter"
        print_success "  -> User '$PVE_MONITORING_USER' created."
    fi
    
    # Prompt for password (will be used in .env configuration)
    if [ -z "$PVE_MONITORING_PASSWORD" ]; then
        echo
        print_info "Please set a password for the Proxmox monitoring user ($PVE_MONITORING_USER):"
        while true; do
            read -s -p "Enter password: " PVE_MONITORING_PASSWORD
            echo " [Password entered]"  # Visual feedback
            read -s -p "Confirm password: " PVE_MONITORING_PASSWORD_CONFIRM
            echo " [Password confirmed]"  # Visual feedback
            
            if [[ "$PVE_MONITORING_PASSWORD" == "$PVE_MONITORING_PASSWORD_CONFIRM" ]]; then
                if [[ ${#PVE_MONITORING_PASSWORD} -lt 8 ]]; then
                    print_warning "Password must be at least 8 characters long. Please try again."
                    continue
                fi
                break
            else
                print_warning "Passwords do not match. Please try again."
            fi
        done
    fi
    
    # Set user password (idempotent - will update if password changed)
    print_info "  -> Setting password for user '$PVE_MONITORING_USER'..."
    (echo "$PVE_MONITORING_PASSWORD"; echo "$PVE_MONITORING_PASSWORD") | pveum passwd "$PVE_MONITORING_USER"
    
    # Assign role (idempotent - no error if already assigned)
    print_info "  -> Assigning role '$PVE_MONITORING_ROLE' to user '$PVE_MONITORING_USER'..."
    pveum aclmod / -user "$PVE_MONITORING_USER" -role "$PVE_MONITORING_ROLE" 2>/dev/null || true
    
    print_success "Proxmox monitoring user setup complete."
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
    # Skip .env configuration for backup stack - PBS doesn't use Docker/.env
    if [[ "$STACK_NAME" == "backup" ]]; then
        print_info "(3/5) Skipping .env configuration for backup stack - PBS uses native config."
        return 0
    fi
    
    print_info "(3/5) Configuring .env file for [$STACK_NAME]..."
    get_stack_config "$STACK_NAME"
    local env_path="/root/.env"

    # Decrypt if not already decrypted
    if [ -z "$ENV_DECRYPTED_PATH" ] || [ ! -s "$ENV_DECRYPTED_PATH" ]; then
        decrypt_repo_env_to_temp "$STACK_NAME" || { print_error "Cannot proceed without encrypted .env for [$STACK_NAME]."; exit 1; }
    else
        print_info "  -> Using previously decrypted .env from $ENV_DECRYPTED_PATH"
    fi

    # Backup existing .env file before pushing the new one
    if pct exec "$CT_ID" -- test -f "$env_path"; then
        if pct exec "$CT_ID" -- cp "$env_path" "$env_path.backup" 2>/dev/null; then
            print_info "  -> Backup created: $env_path.backup"
        else
            print_warning "  -> Could not create backup, proceeding anyway..."
        fi
    fi

    pct push "$CT_ID" "$ENV_DECRYPTED_PATH" "$env_path"
    print_success "Environment file configured successfully."
}

# --- Step 4: Configure Homepage Config (if applicable) ---

configure_homepage_config() {
    print_info "(4/5) Configuring Homepage config files for [$STACK_NAME]..."
    get_stack_config "$STACK_NAME"

    if [[ "$STACK_NAME" == "webtools" ]]; then
        local target_config_dir="/datapool/config/homepage"

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
        local loki_config_dir="/datapool/config/loki"

        print_info "  -> Downloading and pushing monitoring config files..."

        local monitoring_config_files=(
            "prometheus.yml:$prometheus_config_dir"
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

                # Download and push Loki config
        local loki_config_url="$REPO_BASE_URL/config/loki/loki.yml"
        local temp_loki_file="$WORK_DIR/loki.yml"
        
        print_info "    -> Downloading loki.yml"
        curl -sSL "$loki_config_url" -o "$temp_loki_file"
        
        print_info "    -> Pushing loki.yml to LXC ($loki_config_dir)"
        pct push "$CT_ID" "$temp_loki_file" "$loki_config_dir/loki.yml"
        rm "$temp_loki_file"


        print_success "Monitoring config files configured successfully."
    else
        print_info "(4.1/5) No stack-specific config to configure for stack [$STACK_NAME]. Skipping."
    fi
}

# --- Step 4.2: Configure Promtail Config (for all stacks) ---

configure_promtail_config() {
    # Skip Promtail for backup stack - PBS has its own logging
    if [[ "$STACK_NAME" == "backup" ]]; then
        print_info "(4.2/5) Skipping Promtail config for backup stack - PBS has native logging."
        return 0
    fi
    
    print_info "(4.2/5) Configuring Promtail config for [$STACK_NAME]..."
    get_stack_config "$STACK_NAME"
    
    local promtail_config_dir="/datapool/config/promtail"
    local promtail_config_url="$REPO_BASE_URL/config/promtail/promtail.yml"
    local temp_promtail_file="$WORK_DIR/promtail.yml"
    
    print_info "  -> Downloading promtail.yml template"
    curl -sSL "$promtail_config_url" -o "$temp_promtail_file"
    
    # Replace host label with the actual hostname (used in labels and positions filename)
    sed -i "s/REPLACE_HOST_LABEL/$CT_HOSTNAME/g" "$temp_promtail_file"
    
    print_info "  -> Pushing customized promtail.yml to LXC ($promtail_config_dir)"
    pct push "$CT_ID" "$temp_promtail_file" "$promtail_config_dir/promtail.yml"
    rm "$temp_promtail_file"
    
    print_success "Promtail config configured successfully for $CT_HOSTNAME."
}

# --- Step 4.3: Configure PBS (for backup stack) ---

configure_pbs() {
    print_info "(4.3/5) Configuring Proxmox Backup Server for [$STACK_NAME]..."
    get_stack_config "$STACK_NAME"
    
    # Read PBS-specific config from stacks.yaml
    local datastore_name=$(yq -r ".stacks.backup.pbs_datastore_name" "$WORK_DIR/stacks.yaml")
    local gc_schedule=$(yq -r ".stacks.backup.pbs_gc_schedule" "$WORK_DIR/stacks.yaml")
    local prune_schedule=$(yq -r ".stacks.backup.pbs_prune_schedule" "$WORK_DIR/stacks.yaml")
    local verify_schedule=$(yq -r ".stacks.backup.pbs_verify_schedule" "$WORK_DIR/stacks.yaml")
    local prom_user="prometheus@pbs"
    local prom_pass_path="/root/.prometheus_password"

    print_info "  -> Waiting for PBS services to be ready..."
    local max_attempts=30
    local attempt=1
    while [ $attempt -le $max_attempts ]; do
        if pct exec "$CT_ID" -- systemctl is-active proxmox-backup >/dev/null 2>&1; then
            print_success "  -> PBS service is active."
            break
        fi
        print_info "  -> Attempt $attempt/$max_attempts: Waiting for PBS service..."
        sleep 2
        attempt=$((attempt + 1))
    done
    
    if [ $attempt -gt $max_attempts ]; then
        print_error "PBS service failed to start within expected time."
        return 1
    fi
    
    # --- Idempotent Prometheus User & Password Setup ---
    if ! pct exec "$CT_ID" -- test -f "$prom_pass_path"; then
        print_info "  -> Prometheus user credentials not found. Creating new user..."
        
        print_info "  -> Setting up PBS admin password (root@pam) to create monitoring user..."
        local PBS_ADMIN_PASS
        while true;
        do
            echo -n "Enter PBS admin (root@pam) password: " >&2
            read -s PBS_ADMIN_PASS
            echo >&2
            if [ ${#PBS_ADMIN_PASS} -ge 8 ]; then
                break
            else
                print_warning "Password must be at least 8 characters. Try again."
            fi
        done
        echo "$PBS_ADMIN_PASS" | pct exec "$CT_ID" -- proxmox-backup-manager user passwd root@pam 2>/dev/null
        
        pct exec "$CT_ID" -- proxmox-backup-manager user create "$prom_user" --comment "Read-only user for Prometheus monitoring" 2>/dev/null || true
        pct exec "$CT_ID" -- proxmox-backup-manager acl update /datastore/"$datastore_name" --user "$prom_user" --role DatastoreAudit 2>/dev/null || true

        local prom_pass=$(openssl rand -base64 16)
        echo "$prom_pass" | pct exec "$CT_ID" -- proxmox-backup-manager user passwd "$prom_user"
        echo "$prom_pass" | pct exec "$CT_ID" -- sh -c "cat > $prom_pass_path && chmod 600 $prom_pass_path"
        print_success "  -> Prometheus user '$prom_user' created and password stored securely in LXC."
    else
        print_info "  -> Prometheus user credentials found. Skipping creation."
    fi

    local final_prom_pass=$(pct exec "$CT_ID" -- cat "$prom_pass_path")

    print_info "  -> Configuring Prometheus for PBS monitoring..."
    local monitoring_ct_id=$(yq -r ".stacks.monitoring.ct_id" "$WORK_DIR/stacks.yaml")
    if pct status "$monitoring_ct_id" >/dev/null 2>&1;
    then
        local pbs_job_config_temp="$WORK_DIR/pbs_job.yml"
        local pbs_ip_address="$(yq -r ".network.ip_base" "$WORK_DIR/stacks.yaml").$(yq -r ".stacks.backup.ip_octet" "$WORK_DIR/stacks.yaml")"

        cat > "$pbs_job_config_temp" << EOF
- targets: ['$pbs_ip_address:8007']
  labels:
    instance: '$CT_HOSTNAME'
  basic_auth:
    username: '$prom_user'
    password: '$final_prom_pass'
EOF
        pct push "$monitoring_ct_id" "$pbs_job_config_temp" "/etc/prometheus/pbs_job.yml"
        rm "$pbs_job_config_temp"

        print_info "  -> Restarting Prometheus to apply PBS configuration..."
        pct exec "$monitoring_ct_id" -- docker compose restart prometheus 2>/dev/null || print_warning "Could not restart Prometheus - do it manually"
        print_success "  -> Prometheus PBS monitoring configured."
    else
        print_warning "  -> Monitoring stack not found, skipping Prometheus configuration."
    fi
    
    print_info "  -> Creating PBS datastore '$datastore_name' நான்காவது..."
    if pct exec "$CT_ID" -- proxmox-backup-manager datastore create "$datastore_name" /datapool/backups 2>/dev/null;
    then
        print_success "  -> PBS datastore created successfully."
    else
        print_warning "  -> Datastore might already exist or PBS not fully started yet."
    fi
    
    print_info "  -> Setting up garbage collection schedule..."
    pct exec "$CT_ID" -- proxmox-backup-manager gc-schedule update "$datastore_name" --schedule "$gc_schedule" 2>/dev/null || true
    
    print_info "  -> Creating prune job for backup retention..."
    pct exec "$CT_ID" -- proxmox-backup-manager prune-job create "$datastore_name" \
        --schedule "$prune_schedule" --keep-daily 7 --keep-weekly 4 --keep-monthly 6 2>/dev/null || true
    
    print_info "  -> Setting up verification job..."
    pct exec "$CT_ID" -- proxmox-backup-manager verification-job create "$datastore_name" \
        --schedule "$verify_schedule" 2>/dev/null || true
    
    local pbs_ip=$(yq -r ".network.ip_base" "$WORK_DIR/stacks.yaml").$(yq -r ".stacks.backup.ip_octet" "$WORK_DIR/stacks.yaml")
    print_success "PBS configuration completed. Access web interface at: https://${pbs_ip}:8007"
}



# --- Step 4.4: Configure PVE Backup Job ---

configure_pve_backup_job() {
    print_info "(4.4/5) Configuring Proxmox VE backup job..."
    local pbs_storage_name="lxc-backup-01" # This should match the storage added in PVE
    local job_config_file="/etc/pve/jobs.cfg"
    local job_id="vzdump-automated-pbs"

    # First, ensure the PBS storage is added to PVE.
    # This part is complex to automate securely without API tokens, so we guide the user.
    if ! pvesm status --storage "$pbs_storage_name" >/dev/null 2>&1; then
        print_warning "Storage '$pbs_storage_name' not found in Proxmox VE."
        print_warning "Please add it manually before proceeding: Datacenter -> Storage -> Add -> Proxmox Backup Server"
        local pbs_ip=$(yq -r ".network.ip_base" "$WORK_DIR/stacks.yaml").$(yq -r ".stacks.backup.ip_octet" "$WORK_DIR/stacks.yaml")
        local pbs_datastore=$(yq -r ".stacks.backup.pbs_datastore_name" "$WORK_DIR/stacks.yaml")
        print_info "    ID: $pbs_storage_name"
        print_info "    Server: $pbs_ip"
        print_info "    Username: root@pam"
        print_info "    Datastore: $pbs_datastore"
        read -p "Press [Enter] to continue after adding the storage..."
    fi

    # Check if the job already exists
    if grep -q "^vzdump: $job_id" "$job_config_file"; then
        print_warning "Automated PVE backup job '$job_id' already exists. Skipping creation."
        return 0
    fi

    print_info "  -> Creating automated backup job '$job_id'..."
    cat >> "$job_config_file" <<EOF

vzdump: $job_id
    all 1
    comment "Automated backup for all guests to PBS"
    compress zstd
    enabled 1
    mailnotification failure
    mode snapshot
    node $(hostname)
    prune-backups keep-daily=7,keep-weekly=4,keep-monthly=6
    schedule 02:30
    storage $pbs_storage_name
EOF
    print_success "  -> Automated backup job created successfully."
}

# --- Step 5: Docker Compose Deployment ---

deploy_compose() {
    # Skip Docker Compose for backup stack - PBS runs as native systemd service
    if [[ "$STACK_NAME" == "backup" ]]; then
        print_info "(5/5) Skipping Docker Compose for backup stack - PBS runs natively."
        return 0
    fi
    
    print_info "(5/5) Deploying Docker Compose stack for [$STACK_NAME]..."
    get_stack_config "$STACK_NAME"
    local compose_url="$REPO_BASE_URL/docker/$STACK_NAME/docker-compose.yml"
    local temp_compose="$WORK_DIR/docker-compose.yml"

    # Fetch and push docker-compose.yml to LXC
    curl -sSL "$compose_url" -o "$temp_compose"
    pct push "$CT_ID" "$temp_compose" "/root/docker-compose.yml"
    rm "$temp_compose"

    print_info "Pruning unused Docker objects..."
    pct exec "$CT_ID" -- docker system prune -af

    print_info "Starting docker-compose up -d..."
    if ! pct exec "$CT_ID" -- docker compose -f /root/docker-compose.yml up -d; then
        print_error "Docker Compose deployment failed. Please check the output above."
        exit 1
    fi
    print_success "Docker Compose stack for [$STACK_NAME] is deploying in the background."
}

# --- Main Execution ---

# For monitoring stack, decrypt .env first to fetch PVE_PASSWORD, then setup Proxmox user
if [[ "$STACK_NAME" == "monitoring" ]]; then
    # Ensure .env is decrypted locally to read PVE_PASSWORD
    decrypt_repo_env_to_temp "$STACK_NAME" || { print_error "Cannot decrypt env for monitoring."; exit 1; }
    if [ -s "$ENV_DECRYPTED_PATH" ]; then
        # shellcheck disable=SC1090
        PVE_MONITORING_PASSWORD=$(grep '^PVE_PASSWORD=' "$ENV_DECRYPTED_PATH" | cut -d '=' -f 2-)
    fi
    setup_proxmox_monitoring_user
fi

prepare_host
create_lxc

# --- Stack-Specific Deployment ---

if [[ "$STACK_NAME" == "development" ]]; then
    : # Do nothing, setup is handled by lxc-manager.sh
elif [[ "$STACK_NAME" == "backup" ]]; then
    # PBS-specific deployment (no Docker, no .env)
    configure_pbs
    configure_pve_backup_job
else
    # Proceed with standard Docker-based deployment
    configure_env

    if [[ "$STACK_NAME" == "webtools" ]]; then
        configure_homepage_config
    fi

    if [[ "$STACK_NAME" == "monitoring" ]]; then
        configure_stack_configs
    fi

    # Configure Promtail for all stacks (except backup - PBS has native logging)
    configure_promtail_config

    deploy_compose
fi

print_success "-------------------------------------------------
Deployment for stack [$STACK_NAME] initiated successfully!
-------------------------------------------------"