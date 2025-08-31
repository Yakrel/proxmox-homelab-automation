
#!/bin/bash

# This script orchestrates the full deployment of a specific stack.

set -e

# --- Arguments and Setup ---
STACK_NAME=$1
WORK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)"
REPO_BASE_URL="https://raw.githubusercontent.com/Yakrel/proxmox-homelab-automation/main"

# --- Load Shared Functions ---
source "$WORK_DIR/scripts/helper-functions.sh"

# Global variables for monitoring setup
PVE_MONITORING_PASSWORD=""
ENV_ENC_NAME=".env.enc"    # Encrypted env filename expected in repo per stack
ENV_DECRYPTED_PATH=""

# Use shared prompt_env_passphrase function from helper-functions.sh

prompt_pbs_admin_password() {
    prompt_password "Enter PBS admin password for root@pam (web interface): " 8
}

decrypt_env_for_deploy() {
    # Download and decrypt .env.enc for deployment - fail fast, no retries
    local stack="$1"
    local enc_url="$REPO_BASE_URL/docker/$stack/.env.enc"
    local enc_tmp="$WORK_DIR/.env.enc"
    ENV_DECRYPTED_PATH="$WORK_DIR/.env"

    print_info "  -> Downloading encrypted env (.env.enc) for [$stack] from repo..."
    curl -sSL "$enc_url" -o "$enc_tmp"
    if [ ! -s "$enc_tmp" ]; then
        print_error "Encrypted env not found for stack [$stack] at $enc_url"
        return 1
    fi

    # Ask passphrase - fail fast if wrong
    local pass=$(prompt_env_passphrase)
    
    # Single decrypt attempt - fail fast
    if printf '%s' "$pass" | openssl enc -d -aes-256-cbc -pbkdf2 -pass stdin -in "$enc_tmp" -out "$ENV_DECRYPTED_PATH" 2>/dev/null; then
        print_success ".env decrypted successfully."
        rm -f "$enc_tmp"
        return 0
    else
        print_error "Decryption failed. Wrong passphrase or corrupted file."
        rm -f "$enc_tmp" "$ENV_DECRYPTED_PATH" 2>/dev/null || true
        return 1
    fi
}

# --- Print functions now loaded from helper-functions.sh ---

