#!/bin/bash

# Monitoring Stack Deployment with Community Alpine Docker Script
# This script deploys Prometheus, Grafana, and Alertmanager to LXC 104

set -e

# Monitoring Stack Configuration
STACK_TYPE="monitoring"
LXC_ID=104
HOSTNAME="lxc-monitoring-04"
IP_ADDRESS="192.168.1.104/24"
GATEWAY="192.168.1.1"
CPU_CORES=2
RAM_SIZE=2048
DISK_SIZE=12

# Export variables for community script
export CT_ID="$LXC_ID"
export HN="$HOSTNAME" 
export NET="$IP_ADDRESS"
export GATE="$GATEWAY"
export CORE_COUNT="$CPU_CORES"
export RAM_SIZE="$RAM_SIZE"
export DISK_SIZE="$DISK_SIZE"
export CT_TYPE="1"  # Unprivileged
export BRG="vmbr0"

# GitHub Repository
GITHUB_REPO="https://raw.githubusercontent.com/Yakrel/proxmox-homelab-automation/main"
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    print_error "This script must be run as root"
    exit 1
fi

print_info "======================================================"
print_info "Monitoring Stack Deployment"
print_info "======================================================"
print_info "LXC ID: $LXC_ID"
print_info "Hostname: $HOSTNAME"
print_info "IP Address: $IP_ADDRESS"
print_info "CPU Cores: $CPU_CORES"
print_info "RAM: ${RAM_SIZE}MB"
print_info "Disk: ${DISK_SIZE}GB"
print_info "======================================================"

# Check if LXC already exists
if pct status "$LXC_ID" &>/dev/null; then
    print_warning "LXC $LXC_ID already exists. Updating existing deployment..."
    
    # Ensure LXC is running
    if ! pct status "$LXC_ID" | grep -q "running"; then
        print_info "Starting LXC $LXC_ID..."
        pct start "$LXC_ID"
        sleep 5
    fi
    
    LXC_EXISTS=true
else
    LXC_EXISTS=false
fi

# Create LXC with community script if it doesn't exist
if [ "$LXC_EXISTS" = false ]; then
    print_info "Creating LXC container with community script..."
    print_warning "When prompted, please select option 1 (Advanced) and then 1 (Default) for automatic configuration"
    
    # Download and run community script
    bash -c "$(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/ct/alpine-docker.sh)"
    
    if ! pct status "$LXC_ID" &>/dev/null; then
        print_error "LXC creation failed!"
        exit 1
    fi
    
    print_success "LXC $LXC_ID created successfully"
    
    # Wait for container to be ready
    print_info "Waiting for container to be ready..."
    sleep 10
    
    # Ensure container is running
    if ! pct status "$LXC_ID" | grep -q "running"; then
        pct start "$LXC_ID"
        sleep 5
    fi
fi

# Setup datapool mount
print_info "Setting up datapool mount..."
if ! pct config "$LXC_ID" | grep -q "mp=/datapool"; then
    pct set "$LXC_ID" -mp0 /datapool,mp=/datapool,acl=1
    print_success "Datapool mount added"
fi

# Setup datapool permissions and directories
print_info "Setting up datapool directories..."
if [ -d "/datapool" ]; then
    # Create monitoring stack directories with data subdirectories
    mkdir -p /datapool/config/monitoring/{prometheus/{rules,data},alertmanager/data,grafana/{provisioning/{datasources,dashboards},dashboards}}
    
    # Set permissions (unprivileged LXC mapping: 1000 -> 101000)
    chown -R 101000:101000 /datapool/config/monitoring 2>/dev/null || true
    
    print_success "Datapool directories created"
else
    print_error "Datapool not accessible"
    exit 1
fi

# Setup Proxmox monitoring user
print_info "Setting up Proxmox monitoring user..."
if ! pveum user list | grep -q "monitoring@pve"; then
    # Create monitoring user
    pveum user add monitoring@pve --comment "Monitoring user for Prometheus"
    print_success "Monitoring user created"
fi

# Generate or get monitoring password
MONITORING_PASSWORD=""
if pveum user list | grep -q "monitoring@pve"; then
    # Generate a new password for monitoring user
    MONITORING_PASSWORD=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 16)
    pveum passwd monitoring@pve "$MONITORING_PASSWORD"
    print_success "Monitoring user password updated"
