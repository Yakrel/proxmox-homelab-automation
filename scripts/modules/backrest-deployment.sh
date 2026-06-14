#!/bin/bash

# =================================================================
#                      Backup Stack Module
# =================================================================
# Deploys a pre-configured Backrest instance using a generated config.json

# Strict error handling
set -euo pipefail

# --- Helper Functions ---

# Generates a complete, pre-configured config.json for Backrest from a template file.
# This makes the deployment zero-touch, with all repositories and plans ready on first boot.
generate_backrest_config() {
    local config_file="$1"
    local template_file="$2"
    local instance_id="$3"
    local repo_id="$4"
    local repo_guid="$5"
    local username="$6"
    local password_bcrypt="$7"
    local repo_password="$8"
    local sync_key_id="$9"
    local sync_private_key="${10}"
    local sync_public_key="${11}"

    # Check if template file exists
    if [[ ! -f "$template_file" ]]; then
        print_error "Configuration template not found at $template_file"
        return 1
    fi

    # Backrest expects bcrypt hash to be base64 encoded
    # Convert $$2b$$12$$... (from .env) to $2b$12$... then base64 encode
    local bcrypt_raw
    bcrypt_raw=$(printf '%s' "$password_bcrypt" | sed 's/\$\$/$/g')
    local password_bcrypt_b64
    password_bcrypt_b64=$(printf '%s' "$bcrypt_raw" | base64 -w 0)

    # Escape special characters for sed
    local escaped_password_bcrypt
    local escaped_repo_password
    local escaped_sync_private
    local escaped_sync_public

    escaped_password_bcrypt=$(printf '%s' "$password_bcrypt_b64" | sed 's/[&/\$]/\\&/g')
    escaped_repo_password=$(printf '%s' "$repo_password" | sed 's/[&/\$]/\\&/g')
    escaped_sync_private=$(printf '%s' "$sync_private_key" | sed 's/[&/\$]/\\&/g')
    escaped_sync_public=$(printf '%s' "$sync_public_key" | sed 's/[&/\$]/\\&/g')

    sed -e "s|{{INSTANCE_ID}}|$instance_id|g" \
        -e "s|{{REPO_ID}}|$repo_id|g" \
        -e "s|{{REPO_GUID}}|$repo_guid|g" \
        -e "s|{{USERNAME}}|$username|g" \
        -e "s|{{PASSWORD_BCRYPT}}|$escaped_password_bcrypt|g" \
        -e "s|{{REPO_PASSWORD}}|$escaped_repo_password|g" \
        -e "s|{{SYNC_KEY_ID}}|$sync_key_id|g" \
        -e "s|{{SYNC_PRIVATE_KEY}}|$escaped_sync_private|g" \
        -e "s|{{SYNC_PUBLIC_KEY}}|$escaped_sync_public|g" \
        "$template_file" > "$config_file"

    # Verify that the config file was created and is not empty
    if [[ ! -s "$config_file" ]]; then
        print_error "Failed to generate config.json. Output file is empty."
        return 1
    fi
}

# Read the canonical restic repository ID. Backrest uses this as the repo guid.
get_restic_repo_guid() {
    local ct_id="$1"
    local repo_password="$2"
    local repo_config="/datapool/backup/config"
    local image="ghcr.io/yakrel/docker-backrest-rclone:latest"

    if [[ ! -s "$repo_config" ]]; then
        return 1
    fi

    pct exec "$ct_id" -- docker run --rm \
        --user 1000:1000 \
        -e "RESTIC_PASSWORD=$repo_password" \
        -e "XDG_CACHE_HOME=/tmp" \
        -v /datapool/backup:/repos \
        "$image" \
        restic -r /repos cat config | sed -n 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p'
}

# Initialize the repository before Backrest starts so config.json and restic agree.
initialize_restic_repo() {
    local ct_id="$1"
    local repo_password="$2"
    local image="ghcr.io/yakrel/docker-backrest-rclone:latest"

    if [[ -s /datapool/backup/config ]]; then
        print_info "Restic repository already initialized"
        return 0
    fi

    print_info "Initializing restic repository"
    pct exec "$ct_id" -- docker run --rm \
        --user 1000:1000 \
        -e "RESTIC_PASSWORD=$repo_password" \
        -e "XDG_CACHE_HOME=/tmp" \
        -v /datapool/backup:/repos \
        "$image" \
        restic -r /repos init

    print_success "Restic repository initialized"
}

