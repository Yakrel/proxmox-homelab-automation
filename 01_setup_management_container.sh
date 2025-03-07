#!/bin/bash
# Proxmox Homelab Setup - Management Container Setup
# First step: Create and configure management container

set -e

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Define variables
CONTAINER_ID=${CONTAINER_ID:-900}
DISK_SIZE=${DISK_SIZE:-"20"}
REPO_DIR="/opt/proxmox-automation"

# Function to display welcome message
welcome_message() {
  echo -e "${GREEN}=== Proxmox Homelab Automation - All-in-One Setup ===${NC}"
  echo -e "${YELLOW}This script sets up the management container in a single step${NC}"
  echo
}

# Function to get user input
get_user_input() {
  # Get Proxmox information
  read -p "Proxmox API URL (default: https://192.168.1.10:8006/api2/json): " PROXMOX_API_URL_INPUT
  PROXMOX_API_URL=${PROXMOX_API_URL_INPUT:-"https://192.168.1.10:8006/api2/json"}

  # Add default value for container IP
  read -p "Management container IP (default: 192.168.1.200): " CONTAINER_IP_INPUT
  CONTAINER_IP=${CONTAINER_IP_INPUT:-"192.168.1.200"}
  if [[ -z "$CONTAINER_IP" ]]; then
    echo -e "${RED}Error: IP address cannot be empty!${NC}"
    exit 1
  fi

  # Add default value for gateway
  read -p "Network Gateway (default: 192.168.1.1): " GATEWAY_INPUT
  GATEWAY=${GATEWAY_INPUT:-"192.168.1.1"}
  if [[ -z "$GATEWAY" ]]; then
    echo -e "${RED}Error: Gateway address cannot be empty!${NC}"
    exit 1
  fi

  read -p "GitHub repository (default: Yakrel/proxmox-homelab-automation): " GITHUB_REPO_INPUT
  GITHUB_REPO=${GITHUB_REPO_INPUT:-"Yakrel/proxmox-homelab-automation"}
  REPO_URL="git@github.com:${GITHUB_REPO}.git"
  REPO_HTTPS_URL="https://github.com/${GITHUB_REPO}.git"
}

# Function to check and download templates
check_templates() {
  echo -e "\n${YELLOW}Checking and downloading templates...${NC}"

  # Check if pveam is available
  if ! command -v pveam &> /dev/null; then
    echo -e "${RED}Error: pveam command not found. This script must be run on a Proxmox host.${NC}"
    exit 1
  fi

  # Check available repositories
  echo -e "${YELLOW}Checking available template repositories...${NC}"
  pveam update

  # Check if datapool exists
  if pvesm status | grep -q "datapool"; then
    echo -e "${GREEN}Datapool storage found.${NC}"
    STORAGE="datapool"
  else
    echo -e "${YELLOW}Datapool storage not found, using default local.${NC}"
    STORAGE="local"
  fi

  # Check and download Debian template
  check_debian_template
  
  # Check and download Alpine template
  check_alpine_template
  
  # Handle manual template selection if needed
  handle_manual_template_selection
}

# Function to check and download Debian template
check_debian_template() {
  echo -e "\n${YELLOW}Checking Debian template...${NC}"
  DEBIAN_TEMPLATE=$(pveam available -section system | grep -E 'debian.*12.*standard' | sort -V | tail -n 1 | awk '{print $2}')

  if [ -z "$DEBIAN_TEMPLATE" ]; then
    echo -e "${RED}No available Debian template found!${NC}"
  else
    DEBIAN_TEMPLATE_FILENAME=$(basename "$DEBIAN_TEMPLATE")
    
    # Download template if needed
    if pveam list $STORAGE | grep -q "$DEBIAN_TEMPLATE_FILENAME"; then
      echo -e "${GREEN}Debian template ($DEBIAN_TEMPLATE_FILENAME) already downloaded.${NC}"
    else
      echo -e "${YELLOW}Downloading Debian template: $DEBIAN_TEMPLATE${NC}"
      pveam download $STORAGE $DEBIAN_TEMPLATE
    fi
    
    # Set template path
    MANAGEMENT_TEMPLATE_PATH="${STORAGE}:vztmpl/${DEBIAN_TEMPLATE_FILENAME}"
    echo -e "${GREEN}Management template path: $MANAGEMENT_TEMPLATE_PATH${NC}"
  fi
}

