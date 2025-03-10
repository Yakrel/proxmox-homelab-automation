#!/bin/bash

# ======================================================
# Proxmox Homelab Automation Setup Script
# ======================================================
# This script creates Alpine Linux LXC containers on Proxmox and
# deploys Docker services without requiring Terraform or Ansible

# Error handling
set -e
trap 'echo "Error on line $LINENO" ; exit 1' ERR

# Color definitions
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
DEFAULT_PROXMOX_IP="192.168.1.10"
DEFAULT_PROXMOX_USER="root@pam"
DEFAULT_PROXMOX_NODE="pve01"
DEFAULT_STORAGE_POOL="local"
DEFAULT_TIMEZONE="Europe/Istanbul"
DEFAULT_GRAFANA_PASSWORD="admin"
DEFAULT_PRIVATE_NETWORK="192.168.1"

# Default container configurations
# The IP will be automatically set based on CTID: 192.168.1.{CTID}
DEFAULT_CONTAINERS=(
    "media:102:4:16384:32"     # name:ctid:cores:memory_mb:storage_gb
    "monitoring:103:2:4096:16"
    "logging:104:2:4096:16"
    "proxy:125:2:2048:8"
)

PROXMOX_PASSWORD=""
ALPINE_TEMPLATE=""

# ======================================================
# Helper functions
# ======================================================

# Function to print colored text
print_status() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Function to run command on Proxmox via SSH
run_proxmox_command() {
    local command="$1"
    
    if [ "$setup_ssh" == "y" ]; then
        ssh -o StrictHostKeyChecking=no ${proxmox_user%@*}@${proxmox_ip} "$command"
    else
        if command -v expect &> /dev/null; then
            cat > /tmp/run_command.exp << EOF
#!/usr/bin/expect -f
spawn ssh -o StrictHostKeyChecking=no ${proxmox_user%@*}@${proxmox_ip} "$command"
expect "password:"
send "${PROXMOX_PASSWORD}\r"
expect eof
EOF
            chmod +x /tmp/run_command.exp
            output=$(/tmp/run_command.exp | tail -n +2)
            rm -f /tmp/run_command.exp
            echo "$output"
        else
            # Fallback to sshpass if available
            if command -v sshpass &> /dev/null; then
                sshpass -p "${PROXMOX_PASSWORD}" ssh -o StrictHostKeyChecking=no ${proxmox_user%@*}@${proxmox_ip} "$command"
            else
                echo -e "${YELLOW}Both 'expect' and 'sshpass' not found. Using manual SSH.${NC}"
                ssh -o StrictHostKeyChecking=no ${proxmox_user%@*}@${proxmox_ip} "$command"
            fi
        fi
    fi
}

# Function to copy file to Proxmox
copy_to_proxmox() {
    local src="$1"
    local dest="$2"
    
    if [ "$setup_ssh" == "y" ]; then
        scp -o StrictHostKeyChecking=no "$src" ${proxmox_user%@*}@${proxmox_ip}:"$dest"
    else
        if command -v expect &> /dev/null; then
            cat > /tmp/scp_command.exp << EOF
#!/usr/bin/expect -f
spawn scp -o StrictHostKeyChecking=no "$src" ${proxmox_user%@*}@${proxmox_ip}:"$dest"
expect "password:"
send "${PROXMOX_PASSWORD}\r"
expect eof
EOF
            chmod +x /tmp/scp_command.exp
            /tmp/scp_command.exp
            rm -f /tmp/scp_command.exp
        else
            # Fallback to sshpass if available
            if command -v sshpass &> /dev/null; then
                sshpass -p "${PROXMOX_PASSWORD}" scp -o StrictHostKeyChecking=no "$src" ${proxmox_user%@*}@${proxmox_ip}:"$dest"
            else
                echo -e "${YELLOW}Both 'expect' and 'sshpass' not found. Using manual SCP.${NC}"
                scp -o StrictHostKeyChecking=no "$src" ${proxmox_user%@*}@${proxmox_ip}:"$dest"
            fi
        fi
    fi
}