# --- Stack Configuration now uses shared get_stack_config function ---

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
    
    # Use password from .env (should be set from decrypt process above)
    if [ -z "$PVE_MONITORING_PASSWORD" ]; then
        print_error "PVE_PASSWORD not found in .env file. Monitoring stack requires encrypted .env file."
        print_info "Please ensure docker/monitoring/.env.enc exists and contains PVE_PASSWORD."
        exit 1
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

    # Decrypt .env.enc for deployment
    if [ -z "$ENV_DECRYPTED_PATH" ] || [ ! -s "$ENV_DECRYPTED_PATH" ]; then
        decrypt_env_for_deploy "$STACK_NAME" || { print_error "Cannot proceed without encrypted .env for [$STACK_NAME]."; exit 1; }
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
            download_and_push_config "$CT_ID" "$remote_url" "$target_config_dir/$config_file"
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
            download_and_push_config "$CT_ID" "$remote_url" "$target_dir/$config_file"
        done

        # Download and push Loki config
        local loki_config_url="$REPO_BASE_URL/config/loki/loki.yml"
        download_and_push_config "$CT_ID" "$loki_config_url" "$loki_config_dir/loki.yml"


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
    
    download_customize_and_push "$CT_ID" "$promtail_config_url" "$promtail_config_dir/promtail.yml" "$CT_HOSTNAME"
    
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
    
    # --- Idempotent PBS Admin & Prometheus User Setup ---
    local pbs_admin_pass_path="/root/.pbs-admin.pass"
    local pbs_admin_hash_path="/root/.pbs-admin.hash"
    local PBS_ADMIN_PASS=""
    
    # Check if we need to prompt for password (first run or password change requested)
    local need_password_setup=false
    if ! pct exec "$CT_ID" -- test -f "$pbs_admin_pass_path"; then
        print_info "  -> PBS admin password not found. Interactive setup required."
        need_password_setup=true
    else
        # Ask user if they want to change existing password
        print_info "  -> PBS admin password found. Do you want to change it? [y/N]"
        read -r change_password
        if [[ "$change_password" =~ ^[Yy]$ ]]; then
            need_password_setup=true
            print_info "  -> Password change requested."
        fi
    fi
    
    if [ "$need_password_setup" = true ]; then
        print_info "  -> Prompting for PBS admin password..."
        PBS_ADMIN_PASS=$(prompt_pbs_admin_password)
        
        # Create hash of the new password for idempotent checks
        local new_hash=$(printf '%s' "$PBS_ADMIN_PASS" | sha256sum | cut -d' ' -f1)
        
        # Set PBS admin password and store it securely
        print_info "  -> Setting PBS admin password..."
        pct exec "$CT_ID" -- proxmox-backup-manager user update root@pam --password "$PBS_ADMIN_PASS"
        
        # Store password and hash securely
        printf '%s' "$PBS_ADMIN_PASS" | pct exec "$CT_ID" -- sh -c "cat > $pbs_admin_pass_path && chmod 600 $pbs_admin_pass_path"
        printf '%s' "$PBS_ADMIN_PASS" | pct exec "$CT_ID" -- sh -c "cat > /root/.pbs-admin-password && chmod 600 /root/.pbs-admin-password"
        printf '%s' "$new_hash" | pct exec "$CT_ID" -- sh -c "cat > $pbs_admin_hash_path && chmod 600 $pbs_admin_hash_path"
        
        print_success "  -> PBS admin password set and stored securely (root@pam)."
    else
        print_info "  -> Using existing PBS admin password."
        PBS_ADMIN_PASS=$(pct exec "$CT_ID" -- cat "$pbs_admin_pass_path")
    fi
    
    # Create Prometheus user if needed
    if ! pct exec "$CT_ID" -- test -f "$prom_pass_path"; then
        print_info "  -> Creating Prometheus monitoring user..."
        
        pct exec "$CT_ID" -- proxmox-backup-manager user create "$prom_user" --comment "Read-only user for Prometheus monitoring" 2>/dev/null || true
        pct exec "$CT_ID" -- proxmox-backup-manager acl update /datastore/"$datastore_name" --user "$prom_user" --role DatastoreAudit 2>/dev/null || true

        local prom_pass=$(openssl rand -base64 16)
        pct exec "$CT_ID" -- proxmox-backup-manager user update "$prom_user" --password "$prom_pass"
        printf '%s' "$prom_pass" | pct exec "$CT_ID" -- sh -c "cat > $prom_pass_path && chmod 600 $prom_pass_path"
        printf '%s' "$prom_pass" | pct exec "$CT_ID" -- sh -c "cat > /root/.prometheus-password && chmod 600 /root/.prometheus-password"
        print_success "  -> Prometheus user '$prom_user' created and password stored securely."
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
        pct push "$monitoring_ct_id" "$pbs_job_config_temp" "/datapool/config/prometheus/pbs_job.yml"
        rm "$pbs_job_config_temp"

        print_info "  -> Restarting Prometheus to apply PBS configuration..."
        pct exec "$monitoring_ct_id" -- docker compose restart prometheus 2>/dev/null || print_warning "Could not restart Prometheus - do it manually"
        print_success "  -> Prometheus PBS monitoring configured."
    else
        print_warning "  -> Monitoring stack not found, skipping Prometheus configuration."
    fi
    
    print_info "  -> Creating PBS datastore '$datastore_name'..."
    
    # Check if datastore already exists first (idempotent)
    if pct exec "$CT_ID" -- proxmox-backup-manager datastore list 2>/dev/null | grep -q "$datastore_name"; then
        print_success "  -> PBS datastore already exists."
    else
        # Only clean directory if datastore doesn't exist and directory looks uninitialized
        if ! pct exec "$CT_ID" -- test -f /datapool/backups/.gc-status 2>/dev/null; then
            print_info "  -> Cleaning uninitialized datastore directory..."
            pct exec "$CT_ID" -- rm -rf /datapool/backups/* /datapool/backups/.* 2>/dev/null || true
        fi
        
        # Wait for PBS to be fully ready for datastore operations  
        local datastore_attempts=10
        local ds_attempt=1
        while [ $ds_attempt -le $datastore_attempts ]; do
            if pct exec "$CT_ID" -- proxmox-backup-manager datastore create "$datastore_name" /datapool/backups 2>/dev/null; then
                print_success "  -> PBS datastore created successfully."
                break
            else
                print_info "  -> Attempt $ds_attempt/$datastore_attempts: Waiting for PBS to be ready for datastore operations..."
                sleep 3
                ds_attempt=$((ds_attempt + 1))
            fi
        done
        
        if [ $ds_attempt -gt $datastore_attempts ]; then
            print_warning "  -> Could not create datastore after $datastore_attempts attempts."
        fi
    fi
    
    print_info "  -> Creating prune job for backup retention (GFS: 5-4-2)..."
    pct exec "$CT_ID" -- proxmox-backup-manager prune-job create daily-prune \
        --schedule "$prune_schedule" --store "$datastore_name" --keep-daily 5 --keep-weekly 4 --keep-monthly 2 2>/dev/null || true
    
    print_info "  -> Setting up verification job..."
    pct exec "$CT_ID" -- proxmox-backup-manager verify-job create daily-verify \
        --store "$datastore_name" --schedule "$verify_schedule" 2>/dev/null || true
    
    local pbs_ip=$(yq -r ".network.ip_base" "$WORK_DIR/stacks.yaml").$(yq -r ".stacks.backup.ip_octet" "$WORK_DIR/stacks.yaml")
    print_success "PBS configuration completed. Access web interface at: https://${pbs_ip}:8007"
}



# --- Step 4.4: Configure PVE Backup Job ---

configure_pve_backup_job() {
    print_info "(4.4/5) Configuring Proxmox VE backup job..."
    local pbs_storage_name="lxc-backup-01"
    local job_config_file="/etc/pve/jobs.cfg"
    local job_id="vzdump-automated-pbs"
    local pbs_ip=$(yq -r ".network.ip_base" "$WORK_DIR/stacks.yaml").$(yq -r ".stacks.backup.ip_octet" "$WORK_DIR/stacks.yaml")
    local pbs_datastore=$(yq -r ".stacks.backup.pbs_datastore_name" "$WORK_DIR/stacks.yaml")

    # Add or update PBS storage to PVE automatically
    local pbs_admin_pass=$(pct exec "$CT_ID" -- cat /root/.pbs-admin.pass)
    local pbs_fingerprint=$(echo | openssl s_client -connect "$pbs_ip:8007" 2>/dev/null | openssl x509 -fingerprint -noout -sha256 | cut -d= -f2)
    
    if [ -z "$pbs_fingerprint" ]; then
        print_error "Could not get PBS certificate fingerprint. PBS may not be ready."
        exit 1
    fi
    
    # Check if storage exists and needs update
    if pvesm status --storage "$pbs_storage_name" >/dev/null 2>&1; then
        print_info "  -> PBS storage '$pbs_storage_name' exists. Checking if update needed..."
        
        # Test current storage connection - if it fails, password or fingerprint changed
        if ! pvesm list "$pbs_storage_name" >/dev/null 2>&1; then
            print_info "  -> Storage connection test failed. Updating PBS storage configuration..."
            pvesm set "$pbs_storage_name" \
                --password "$pbs_admin_pass" \
                --fingerprint "$pbs_fingerprint" || {
                print_error "Failed to update PBS storage configuration."
                exit 1
            }
            print_success "  -> PBS storage configuration updated successfully."
        else
            print_success "  -> PBS storage connection is working."
        fi
    else
        print_info "  -> Adding PBS storage '$pbs_storage_name' to Proxmox VE..."
        
        # Add PBS storage using pvesm
        if ! pvesm add pbs "$pbs_storage_name" \
            --server "$pbs_ip" \
            --datastore "$pbs_datastore" \
            --username root@pam \
            --password "$pbs_admin_pass" \
            --content backup \
            --port 8007 \
            --fingerprint "$pbs_fingerprint" 2>&1; then
            print_error "Failed to add PBS storage to Proxmox VE."
            exit 1
        fi
        
        print_success "  -> PBS storage '$pbs_storage_name' added to Proxmox VE."
    fi

    # Check if the job already exists
    if grep -q "^vzdump: $job_id" "$job_config_file"; then
        print_warning "Automated PVE backup job '$job_id' already exists. Skipping creation."
        return 0
    fi

    print_info "  -> Creating automated backup job '$job_id' (GFS: 5-4-2)..."
    cat >> "$job_config_file" <<EOF

vzdump: $job_id
    all 1
    comment "Automated GFS backup for all guests to PBS (5-4-2)"
    compress zstd
    enabled 1
    mailnotification failure
    mode snapshot
    node $(hostname)
    notes-template "{{guestname}} backup - {{cluster}} - {{node}}"
    prune-backups keep-daily=5,keep-weekly=4,keep-monthly=2
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

    # Fetch and push docker-compose.yml to LXC
    download_and_push_config "$CT_ID" "$compose_url" "/root/docker-compose.yml"

    print_info "Starting docker-compose up -d --remove-orphans..."
    if ! pct exec "$CT_ID" -- docker compose -f /root/docker-compose.yml up -d --remove-orphans; then
        print_error "Docker Compose deployment failed. Please check the output above."
        exit 1
    fi
    print_success "Docker Compose stack for [$STACK_NAME] is deploying in the background."
}

# --- Main Execution ---

# For monitoring stack, decrypt .env first to fetch PVE_PASSWORD, then setup Proxmox user
if [[ "$STACK_NAME" == "monitoring" ]]; then
    # Monitoring stack requires encrypted .env - decrypt it first
    decrypt_env_for_deploy "$STACK_NAME" || { print_error "Cannot decrypt .env.enc for monitoring stack. Required for PVE_PASSWORD."; exit 1; }
    
    # Read PVE_PASSWORD from decrypted .env
    if [ -s "$ENV_DECRYPTED_PATH" ]; then
        PVE_MONITORING_PASSWORD=$(grep '^PVE_PASSWORD=' "$ENV_DECRYPTED_PATH" | cut -d '=' -f 2-)
        print_info "Loaded PVE_PASSWORD from encrypted .env file"
    else
        print_error "Decrypted .env file is empty or missing. Cannot proceed with monitoring stack."
        exit 1
    fi
    
    setup_proxmox_monitoring_user
fi

prepare_host
create_lxc

# --- Stack-Specific Deployment ---

if [[ "$STACK_NAME" == "development" ]]; then
    # Development setup is handled by lxc-manager.sh (no Docker, no datapool, no additional config)
    print_info "(3/5) Development stack setup completed by LXC manager."
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