# Function to check and download Alpine template
check_alpine_template() {
  echo -e "\n${YELLOW}Checking Alpine template...${NC}"
  ALPINE_TEMPLATE=$(pveam available -section system | grep -E 'alpine.*3\..*default' | sort -V | tail -n 1 | awk '{print $2}')

  if [ -z "$ALPINE_TEMPLATE" ]; then
    echo -e "${RED}No available Alpine template found!${NC}"
  else
    ALPINE_TEMPLATE_FILENAME=$(basename "$ALPINE_TEMPLATE")
    
    # Download template if needed
    if pveam list $STORAGE | grep -q "$ALPINE_TEMPLATE_FILENAME"; then
      echo -e "${GREEN}Alpine template ($ALPINE_TEMPLATE_FILENAME) already downloaded.${NC}"
    else
      echo -e "${YELLOW}Downloading Alpine template: $ALPINE_TEMPLATE${NC}"
      pveam download $STORAGE $ALPINE_TEMPLATE
    fi
    
    # Set template path
    ALPINE_TEMPLATE_PATH="${STORAGE}:vztmpl/${ALPINE_TEMPLATE_FILENAME}"
    echo -e "${GREEN}Alpine template path: $ALPINE_TEMPLATE_PATH${NC}"
  fi
}

# Function to handle manual template selection if needed
handle_manual_template_selection() {
  # List available templates
  echo -e "\n${YELLOW}Checking available templates...${NC}"
  TEMPLATES=$(pveam list $STORAGE 2>/dev/null | grep -E 'alpine|debian' | awk '{print $1}' || echo "")

  if [ -z "$TEMPLATES" ]; then
    # Check local repositories
    echo -e "${YELLOW}Checking local templates...${NC}"
    
    # Possible template locations
    TEMPLATE_LOCATIONS=(
        "${STORAGE}:vztmpl"
        "local:vztmpl"
        "${STORAGE}:template/cache"
    )
    
    for LOCATION in "${TEMPLATE_LOCATIONS[@]}"; do
      echo -e "${YELLOW}Checking location $LOCATION...${NC}"
      LOCATION_TEMPLATES=$(pct template list 2>/dev/null | grep "$LOCATION" | grep -E 'debian|alpine' || echo "")
      if [ ! -z "$LOCATION_TEMPLATES" ]; then
        TEMPLATES="$LOCATION_TEMPLATES"
        echo -e "${GREEN}Templates found!${NC}"
        echo "$TEMPLATES"
        break
      fi
    done
    
    if [ -z "$TEMPLATES" ]; then
      echo -e "${RED}No templates found!${NC}"
      echo -e "${YELLOW}Please enter existing template path and name (e.g., datapool:vztmpl/debian-12-standard_12.1-1_amd64.tar.zst):${NC}"
      read -p "Template full path: " TEMPLATE_PATH
      if [ -z "$TEMPLATE_PATH" ]; then
        echo -e "${RED}Template path cannot be empty. Script terminated.${NC}"
        exit 1
      fi
    else
      echo -e "${GREEN}Available templates:${NC}"
      echo "$TEMPLATES"
      echo
      echo -e "${YELLOW}Using Debian template for management container.${NC}"
      if [ ! -z "$MANAGEMENT_TEMPLATE_PATH" ]; then
        echo -e "${GREEN}Management template automatically selected: $MANAGEMENT_TEMPLATE_PATH${NC}"
        TEMPLATE_PATH="$MANAGEMENT_TEMPLATE_PATH"
      else
        read -p "Enter the full path of the template you want to use: " TEMPLATE_PATH
        if [ -z "$TEMPLATE_PATH" ]; then
          echo -e "${RED}Template path cannot be empty. Script terminated.${NC}"
          exit 1
        fi
      fi
    fi
  else
    echo -e "${GREEN}Available templates:${NC}"
    echo "$TEMPLATES"
    echo
    echo -e "${YELLOW}Using Debian template for management container.${NC}"
    if [ ! -z "$MANAGEMENT_TEMPLATE_PATH" ]; then
      echo -e "${GREEN}Management template automatically selected: $MANAGEMENT_TEMPLATE_PATH${NC}"
      TEMPLATE_PATH="$MANAGEMENT_TEMPLATE_PATH"
    else
      read -p "Enter the full path of the template you want to use: " TEMPLATE_PATH
      if [ -z "$TEMPLATE_PATH" ]; then
        echo -e "${RED}Template path cannot be empty. Script terminated.${NC}"
        exit 1
      fi
    fi
  fi

  # Save Alpine template path for tfvars
  if [ ! -z "$ALPINE_TEMPLATE_PATH" ]; then
    # Save Alpine template path to variable
    ALPINE_TEMPLATE_FOR_TFVARS="$ALPINE_TEMPLATE_PATH"
  else
    # If not automatically downloaded, ask for Alpine template path
    echo -e "\n${YELLOW}Enter Alpine template path for LXC containers:${NC}"
    read -p "Alpine template path (e.g., datapool:vztmpl/alpine-3.21-default_20241217_amd64.tar.xz): " ALPINE_TEMPLATE_FOR_TFVARS
    
    if [ -z "$ALPINE_TEMPLATE_FOR_TFVARS" ]; then
      echo -e "${YELLOW}No Alpine template path entered, using default value.${NC}"
      ALPINE_TEMPLATE_FOR_TFVARS="${STORAGE}:template/cache/alpine-3.21-default_20241217_amd64.tar.xz"
    fi
  fi
}