# Function to set up one container
setup_container() {
    local name="$1"
    local ctid="$2"
    local cores="$3"
    local memory="$4"
    local storage="$5"
    local ip="${private_network}.${ctid}"
    
    print_status "$BLUE" "Setting up $name container (ID: $ctid, IP: $ip)..."
    
    # Check if container already exists
    if run_proxmox_command "pct list | grep -q ' $ctid '"; then
        print_status "$YELLOW" "Container $ctid already exists. Skipping creation."
    else
        # Create the container
        print_status "$BLUE" "Creating container $ctid..."
        run_proxmox_command "pct create $ctid $STORAGE_POOL:vztmpl/$ALPINE_TEMPLATE \
            --hostname $name \
            --cores $cores \
            --memory $memory \
            --swap 512 \
            --rootfs $STORAGE_POOL:$storage \
            --net0 name=eth0,bridge=vmbr0,ip=$ip/24,gw=${private_network}.1 \
            --unprivileged 1 \
            --features nesting=1 \
            --start 1"
            
        print_status "$GREEN" "Container $name created."
        
        # Wait for container to start
        print_status "$BLUE" "Waiting for container to start..."
        sleep 10
    fi
    
    # Mount datapool if it exists and not already mounted
    if [ "$datapool_exists" == "true" ]; then
        # Check if datapool is already mounted
        if ! run_proxmox_command "pct config $ctid | grep -q 'mp0: datapool'"; then
            print_status "$BLUE" "Mounting datapool to container..."
            run_proxmox_command "pct set $ctid -mp0 /datapool,mp=/datapool"
        else
            print_status "$YELLOW" "Datapool already mounted to container $ctid."
        fi
    fi
    
    # Install Docker and dependencies
    print_status "$BLUE" "Installing Docker and dependencies..."
    run_proxmox_command "pct exec $ctid -- ash -c \"apk update && 
        apk add --no-cache docker docker-compose curl bash openssh && 
        rc-update add docker default && 
        rc-service docker start\""
    
    # Set up passwordless console access
    print_status "$BLUE" "Setting up container console access..."
    run_proxmox_command "pct exec $ctid -- ash -c \"passwd -d root\""
    
    # Copy Docker Compose files and create directories
    prepare_container_for_service "$name" "$ctid" "$ip"
    
    print_status "$GREEN" "Container $name setup completed successfully."
    
    # Return the container information
    echo "$name:$ctid:$ip"
}

# Function to prepare container for specific service
prepare_container_for_service() {
    local service="$1"
    local ctid="$2"
    local ip="$3"
    
    # Make sure target directory exists
    run_proxmox_command "pct exec $ctid -- mkdir -p /root/docker"
    
    # Create necessary directories based on service type
    case "$service" in
        media)
            print_status "$BLUE" "Setting up media service directories..."
            run_proxmox_command "pct exec $ctid -- mkdir -p /datapool/config/{sonarr-config,radarr-config,bazarr-config,jellyfin-config,jellyseerr-config,qbittorrent-config,prowlarr-config,flaresolverr-config,watchtower-media-config,recyclarr-config,youtube-dl-config}"
            run_proxmox_command "pct exec $ctid -- mkdir -p /datapool/media/{tv,movies,youtube/{playlists,channels}}"
            run_proxmox_command "pct exec $ctid -- mkdir -p /datapool/torrents/{tv,movies}"
            ;;
        monitoring)
            print_status "$BLUE" "Setting up monitoring service directories..."
            run_proxmox_command "pct exec $ctid -- mkdir -p /datapool/config/{prometheus-config,grafana-config,alertmanager-config,watchtower-monitoring-config}"
            
            # Create .env file for Grafana
            cat > /tmp/monitoring.env << EOF
