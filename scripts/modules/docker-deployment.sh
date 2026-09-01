#!/bin/bash

# =================================================================
#                     Docker Deployment Module
# =================================================================
# Handles Docker-based stack deployments - fail fast approach
set -euo pipefail

# Setup homepage configuration files from repository
setup_homepage_config() {
    prepare_host_directory /fastpool/config/homepage
    prepare_host_directory /fastpool/config/homepage/assets

    # List of homepage config files to copy
    local config_files=("services.yaml" "bookmarks.yaml" "widgets.yaml" "settings.yaml" "docker.yaml")

    # Copy all files from local workspace
    for config_file in "${config_files[@]}"; do
        local source_file="$WORK_DIR/config/homepage/$config_file"
        local dest_file="/fastpool/config/homepage/$config_file"
        
        install -o 101000 -g 101000 -m 0644 "$source_file" "$dest_file"
    done

    install -o 101000 -g 101000 -m 0644 \
        "$WORK_DIR/config/homepage/assets/homepage-background.png" \
        /fastpool/config/homepage/assets/homepage-background.png
}

setup_gateway_permissions() {
    prepare_host_directory /fastpool/config/npm
    prepare_host_directory /fastpool/config/npm/data
    prepare_host_directory /fastpool/config/npm/letsencrypt
    prepare_host_directory /fastpool/config/adguard
    prepare_host_directory /fastpool/config/adguard/work
    prepare_host_directory /fastpool/config/adguard/conf
}

setup_desktop_permissions() {
    prepare_host_directory /fastpool/config/desktop-workspace
    prepare_host_directory /fastpool/config/desktop-workspace/.config
    prepare_host_directory /fastpool/config/vaultwarden
    prepare_host_directory /fastpool/config/radicale
    prepare_host_directory /fastpool/config/radicale/config
    prepare_host_directory /fastpool/config/radicale/data
}



setup_sshwifty_config() {
    prepare_host_directory /fastpool/config/sshwifty

    # Presets contain host addresses only. Sshwifty asks for SSH credentials at
    # connection time, so no private key or password is stored on disk.
    local source_template="$WORK_DIR/config/sshwifty/sshwifty.conf.json.template"
    local dest_file="/fastpool/config/sshwifty/sshwifty.conf.json"

    install -o 101000 -g 101000 -m 0644 "$source_template" "$dest_file"
}

setup_hermes_telegram() {
    prepare_host_directory /fastpool/config/hermes 0700

    [[ -f "${ENV_DECRYPTED_PATH:-}" ]] || {
        print_error "Decrypted environment file not found"
        return 1
    }

    local tg_token tg_chat_id
    tg_token=$(get_env_value "HERMES_TELEGRAM_TOKEN")
    tg_chat_id=$(get_env_value "HERMES_TELEGRAM_CHAT_ID")

    if [[ -z "$tg_token" || -z "$tg_chat_id" ]]; then
        print_error "Missing required Hermes Telegram environment variables"
        return 1
    fi

    local env_tmp
    env_tmp=$(mktemp /fastpool/config/hermes/.env.XXXXXX)
    register_runtime_temp_file "$env_tmp"

    if ! HERMES_TG_TOKEN="$tg_token" \
        HERMES_TG_CHAT_ID="$tg_chat_id" \
        python3 - /fastpool/config/hermes/.env "$env_tmp" <<'PYEOF'
import os
import sys

token = os.environ["HERMES_TG_TOKEN"]
chat_id = os.environ["HERMES_TG_CHAT_ID"]

if any("\n" in value or "\r" in value for value in (token, chat_id)):
    raise ValueError("Hermes environment values must be single-line")

source_path, destination_path = sys.argv[1:3]
managed_keys = {"TELEGRAM_BOT_TOKEN", "TELEGRAM_ALLOWED_USERS"}
lines = []

if os.path.exists(source_path):
    with open(source_path, encoding="utf-8") as source_file:
        for line in source_file:
            key = line.split("=", 1)[0].strip()
            if key not in managed_keys:
                lines.append(line.rstrip("\n"))

lines.extend((
    f"TELEGRAM_BOT_TOKEN={token}",
    f"TELEGRAM_ALLOWED_USERS={chat_id}",
))

with open(destination_path, "w", encoding="utf-8") as env_file:
    env_file.write("\n".join(lines) + "\n")
PYEOF
    then
        rm -f "$env_tmp"
        print_error "Failed to configure Hermes Telegram credentials"
        return 1
    fi

    chown 101000:101000 "$env_tmp"
    chmod 0600 "$env_tmp"
    mv -f "$env_tmp" /fastpool/config/hermes/.env
}