# Function to create management container
create_management_container() {
  echo -e "\n${GREEN}Creating management container (ID: $CONTAINER_ID)...${NC}"

  # Show debug info
  echo -e "${YELLOW}DEBUG: Template path: $TEMPLATE_PATH${NC}"
  echo -e "${YELLOW}DEBUG: IP: $CONTAINER_IP${NC}"
  echo -e "${YELLOW}DEBUG: Gateway: $GATEWAY${NC}"
  echo -e "${YELLOW}DEBUG: Disk size: ${DISK_SIZE}G${NC}"

  # Container creation command
  pct create $CONTAINER_ID "$TEMPLATE_PATH" \
    --hostname management \
    --memory 2048 \
    --swap 512 \
    --cores 2 \
    --rootfs "${STORAGE}:${DISK_SIZE}" \
    --net0 name=eth0,bridge=vmbr0,ip=$CONTAINER_IP/24,gw=$GATEWAY \
    --password debian \
    --unprivileged 1 \
    --features nesting=1,keyctl=1,fuse=1 \
    --start 1

  echo -e "\n${YELLOW}Waiting for container to start...${NC}"
  sleep 15

  # Check if container is running
  echo -e "${YELLOW}Checking container status...${NC}"
  CONTAINER_STATUS=$(pct status $CONTAINER_ID 2>/dev/null || echo "unknown")
  if [[ "$CONTAINER_STATUS" != *"running"* ]]; then
    echo -e "${RED}Warning: Container does not appear to be running. Status: $CONTAINER_STATUS${NC}"
    echo -e "${YELLOW}Waiting a bit longer for the container to start...${NC}"
    sleep 15
    CONTAINER_STATUS=$(pct status $CONTAINER_ID 2>/dev/null || echo "unknown")
    if [[ "$CONTAINER_STATUS" != *"running"* ]]; then
      echo -e "${RED}Error: Container is not running. Please check manually.${NC}"
      echo -e "${YELLOW}You can try running ${NC}pct start $CONTAINER_ID"
      exit 1
    fi
  fi
  
  return 0
}