GRAFANA_PASSWORD=$grafana_password
EOF
            run_proxmox_command "pct push $ctid /tmp/monitoring.env /root/docker/.env"
            ;;
        logging)
            print_status "$BLUE" "Setting up logging service directories..."
            run_proxmox_command "pct exec $ctid -- mkdir -p /datapool/config/{elasticsearch-config,logstash-config,kibana-config,filebeat-config,watchtower-logging-config}"
            ;;
        proxy)
            print_status "$BLUE" "Setting up proxy service directories..."
            run_proxmox_command "pct exec $ctid -- mkdir -p /datapool/config/{cloudflared-config,watchtower-proxy-config,adguard-config/{work,conf}}"
            
            # Create .env file for Cloudflared
            cat > /tmp/proxy.env << EOF
CLOUDFLARED_TOKEN=$cloudflared_token
EOF
            run_proxmox_command "pct push $ctid /tmp/proxy.env /root/docker/.env"
            ;;
    esac
    
    # Download Docker Compose file from GitHub
    print_status "$BLUE" "Downloading Docker Compose file for $service..."
    local compose_url="https://raw.githubusercontent.com/yourusername/yourrepository/main/docker/$service/docker-compose.yml"
    local compose_file="/tmp/docker-compose.yml"
    wget --retry-connrefused --waitretry=5 --quiet -O "$compose_file" "$compose_url"
    if [ $? -ne 0 ]; then
        print_status "$RED" "Failed to download Docker Compose file for $service."
        exit 1
    fi
    run_proxmox_command "pct push $ctid $compose_file /root/docker/docker-compose.yml"
    
    # Update timezone in compose file
    run_proxmox_command "pct exec $ctid -- sed -i 's|Europe/Istanbul|$timezone|g' /root/docker/docker-compose.yml"
    
    # Start Docker Compose services
    print_status "$BLUE" "Starting Docker Compose services for $service..."
    run_proxmox_command "pct exec $ctid -- bash -c 'cd /root/docker && docker-compose up -d'"
}

# ======================================================
# Main Script
# ======================================================

print_status "$GREEN" "===== Proxmox Homelab Automation Setup ====="

# --------------------------------------
# Check prerequisites
# --------------------------------------
print_status "$YELLOW" "[1/8] Checking prerequisites"

# Check if curl is installed; if not, install it.
if ! command -v curl &> /dev/null; then
    print_status "$YELLOW" "curl not found. Installing curl..."
    apt-get update && apt-get install -y curl
fi

# Check if sshpass is installed; if not, install it.
if ! command -v sshpass &> /dev/null; then
    print_status "$YELLOW" "sshpass not found. Installing sshpass..."
    apt-get update && apt-get install -y sshpass
fi

# Check if expect is installed; if not, install it.
if ! command -v expect &> /dev/null; then
    print_status "$YELLOW" "expect not found. Installing expect..."
    apt-get update && apt-get install -y expect
fi

print_status "$GREEN" "All prerequisites are met."

# --------------------------------------
# SSH key setup
# --------------------------------------
print_status "$YELLOW" "[2/8] Setting up SSH keys"

if [ ! -f ~/.ssh/id_rsa ]; then
    echo "SSH key not found. Generating a new SSH key..."
    ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N ""
    print_status "$GREEN" "SSH key generated successfully."
fi

print_status "$GREEN" "SSH key is ready for use."

# --------------------------------------
# Ask Proxmox connection details
# --------------------------------------
print_status "$YELLOW" "[3/8] Proxmox connection information"
print_status "$BLUE" "We'll ask for your Proxmox details once and use them throughout the script"
read -p "Enter Proxmox server IP [$DEFAULT_PROXMOX_IP]: " proxmox_ip
proxmox_ip=${proxmox_ip:-$DEFAULT_PROXMOX_IP}

read -p "Enter Proxmox username [$DEFAULT_PROXMOX_USER]: " proxmox_user
proxmox_user=${proxmox_user:-$DEFAULT_PROXMOX_USER}

