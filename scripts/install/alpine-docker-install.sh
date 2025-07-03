#!/usr/bin/env bash

# Copyright (c) 2021-2025 tteck
# Author: tteck (tteckster)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://www.docker.com/
#
# This is a modified version for proxmox-homelab-automation
# It has been automated to skip interactive prompts.

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apk add tzdata
msg_ok "Installed Dependencies"

msg_info "Installing Docker"
$STD apk add docker
$STD rc-service docker start
$STD rc-update add docker default
msg_ok "Installed Docker"

get_latest_release() {
  curl -fsSL "https://api.github.com/repos/$1/releases/latest" | grep '"tag_name":' | cut -d'"' -f4
}
DOCKER_COMPOSE_LATEST_VERSION=$(get_latest_release "docker/compose")

# Automated choices:
# - Portainer: No
# - Portainer Agent: No
# - Docker Compose: Yes

msg_info "Skipping Portainer installation (automated choice)."
msg_info "Skipping Portainer Agent installation (automated choice)."

msg_info "Installing Docker Compose $DOCKER_COMPOSE_LATEST_VERSION"
DOCKER_CONFIG=${DOCKER_CONFIG:-$HOME/.docker}
mkdir -p "$DOCKER_CONFIG"/cli-plugins
curl -fsSL "https://github.com/docker/compose/releases/download/$DOCKER_COMPOSE_LATEST_VERSION/docker-compose-linux-x86_64" -o "$DOCKER_CONFIG"/cli-plugins/docker-compose
chmod +x "$DOCKER_CONFIG"/cli-plugins/docker-compose
msg_ok "Installed Docker Compose $DOCKER_COMPOSE_LATEST_VERSION"

motd_ssh
customize
