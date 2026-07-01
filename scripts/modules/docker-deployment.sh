#!/bin/bash

# =================================================================
#                     Docker Deployment Module
# =================================================================
# Handles Docker-based stack deployments - fail fast approach
set -euo pipefail

# Setup homepage configuration files from repository
setup_homepage_config() {
    local ct_id="$1"

    print_info "Setting up Homepage configuration"

    # Ensure directory exists
    mkdir -p /datapool/config/homepage

    # List of homepage config files to copy
    local config_files=("services.yaml" "bookmarks.yaml" "widgets.yaml" "settings.yaml" "docker.yaml")

    # Copy all files from local workspace
    for config_file in "${config_files[@]}"; do
        local source_file="$WORK_DIR/config/homepage/$config_file"
        local dest_file="/datapool/config/homepage/$config_file"
        
        if [[ -f "$source_file" ]]; then
            cp "$source_file" "$dest_file" || {
                print_error "Failed to copy $config_file"
                exit 1
            }
        else
            print_error "Source file not found: $source_file"
            exit 1
        fi
    done

    print_success "Homepage configured"
}

setup_gateway_permissions() {
    print_info "Preparing Gateway directories"

    mkdir -p /datapool/config/npm/data
    mkdir -p /datapool/config/npm/letsencrypt
    mkdir -p /datapool/config/adguard/work
    mkdir -p /datapool/config/adguard/conf

    fix_path_owner_recursive /datapool/config/npm
    fix_path_owner_recursive /datapool/config/adguard

    print_success "Gateway directories ready"
}

setup_desktop_permissions() {
    print_info "Preparing Desktop directories"

    mkdir -p /datapool/config/homepage
    mkdir -p /datapool/config/couchdb/data /datapool/config/couchdb/local.d
    mkdir -p /datapool/config/desktop-workspace
    mkdir -p /datapool/config/vaultwarden
    mkdir -p /datapool/config/guacamole
    mkdir -p /datapool/config/sshwifty
    mkdir -p /datapool/config/futo-notes/postgres
    mkdir -p /datapool/config/futo-notes/blobs

    # These are small writable app-config trees; keep large browser/password data shallow.
    fix_path_owner_recursive /datapool/config/homepage
    fix_path_owner_recursive /datapool/config/couchdb
    fix_path_owner /datapool/config/desktop-workspace
    # Fix all configuration directories (PulseAudio, window manager, themes, etc.) at once
    mkdir -p /datapool/config/desktop-workspace/.config
    fix_path_owner_recursive /datapool/config/desktop-workspace/.config
    fix_path_owner /datapool/config/vaultwarden
    fix_path_owner_recursive /datapool/config/guacamole
    fix_path_owner_recursive /datapool/config/sshwifty

    # Fix permissions using our helper functions
    fix_path_owner_recursive /datapool/config/futo-notes
    chmod -R 700 /datapool/config/futo-notes/postgres

    print_success "Desktop directories ready"
}

