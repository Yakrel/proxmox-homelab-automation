#!/bin/bash
# Monitoring LXC Setup Script
# LXC ID: 104 - Monitoring Stack
# Services: Prometheus, Grafana, Node Exporter, cAdvisor

set -e

LXC_ID=104
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${YELLOW}Setting up Monitoring LXC (ID: $LXC_ID)...${NC}"

# Check if running in LXC
if [ ! -f /.dockerenv ] && [ -f /proc/1/cgroup ] && grep -q lxc /proc/1/cgroup 2>/dev/null; then
    echo -e "${GREEN}Running inside LXC container ${LXC_ID}${NC}"
    
    # Update system
    echo -e "${YELLOW}Updating system packages...${NC}"
    apt update && apt upgrade -y
    
    # Install required packages
    echo -e "${YELLOW}Installing required packages...${NC}"
    apt install -y curl wget gnupg lsb-release ca-certificates
    
    # Install Docker
    echo -e "${YELLOW}Installing Docker...${NC}"
    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    apt update
    apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    # Start and enable Docker
    systemctl start docker
    systemctl enable docker
    
    # Create monitoring directories
    echo -e "${YELLOW}Creating monitoring directory structure...${NC}"
    mkdir -p /datapool/config/monitoring/{prometheus,grafana,alertmanager}
    mkdir -p /datapool/config/monitoring/prometheus/rules
    mkdir -p /datapool/config/monitoring/grafana/provisioning/{datasources,dashboards}
    
    # Set proper permissions
    chown -R 1000:1000 /datapool/config/monitoring
    
    echo -e "${GREEN}Monitoring LXC setup completed successfully!${NC}"
    echo -e "${YELLOW}Next: Deploy monitoring stack with deploy_stack.sh${NC}"
    
else
    echo -e "${RED}Error: This script should be run inside LXC container ${LXC_ID}${NC}"
    echo -e "${YELLOW}Run from Proxmox host: pct exec ${LXC_ID} -- bash -c 'curl -sSL https://raw.githubusercontent.com/Yakrel/proxmox-homelab-automation/main/scripts/lxc/setup_monitoring_lxc.sh | bash'${NC}"
    exit 1
fi