# Function to install required software
install_required_software() {
  echo -e "\n${GREEN}Installing required software...${NC}"
  pct exec $CONTAINER_ID -- bash -c "apt update && DEBIAN_FRONTEND=noninteractive apt install -y git python3 python3-pip curl jq unzip software-properties-common wget gpg locales" || {
    echo -e "${RED}Error: Failed to install required software. Checking container access.${NC}"
    exit 1
  }

  # Configure locale settings
  echo -e "\n${GREEN}Configuring locale settings...${NC}"
  pct exec $CONTAINER_ID -- bash -c "
    sed -i 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen && \
    locale-gen en_US.UTF-8 && \
    update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 && \
    echo 'export LC_ALL=en_US.UTF-8' >> /root/.bashrc && \
    echo 'export LANG=en_US.UTF-8' >> /root/.bashrc
  "

  # Install Terraform - Official HashiCorp method
  echo -e "\n${GREEN}Installing Terraform...${NC}"
  pct exec $CONTAINER_ID -- bash -c "
    # Add HashiCorp GPG key
    wget -O- https://apt.releases.hashicorp.com/gpg | \
    gpg --dearmor | \
    tee /usr/share/keyrings/hashicorp-archive-keyring.gpg > /dev/null && \
    
    # Add repository
    echo \"deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
    https://apt.releases.hashicorp.com \$(lsb_release -cs) main\" | \
    tee /etc/apt/sources.list.d/hashicorp.list && \
    
    # Update and install
    apt update && \
    apt install -y terraform
  "

  # Install Ansible - Official method for Debian
  echo -e "\n${GREEN}Installing Ansible...${NC}"
  pct exec $CONTAINER_ID -- bash -c "
    # Determine appropriate Ubuntu codename (jammy for Debian 12)
    UBUNTU_CODENAME=jammy && \
    
    # Download Ansible GPG key
    wget -O- \"https://keyserver.ubuntu.com/pks/lookup?fingerprint=on&op=get&search=0x6125E2A8C77F2818FB7BD15B93C4A3FD7BB9C367\" | \
    gpg --dearmor -o /usr/share/keyrings/ansible-archive-keyring.gpg && \
    
    # Add repository
    echo \"deb [signed-by=/usr/share/keyrings/ansible-archive-keyring.gpg] \
    http://ppa.launchpad.net/ansible/ansible/ubuntu \$UBUNTU_CODENAME main\" | \
    tee /etc/apt/sources.list.d/ansible.list && \
    
    # Update and install
    apt update && \
    apt install -y ansible && \
    
    # Install Ansible collections
    ansible-galaxy collection install community.docker && \
    ansible-galaxy collection install community.general
  "
  
  return 0
}

# Function to set up SSH
setup_ssh() {
  echo -e "\n${GREEN}Creating SSH key...${NC}"
  pct exec $CONTAINER_ID -- bash -c "ssh-keygen -t rsa -b 4096 -f /root/.ssh/id_rsa -N ''"

  # Display SSH key and wait for user to add it to GitHub
  echo -e "\n${BLUE}===============================================================${NC}"
  echo -e "${YELLOW}IMPORTANT: You need to add the following SSH public key to your GitHub account${NC}"
  echo -e "${BLUE}===============================================================${NC}"
  echo
  pct exec $CONTAINER_ID -- cat /root/.ssh/id_rsa.pub
  echo
  echo -e "${BLUE}===============================================================${NC}"
  echo -e "${YELLOW}Please add the SSH key above to your GitHub account:${NC}"
  echo -e "1. Go to ${GREEN}https://github.com/settings/keys${NC}"
  echo -e "2. Click 'New SSH key' button"
  echo -e "3. Copy and paste the key above and enter a title"
  echo -e "4. Click 'Add SSH key' button"
  echo
  read -p "Press ENTER after adding the SSH key to GitHub..." reply

  # Test GitHub SSH connection
  echo -e "\n${YELLOW}Testing GitHub SSH connection...${NC}"
  pct exec $CONTAINER_ID -- bash -c "ssh -o StrictHostKeyChecking=no -T git@github.com || true"
  echo -e "${GREEN}Note: A 'Permission denied' message above is normal, this confirms the connection works.${NC}"
  
  return 0
}

# Function to clone repository
clone_repository() {
  echo -e "\n${GREEN}Cloning repository (${REPO_URL})...${NC}"
  pct exec $CONTAINER_ID -- bash -c "mkdir -p $(dirname $REPO_DIR) && \
  (GIT_SSH_COMMAND='ssh -o StrictHostKeyChecking=no' git clone $REPO_URL $REPO_DIR 2>/dev/null || \
   (echo 'SSH cloning failed, trying HTTPS...' && \
    git clone $REPO_HTTPS_URL $REPO_DIR))"

  # Check if repository was successfully cloned
  pct exec $CONTAINER_ID -- bash -c "if [ -d \"$REPO_DIR/.git\" ]; then \
    echo -e \"${GREEN}✅ Repository successfully cloned: $REPO_DIR${NC}\"; \
  else \
    echo -e \"${RED}❌ Failed to clone repository. Please check your GitHub connection.${NC}\"; \
    exit 1; \
  fi"
  
  return 0
}