setup_sshwifty_config() {
    local ct_id="$1"

    print_info "Setting up sshwifty configuration"

    mkdir -p /datapool/config/sshwifty
    mkdir -p /root/.ssh
    chmod 700 /root/.ssh

    # Generate SSH key pair for sshwifty → Proxmox auth (idempotent)
    local key_file="/datapool/config/sshwifty/sshwifty_key"
    if [[ ! -f "$key_file" ]]; then
        print_info "Generating ed25519 SSH key for sshwifty"
        ssh-keygen -t ed25519 -N "" -f "$key_file" -C "sshwifty@homelab" || {
            print_error "Failed to generate SSH key"
            exit 1
        }
        chmod 600 "$key_file"
        chmod 644 "${key_file}.pub"
        print_success "SSH key generated: $key_file"
    else
        print_info "SSH key already exists: $key_file"
    fi

    # Add public key to Proxmox authorized_keys (idempotent)
    local pub_key
    pub_key=$(cat "${key_file}.pub")
    touch /root/.ssh/authorized_keys
    chmod 600 /root/.ssh/authorized_keys

    if ! grep -qF "$pub_key" /root/.ssh/authorized_keys; then
        echo "$pub_key" >> /root/.ssh/authorized_keys
        print_success "sshwifty public key added to Proxmox authorized_keys"
    else
        print_info "sshwifty public key already in authorized_keys"
    fi

    # Build sshwifty.conf.json with private key embedded (Python handles JSON escaping)
    local source_template="$WORK_DIR/config/sshwifty/sshwifty.conf.json.template"
    local dest_file="/datapool/config/sshwifty/sshwifty.conf.json"

    [[ -f "$source_template" ]] || { print_error "sshwifty template not found: $source_template"; exit 1; }

    if ! python3 - <<PYEOF
import json

with open("$source_template") as f:
    config = json.load(f)

with open("$key_file") as f:
    private_key = f.read()

# Inject private key into preset
config["Presets"][0]["Meta"]["PrivateKey"] = private_key

with open("$dest_file", "w") as f:
    json.dump(config, f, indent=4)

import os
os.chmod("$dest_file", 0o644)
PYEOF
    then
        print_error "Failed to generate sshwifty.conf.json"
        exit 1
    fi

    # Enforce correct file permissions on key files and configuration
    chmod 644 "$dest_file"
    chmod 600 "$key_file"
    chmod 644 "${key_file}.pub"

    fix_path_owner_recursive /datapool/config/sshwifty

    print_success "sshwifty configured with key-based auth"
}