setup_utility_permissions() {
    prepare_host_directory /fastpool/config/jdownloader2
    # MeTube persists cookies uploaded through Advanced Options in this directory.
    prepare_host_directory /fastpool/config/metube
    prepare_host_directory /fastpool/config/repackarr
    prepare_host_directory /fastpool/config/repackarr/data
    prepare_host_directory /fastpool/config/repackarr/logs
    prepare_host_directory /fastpool/config/samba 0700
    prepare_host_directory /fastpool/config/changedetection
    prepare_host_directory /fastpool/config/karakeep
    prepare_host_directory /fastpool/config/karakeep/data
    prepare_host_directory /fastpool/config/karakeep/meilisearch
    prepare_host_directory /fastpool/config/beszel
    prepare_host_directory /datapool/downloads
    prepare_host_directory /datapool/downloads/jdownloader
    prepare_host_directory /datapool/downloads/metube

    [[ -f "${ENV_DECRYPTED_PATH:-}" ]] || {
        print_error "Decrypted environment file not found"
        return 1
    }

    local samba_user samba_password samba_tmp
    samba_user=$(get_env_value "SAMBA_USER")
    samba_password=$(get_env_value "SAMBA_PASSWORD")

    if [[ -z "$samba_user" || -z "$samba_password" ]]; then
        print_error "Missing required Samba environment variables"
        return 1
    fi

    samba_tmp=$(mktemp /fastpool/config/samba/config.yml.XXXXXX)
    register_runtime_temp_file "$samba_tmp"
    if ! SAMBA_RENDER_USER="$samba_user" \
        SAMBA_RENDER_PASSWORD="$samba_password" \
        python3 - "$WORK_DIR/config/samba/config.yml" "$samba_tmp" <<'PYEOF'
import json
import os
import sys

with open(sys.argv[1], encoding="utf-8") as source_file:
    content = source_file.read()

content = content.replace("${SAMBA_USER}", json.dumps(os.environ["SAMBA_RENDER_USER"]))
content = content.replace("${SAMBA_PASSWORD}", json.dumps(os.environ["SAMBA_RENDER_PASSWORD"]))

with open(sys.argv[2], "w", encoding="utf-8") as destination_file:
    destination_file.write(content)
PYEOF
    then
        rm -f "$samba_tmp"
        print_error "Failed to generate Samba configuration"
        return 1
    fi

    yq '.' "$samba_tmp" >/dev/null
    chown 101000:101000 "$samba_tmp"
    chmod 0600 "$samba_tmp"
    mv -f "$samba_tmp" /fastpool/config/samba/config.yml
}


setup_ai_permissions() {
    prepare_host_directory /fastpool/config/omniroute
    prepare_host_directory /fastpool/config/hindsight

    # Keep the working Telegram integration while leaving model/provider
    # configuration to Hermes' first-run wizard and dashboard.
    setup_hermes_telegram
}



# Setup CouchDB directories and configuration
setup_couchdb_config() {
    prepare_host_directory /fastpool/config/couchdb
    prepare_host_directory /fastpool/config/couchdb/data
    prepare_host_directory /fastpool/config/couchdb/local.d

    # Copy CouchDB configuration file
    local source_file="$WORK_DIR/config/couchdb/local.ini"
    local dest_file="/fastpool/config/couchdb/local.d/local.ini"

    install -o 101000 -g 101000 -m 0644 "$source_file" "$dest_file"
}