# Configure Backrest directories and permissions on host
configure_backrest_directories() {
    # Create Backrest directories on host (idempotent with -p)
    mkdir -p /datapool/config/backrest/config
    mkdir -p /datapool/config/backrest/data
    mkdir -p /datapool/config/backrest/cache
    mkdir -p /datapool/backup

    # Set ownership for unprivileged container access (UID 1000 in container = UID 101000 on host)
    fix_path_owner_recursive /datapool/config/backrest
    fix_path_owner /datapool/backup
}

# Configure rclone for Google Drive sync - creates config files for Docker container
# rclone is now installed inside the Docker image, not in the LXC container
configure_rclone_config() {
    local rclone_conf="/datapool/config/backrest/config/rclone.conf"
    local rclone_conf_enc="$WORK_DIR/docker/utility/config/rclone.conf.enc"

    print_info "Configuring rclone from encrypted configuration"

    # Decrypt rclone.conf
    if ! openssl enc -aes-256-cbc -d -pbkdf2 -salt \
        -in "$rclone_conf_enc" \
        -out "$rclone_conf" \
        -pass "pass:$ENV_ENC_KEY"; then
        print_error "Failed to decrypt rclone.conf.enc"
        return 1
    fi

    print_success "Rclone configuration decrypted"
    chown 101000:101000 "$rclone_conf"
    chmod 600 "$rclone_conf"

    # Create sync script on host in Backrest config dir (mounted to container as /config)
    cat > /datapool/config/backrest/config/sync-to-gdrive.sh << 'SYNCEOF'
#!/bin/sh
# Backrest hook script: Sync backups to Google Drive after successful backup
# Optimized for 20 MB/s connection

LOG_FILE="/config/rclone-gdrive-sync.log"
LOG_MAX_BYTES=5242880

# Keep only the newest log data in a single file. No .1/.2 rotation.
if [ -f "$LOG_FILE" ]; then
    log_size=$(wc -c "$LOG_FILE" | awk '{print $1}')
    if [ "$log_size" -gt "$LOG_MAX_BYTES" ]; then
        tmp_file="${LOG_FILE}.tmp"
        tail -c "$LOG_MAX_BYTES" "$LOG_FILE" > "$tmp_file"
        mv "$tmp_file" "$LOG_FILE"
    fi
fi

echo "$(date): Starting Google Drive sync from /repos to gdrive:homelab-backups" >> "$LOG_FILE"

/usr/bin/rclone sync /repos gdrive:homelab-backups \
    --config=/config/rclone.conf \
    --log-file="$LOG_FILE" \
    --log-level=INFO \
    --fast-list \
    --checksum \
    --transfers=4 \
    --checkers=8 \
    --tpslimit=8 \
    --tpslimit-burst=16 \
    --retries=10 \
    --low-level-retries=20 \
    --retries-sleep=10s \
    --timeout=10m \
    --contimeout=60s \
    --drive-chunk-size=64M \
    --drive-upload-cutoff=64M \
    --drive-use-trash=false \
    --exclude="**/cache/**" \
    --exclude="**/*.tmp"
rclone_exit_code=$?

if [ "$rclone_exit_code" -eq 0 ]; then
    echo "$(date): Sync completed successfully" >> "$LOG_FILE"
    exit 0
else
    echo "$(date): Sync failed with exit code $rclone_exit_code" >> "$LOG_FILE"
    exit "$rclone_exit_code"
fi
SYNCEOF

    # Set ownership and permissions for container access
    chown 101000:101000 /datapool/config/backrest/config/sync-to-gdrive.sh
    chmod +x /datapool/config/backrest/config/sync-to-gdrive.sh
}