# Function to get configuration information
get_config_info() {
  echo -e "\n${GREEN}Getting configuration information...${NC}"
  read -sp "Enter your Proxmox root password: " PROXMOX_PASSWORD
  echo

  # Cloudflare Tunnel token
  read -sp "Cloudflare Tunnel token (leave blank if not used): " CLOUDFLARE_TOKEN
  echo

  # Grafana password
  read -sp "Enter Grafana admin password (leave blank for 'homelab'): " GRAFANA_PASSWORD_INPUT
  GRAFANA_PASSWORD=${GRAFANA_PASSWORD_INPUT:-"homelab"}
  echo
  
  return 0
}

# Function to create configuration files
create_config_files() {
  echo -e "\n${YELLOW}Creating Terraform configuration file...${NC}"
  pct exec $CONTAINER_ID -- bash -c "if [ -f \"$REPO_DIR/terraform/terraform.tfvars.example\" ]; then \
    cp \"$REPO_DIR/terraform/terraform.tfvars.example\" \"$REPO_DIR/terraform/terraform.tfvars\" && \
    sed -i \"s|proxmox_api_url = \\\".*\\\"|proxmox_api_url = \\\"$PROXMOX_API_URL\\\"|g\" \"$REPO_DIR/terraform/terraform.tfvars\" && \
    sed -i \"s|proxmox_password = \\\".*\\\"|proxmox_password = \\\"$PROXMOX_PASSWORD\\\"|g\" \"$REPO_DIR/terraform/terraform.tfvars\" && \
    sed -i \"s|gateway = \\\".*\\\"|gateway = \\\"$GATEWAY\\\"|g\" \"$REPO_DIR/terraform/terraform.tfvars\" && \
    sed -i \"s|alpine_template = \\\".*\\\"|alpine_template = \\\"$ALPINE_TEMPLATE_FOR_TFVARS\\\"|g\" \"$REPO_DIR/terraform/terraform.tfvars\" && \
    sed -i \"s|grafana_password = \\\".*\\\"|grafana_password = \\\"$GRAFANA_PASSWORD\\\"|g\" \"$REPO_DIR/terraform/terraform.tfvars\" && \
    echo '✅ terraform.tfvars file created'; \
  else \
    echo '❌ terraform.tfvars.example file not found!'; \
    exit 1; \
  fi"

  # Create docker/monitoring/.env file
  echo -e "\n${YELLOW}Creating Grafana configuration file...${NC}"
  pct exec $CONTAINER_ID -- bash -c "if [ -f \"$REPO_DIR/docker/monitoring/.env.example\" ]; then \
    cp \"$REPO_DIR/docker/monitoring/.env.example\" \"$REPO_DIR/docker/monitoring/.env\" && \
    sed -i \"s|GRAFANA_PASSWORD=.*|GRAFANA_PASSWORD=$GRAFANA_PASSWORD|g\" \"$REPO_DIR/docker/monitoring/.env\" && \
    echo '✅ docker/monitoring/.env file created'; \
  else \
    echo '⚠️ docker/monitoring/.env.example file not found, skipping.'; \
  fi"
  
  # Make 02_terraform_to_ansible.sh executable
  pct exec $CONTAINER_ID -- bash -c "if [ -f \"$REPO_DIR/02_terraform_to_ansible.sh\" ]; then \
    chmod +x \"$REPO_DIR/02_terraform_to_ansible.sh\"; \
  fi"
  
  return 0
}

