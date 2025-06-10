#!/bin/bash
# Monitoring LXC Directory Setup Script
# LXC ID: 104 - Monitoring Stack
# Services: Prometheus, Grafana, Node Exporter, cAdvisor

set -e

LXC_ID=104
PUID=1000
PGID=1000

YELLOW='\033[1;33m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${YELLOW}Setting up directory structure for Monitoring LXC (ID: $LXC_ID)...${NC}"
echo -e "${GREEN}Note: Alpine LXC with Docker should be created first using create_alpine_lxc.sh${NC}"

# Define directory arrays for monitoring stack
CONFIG_DIRS=("prometheus" "grafana" "alertmanager" "watchtower-monitoring")
PROMETHEUS_SUBDIRS=("rules")
GRAFANA_SUBDIRS=("provisioning/datasources" "provisioning/dashboards")

echo -e "${YELLOW}Creating monitoring configuration directories...${NC}"

# Create main config directories
for dir in "${CONFIG_DIRS[@]}"; do
    mkdir -p "/datapool/config/$dir"
    echo "Created: /datapool/config/$dir"
done

# Create Prometheus subdirectories
for subdir in "${PROMETHEUS_SUBDIRS[@]}"; do
    mkdir -p "/datapool/config/prometheus/$subdir"
    echo "Created: /datapool/config/prometheus/$subdir"
done

# Create Grafana subdirectories
for subdir in "${GRAFANA_SUBDIRS[@]}"; do
    mkdir -p "/datapool/config/grafana/$subdir"
    echo "Created: /datapool/config/grafana/$subdir"
done

# Set proper ownership for all directories (host-side unprivileged LXC mapping)
echo -e "${YELLOW}Setting ownership (101000:101000) for monitoring directories...${NC}"
chown -R 101000:101000 "/datapool/config/prometheus"
chown -R 101000:101000 "/datapool/config/grafana"
chown -R 101000:101000 "/datapool/config/alertmanager"
chown -R 101000:101000 "/datapool/config/watchtower-monitoring"

echo -e "${GREEN}✓ Monitoring LXC directory structure created successfully!${NC}"
echo -e "${YELLOW}Directory structure:${NC}"
echo -e "  /datapool/config/prometheus/"
echo -e "  ├── rules/"
echo -e "  /datapool/config/grafana/"
echo -e "  ├── provisioning/"
echo -e "  │   ├── datasources/"
echo -e "  │   └── dashboards/"
echo -e "  /datapool/config/alertmanager/"
echo -e "  /datapool/config/watchtower-monitoring/"
echo ""
echo -e "${GREEN}Next steps:${NC}"
echo -e "1. Create Alpine LXC: ${YELLOW}bash scripts/automation/create_alpine_lxc.sh monitoring${NC}"
echo -e "2. Deploy monitoring stack: ${YELLOW}bash scripts/automation/deploy_stack.sh monitoring 104${NC}"