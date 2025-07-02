#!/bin/bash

# ==============================================================================
#
#               --- Central Configuration File ---
#
# This file contains all the global settings for the Proxmox Homelab.
# By centralizing these variables, you can easily adapt the entire
# automation suite to your specific environment by editing just this file.
#
# ==============================================================================

# --- GitHub & Repository Settings ---
# The URL to the raw content of your GitHub repository.
export GITHUB_REPO_URL="https://raw.githubusercontent.com/Yakrel/proxmox-homelab-automation/main"

# The base URL for the community-scripts used for LXC creation.
export COMMUNITY_SCRIPTS_URL="https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main"


# --- Homelab Global Settings ---
# Default timezone for all LXC containers.
export HOMELAB_TIMEZONE="Europe/Istanbul"

# Default PUID/PGID for Docker containers to ensure consistent file permissions.
export HOMELAB_PUID="1000"
export HOMELAB_PGID="1000"


# --- Proxmox Host Settings ---
# The host UID/GID that the unprivileged LXC user (1000) maps to.
# This is typically 100000 + the container UID.
# Used for setting permissions on the /datapool volumes.
export HOMELAB_HOST_UID="101000"
export HOMELAB_HOST_GID="101000"


# --- LXC Network Configuration ---
# The name of the Proxmox bridge for LXC networking.
export LXC_BRIDGE="vmbr0"

# The gateway (router) IP address for the LXCs.
export LXC_GATEWAY="192.168.1.1"

# The DNS nameserver for the LXCs.
export LXC_NAMESERVER="192.168.1.1"