read -p "Enter Proxmox node name [$DEFAULT_PROXMOX_NODE]: " proxmox_node
proxmox_node=${proxmox_node:-$DEFAULT_PROXMOX_NODE}

print_status "$BLUE" "Enter Proxmox password (will be used for SSH and other connections):"
read -s PROXMOX_PASSWORD
echo ""

# Ask for timezone
read -p "Enter your timezone [$DEFAULT_TIMEZONE]: " timezone
timezone=${timezone:-$DEFAULT_TIMEZONE}

# Ask for private network
read -p "Enter your private network prefix [$DEFAULT_PRIVATE_NETWORK]: " private_network
private_network=${private_network:-$DEFAULT_PRIVATE_NETWORK}

# --------------------------------------
# Setup SSH key authentication to Proxmox (optional)
# --------------------------------------
print_status "$YELLOW" "[4/8] Setting up SSH key authentication to Proxmox"
print_status "$BLUE" "This will let us connect to Proxmox without asking for a password each time"
read -p "Would you like to set up SSH key authentication to Proxmox? (y/n): " setup_ssh

if [ "$setup_ssh" == "y" ]; then
    echo "Copying SSH key to Proxmox server..."
    if command -v expect &> /dev/null; then
        # Create a temporary expect script to handle the SSH password
        cat > /tmp/ssh_copy_id.exp << EOF
#!/usr/bin/expect -f
spawn ssh-copy-id -o StrictHostKeyChecking=no ${proxmox_user%@*}@${proxmox_ip}
expect "password:"
send "${PROXMOX_PASSWORD}\r"
expect eof
EOF
        chmod +x /tmp/ssh_copy_id.exp
        /tmp/ssh_copy_id.exp
        rm -f /tmp/ssh_copy_id.exp
        print_status "$GREEN" "SSH key copied to Proxmox server."
    else
        print_status "$YELLOW" "Expect utility not found, using manual method."
        ssh-copy-id -o StrictHostKeyChecking=no ${proxmox_user%@*}@${proxmox_ip}
    fi
fi

# --------------------------------------
# Proxmox configuration scripts (optional)
# --------------------------------------
print_status "$YELLOW" "[5/8] Running Proxmox configuration scripts"

read -p "Do you want to run storage.sh and security.sh scripts on your Proxmox server? (y/n): " run_scripts

if [ "$run_scripts" == "y" ]; then
    echo "Copying scripts to Proxmox server..."
    copy_to_proxmox "scripts/storage.sh" "/tmp/storage.sh"
    copy_to_proxmox "scripts/security.sh" "/tmp/security.sh"
    
    echo "Running scripts on Proxmox server..."
    if [ "$setup_ssh" != "y" ] && command -v expect &> /dev/null; then
        # Run storage script with SMB password set
        cat > /tmp/run_storage.exp << EOF
#!/usr/bin/expect -f
spawn ssh -o StrictHostKeyChecking=no ${proxmox_user%@*}@${proxmox_ip} "bash /tmp/storage.sh"
expect "password:"
send "${PROXMOX_PASSWORD}\r"
expect "New SMB password:"
send "${PROXMOX_PASSWORD}\r"
expect "Retype new SMB password:"
send "${PROXMOX_PASSWORD}\r"
expect eof
EOF
        chmod +x /tmp/run_storage.exp
        /tmp/run_storage.exp
        rm -f /tmp/run_storage.exp
        
        # Run security script
        cat > /tmp/run_security.exp << EOF
#!/usr/bin/expect -f
spawn ssh -o StrictHostKeyChecking=no ${proxmox_user%@*}@${proxmox_ip} "bash /tmp/security.sh"
expect "password:"
send "${PROXMOX_PASSWORD}\r"
expect eof
EOF
        chmod +x /tmp/run_security.exp
        /tmp/run_security.exp
        rm -f /tmp/run_security.exp
    else
        run_proxmox_command "bash /tmp/storage.sh"
        run_proxmox_command "bash /tmp/security.sh"
    fi
    
    print_status "$GREEN" "Proxmox configuration scripts executed."