# Setup Guacamole configuration from template
setup_guacamole_config() {
    if [[ ! -f "${ENV_DECRYPTED_PATH:-}" ]]; then
        print_error "Decrypted environment file not found at ENV_DECRYPTED_PATH"
        exit 1
    fi

    local guacamole_user guacamole_password desktop_ip desktop_user desktop_password laptop_ip laptop_rdp_user laptop_rdp_password
    guacamole_user=$(get_env_value "GUACAMOLE_USER")
    guacamole_password=$(get_env_value "GUACAMOLE_PASSWORD")
    
    desktop_ip=$(get_env_value "DESKTOP_IP")
    desktop_user=$(get_env_value "DESKTOP_USER")
    desktop_password=$(get_env_value "DESKTOP_PASSWORD")

    laptop_ip=$(get_env_value "LAPTOP_IP")
    laptop_rdp_user=$(get_env_value "LAPTOP_RDP_USER")
    laptop_rdp_password=$(get_env_value "LAPTOP_RDP_PASSWORD")

    if [[ -n "$laptop_ip$laptop_rdp_user$laptop_rdp_password" ]] && \
       [[ -z "$laptop_ip" || -z "$laptop_rdp_user" || -z "$laptop_rdp_password" ]]; then
        print_error "LAPTOP_IP, LAPTOP_RDP_USER and LAPTOP_RDP_PASSWORD must be set together"
        return 1
    fi

    # Fail fast if variables are missing
    if [[ -z "$guacamole_user" || -z "$guacamole_password" || -z "$desktop_ip" || -z "$desktop_user" || -z "$desktop_password" ]]; then
        print_error "Missing required Guacamole or Desktop workstation configuration in environment file"
        exit 1
    fi

    # The official Guacamole image runs as UID 1001, while host bind sources
    # are owned by the LXC's UID 1000 mapping. Keep this read-only mount
    # readable; the Desktop LXC and authenticated Samba administrator remain
    # trusted boundaries for the credentials stored here.
    prepare_host_directory /fastpool/config/guacamole
    prepare_host_directory /fastpool/config/guacamole/extensions

    local quickconnect_jar="/fastpool/config/guacamole/extensions/guacamole-auth-quickconnect-1.5.5.jar"
    if [[ ! -f "$quickconnect_jar" ]]; then
        local qc_tmp
        qc_tmp=$(mktemp /fastpool/config/guacamole/extensions/quickconnect.XXXXXX)
        register_runtime_temp_file "$qc_tmp"
        if curl -fsSL "https://archive.apache.org/dist/guacamole/1.5.5/binary/guacamole-auth-quickconnect-1.5.5.tar.gz" | tar -xz -O "guacamole-auth-quickconnect-1.5.5/guacamole-auth-quickconnect-1.5.5.jar" > "$qc_tmp"; then
            chown 101000:101000 "$qc_tmp"
            chmod 0644 "$qc_tmp"
            mv -f "$qc_tmp" "$quickconnect_jar"
        else
            rm -f "$qc_tmp"
            print_error "Failed to download guacamole-auth-quickconnect extension"
        fi
    fi

    local source_template="$WORK_DIR/config/guacamole/user-mapping.xml.template"
    local dest_file="/fastpool/config/guacamole/user-mapping.xml"

    local guacamole_tmp
    guacamole_tmp=$(mktemp /fastpool/config/guacamole/user-mapping.xml.XXXXXX)
    register_runtime_temp_file "$guacamole_tmp"

    if ! GUACAMOLE_RENDER_USER="$guacamole_user" \
        GUACAMOLE_RENDER_PASSWORD="$guacamole_password" \
        DESKTOP_RENDER_IP="$desktop_ip" \
        DESKTOP_RENDER_USER="$desktop_user" \
        DESKTOP_RENDER_PASSWORD="$desktop_password" \
        LAPTOP_RENDER_IP="$laptop_ip" \
        LAPTOP_RENDER_USER="$laptop_rdp_user" \
        LAPTOP_RENDER_PASSWORD="$laptop_rdp_password" \
        python3 - "$source_template" "$guacamole_tmp" <<'PYEOF'
import os
import sys
import xml.etree.ElementTree as ET
from xml.sax.saxutils import escape

with open(sys.argv[1], encoding="utf-8") as source_file:
    content = source_file.read()

replacements = {
    "GUACAMOLE_USER_PLACEHOLDER": os.environ["GUACAMOLE_RENDER_USER"],
    "GUACAMOLE_PASSWORD_PLACEHOLDER": os.environ["GUACAMOLE_RENDER_PASSWORD"],
    "DESKTOP_IP_PLACEHOLDER": os.environ["DESKTOP_RENDER_IP"],
    "DESKTOP_USER_PLACEHOLDER": os.environ["DESKTOP_RENDER_USER"],
    "DESKTOP_PASSWORD_PLACEHOLDER": os.environ["DESKTOP_RENDER_PASSWORD"],
    "LAPTOP_IP_PLACEHOLDER": os.environ["LAPTOP_RENDER_IP"],
    "LAPTOP_USER_PLACEHOLDER": os.environ["LAPTOP_RENDER_USER"],
    "LAPTOP_PASSWORD_PLACEHOLDER": os.environ["LAPTOP_RENDER_PASSWORD"],
}

for placeholder, value in replacements.items():
    content = content.replace(placeholder, escape(value, {'"': "&quot;", "'": "&apos;"}))

root = ET.fromstring(content)
if not os.environ["LAPTOP_RENDER_IP"]:
    for authorize in root.findall("authorize"):
        for connection in authorize.findall("connection"):
            if connection.get("name") == "Laptop (RDP)":
                authorize.remove(connection)

ET.indent(root, space="    ")
ET.ElementTree(root).write(sys.argv[2], encoding="unicode")
PYEOF
    then
        rm -f "$guacamole_tmp"
        print_error "Failed to generate user-mapping.xml from template"
        return 1
    fi

    chown 101000:101000 "$guacamole_tmp"
    chmod 0644 "$guacamole_tmp"
    mv -f "$guacamole_tmp" "$dest_file"
}


