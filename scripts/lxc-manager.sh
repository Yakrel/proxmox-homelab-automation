#!/bin/bash

# This script is responsible for creating a new LXC container using dynamic templates.

set -e

# --- Arguments and Setup ---
STACK_NAME=$1
WORK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)"

source "$WORK_DIR/scripts/stack-config.sh"

# --- Helper Functions ---
print_info() { echo -e "\033[36m[INFO]\033[0m $1"; }
print_success() { echo -e "\033[32m[SUCCESS]\033[0m $1"; }
print_error() { echo -e "\033[31m[ERROR]\033[0m $1"; }
print_warning() { echo -e "\033[33m[WARNING]\033[0m $1"; }

# --- LXC Creation Logic ---

get_stack_config "$STACK_NAME"

print_info "Finding the latest template for type '$CT_TEMPLATE_TYPE'...";
pveam update > /dev/null

# Dynamically find the latest template filename
LATEST_TEMPLATE=$(pveam list "$STORAGE_POOL" | grep "$CT_TEMPLATE_TYPE" | sort -V | tail -n 1 | awk '{print $1}')

if [ -z "$LATEST_TEMPLATE" ]; then
    print_warning "No local template found for '$CT_TEMPLATE_TYPE'. Downloading the latest version...";
    # The download name is usually the type itself, e.g., 'alpine-linux' or 'ubuntu'
    download_name="$CT_TEMPLATE_TYPE-linux"
    if [ "$CT_TEMPLATE_TYPE" == "ubuntu" ]; then
        download_name="ubuntu"
    fi
    pveam download "$STORAGE_POOL" "$download_name"
    # Re-run the find command after download
    LATEST_TEMPLATE=$(pveam list "$STORAGE_POOL" | grep "$CT_TEMPLATE_TYPE" | sort -V | tail -n 1 | awk '{print $1}')
    print_success "Downloaded: $LATEST_TEMPLATE"
else
    print_info "Found latest available template: $LATEST_TEMPLATE"
fi

print_info "Creating LXC container $CT_ID ($CT_HOSTNAME) using $LATEST_TEMPLATE...";

pct create "$CT_ID" "$LATEST_TEMPLATE" \
    --hostname "$CT_HOSTNAME" \
    --storage "$STORAGE_POOL" \
    --cores "$CT_CORES" \
    --memory "$CT_RAM_MB" \
    --swap 0 \
    --net0 name=eth0,bridge="$CT_BRIDGE",ip="$CT_IP_CIDR",gw="$CT_GATEWAY_IP" \
    --onboot 1 \
    --unprivileged 1

print_info "Mounting datapool with ACL support...";
pct set "$CT_ID" -mp0 /datapool,mp=/datapool,acl=1

print_info "Starting container...";
pct start "$CT_ID"

sleep 10 # Wait for container to boot and network to be ready

print_info "Installing Docker and essential tools inside the container...";
if [[ "$CT_TEMPLATE_TYPE" == "alpine" ]]; then
    pct exec "$CT_ID" -- apk update
    pct exec "$CT_ID" -- apk add --no-cache docker docker-cli-compose
    pct exec "$CT_ID" -- rc-update add docker boot
    pct exec "$CT_ID" -- service docker start
elif [[ "$CT_TEMPLATE_TYPE" == "ubuntu" ]]; then
    pct exec "$CT_ID" -- apt-get update
    pct exec "$CT_ID" -- apt-get install -y docker.io docker-compose-plugin
    pct exec "$CT_ID" -- systemctl enable --now docker
fi

print_success "LXC container for [$STACK_NAME] created and ready."