else
    echo "Skipping Proxmox configuration scripts."
fi

# --------------------------------------
# Storage pool and template selection
# --------------------------------------
print_status "$YELLOW" "[6/8] Selecting storage pool and template"

# Get list of storage pools
echo "Checking available storage on Proxmox server..."
STORAGE_INFO=$(run_proxmox_command "pvesm status")

print_status "$BLUE" "Available storage pools on Proxmox:"
echo "$STORAGE_INFO"

# Parse available storage options
STORAGE_OPTIONS=()
while IFS= read -r line; do
    # Skip empty lines
    [ -z "$line" ] && continue
    
    # Extract storage name (first column)
    storage_name=$(echo "$line" | awk '{print $1}')
    
    # Skip header line
    [[ "$storage_name" == "Name" ]] && continue
    
    STORAGE_OPTIONS+=("$storage_name")
done <<< "$STORAGE_INFO"

# Check if we have storage options
if [ ${#STORAGE_OPTIONS[@]} -eq 0 ]; then
    print_status "$RED" "No storage pools found on Proxmox. Please create at least one storage pool."
    exit 1
fi

# Display options and ask user to select
print_status "$YELLOW" "Please select a storage pool to use for LXC containers:"
select STORAGE_POOL in "${STORAGE_OPTIONS[@]}"; do
    if [ -n "$STORAGE_POOL" ]; then
        echo "Selected storage pool: $STORAGE_POOL"
        break
    else
        print_status "$RED" "Invalid selection. Please try again."
    fi
done

# Check if datapool exists on Proxmox
print_status "$YELLOW" "Checking if /datapool exists on Proxmox..."
datapool_exists=$(run_proxmox_command "[ -d /datapool ] && echo 'true' || echo 'false'")

if [ "$datapool_exists" == "true" ]; then
    print_status "$GREEN" "/datapool exists and will be mounted to containers."
else
    print_status "$YELLOW" "/datapool does not exist. Container data will be stored in the container's rootfs."
    read -p "Would you like to continue without datapool? (y/n): " continue_without_datapool
    if [ "$continue_without_datapool" != "y" ]; then
        print_status "$RED" "Exiting as datapool is required."
        exit 1
    fi
fi

# Update template repos and find Alpine template
print_status "$YELLOW" "Updating container template repositories..."
run_proxmox_command "pveam update"

print_status "$YELLOW" "Finding the latest Alpine template..."
ALPINE_TEMPLATES=$(run_proxmox_command "pveam available | grep alpine | grep -v edge | sort -V")

if [ -z "$ALPINE_TEMPLATES" ]; then
    print_status "$RED" "No Alpine templates found in repository. Please check your Proxmox repositories."
    exit 1
fi

# Show latest Alpine versions
print_status "$BLUE" "Available Alpine templates:"
echo "$ALPINE_TEMPLATES" | tail -n 5

# Automatically select latest stable version (non-edge, non-RC)
ALPINE_TEMPLATE=$(echo "$ALPINE_TEMPLATES" | grep -i default | grep -v edge | grep -v rc | tail -n 1 | awk '{print $2}')

# If not found, select any Alpine version
if [ -z "$ALPINE_TEMPLATE" ]; then
    ALPINE_TEMPLATE=$(echo "$ALPINE_TEMPLATES" | tail -n 1 | awk '{print $2}')
fi

print_status "$GREEN" "Selected latest Alpine template: $ALPINE_TEMPLATE"

# Allow user to select a different template
read -p "Do you want to use this template or select a different one? (use/select): " template_choice

if [ "$template_choice" == "select" ]; then
    print_status "$BLUE" "Available Alpine templates:"
    echo "$ALPINE_TEMPLATES"
    
    print_status "$YELLOW" "Please enter the name of the Alpine template to use:"
    read -p "Template name: " user_template
    
    if [ -n "$user_template" ]; then
        ALPINE_TEMPLATE=$user_template
        print_status "$GREEN" "Using template: $ALPINE_TEMPLATE"
    else
        print_status "$YELLOW" "No template entered, using previously selected: $ALPINE_TEMPLATE"
    fi
fi

# Check if the template is downloaded
print_status "$YELLOW" "Checking if template is downloaded..."
TEMPLATE_DOWNLOADED=$(run_proxmox_command "pveam list $STORAGE_POOL | grep $ALPINE_TEMPLATE" || echo "")

if [ -z "$TEMPLATE_DOWNLOADED" ]; then
    print_status "$YELLOW" "Downloading Alpine template to $STORAGE_POOL..."
    run_proxmox_command "pveam download $STORAGE_POOL $ALPINE_TEMPLATE"
    
    # Make sure download was successful
    TEMPLATE_VERIFY=$(run_proxmox_command "pveam list $STORAGE_POOL | grep $ALPINE_TEMPLATE" || echo "")
    if [ -z "$TEMPLATE_VERIFY" ]; then
        print_status "$RED" "Failed to download template. Please check Proxmox logs."
        exit 1
    fi
else
    print_status "$GREEN" "Template already downloaded."
fi

# --------------------------------------
# Configure environment variables
# --------------------------------------
print_status "$YELLOW" "[7/8] Setting up environment variables"

# Set up Grafana password
read -p "Enter Grafana password [$DEFAULT_GRAFANA_PASSWORD]: " grafana_password
grafana_password=${grafana_password:-$DEFAULT_GRAFANA_PASSWORD}

# Set up Cloudflare Tunnel Token if needed
print_status "$BLUE" "The Cloudflare Tunnel Token is needed if you want to expose services to the internet."
print_status "$BLUE" "If you don't have one, you can leave it blank for now and update it later."
read -p "Enter Cloudflare Tunnel Token (can be blank): " cloudflared_token
cloudflared_token=${cloudflared_token:-"your_token_here"}

# --------------------------------------
# Container setup
# --------------------------------------
print_status "$YELLOW" "[8/8] Setting up containers"

# Choose which services to install
echo "Which services would you like to install? (Select option number and press Enter)"
options=("All" "Media" "Monitoring" "Logging" "Proxy" "Exit")

select opt in "${options[@]}"; do
    case $opt in
        "All")
            services_to_install=("media" "monitoring" "logging" "proxy")
            break
            ;;
        "Media")
            services_to_install=("media")
            break
            ;;
        "Monitoring")
            services_to_install=("monitoring")
            break
            ;;
        "Logging")
            services_to_install=("logging")
            break
            ;;
        "Proxy")
            services_to_install=("proxy")
            break
            ;;
        "Exit")
            exit 0
            ;;
        *) 
            print_status "$RED" "Invalid option $REPLY"
            ;;
    esac