fi

# Assign monitoring role
if ! pveum acl list | grep -q "monitoring@pve"; then
    pveum aclmod / -user monitoring@pve -role PVEAuditor
    print_success "Monitoring role assigned"
fi

# Download and deploy Docker Compose files
print_info "Downloading Docker Compose files..."
STACK_DIR="/opt/monitoring"

# Create stack directory in LXC
pct exec "$LXC_ID" -- mkdir -p "$STACK_DIR"

# Download compose and config files to temp directory
wget -q -O "$TEMP_DIR/docker-compose.yml" "$GITHUB_REPO/docker/monitoring/docker-compose.yml"
wget -q -O "$TEMP_DIR/.env.example" "$GITHUB_REPO/docker/monitoring/.env.example" 2>/dev/null || true

# Download monitoring configuration files
wget -q -O "$TEMP_DIR/prometheus.yml.template" "$GITHUB_REPO/docker/monitoring/prometheus.yml.template" 2>/dev/null || true
wget -q -O "$TEMP_DIR/alertmanager.yml.template" "$GITHUB_REPO/docker/monitoring/alertmanager.yml.template" 2>/dev/null || true
wget -q -O "$TEMP_DIR/alerts.yml" "$GITHUB_REPO/docker/monitoring/alerts.yml" 2>/dev/null || true

# Fallback to static files if templates don't exist
if [ ! -f "$TEMP_DIR/prometheus.yml.template" ]; then
    wget -q -O "$TEMP_DIR/prometheus.yml" "$GITHUB_REPO/docker/monitoring/prometheus.yml" 2>/dev/null || true
fi
if [ ! -f "$TEMP_DIR/alertmanager.yml.template" ]; then
    wget -q -O "$TEMP_DIR/alertmanager.yml" "$GITHUB_REPO/docker/monitoring/alertmanager.yml" 2>/dev/null || true
fi

if [ ! -f "$TEMP_DIR/docker-compose.yml" ]; then
    print_error "Failed to download docker-compose.yml"
    exit 1
fi

# Copy files to LXC
pct push "$LXC_ID" "$TEMP_DIR/docker-compose.yml" "$STACK_DIR/docker-compose.yml"
if [ -f "$TEMP_DIR/.env.example" ]; then
    pct push "$LXC_ID" "$TEMP_DIR/.env.example" "$STACK_DIR/.env.example"
fi

# Copy monitoring config files
for file in prometheus.yml.template alertmanager.yml.template alerts.yml prometheus.yml alertmanager.yml; do
    if [ -f "$TEMP_DIR/$file" ]; then
        pct push "$LXC_ID" "$TEMP_DIR/$file" "$STACK_DIR/$file"
    fi
done

print_success "Docker Compose files deployed"

# Setup environment file
print_info "Setting up environment configuration..."
if pct exec "$LXC_ID" -- test -f "$STACK_DIR/.env"; then
    print_info "Backing up existing .env file..."
    pct exec "$LXC_ID" -- cp "$STACK_DIR/.env" "$STACK_DIR/.env.backup"
fi

# Interactive setup for Grafana admin password
echo ""
print_info "Grafana Admin Password Configuration"

GRAFANA_ADMIN_PASSWORD=""
if pct exec "$LXC_ID" -- test -f "$STACK_DIR/.env" 2>/dev/null; then
    GRAFANA_ADMIN_PASSWORD=$(pct exec "$LXC_ID" -- grep "GRAFANA_ADMIN_PASSWORD=" "$STACK_DIR/.env" 2>/dev/null | cut -d'=' -f2 || true)
fi

if [ -z "$GRAFANA_ADMIN_PASSWORD" ]; then
    read -s -p "Enter Grafana admin password: " GRAFANA_ADMIN_PASSWORD
    echo ""
    if [ -z "$GRAFANA_ADMIN_PASSWORD" ]; then
        print_error "Grafana admin password is required"
        exit 1
    fi
fi

