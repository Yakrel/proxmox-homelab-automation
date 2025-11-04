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

# Configure Backrest directories and permissions on host
configure_backrest_directories() {
    # Create Backrest directories on host (idempotent with -p)
    mkdir -p /datapool/config/backrest/config
    mkdir -p /datapool/config/backrest/data
    mkdir -p /datapool/config/backrest/cache
    mkdir -p /datapool/backup

    # Set ownership for unprivileged container access (UID 1000 in container = UID 101000 on host)
    chown -R 101000:101000 /datapool/config/backrest
    chown -R 101000:101000 /datapool/backup
}

# Configure rclone for Google Drive sync inside LXC container
configure_rclone_in_lxc() {
    local ct_id="$1"

    # Read OAuth credentials from decrypted .env
    local gdrive_client_id gdrive_client_secret gdrive_oauth_token
    gdrive_client_id=$(echo "$env_content" | grep "^GDRIVE_CLIENT_ID=" | cut -d'=' -f2-)
    gdrive_client_secret=$(echo "$env_content" | grep "^GDRIVE_CLIENT_SECRET=" | cut -d'=' -f2-)
    gdrive_oauth_token=$(echo "$env_content" | grep "^GDRIVE_OAUTH_TOKEN=" | cut -d'=' -f2-)

    # Validate credentials exist
    if [[ -z "$gdrive_client_id" || -z "$gdrive_client_secret" || -z "$gdrive_oauth_token" ]]; then
        return 0
    fi

    # Install rclone in Alpine LXC
    pct exec "$ct_id" -- apk add --no-cache rclone

    # Create rclone config directory in LXC
    pct exec "$ct_id" -- mkdir -p /root/.config/rclone

    # Create rclone config file temporarily on host
    local temp_rclone_conf="/tmp/rclone-${ct_id}.conf"
    cat > "$temp_rclone_conf" << EOF
[gdrive]
type = drive
scope = drive
client_id = ${gdrive_client_id}
client_secret = ${gdrive_client_secret}
token = ${gdrive_oauth_token}
EOF

    # Push rclone config to LXC
    pct push "$ct_id" "$temp_rclone_conf" /root/.config/rclone/rclone.conf

    # Set secure permissions
    pct exec "$ct_id" -- chmod 600 /root/.config/rclone/rclone.conf

    # Copy rclone config to Backrest config dir for Docker container access
    cp "$temp_rclone_conf" /datapool/config/backrest/config/rclone.conf
    chown 101000:101000 /datapool/config/backrest/config/rclone.conf
    chmod 600 /datapool/config/backrest/config/rclone.conf

    # Clean up temporary file
    rm -f "$temp_rclone_conf"

    # Create sync script on host in Backrest config dir (mounted to container as /config)
    cat > /datapool/config/backrest/config/sync-to-gdrive.sh << 'SYNCEOF'
#!/bin/sh
# Backrest hook script: Sync backups to Google Drive after successful backup

LOG_FILE="/config/rclone-gdrive-sync.log"

echo "$(date): Starting Google Drive sync" >> "$LOG_FILE"

/usr/bin/rclone sync /repos gdrive:homelab-backups \
    --config=/config/rclone.conf \
    --log-file="$LOG_FILE" \
    --log-level=INFO \
    --fast-list \
    --checksum \
    --exclude="**/cache/**" \
    --exclude="**/*.tmp" 2>&1 | tee -a "$LOG_FILE"

if [ $? -eq 0 ]; then
    echo "$(date): Sync completed successfully" >> "$LOG_FILE"
    exit 0
else
    echo "$(date): Sync failed with error code $?" >> "$LOG_FILE"
    exit 1
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
    if [[ -z "$backrest_instance_id" || -z "$backrest_repo_id" || -z "$backrest_repo_guid" || \
          -z "$backrest_auth_username" || -z "$backrest_auth_password_bcrypt" || -z "$backrest_repo_password" || \
          -z "$backrest_sync_key_id" || -z "$backrest_sync_private_key" || -z "$backrest_sync_public_key" ]]; then
        print_error "Missing required environment variables in .env file"
        return 1
    fi

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

    # Configure rclone for Google Drive sync in LXC (uses same env_content)
    if ! configure_rclone_in_lxc "$ct_id"; then
        print_warning "Failed to configure rclone, continuing without cloud sync"
    fi

    local backrest_ip
    backrest_ip=$(get_lxc_ip "$ct_id")
    print_success "Backrest deployment completed"
    print_info "Web UI: http://${backrest_ip}:9898"
    print_info "Username: $backrest_auth_username"
}