done

# Ask for container IDs and set up containers
installed_containers=()

for service in "${services_to_install[@]}"; do
    # Find default ID for this service
    default_ctid=""
    default_cores=""
    default_memory=""
    default_storage=""
    
    for container in "${DEFAULT_CONTAINERS[@]}"; do
        name=$(echo $container | cut -d: -f1)
        if [ "$name" == "$service" ]; then
            default_ctid=$(echo $container | cut -d: -f2)
            default_cores=$(echo $container | cut -d: -f3)
            default_memory=$(echo $container | cut -d: -f4)
            default_storage=$(echo $container | cut -d: -f5)
            break
        fi
    done
    
    print_status "$BLUE" "Setting up $service service:"
    
    # Ask for CTID with default values
    read -p "Enter container ID (CTID) for $service [$default_ctid]: " ctid
    ctid=${ctid:-$default_ctid}
    
    # Ask for resources if needed
    read -p "Enter CPU cores for $service [$default_cores]: " cores
    cores=${cores:-$default_cores}
    
    read -p "Enter memory in MB for $service [$default_memory]: " memory
    memory=${memory:-$default_memory}
    
    read -p "Enter storage in GB for $service [$default_storage]: " storage
    storage=${storage:-$default_storage}
    
    # Set up the container
    container_info=$(setup_container "$service" "$ctid" "$cores" "$memory" "$storage")
    installed_containers+=("$container_info")