# Interactive setup for email notifications (optional)
echo ""
print_info "Email Notification Configuration (Optional)"
read -p "Enter email address for alerts (optional): " ALERT_EMAIL
if [ -z "$ALERT_EMAIL" ]; then
    ALERT_EMAIL="admin@localhost"
fi

# Get Proxmox VE URL
PVE_URL="https://$(hostname -f):8006"

# Create .env file
pct exec "$LXC_ID" -- bash -c "cat > $STACK_DIR/.env << 'EOF'
# Monitoring Stack Environment Configuration
# Generated by Proxmox Homelab Automation

# User and Group IDs (for unprivileged LXC)
PUID=1000
PGID=1000

# Timezone
TZ=Europe/Istanbul

# Paths
CONFIG_ROOT=/datapool/config

# Grafana Configuration
GRAFANA_ADMIN_PASSWORD=$GRAFANA_ADMIN_PASSWORD

# Proxmox VE Configuration
PVE_URL=$PVE_URL
PVE_USERNAME=monitoring@pve
PVE_PASSWORD=$MONITORING_PASSWORD

# Alert Configuration
ALERT_EMAIL=$ALERT_EMAIL

# Service URLs
GRAFANA_URL=http://192.168.1.104:3000
PROMETHEUS_URL=http://192.168.1.104:9090
ALERTMANAGER_URL=http://192.168.1.104:9093

# Setup Instructions:
# 1. Grafana: http://192.168.1.104:3000 (admin/$GRAFANA_ADMIN_PASSWORD)
# 2. Prometheus: http://192.168.1.104:9090
# 3. Alertmanager: http://192.168.1.104:9093
# 4. Configure email SMTP settings in Grafana for notifications
# 5. Import Proxmox dashboards from https://grafana.com/grafana/dashboards/
EOF"

print_success "Environment file created"

# Deploy monitoring configuration files
print_info "Deploying monitoring configurations..."
for file in prometheus.yml alertmanager.yml alerts.yml; do
    if pct exec "$LXC_ID" -- test -f "$STACK_DIR/$file" 2>/dev/null; then
        case $file in
            prometheus.yml)
                pct exec "$LXC_ID" -- cp "$STACK_DIR/$file" "/datapool/config/monitoring/prometheus/prometheus.yml"
                ;;
            alertmanager.yml)
                pct exec "$LXC_ID" -- cp "$STACK_DIR/$file" "/datapool/config/monitoring/alertmanager/alertmanager.yml"
                ;;
            alerts.yml)
                pct exec "$LXC_ID" -- cp "$STACK_DIR/$file" "/datapool/config/monitoring/prometheus/rules/alerts.yml"
                ;;
        esac
    fi
done

# Deploy services
print_info "Deploying monitoring services..."
pct exec "$LXC_ID" -- bash -c "cd $STACK_DIR && docker compose pull"
pct exec "$LXC_ID" -- bash -c "cd $STACK_DIR && docker compose up -d"

if [ $? -eq 0 ]; then
    print_success "Monitoring stack deployed successfully!"
    
    print_info "======================================================"
    print_info "Service Status:"
    pct exec "$LXC_ID" -- bash -c "cd $STACK_DIR && docker compose ps"
    
    print_info "======================================================"
    print_info "Service URLs:"
    print_info "Grafana:      http://192.168.1.104:3000"
    print_info "Prometheus:   http://192.168.1.104:9090"
    print_info "Alertmanager: http://192.168.1.104:9093"
    print_info "======================================================"
    print_info "Login Credentials:"
    print_info "Grafana Admin: admin / $GRAFANA_ADMIN_PASSWORD"
    print_info "Proxmox User:  monitoring@pve / $MONITORING_PASSWORD"
    print_info "======================================================"
    print_info "Next Steps:"
    print_info "1. Log into Grafana and configure data sources"
    print_info "2. Import Proxmox VE dashboards from Grafana.com"
    print_info "3. Configure alert notification channels"
    print_info "4. Set up additional monitoring targets as needed"
    print_info "======================================================"
    
    # Clean up
    pct exec "$LXC_ID" -- rm -f "$STACK_DIR/.env.example" 2>/dev/null || true
    
    exit 0
else
    print_error "Failed to deploy monitoring stack"
    exit 1
fi