setup_utility_permissions() {
    print_info "Preparing Utility directories"

    mkdir -p /datapool/config/jdownloader2
    mkdir -p /datapool/config/metube
    mkdir -p /datapool/config/repackarr/data /datapool/config/repackarr/logs
    mkdir -p /datapool/config/samba
    mkdir -p /datapool/torrents/other
    mkdir -p /datapool/media/kids/youtube

    # Copy Samba configuration if template exists in repository and replace environment variables
    if [[ -f "$WORK_DIR/config/samba/config.yml" ]]; then
        if [[ -n "${ENV_DECRYPTED_PATH:-}" && -f "$ENV_DECRYPTED_PATH" ]]; then
            local samba_user samba_password
            samba_user=$(grep "^SAMBA_USER=" "$ENV_DECRYPTED_PATH" | cut -d'=' -f2- | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//")
            samba_password=$(grep "^SAMBA_PASSWORD=" "$ENV_DECRYPTED_PATH" | cut -d'=' -f2- | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//")
            
            if [[ -n "$samba_user" && -n "$samba_password" ]]; then
                sed -e "s/\${SAMBA_USER}/$samba_user/g" \
                    -e "s/\${SAMBA_PASSWORD}/$samba_password/g" \
                    "$WORK_DIR/config/samba/config.yml" > /datapool/config/samba/config.yml
            else
                cp "$WORK_DIR/config/samba/config.yml" /datapool/config/samba/config.yml
            fi
        else
            cp "$WORK_DIR/config/samba/config.yml" /datapool/config/samba/config.yml
        fi
    fi

    # Current trees are small and commonly written by user-mapped containers.
    fix_path_owner_recursive /datapool/config/jdownloader2
    fix_path_owner_recursive /datapool/config/metube
    fix_path_owner_recursive /datapool/config/repackarr
    # Samba directory is owned by 101000, but cache and lib must be world-writable (777) so Samba's root process can manage lock files
    mkdir -p /datapool/config/samba/cache /datapool/config/samba/lib/private
    fix_path_owner_recursive /datapool/config/samba
    chmod 777 /datapool/config/samba/cache /datapool/config/samba/lib
    fix_path_owner /datapool/torrents/other
    fix_path_owner /datapool/media/kids
    fix_path_owner /datapool/media/kids/youtube

    print_success "Utility directories ready"
}

setup_gaming_permissions() {
    print_info "Preparing Gaming directories"

    mkdir -p /datapool/config/gameservers/palworld
    mkdir -p /datapool/config/gameservers/satisfactory
    mkdir -p /datapool/config/gameservers/conan

    fix_path_owner_recursive /datapool/config/gameservers
    print_success "Gaming directories ready"
}

# Setup CouchDB directories and configuration
setup_couchdb_config() {
    local ct_id="$1"

    print_info "Setting up CouchDB"

    # Create CouchDB directories
    mkdir -p /datapool/config/couchdb/data
    mkdir -p /datapool/config/couchdb/local.d

    # Copy CouchDB configuration file
    local source_file="$WORK_DIR/config/couchdb/local.ini"
    local dest_file="/datapool/config/couchdb/local.d/local.ini"

    if [[ -f "$source_file" ]]; then
        cp "$source_file" "$dest_file" || {
            print_error "Failed to copy local.ini"
            exit 1
        }
    else
        print_error "Source file not found: $source_file"
        exit 1
    fi

    print_success "CouchDB configured"
}

# Setup Guacamole configuration from template
setup_guacamole_config() {
    local ct_id="$1"

    print_info "Setting up Guacamole configuration"

    if [[ ! -f "${ENV_DECRYPTED_PATH:-}" ]]; then
        print_error "Decrypted environment file not found at ENV_DECRYPTED_PATH"
        exit 1
    fi

    # Helper function to read values safely from .env without sourcing (prevents command execution of unquoted values with spaces)
    get_env_val() {
        local key="$1"
        local val
        val=$(grep "^${key}=" "$ENV_DECRYPTED_PATH" | cut -d'=' -f2-)
        # Strip leading/trailing single/double quotes
        val=$(echo "$val" | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//")
        echo "$val"
    }

    local guacamole_user guacamole_password desktop_ip desktop_user desktop_password laptop_ip laptop_rdp_user laptop_rdp_password
    guacamole_user=$(get_env_val "GUACAMOLE_USER")
    guacamole_password=$(get_env_val "GUACAMOLE_PASSWORD")
    
    desktop_ip=$(get_env_val "DESKTOP_IP")
    if [[ -z "$desktop_ip" ]]; then
        desktop_ip=$(get_env_val "WINDOWS_IP")
    fi
    
    desktop_user=$(get_env_val "DESKTOP_USER")
    if [[ -z "$desktop_user" ]]; then
        desktop_user=$(get_env_val "WINDOWS_RDP_USER")
    fi
    
    desktop_password=$(get_env_val "DESKTOP_PASSWORD")
    if [[ -z "$desktop_password" ]]; then
        desktop_password=$(get_env_val "WINDOWS_RDP_PASSWORD")
    fi

    laptop_ip=$(get_env_val "LAPTOP_IP")
    laptop_rdp_user=$(get_env_val "LAPTOP_RDP_USER")
    laptop_rdp_password=$(get_env_val "LAPTOP_RDP_PASSWORD")

    # Fallback for laptop configuration if not explicitly set
    if [[ -z "$laptop_rdp_user" ]]; then
        laptop_rdp_user="$desktop_user"
    fi
    if [[ -z "$laptop_rdp_password" ]]; then
        laptop_rdp_password="$desktop_password"
    fi
    if [[ -z "$laptop_ip" ]]; then
        # Default placeholder to prevent sed failure or invalid XML mapping if missing
        laptop_ip="192.168.1.21"
    fi

    # Fail fast if variables are missing
    if [[ -z "$guacamole_user" || -z "$guacamole_password" || -z "$desktop_ip" || -z "$desktop_user" || -z "$desktop_password" ]]; then
        print_error "Missing required Guacamole or Desktop workstation configuration in environment file"
        exit 1
    fi

    # Create guacamole config directory on host
    mkdir -p /datapool/config/guacamole

    local source_template="$WORK_DIR/config/guacamole/user-mapping.xml.template"
    local dest_file="/datapool/config/guacamole/user-mapping.xml"

    if [[ -f "$source_template" ]]; then
        # Replace placeholders with environment values
        sed -e "s|GUACAMOLE_USER_PLACEHOLDER|${guacamole_user}|g" \
            -e "s|GUACAMOLE_PASSWORD_PLACEHOLDER|${guacamole_password}|g" \
            -e "s|WINDOWS_IP_PLACEHOLDER|${desktop_ip}|g" \
            -e "s|WINDOWS_USER_PLACEHOLDER|${desktop_user}|g" \
            -e "s|WINDOWS_PASSWORD_PLACEHOLDER|${desktop_password}|g" \
            -e "s|LAPTOP_IP_PLACEHOLDER|${laptop_ip}|g" \
            -e "s|LAPTOP_USER_PLACEHOLDER|${laptop_rdp_user}|g" \
            -e "s|LAPTOP_PASSWORD_PLACEHOLDER|${laptop_rdp_password}|g" \
            "$source_template" > "$dest_file" || {
                print_error "Failed to generate user-mapping.xml from template"
                exit 1
            }
    else
        print_error "Guacamole user-mapping.xml.template not found at $source_template"
        exit 1
    fi

    # Fix ownership
    fix_path_owner_recursive /datapool/config/guacamole

    print_success "Guacamole configured"
}


# Setup Immich directories with correct ownership
setup_immich_directories() {
    print_info "Preparing Immich directories"

    # Create all required Immich directories
    mkdir -p /datapool/media/immich/{upload,library,thumbs,profile,backups,encoded-video}
    mkdir -p /datapool/config/immich/{postgres,cache}

    # These services run as user 1000 inside unprivileged LXC containers, so the
    # host paths must map to 101000:101000 to remain writable after bind mounts.
    fix_path_owner_recursive /datapool/config/immich/cache

    # Set appropriate permissions (chmod only, ownership handled globally)
    chmod -R 755 /datapool/media/immich
    chmod -R 700 /datapool/config/immich/postgres

    print_success "Immich configured"
}

# Setup Tdarr directories
setup_tdarr_directories() {
    print_info "Preparing Tdarr directories"

    # Create config and temp directories
    mkdir -p /datapool/config/tdarr/{server,configs,logs}
    mkdir -p /datapool/temp/tdarr

    # Ensure correct ownership for LXC user (101000 mapping for user 1000)
    fix_path_owner_recursive /datapool/config/tdarr
    fix_path_owner_recursive /datapool/temp/tdarr

    # Ensure correct permissions for the temp directory (transcoding needs write access)
    chmod -R 777 /datapool/temp/tdarr

    print_success "Tdarr configured"
}


# Download and configure Docker Compose files
setup_docker_compose() {
    local stack_name="$1"
    local ct_id="$2"
    
    print_info "Setting up Docker Compose for $stack_name"
    
    # Copy compose file from local workspace
    local source_file="$WORK_DIR/docker/$stack_name/docker-compose.yml"
    
    if [[ -f "$source_file" ]]; then
        # Copy app compose to container root directory directly
        pct push "$ct_id" "$source_file" "/root/docker-compose.yml" || { 
            print_error "Failed to push compose file"
            exit 1 
        }
    else
        print_error "docker-compose.yml not found at $source_file"
        exit 1
    fi
    
    print_success "Docker Compose configured"
}

# Verify Docker is available in container (already installed during LXC provisioning)
verify_docker() {
    local ct_id="$1"

    # Docker should already be installed by lxc-manager.sh
    # This verification will fail-fast with visible error if missing
    pct exec "$ct_id" -- docker --version

    print_success "Docker verified"
}

# Deploy Docker Compose services - pull latest images
deploy_docker_services() {
    local stack_name="$1"
    local ct_id="$2"

    print_info "Deploying services for $stack_name"

    # Pre-create Satisfactory local gamefiles directory on the SSD and set proper ownership
    if [ "$stack_name" = "gaming" ]; then
        pct exec "$ct_id" -- sh -c "mkdir -p /opt/satisfactory && chown -R 1000:1000 /opt/satisfactory"
    fi

    # Pull images and deploy in one command
    pct exec "$ct_id" -- sh -c "cd /root && docker compose up -d --pull always --remove-orphans" || {
        print_error "Failed to deploy services"
        exit 1
    }

    print_success "Services deployed"
}

# Setup aliases and MOTD for game servers
setup_gameserver_aliases() {
    local ct_id="$1"
    print_info "Configuring Game Server aliases"

    # Define the marker used to identify our block
    local start_marker="# --- Game Server Manager Aliases ---"
    local end_marker="# --- End Game Server Manager ---"

    # Create the alias content locally
    local alias_file="/tmp/gameserver_aliases.sh"
    cat <<EOF > "$alias_file"

$start_marker
# Aliases for Game Server Management
# Core services (watchtower) always run via base compose
# Game servers are managed separately via profiles

# Ensure core services are always running, then start/stop game containers
alias start-palworld='cd /root && echo "Starting Palworld..." && docker stop satisfactory-server 2>/dev/null || true && docker compose up -d && docker compose --profile palworld up -d --pull always'
alias start-satisfactory='cd /root && echo "Starting Satisfactory..." && docker stop palworld-server 2>/dev/null || true && docker compose up -d && docker compose --profile satisfactory up -d --pull always'
alias stop-games='cd /root && echo "Stopping all game servers..." && docker stop palworld-server satisfactory-server 2>/dev/null || true'
alias game-status='cd /root && docker compose ps -a'

# --- Game Server MOTD (Login Message) ---
# Display only on interactive shell login
if [ -t 0 ]; then
    echo -e "\033[1;36m=====================================================\033[0m"
    echo -e "\033[1;32m       Proxmox Homelab Game Server Manager           \033[0m"
    echo -e "\033[1;36m=====================================================\033[0m"
    echo -e " Available Commands:"
    echo -e "  \033[1;33mstart-palworld\033[0m      : Start Palworld (stops others)"
    echo -e "  \033[1;33mstart-satisfactory\033[0m  : Start Satisfactory (stops others)"
    echo -e "  \033[1;33mstop-games\033[0m          : Stop all running games"
    echo -e "  \033[1;33mgame-status\033[0m         : Show running containers"
    echo -e "\033[1;36m=====================================================\033[0m"
    echo
fi
$end_marker
EOF

    # Target files for aliases (Alpine uses .profile by default, Bash uses .bashrc)
    local target_files=("/root/.bashrc" "/root/.profile")
    
    # Push the alias file to the container
    pct push "$ct_id" "$alias_file" "/tmp/aliases.sh"

    # Loop through targets and apply changes
    for target in "${target_files[@]}"; do
        # Create file if it doesn't exist
        pct exec "$ct_id" -- touch "$target"
        
        # Clean existing block if present (Idempotency) using sed
        pct exec "$ct_id" -- sh -c "if grep -qF '$start_marker' '$target'; then sed -i '/$start_marker/,/$end_marker/d' '$target'; fi"
        
        # Append new block
        pct exec "$ct_id" -- sh -c "cat /tmp/aliases.sh >> '$target'"
    done

    # Cleanup
    pct exec "$ct_id" -- rm -f "/tmp/aliases.sh"
    rm -f "$alias_file"

    print_success "Game Server aliases configured"
}

# Full Docker deployment workflow
deploy_docker_stack() {
    local stack_name="$1"
    local ct_id="$2"
    
    # Check if docker-compose.yml exists for this stack locally
    local compose_file="$WORK_DIR/docker/$stack_name/docker-compose.yml"
    
    if [[ ! -f "$compose_file" ]]; then
        print_info "No docker-compose.yml found for $stack_name at $compose_file, skipping"
        return 0
    fi
    
    verify_docker "$ct_id"
    
    # Setup Homepage config files for desktop stack
    if [[ "$stack_name" == "desktop" ]]; then
        setup_desktop_permissions
        setup_homepage_config "$ct_id"
        setup_couchdb_config "$ct_id"
        setup_guacamole_config "$ct_id"
        setup_sshwifty_config "$ct_id"
    fi

    if [[ "$stack_name" == "utility" ]]; then
        setup_utility_permissions
    fi

    if [[ "$stack_name" == "gaming" ]]; then
        setup_gaming_permissions
    fi

    # Setup Immich directories for media stack
    if [[ "$stack_name" == "media" ]]; then
        setup_immich_directories
        setup_tdarr_directories
        
        # Setup secure vault infrastructure requirements
        print_info "Installing security tools for media stack"
        pct exec "$ct_id" -- apt-get update
        pct exec "$ct_id" -- apt-get install -y gocryptfs
    fi

    if [[ "$stack_name" == "gateway" ]]; then
        setup_gateway_permissions
    fi

    setup_docker_compose "$stack_name" "$ct_id"
    deploy_docker_services "$stack_name" "$ct_id"

    # Setup aliases for gaming stack
    if [[ "$stack_name" == "gaming" ]]; then
        setup_gameserver_aliases "$ct_id"
    fi
    
    print_success "Stack deployed: $stack_name"
}