done

# --------------------------------------
# Final status check
# --------------------------------------
print_status "$YELLOW" "Checking container status..."

if [ ${#installed_containers[@]} -gt 0 ]; then
    for container_info in "${installed_containers[@]}"; do
        name=$(echo $container_info | cut -d: -f1)
        ctid=$(echo $container_info | cut -d: -f2)
        ip=$(echo $container_info | cut -d: -f3)
        
        print_status "$BLUE" "Checking ${name} container (${ip})..."
        run_proxmox_command "pct exec $ctid -- docker ps"
    done
    
    print_status "$GREEN" "===== Homelab setup completed successfully! ====="
    print_status "$BLUE" "You can access your services at the following addresses:"
    
    # Create a formatted summary of all services
    echo ""
    echo "┌────────────────────────────────────────────────────────────────┐"
    echo "│                       SERVICE SUMMARY                           │"
    echo "├────────────┬─────────┬────────────────┬────────────────────────┤"
    echo "│ Service    │ CTID    │ IP Address     │ Available Ports        │"
    echo "├────────────┼─────────┼────────────────┼────────────────────────┤"
    
    for container_info in "${installed_containers[@]}"; do
        name=$(echo $container_info | cut -d: -f1)
        ctid=$(echo $container_info | cut -d: -f2)
        ip=$(echo $container_info | cut -d: -f3)
        
        case $name in
            "media")
                ports="8989,7878,6767,8096,5055,8080..."
                printf "│ %-10s │ %-7s │ %-14s │ %-22s │\n" "Media" "$ctid" "$ip" "$ports"
                ;;
            "monitoring")
                ports="9090,3000,9093,9100"
                printf "│ %-10s │ %-7s │ %-14s │ %-22s │\n" "Monitoring" "$ctid" "$ip" "$ports"
                ;;
            "logging")
                ports="9200,5601,5044"
                printf "│ %-10s │ %-7s │ %-14s │ %-22s │\n" "Logging" "$ctid" "$ip" "$ports"
                ;;
            "proxy")
                ports="3000,80,53"
                printf "│ %-10s │ %-7s │ %-14s │ %-22s │\n" "Proxy" "$ctid" "$ip" "$ports"
                ;;
        esac
    done
    
    echo "└────────────┴─────────┴────────────────┴────────────────────────┘"
    echo ""
    
    # Detailed service URLs
    print_status "$BLUE" "Detailed service URLs:"
    for container_info in "${installed_containers[@]}"; do
        name=$(echo $container_info | cut -d: -f1)
        ip=$(echo $container_info | cut -d: -f3)
        
        case $name in
            "media")
                echo "- Media Stack (${ip}):"
                echo "  ├─ Sonarr: http://${ip}:8989"
                echo "  ├─ Radarr: http://${ip}:7878"
                echo "  ├─ Bazarr: http://${ip}:6767"
                echo "  ├─ Jellyfin: http://${ip}:8096"
                echo "  ├─ Jellyseerr: http://${ip}:5055"
                echo "  ├─ qBittorrent: http://${ip}:8080"
                echo "  ├─ Prowlarr: http://${ip}:9696"
                echo "  ├─ FlareSolverr: http://${ip}:8191"
                echo "  └─ Youtube-DL: http://${ip}:8998"
                ;;
            "monitoring")
                echo "- Monitoring Stack (${ip}):"
                echo "  ├─ Prometheus: http://${ip}:9090"
                echo "  ├─ Grafana: http://${ip}:3000"
                echo "  ├─ Alertmanager: http://${ip}:9093"
                echo "  └─ Node Exporter: http://${ip}:9100"
                ;;
            "logging")
                echo "- Logging Stack (${ip}):"
                echo "  ├─ Elasticsearch: http://${ip}:9200"
                echo "  └─ Kibana: http://${ip}:5601"
                ;;
            "proxy")
                echo "- Proxy Stack (${ip}):"
                echo "  └─ AdGuard Home: http://${ip}:3000"
                ;;
        esac
    done
    
    # Save summary to a file in the current directory
    SUMMARY_FILE="homelab_summary.txt"
    {
        echo "Proxmox Homelab - Installation Summary"
        echo "====================================="
        echo "Date: $(date)"
        echo "Proxmox Server: ${proxmox_ip} (${proxmox_node})"
        echo ""
        echo "Installed Services:"
        
        for container_info in "${installed_containers[@]}"; do
            name=$(echo $container_info | cut -d: -f1)
            ctid=$(echo $container_info | cut -d: -f2)
            ip=$(echo $container_info | cut -d: -f3)
            echo "- ${name} (CTID: ${ctid}, IP: ${ip})"
        done
        
        echo ""
        echo "Access Information:"
        
        for container_info in "${installed_containers[@]}"; do
            name=$(echo $container_info | cut -d: -f1)
            ip=$(echo $container_info | cut -d: -f3)
            
            case $name in
                "media")
                    echo "- Media Stack (${ip}):"
                    echo "  * Sonarr: http://${ip}:8989"
                    echo "  * Radarr: http://${ip}:7878"
                    echo "  * Bazarr: http://${ip}:6767"
                    echo "  * Jellyfin: http://${ip}:8096"
                    echo "  * Jellyseerr: http://${ip}:5055"
                    echo "  * qBittorrent: http://${ip}:8080"
                    echo "  * Prowlarr: http://${ip}:9696"
                    echo "  * FlareSolverr: http://${ip}:8191"
                    echo "  * Youtube-DL: http://${ip}:8998"
                    ;;
                "monitoring")
                    echo "- Monitoring Stack (${ip}):"
                    echo "  * Prometheus: http://${ip}:9090"
                    echo "  * Grafana: http://${ip}:3000 (admin / ${grafana_password})"
                    echo "  * Alertmanager: http://${ip}:9093"
                    echo "  * Node Exporter: http://${ip}:9100"
                    ;;
                "logging")
                    echo "- Logging Stack (${ip}):"
                    echo "  * Elasticsearch: http://${ip}:9200"
                    echo "  * Kibana: http://${ip}:5601"
                    ;;
                "proxy")
                    echo "- Proxy Stack (${ip}):"
                    echo "  * AdGuard Home: http://${ip}:3000"
                    if [ "$cloudflared_token" != "your_token_here" ]; then
                        echo "  * Cloudflared Tunnel: Configured with your token"
                    else
                        echo "  * Cloudflared Tunnel: Not configured (token missing)"
                    fi
                    ;;
            esac
        done
        
        echo ""
        echo "Notes:"
        echo "- All containers are using Alpine Linux"
        echo "- All data is stored in /datapool for persistence"
        echo "- Container console access is passwordless (root)"
        echo ""
        echo "Maintenance Commands:"
        echo "- Docker Compose commands: pct exec CTID -- cd /root/docker && docker-compose <command>"
        echo "- Container shell access: pct enter CTID"
        echo "- Container restart: pct restart CTID"
        echo ""
    } > "$SUMMARY_FILE"
    
    print_status "$GREEN" "A detailed summary has been saved to: $SUMMARY_FILE"
    echo ""
    echo "Enjoy your homelab!"
else
    print_status "$RED" "No containers were installed."
fi

# Cleanup temporary files
print_status "$YELLOW" "Cleaning up temporary files..."
rm -f /tmp/monitoring.env /tmp/proxy.env /tmp/docker-compose.yml

# Self-delete the script
print_status "$YELLOW" "Self-deleting the setup script..."
rm -- "$0"

exit 0
