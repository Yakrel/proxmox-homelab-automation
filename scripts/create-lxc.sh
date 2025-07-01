#!/bin/bash

# Unified LXC Stack Creation Script
# Uses community Alpine Docker script with predefined stack configurations

set -e

# Stack configurations (all in one place)
declare -A STACK_CONFIGS
STACK_CONFIGS[proxy]="100:lxc-proxy-01:192.168.1.100/24:1:1024:8"
STACK_CONFIGS[media]="101:lxc-media-01:192.168.1.101/24:4:4096:20"
STACK_CONFIGS[files]="102:lxc-files-01:192.168.1.102/24:2:2048:16"
STACK_CONFIGS[webtools]="103:lxc-webtools-01:192.168.1.103/24:2:2048:16"
STACK_CONFIGS[monitoring]="104:lxc-monitoring-01:192.168.1.104/24:2:4096:16"
STACK_CONFIGS[content]="105:lxc-content-01:192.168.1.105/24:2:2048:16"

# Input validation
if [ $# -ne 1 ]; then
    echo "Usage: $0 <stack_type>"
    echo "Available stacks: ${!STACK_CONFIGS[@]}"
    exit 1
fi

STACK_TYPE=$1

# Check if stack exists
if [[ ! -v STACK_CONFIGS[$STACK_TYPE] ]]; then
    echo "ERROR: Invalid stack type: $STACK_TYPE"
    echo "Available stacks: ${!STACK_CONFIGS[@]}"
    exit 1
fi

# Parse configuration
IFS=':' read -ra CONFIG <<< "${STACK_CONFIGS[$STACK_TYPE]}"
LXC_ID="${CONFIG[0]}"
HOSTNAME="${CONFIG[1]}"
IP_ADDRESS="${CONFIG[2]}"
CPU_CORES="${CONFIG[3]}"
RAM_SIZE="${CONFIG[4]}"
DISK_SIZE="${CONFIG[5]}"

echo "Creating $STACK_TYPE stack (LXC $LXC_ID)..."
echo "  Hostname: $HOSTNAME"
echo "  IP: $IP_ADDRESS"
echo "  Resources: ${CPU_CORES}C/${RAM_SIZE}MB/${DISK_SIZE}GB"

# Export variables for community script
export var_cpu="$CPU_CORES"
export var_ram="$RAM_SIZE"
export var_disk="$DISK_SIZE"
export var_hostname="$HOSTNAME"
export var_ip="$IP_ADDRESS"
export var_gateway="192.168.1.1"
export var_unprivileged="1"
export var_bridge="vmbr0"

# Run community Alpine Docker script
bash -c "$(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/ct/alpine-docker.sh)"

# Add datapool mount after creation
echo "Adding datapool mount..."
pct set "$LXC_ID" -mp0 /datapool,mp=/datapool,acl=1

echo "Stack $STACK_TYPE created successfully!"