# Deploy Backrest stack
deploy_backrest() {
    local ct_id="$1"

    # Configure directories on the host
    if ! configure_backrest_directories; then
        print_error "Failed to configure Backrest directories"
        return 1
    fi

    # Safely read variables from the decrypted .env file without sourcing it
    # Optimization: Read file once and parse all variables to avoid multiple file reads
    local backrest_instance_id backrest_repo_id backrest_repo_guid
    local backrest_auth_username backrest_auth_password_bcrypt backrest_repo_password
    local backrest_sync_key_id backrest_sync_private_key backrest_sync_public_key
    local env_content

    env_content=$(cat "$ENV_DECRYPTED_PATH")
    
    backrest_instance_id=$(echo "$env_content" | grep "^BACKREST_INSTANCE_ID=" | cut -d'=' -f2-)
    backrest_repo_id=$(echo "$env_content" | grep "^BACKREST_REPO_ID=" | cut -d'=' -f2-)
    backrest_repo_guid=$(echo "$env_content" | grep "^BACKREST_REPO_GUID=" | cut -d'=' -f2-)
    backrest_auth_username=$(echo "$env_content" | grep "^BACKREST_AUTH_USERNAME=" | cut -d'=' -f2-)
    backrest_auth_password_bcrypt=$(echo "$env_content" | grep "^BACKREST_AUTH_PASSWORD_BCRYPT=" | cut -d'=' -f2-)
    backrest_repo_password=$(echo "$env_content" | grep "^BACKREST_REPO_PASSWORD=" | cut -d'=' -f2-)
    backrest_sync_key_id=$(echo "$env_content" | grep "^BACKREST_SYNC_KEY_ID=" | cut -d'=' -f2-)
    backrest_sync_private_key=$(echo "$env_content" | grep "^BACKREST_SYNC_PRIVATE_KEY=" | cut -d'=' -f2-)
    backrest_sync_public_key=$(echo "$env_content" | grep "^BACKREST_SYNC_PUBLIC_KEY=" | cut -d'=' -f2-)

    # Validate required variables
    if [[ -z "$backrest_instance_id" || -z "$backrest_repo_id" || \
          -z "$backrest_auth_username" || -z "$backrest_auth_password_bcrypt" || -z "$backrest_repo_password" || \
          -z "$backrest_sync_key_id" || -z "$backrest_sync_private_key" || -z "$backrest_sync_public_key" ]]; then
        print_error "Missing required environment variables in .env file"
        return 1
    fi

    if ! initialize_restic_repo "$ct_id" "$backrest_repo_password"; then
        print_error "Failed to initialize restic repository"
        return 1
    fi

    local actual_repo_guid
    actual_repo_guid=$(get_restic_repo_guid "$ct_id" "$backrest_repo_password")
    if [[ -z "$actual_repo_guid" ]]; then
        print_error "Could not read restic repository ID from /datapool/backup/config"
        return 1
    fi

    if [[ -n "$backrest_repo_guid" && "$backrest_repo_guid" != "$actual_repo_guid" ]]; then
        print_warning "BACKREST_REPO_GUID differs from restic repository ID, using repository ID"
    fi
    backrest_repo_guid="$actual_repo_guid"

    # Generate the complete, pre-configured config.json from the template
    if ! generate_backrest_config \
        "/datapool/config/backrest/config/config.json" \
        "$WORK_DIR/config/backrest/config.json.template" \
        "$backrest_instance_id" \
        "$backrest_repo_id" \
        "$backrest_repo_guid" \
        "$backrest_auth_username" \
        "$backrest_auth_password_bcrypt" \
        "$backrest_repo_password" \
        "$backrest_sync_key_id" \
        "$backrest_sync_private_key" \
        "$backrest_sync_public_key"; then
        print_error "Could not generate Backrest configuration. Aborting."
        return 1
    fi

    # Set secure permissions and ownership on the config file
    chown 101000:101000 /datapool/config/backrest/config/config.json
    chmod 600 /datapool/config/backrest/config/config.json

    # Configure rclone config file for Docker container (uses same env_content)
    if ! configure_rclone_config; then
        print_warning "Failed to configure rclone, continuing without cloud sync"
    fi

    local backrest_ip
    backrest_ip=$(get_lxc_ip "$ct_id")
    print_success "Backrest deployment completed"
    print_info "Web UI: http://${backrest_ip}:9898"
    print_info "Username: $backrest_auth_username"
}
