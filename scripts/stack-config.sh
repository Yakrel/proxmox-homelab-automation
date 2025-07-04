#!/bin/bash

# This script defines the specifications for each LXC stack.
# It uses a template type (e.g., 'alpine', 'ubuntu') instead of a hardcoded filename.

get_stack_config() {
    local stack=$1
    case $stack in
        "proxy")
            CT_ID="100"; CT_HOSTNAME="proxy"; CT_CORES="2"; CT_RAM_MB="2048"; CT_IP_CIDR="192.168.1.100/24"; CT_GATEWAY_IP="192.168.1.1"; CT_BRIDGE="vmbr0"; STORAGE_POOL="datapool";
            CT_TEMPLATE_TYPE="alpine"
            ;;
        "media")
            CT_ID="101"; CT_HOSTNAME="media"; CT_CORES="4"; CT_RAM_MB="10240"; CT_IP_CIDR="192.168.1.101/24"; CT_GATEWAY_IP="192.168.1.1"; CT_BRIDGE="vmbr0"; STORAGE_POOL="datapool";
            CT_TEMPLATE_TYPE="alpine"
            ;;
        "files")
            CT_ID="102"; CT_HOSTNAME="files"; CT_CORES="2"; CT_RAM_MB="3072"; CT_IP_CIDR="192.168.1.102/24"; CT_GATEWAY_IP="192.168.1.1"; CT_BRIDGE="vmbr0"; STORAGE_POOL="datapool";
            CT_TEMPLATE_TYPE="alpine"
            ;;
        "webtools")
            CT_ID="103"; CT_HOSTNAME="webtools"; CT_CORES="2"; CT_RAM_MB="6144"; CT_IP_CIDR="192.168.1.103/24"; CT_GATEWAY_IP="192.168.1.1"; CT_BRIDGE="vmbr0"; STORAGE_POOL="datapool";
            CT_TEMPLATE_TYPE="alpine"
            ;;
        "monitoring")
            CT_ID="104"; CT_HOSTNAME="monitoring"; CT_CORES="4"; CT_RAM_MB="6144"; CT_IP_CIDR="192.168.1.104/24"; CT_GATEWAY_IP="192.168.1.1"; CT_BRIDGE="vmbr0"; STORAGE_POOL="datapool";
            CT_TEMPLATE_TYPE="alpine"
            ;;
        "development")
            CT_ID="150"; CT_HOSTNAME="development"; CT_CORES="4"; CT_RAM_MB="8192"; CT_IP_CIDR="192.168.1.150/24"; CT_GATEWAY_IP="192.168.1.1"; CT_BRIDGE="vmbr0"; STORAGE_POOL="datapool";
            CT_TEMPLATE_TYPE="ubuntu"
            ;;
        *)
            echo -e "\033[31m[ERROR]\033[0m Unknown stack: $stack" >&2
            exit 1
            ;;
    esac
}
