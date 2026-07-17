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

    BACKREST_RENDER_INSTANCE_ID="$instance_id" \
    BACKREST_RENDER_REPO_ID="$repo_id" \
    BACKREST_RENDER_REPO_GUID="$repo_guid" \
    BACKREST_RENDER_USERNAME="$username" \
    BACKREST_RENDER_PASSWORD_BCRYPT="$password_bcrypt_b64" \
    BACKREST_RENDER_REPO_PASSWORD="$repo_password" \
    BACKREST_RENDER_SYNC_KEY_ID="$sync_key_id" \
    BACKREST_RENDER_SYNC_PRIVATE_KEY="$sync_private_key" \
    BACKREST_RENDER_SYNC_PUBLIC_KEY="$sync_public_key" \
    python3 - "$template_file" "$config_file" <<'PYEOF'
import json
import os
import sys

with open(sys.argv[1], encoding="utf-8") as template_file:
    config = json.load(template_file)

replacements = {
    "{{INSTANCE_ID}}": os.environ["BACKREST_RENDER_INSTANCE_ID"],
    "{{REPO_ID}}": os.environ["BACKREST_RENDER_REPO_ID"],
    "{{REPO_GUID}}": os.environ["BACKREST_RENDER_REPO_GUID"],
    "{{USERNAME}}": os.environ["BACKREST_RENDER_USERNAME"],
    "{{PASSWORD_BCRYPT}}": os.environ["BACKREST_RENDER_PASSWORD_BCRYPT"],
    "{{REPO_PASSWORD}}": os.environ["BACKREST_RENDER_REPO_PASSWORD"],
    "{{SYNC_KEY_ID}}": os.environ["BACKREST_RENDER_SYNC_KEY_ID"],
    "{{SYNC_PRIVATE_KEY}}": os.environ["BACKREST_RENDER_SYNC_PRIVATE_KEY"],
    "{{SYNC_PUBLIC_KEY}}": os.environ["BACKREST_RENDER_SYNC_PUBLIC_KEY"],
}

def render(value):
    if isinstance(value, str):
        for placeholder, replacement in replacements.items():
            value = value.replace(placeholder, replacement)
        return value
    if isinstance(value, list):
        return [render(item) for item in value]
    if isinstance(value, dict):
        return {key: render(item) for key, item in value.items()}
    return value

with open(sys.argv[2], "w", encoding="utf-8") as output_file:
    json.dump(render(config), output_file, indent=2)
    output_file.write("\n")
PYEOF
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
    prepare_host_directory /fastpool/config/backrest 0700
    prepare_host_directory /fastpool/config/backrest/config 0700
    prepare_host_directory /fastpool/config/backrest/data 0700
    prepare_host_directory /fastpool/config/backrest/cache 0700
    prepare_host_directory /datapool/backup
}

# Configure rclone for Google Drive sync - creates config files for Docker container
# rclone is now installed inside the Docker image, not in the LXC container
configure_rclone_config() {
    local rclone_conf="/fastpool/config/backrest/config/rclone.conf"
    local rclone_conf_enc="$WORK_DIR/docker/utility/config/rclone.conf.enc"
    local rclone_tmp

    print_info "Configuring rclone from encrypted configuration"

    rclone_tmp=$(mktemp /fastpool/config/backrest/config/rclone.conf.XXXXXX)
    register_runtime_temp_file "$rclone_tmp"

    # Decrypt to a private temporary file so a failed decrypt cannot truncate
    # the last known-good runtime configuration.
    if ! openssl enc -aes-256-cbc -d -pbkdf2 -salt \
        -in "$rclone_conf_enc" \
        -out "$rclone_tmp" \
        -pass env:ENV_ENC_KEY; then
        rm -f "$rclone_tmp"
        print_error "Failed to decrypt rclone.conf.enc"
        return 1
    fi

    chown 101000:101000 "$rclone_tmp"
    chmod 0600 "$rclone_tmp"
    mv -f "$rclone_tmp" "$rclone_conf"

    # Create sync script on host in Backrest config dir (mounted to container as /config)
    local sync_tmp
    sync_tmp=$(mktemp /fastpool/config/backrest/config/sync-to-gdrive.sh.XXXXXX)
    register_runtime_temp_file "$sync_tmp"
    cat > "$sync_tmp" << 'SYNCEOF'
#!/bin/sh
# Backrest hook script: Sync backups to Google Drive after successful backup
# This is an exact mirror: successful forget/prune deletions are permanently
# propagated to Drive so stale restic pack files do not consume cloud quota.
# Optimized for 20 MB/s connection.

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

    chown 101000:101000 "$sync_tmp"
    chmod 0700 "$sync_tmp"
    mv -f "$sync_tmp" /fastpool/config/backrest/config/sync-to-gdrive.sh

    print_success "Rclone configuration decrypted"
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
    local backrest_instance_id backrest_repo_id backrest_repo_guid
    local backrest_auth_username backrest_auth_password_bcrypt backrest_repo_password
    local backrest_sync_key_id backrest_sync_private_key backrest_sync_public_key

    backrest_instance_id=$(get_env_value "BACKREST_INSTANCE_ID")
    backrest_repo_id=$(get_env_value "BACKREST_REPO_ID")
    backrest_repo_guid=$(get_env_value "BACKREST_REPO_GUID")
    backrest_auth_username=$(get_env_value "BACKREST_AUTH_USERNAME")
    backrest_auth_password_bcrypt=$(get_env_value "BACKREST_AUTH_PASSWORD_BCRYPT")
    backrest_repo_password=$(get_env_value "BACKREST_REPO_PASSWORD")
    backrest_sync_key_id=$(get_env_value "BACKREST_SYNC_KEY_ID")
    backrest_sync_private_key=$(get_env_value "BACKREST_SYNC_PRIVATE_KEY")
    backrest_sync_public_key=$(get_env_value "BACKREST_SYNC_PUBLIC_KEY")

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

    # Generate and validate a private temporary config before replacing the
    # last known-good Backrest configuration.
    local backrest_config_tmp
    backrest_config_tmp=$(mktemp /fastpool/config/backrest/config/config.json.XXXXXX)
    register_runtime_temp_file "$backrest_config_tmp"

    if ! generate_backrest_config \
        "$backrest_config_tmp" \
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
        rm -f "$backrest_config_tmp"
        print_error "Could not generate Backrest configuration. Aborting."
        return 1
    fi

    python3 -m json.tool "$backrest_config_tmp" >/dev/null
    chown 101000:101000 "$backrest_config_tmp"
    chmod 0600 "$backrest_config_tmp"
    mv -f "$backrest_config_tmp" /fastpool/config/backrest/config/config.json

    # Cloud replication is part of this stack; fail rather than leaving a stale
    # or missing rclone configuration behind.
    if ! configure_rclone_config; then
        print_error "Failed to configure rclone"
        return 1
    fi

    local backrest_ip
    backrest_ip=$(get_lxc_ip "$ct_id")
    print_success "Backrest deployment completed"
    print_info "Web UI: http://${backrest_ip}:9898"
    print_info "Username: $backrest_auth_username"
}