# Prepare each media stack bind root without recursively touching app data.
setup_media_permissions() {
    local app
    for app in sonarr radarr bazarr jellyfin jellyseerr qbittorrent prowlarr profilarr cleanuperr; do
        prepare_host_directory "/fastpool/config/$app"
    done

    # Servarr and qBittorrent share one filesystem root for hardlinks.
    prepare_host_directory /datapool/media
    prepare_host_directory /datapool/media/torrents
    prepare_host_directory /datapool/media/torrents/complete
    prepare_host_directory /datapool/media/torrents/incomplete
    prepare_host_directory /datapool/media/torrents/movies
    prepare_host_directory /datapool/media/torrents/tv
    prepare_host_directory /datapool/media/torrents/games
    prepare_host_directory /datapool/media/torrents/other
    prepare_host_directory /datapool/media/torrents/kids
    prepare_host_directory /datapool/media/torrents/kids/movies
    prepare_host_directory /datapool/media/torrents/kids/tv
    prepare_host_directory /datapool/media/library
    prepare_host_directory /datapool/media/library/movies
    prepare_host_directory /datapool/media/library/tv
    prepare_host_directory /datapool/media/library/kids
    prepare_host_directory /datapool/media/library/kids/movies
    prepare_host_directory /datapool/media/library/kids/tv

    # Immich directories
    prepare_host_directory /datapool/photos
    prepare_host_directory /datapool/photos/immich
    prepare_host_directory /datapool/photos/immich/upload
    prepare_host_directory /datapool/photos/immich/library
    prepare_host_directory /datapool/photos/immich/thumbs
    prepare_host_directory /datapool/photos/immich/profile
    prepare_host_directory /datapool/photos/immich/backups
    prepare_host_directory /datapool/photos/immich/encoded-video
    prepare_host_directory /fastpool/config/immich
    prepare_host_directory /fastpool/config/immich/postgres 0700
    prepare_host_directory /fastpool/config/immich/cache

    # Tdarr directories
    prepare_host_directory /fastpool/config/tdarr
    prepare_host_directory /fastpool/config/tdarr/server
    prepare_host_directory /fastpool/config/tdarr/configs
    prepare_host_directory /fastpool/config/tdarr/logs
    prepare_host_directory /datapool/media/library/.tdarr-cache
}

setup_gaming_permissions() {
    prepare_host_directory /fastpool/config/gameservers
    prepare_host_directory /fastpool/config/gameservers/palworld
    prepare_host_directory /fastpool/config/gameservers/palworld/Saved
    prepare_host_directory /fastpool/config/gameservers/palworld/backups
}




# Prepare stack-specific host bind sources and generated configuration.
prepare_docker_stack() {
    local stack_name="$1"

    case "$stack_name" in
        desktop)
            setup_desktop_permissions
            setup_homepage_config
            setup_couchdb_config
            setup_guacamole_config
            setup_sshwifty_config
            ;;
        utility)
            setup_utility_permissions
            ;;
        ai)
            setup_ai_permissions
            ;;
        media)
            setup_media_permissions
            ;;
        gateway)
            setup_gateway_permissions
            ;;
        gaming)
            setup_gaming_permissions
            ;;
    esac

}

# Download and configure Docker Compose files
setup_docker_compose() {
    local stack_name="$1"
    local ct_id="$2"
    
    # Copy compose file from local workspace
    local source_file="$WORK_DIR/docker/$stack_name/docker-compose.yml"
    
    pct push "$ct_id" "$source_file" "/root/docker-compose.yml"
}

# Deploy Docker Compose services. Compose recreates only services whose image or
# effective definition changed; unrelated services are not force-recreated.
deploy_docker_services() {
    local stack_name="$1"
    local ct_id="$2"
    local wait_flags=""

    if [[ "$stack_name" == "ai" ]]; then
        wait_flags="--wait --wait-timeout 120"
    fi

    pct exec "$ct_id" -- sh -c \
        "cd /root && docker compose up -d $wait_flags --remove-orphans" || {
        print_error "Failed to deploy services"
        return 1
    }
}




# Full Docker deployment workflow
deploy_docker_stack() {
    local stack_name="$1"
    local ct_id="$2"
    
    local compose_file="$WORK_DIR/docker/$stack_name/docker-compose.yml"
    [[ -f "$compose_file" ]] || {
        print_error "docker-compose.yml not found at $compose_file"
        return 1
    }

    prepare_docker_stack "$stack_name"

    deploy_lxc_beszel_agent \
        "$ct_id" "lxc-${stack_name}" "$ENV_DECRYPTED_PATH" "docker*,beszel*"

    setup_docker_compose "$stack_name" "$ct_id"
    deploy_docker_services "$stack_name" "$ct_id"
    
    print_success "Stack deployed: $stack_name"
}