# Function to create directory structure
create_directory_structure() {
  echo -e "\n${YELLOW}Do you want to create directory structure for LXC containers?${NC}"
  echo -e "This will create only the /datapool/config, /datapool/media and /datapool/torrents directories"
  read -p "Create directory structure? (y/n): " CREATE_DIRECTORIES

  if [[ "$CREATE_DIRECTORIES" =~ ^[Yy]$ ]]; then
    echo -e "\n${YELLOW}Creating directory structure...${NC}"
    
    # Config directories - Run on the host, not inside container
    mkdir -p /datapool/config/{sonarr-config,radarr-config,bazarr-config,jellyfin-config,jellyseerr-config,qbittorrent-config,prowlarr-config,flaresolverr-config,watchtower-media-config,recyclarr-config,youtube-dl-config,prometheus-config,grafana-config,alertmanager-config,watchtower-monitoring-config,elasticsearch-config,logstash-config,kibana-config,filebeat-config,watchtower-logging-config,cloudflared-config,watchtower-proxy-config,adguard-config/{work,conf}}
    
    # Media and torrent directories
    mkdir -p /datapool/media/{tv,movies,youtube/{playlists,channels}}
    mkdir -p /datapool/torrents/{tv,movies}
    
    # Set permissions
    chown -R 100000:100000 /datapool/config
    chown -R 100000:100000 /datapool/media
    chown -R 100000:100000 /datapool/torrents
    
    echo -e "${GREEN}✅ Directory structure successfully created!${NC}"
  else
    echo -e "${YELLOW}Directory structure not created. Please create required directories manually.${NC}"
  fi
}

# Function to display configuration summary
display_config_summary() {
  echo -e "\n${GREEN}=== Configuration Summary ===${NC}"
  echo -e "${YELLOW}Proxmox API URL:${NC} $PROXMOX_API_URL"
  echo -e "${YELLOW}Gateway IP:${NC} $GATEWAY"
  echo -e "${YELLOW}Management IP:${NC} $CONTAINER_IP"
  echo -e "${YELLOW}Management Template:${NC} $TEMPLATE_PATH"
  echo -e "${YELLOW}Alpine Template:${NC} $ALPINE_TEMPLATE_FOR_TFVARS"
  echo -e "${YELLOW}Grafana Password:${NC} $GRAFANA_PASSWORD"
  if [ -n "$CLOUDFLARE_TOKEN" ]; then
    echo -e "${YELLOW}Cloudflare Token:${NC} ${CLOUDFLARE_TOKEN:0:5}*****"
  else
    echo -e "${YELLOW}Cloudflare Token:${NC} Not provided"
  fi
}

# Function to run automated steps
run_automated_steps() {
  echo
  read -p "Do you want to automatically run Terraform and Ansible steps? (y/n): " AUTO_CONTINUE

  if [[ "$AUTO_CONTINUE" =~ ^[Yy]$ ]]; then
    echo -e "\n${GREEN}Creating LXC containers with Terraform...${NC}"
    pct exec $CONTAINER_ID -- bash -c "cd $REPO_DIR/terraform && terraform init && terraform apply -auto-approve"
    
    echo -e "\n${GREEN}Creating Ansible inventory...${NC}"
    pct exec $CONTAINER_ID -- bash -c "cd $REPO_DIR && ./02_terraform_to_ansible.sh"
    
    echo -e "\n${GREEN}Configuring with Ansible...${NC}"
    pct exec $CONTAINER_ID -- bash -c "cd $REPO_DIR/ansible && ansible-playbook -i inventory/all playbook.yml"
    
    echo -e "\n${GREEN}✅ All operations completed! Your homelab is ready.${NC}"
  else
    echo -e "\n${YELLOW}Process stopped. You can continue manually.${NC}"
  fi
}

# Function to display completion message
display_completion_message() {
  echo -e "\n${GREEN}✅ Setup and configuration completed!${NC}"
  echo -e "${YELLOW}To continue with your homelab setup, follow these steps:${NC}"
  echo -e "1. Log into the management container: ${GREEN}pct enter $CONTAINER_ID${NC}"
  echo -e "2. Create LXC containers with Terraform: ${GREEN}cd $REPO_DIR/terraform && terraform init && terraform apply${NC}"
  echo -e "3. Create Ansible inventory: ${GREEN}cd $REPO_DIR && ./02_terraform_to_ansible.sh${NC}"
  echo -e "4. Configure with Ansible: ${GREEN}cd $REPO_DIR/ansible && ansible-playbook -i inventory/all playbook.yml${NC}"
}

# Main function
main() {
  welcome_message
  get_user_input
  check_templates
  create_management_container
  install_required_software
  setup_ssh
  clone_repository
  get_config_info
  create_config_files
  create_directory_structure
  display_config_summary
  run_automated_steps
  display_completion_message
}

# Run the main function
main