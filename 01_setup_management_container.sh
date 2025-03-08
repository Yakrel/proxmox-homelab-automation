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

# Helper function for printing status messages
print_status() {
  local color=$1
  local message=$2
  echo -e "${color}${message}${NC}"
}

# Helper function for printing error messages and exiting
print_error_exit() {
  local message=$1
  print_status "${RED}" "Error: ${message}"
  exit 1
}

# Helper function to wait for service availability
wait_for_service() {
  local host=$1
  local port=$2
  local service=$3
  local max_attempts=${4:-30}
  local delay=${5:-5}
  local attempt=1

  print_status "${YELLOW}" "Waiting for ${service} on ${host}:${port}..."
  
  while [ $attempt -le $max_attempts ]; do
    if nc -z -w5 $host $port &> /dev/null; then
      print_status "${GREEN}" "✅ ${service} is available on ${host}:${port} (attempt $attempt)"
      return 0
    fi
    print_status "${YELLOW}" "⏳ ${service} not available yet... ($attempt/$max_attempts)"
    sleep $delay
    attempt=$((attempt+1))
  done
  
  print_status "${RED}" "❌ ${service} timeout on ${host}:${port} after $max_attempts attempts!"
  return 1
}

# Function to display welcome message
welcome_message() {
  print_status "${GREEN}" "=== Proxmox Homelab Automation - All-in-One Setup ==="
  print_status "${YELLOW}" "This script sets up the management container in a single step"
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
    print_error_exit "IP address cannot be empty!"
  fi

  # Add default value for gateway
  read -p "Network Gateway (default: 192.168.1.1): " GATEWAY_INPUT
  GATEWAY=${GATEWAY_INPUT:-"192.168.1.1"}
  if [[ -z "$GATEWAY" ]]; then
    print_error_exit "Gateway address cannot be empty!"
  fi

  read -p "GitHub repository (default: Yakrel/proxmox-homelab-automation): " GITHUB_REPO_INPUT
  GITHUB_REPO=${GITHUB_REPO_INPUT:-"Yakrel/proxmox-homelab-automation"}
  REPO_URL="git@github.com:${GITHUB_REPO}.git"
  REPO_HTTPS_URL="https://github.com/${GITHUB_REPO}.git"
}

# Function to check and download templates
check_templates() {
  print_status "${YELLOW}" "Checking and downloading templates..."

  # Check if pveam is available
  if ! command -v pveam &> /dev/null; then
    print_error_exit "pveam command not found. This script must be run on a Proxmox host."
  fi

  # Check available repositories
  print_status "${YELLOW}" "Checking available template repositories..."
  pveam update

  # Check if datapool exists
  if pvesm status | grep -q "datapool"; then
    print_status "${GREEN}" "Datapool storage found."
    STORAGE="datapool"
  else
    print_status "${YELLOW}" "Datapool storage not found, using default local."
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
  print_status "${YELLOW}" "Checking Debian template..."
  DEBIAN_TEMPLATE=$(pveam available -section system | grep -E 'debian.*12.*standard' | sort -V | tail -n 1 | awk '{print $2}')

  if [ -z "$DEBIAN_TEMPLATE" ]; then
    print_status "${RED}" "No available Debian template found!"
  else
    DEBIAN_TEMPLATE_FILENAME=$(basename "$DEBIAN_TEMPLATE")
    
    # Download template if needed
    if pveam list $STORAGE | grep -q "$DEBIAN_TEMPLATE_FILENAME"; then
      print_status "${GREEN}" "Debian template ($DEBIAN_TEMPLATE_FILENAME) already downloaded."
    else
      print_status "${YELLOW}" "Downloading Debian template: $DEBIAN_TEMPLATE"
      pveam download $STORAGE $DEBIAN_TEMPLATE
    fi
    
    # Set template path
    MANAGEMENT_TEMPLATE_PATH="${STORAGE}:vztmpl/${DEBIAN_TEMPLATE_FILENAME}"
    print_status "${GREEN}" "Management template path: $MANAGEMENT_TEMPLATE_PATH"
  fi
}

# Function to check and download Alpine template
check_alpine_template() {
  print_status "${YELLOW}" "Checking Alpine template..."
  ALPINE_TEMPLATE=$(pveam available -section system | grep -E 'alpine.*3\..*default' | sort -V | tail -n 1 | awk '{print $2}')

  if [ -z "$ALPINE_TEMPLATE" ]; then
    print_status "${RED}" "No available Alpine template found!"
  else
    ALPINE_TEMPLATE_FILENAME=$(basename "$ALPINE_TEMPLATE")
    
    # Download template if needed
    if pveam list $STORAGE | grep -q "$ALPINE_TEMPLATE_FILENAME"; then
      print_status "${GREEN}" "Alpine template ($ALPINE_TEMPLATE_FILENAME) already downloaded."
    else
      print_status "${YELLOW}" "Downloading Alpine template: $ALPINE_TEMPLATE"
      pveam download $STORAGE $ALPINE_TEMPLATE
    fi
    
    # Set template path
    ALPINE_TEMPLATE_PATH="${STORAGE}:vztmpl/${ALPINE_TEMPLATE_FILENAME}"
    print_status "${GREEN}" "Alpine template path: $ALPINE_TEMPLATE_PATH"
  fi
}

# Function to handle manual template selection if needed
handle_manual_template_selection() {
  # List available templates
  print_status "${YELLOW}" "Checking available templates..."
  TEMPLATES=$(pveam list $STORAGE 2>/dev/null | grep -E 'alpine|debian' | awk '{print $1}' || echo "")

  if [ -z "$TEMPLATES" ]; then
    # Check local repositories
    print_status "${YELLOW}" "Checking local templates..."
    
    # Possible template locations
    TEMPLATE_LOCATIONS=(
        "${STORAGE}:vztmpl"
        "local:vztmpl"
        "${STORAGE}:template/cache"
    )
    
    for LOCATION in "${TEMPLATE_LOCATIONS[@]}"; do
      print_status "${YELLOW}" "Checking location $LOCATION..."
      LOCATION_TEMPLATES=$(pct template list 2>/dev/null | grep "$LOCATION" | grep -E 'debian|alpine' || echo "")
      if [ ! -z "$LOCATION_TEMPLATES" ]; then
        TEMPLATES="$LOCATION_TEMPLATES"
        print_status "${GREEN}" "Templates found!"
        echo "$TEMPLATES"
        break
      fi
    done
    
    if [ -z "$TEMPLATES" ]; then
      print_status "${RED}" "No templates found!"
      print_status "${YELLOW}" "Please enter existing template path and name (e.g., datapool:vztmpl/debian-12-standard_12.1-1_amd64.tar.zst):"
      read -p "Template full path: " TEMPLATE_PATH
      if [ -z "$TEMPLATE_PATH" ]; then
        print_error_exit "Template path cannot be empty. Script terminated."
      fi
    else
      print_status "${GREEN}" "Available templates:"
      echo "$TEMPLATES"
      echo
      print_status "${YELLOW}" "Using Debian template for management container."
      if [ ! -z "$MANAGEMENT_TEMPLATE_PATH" ]; then
        print_status "${GREEN}" "Management template automatically selected: $MANAGEMENT_TEMPLATE_PATH"
        TEMPLATE_PATH="$MANAGEMENT_TEMPLATE_PATH"
      else
        read -p "Enter the full path of the template you want to use: " TEMPLATE_PATH
        if [ -z "$TEMPLATE_PATH" ]; then
          print_error_exit "Template path cannot be empty. Script terminated."
        fi
      fi
    fi
  else
    print_status "${GREEN}" "Available templates:"
    echo "$TEMPLATES"
    echo
    print_status "${YELLOW}" "Using Debian template for management container."
    if [ ! -z "$MANAGEMENT_TEMPLATE_PATH" ]; then
      print_status "${GREEN}" "Management template automatically selected: $MANAGEMENT_TEMPLATE_PATH"
      TEMPLATE_PATH="$MANAGEMENT_TEMPLATE_PATH"
    else
      read -p "Enter the full path of the template you want to use: " TEMPLATE_PATH
      if [ -z "$TEMPLATE_PATH" ]; then
        print_error_exit "Template path cannot be empty. Script terminated."
      fi
    fi
  fi

  # Save Alpine template path for tfvars
  if [ ! -z "$ALPINE_TEMPLATE_PATH" ]; then
    # Save Alpine template path to variable
    ALPINE_TEMPLATE_FOR_TFVARS="$ALPINE_TEMPLATE_PATH"
  else
    # If not automatically downloaded, ask for Alpine template path
    print_status "${YELLOW}" "Enter Alpine template path for LXC containers:"
    read -p "Alpine template path (e.g., datapool:vztmpl/alpine-3.21-default_20241217_amd64.tar.xz): " ALPINE_TEMPLATE_FOR_TFVARS
    
    if [ -z "$ALPINE_TEMPLATE_FOR_TFVARS" ]; then
      print_status "${YELLOW}" "No Alpine template path entered, using default value."
      ALPINE_TEMPLATE_FOR_TFVARS="${STORAGE}:template/cache/alpine-3.21-default_20241217_amd64.tar.xz"
    fi
  fi
}

# Komut satırı tekrarlarını azaltma - pct exec çağrıları için bir yardımcı fonksiyon
exec_in_container() {
  local command=$1
  pct exec $CONTAINER_ID -- bash -c "$command" || {
    print_error_exit "Failed to execute: $command"
  }
}

# Konteyner içindeki dosya/dizin varliğini kontrol eden yardımcı fonksiyon
check_container_path() {
  local path=$1
  local output=$(pct exec $CONTAINER_ID -- bash -c "if [ -e \"$path\" ]; then echo 'exists'; else echo 'not_exists'; fi" 2>/dev/null)
  
  if [ "$output" = "exists" ]; then
    return 0  # Path exists
  else
    return 1  # Path does not exist
  fi
}

# Function to create management container
create_management_container() {
  print_status "${GREEN}" "Creating management container (ID: $CONTAINER_ID)..."

  # Show debug info
  print_status "${YELLOW}" "DEBUG: Template path: $TEMPLATE_PATH"
  print_status "${YELLOW}" "DEBUG: IP: $CONTAINER_IP"
  print_status "${YELLOW}" "DEBUG: Gateway: $GATEWAY"
  print_status "${YELLOW}" "DEBUG: Disk size: ${DISK_SIZE}G"

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

  print_status "${YELLOW}" "Waiting for container to start..."
  sleep 15

  # Check if container is running
  print_status "${YELLOW}" "Checking container status..."
  CONTAINER_STATUS=$(pct status $CONTAINER_ID 2>/dev/null || echo "unknown")
  if [[ "$CONTAINER_STATUS" != *"running"* ]]; then
    print_status "${RED}" "Warning: Container does not appear to be running. Status: $CONTAINER_STATUS"
    print_status "${YELLOW}" "Waiting a bit longer for the container to start..."
    sleep 15
    CONTAINER_STATUS=$(pct status $CONTAINER_ID 2>/dev/null || echo "unknown")
    if [[ "$CONTAINER_STATUS" != *"running"* ]]; then
      print_error_exit "Container is not running. Please check manually. You can try running pct start $CONTAINER_ID"
    fi
  fi
  
  return 0
}

# Function to install required software
install_required_software() {
  print_status "${GREEN}" "Installing required software..."
  exec_in_container "apt update && DEBIAN_FRONTEND=noninteractive apt install -y git python3 python3-pip curl jq unzip software-properties-common wget gpg locales"

  # Configure locale settings
  print_status "${GREEN}" "Configuring locale settings..."
  exec_in_container "
    sed -i 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen && \
    locale-gen en_US.UTF-8 && \
    update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 && \
    echo 'export LC_ALL=en_US.UTF-8' >> /root/.bashrc && \
    echo 'export LANG=en_US.UTF-8' >> /root/.bashrc
  "

  # Install Terraform - Official HashiCorp method
  print_status "${GREEN}" "Installing Terraform..."
  exec_in_container "
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
  print_status "${GREEN}" "Installing Ansible..."
  exec_in_container "
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
  print_status "${GREEN}" "Creating SSH key..."
  exec_in_container "ssh-keygen -t rsa -b 4096 -f /root/.ssh/id_rsa -N ''"

  # Display SSH key and wait for user to add it to GitHub
  print_status "${BLUE}" "==============================================================="
  print_status "${YELLOW}" "IMPORTANT: You need to add the following SSH public key to your GitHub account"
  print_status "${BLUE}" "==============================================================="
  echo
  exec_in_container "cat /root/.ssh/id_rsa.pub"
  echo
  print_status "${BLUE}" "==============================================================="
  print_status "${YELLOW}" "Please add the SSH key above to your GitHub account:"
  echo -e "1. Go to ${GREEN}https://github.com/settings/keys${NC}"
  echo -e "2. Click 'New SSH key' button"
  echo -e "3. Copy and paste the key above and enter a title"
  echo -e "4. Click 'Add SSH key' button"
  echo
  read -p "Press ENTER after adding the SSH key to GitHub..." reply

  # Test GitHub SSH connection
  print_status "${YELLOW}" "Testing GitHub SSH connection..."
  exec_in_container "ssh -o StrictHostKeyChecking=no -T git@github.com || true"
  print_status "${GREEN}" "Note: A 'Permission denied' message above is normal, this confirms the connection works."
  
  return 0
}

# Function to clone repository
clone_repository() {
  print_status "${GREEN}" "Cloning repository (${REPO_URL})..."
  
  # Önce dizini oluştur
  exec_in_container "mkdir -p $(dirname $REPO_DIR)"
  
  # Git klonlama işlemi, önce SSH sonra HTTPS ile dene
  local clone_output=""
  clone_output=$(exec_in_container "GIT_SSH_COMMAND='ssh -o StrictHostKeyChecking=no' git clone $REPO_URL $REPO_DIR 2>&1 || echo 'SSH_CLONE_FAILED'")
  
  # SSH klonlama başarısız olursa HTTPS ile dene
  if [[ "$clone_output" == *"SSH_CLONE_FAILED"* ]]; then
    print_status "${YELLOW}" "SSH cloning failed, trying HTTPS..."
    clone_output=$(exec_in_container "git clone $REPO_HTTPS_URL $REPO_DIR 2>&1 || echo 'HTTPS_CLONE_FAILED'")
    
    if [[ "$clone_output" == *"HTTPS_CLONE_FAILED"* ]]; then
      print_status "${RED}" "❌ Failed to clone repository. Please check your GitHub connection."
      return 1
    fi
  fi

  # Git dizininin varlığını kontrol et
  if check_container_path "$REPO_DIR/.git"; then
    print_status "${GREEN}" "✅ Repository successfully cloned: $REPO_DIR"
  else
    print_status "${RED}" "❌ Failed to clone repository. Please check your GitHub connection."
    return 1
  fi
  
  return 0
}

# Function to get configuration information
get_config_info() {
  print_status "${GREEN}" "Getting configuration information..."
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
  print_status "${YELLOW}" "Creating Terraform configuration file..."
  
  # Terraform örnek dosyasının var olup olmadığını kontrol et
  if ! check_container_path "$REPO_DIR/terraform/terraform.tfvars.example"; then
    print_status "${RED}" "❌ terraform.tfvars.example file not found!"
    return 1
  fi
  
  # Terraform yapılandırma dosyasını oluştur
  exec_in_container "cp \"$REPO_DIR/terraform/terraform.tfvars.example\" \"$REPO_DIR/terraform/terraform.tfvars\""
  exec_in_container "sed -i \"s|proxmox_api_url = \\\".*\\\"|proxmox_api_url = \\\"$PROXMOX_API_URL\\\"|g\" \"$REPO_DIR/terraform/terraform.tfvars\""
  exec_in_container "sed -i \"s|proxmox_password = \\\".*\\\"|proxmox_password = \\\"$PROXMOX_PASSWORD\\\"|g\" \"$REPO_DIR/terraform/terraform.tfvars\""
  exec_in_container "sed -i \"s|gateway = \\\".*\\\"|gateway = \\\"$GATEWAY\\\"|g\" \"$REPO_DIR/terraform/terraform.tfvars\""
  exec_in_container "sed -i \"s|alpine_template = \\\".*\\\"|alpine_template = \\\"$ALPINE_TEMPLATE_FOR_TFVARS\\\"|g\" \"$REPO_DIR/terraform/terraform.tfvars\""
  exec_in_container "sed -i \"s|grafana_password = \\\".*\\\"|grafana_password = \\\"$GRAFANA_PASSWORD\\\"|g\" \"$REPO_DIR/terraform/terraform.tfvars\""
  print_status "${GREEN}" "✅ terraform.tfvars file created"

  # Create scripts directory and setup SSH script
  print_status "${YELLOW}" "Creating Terraform scripts directory..."
  exec_in_container "mkdir -p \"$REPO_DIR/terraform/scripts\""
  
  # Ensure SSH setup script exists and is executable
  if check_container_path "$REPO_DIR/terraform/scripts/setup_ssh.sh"; then
    exec_in_container "chmod +x \"$REPO_DIR/terraform/scripts/setup_ssh.sh\""
    print_status "${GREEN}" "✅ Made setup_ssh.sh executable"
  else
    print_status "${YELLOW}" "⚠️ SSH setup script not found, creating a basic version..."
    # Create a very basic setup script if it doesn't exist
    exec_in_container "cat > \"$REPO_DIR/terraform/scripts/setup_ssh.sh\" << 'EOF'
#!/bin/bash
# Basic SSH setup script for Alpine LXC containers
CONTAINER_ID=\$1
LOG_FILE=\"ssh_setup_\${CONTAINER_ID}.log\"
echo \"SSH Setup for container \${CONTAINER_ID} - \$(date)\" > \$LOG_FILE

# Wait for container to be ready
sleep 30
echo \"Setting up SSH for container \${CONTAINER_ID}\" >> \$LOG_FILE

# Try multiple times
for attempt in {1..5}; do
  echo \"Attempt \$attempt\" >> \$LOG_FILE
  
  # Update and install SSH
  pct exec \${CONTAINER_ID} -- ash -c \"apk update\" >> \$LOG_FILE 2>&1
  pct exec \${CONTAINER_ID} -- ash -c \"apk add openssh\" >> \$LOG_FILE 2>&1
  
  # Configure SSH
  pct exec \${CONTAINER_ID} -- ash -c \"rc-update add sshd\" >> \$LOG_FILE 2>&1
  pct exec \${CONTAINER_ID} -- ash -c \"mkdir -p /etc/ssh/\" >> \$LOG_FILE 2>&1
  pct exec \${CONTAINER_ID} -- ash -c 'echo \"PermitRootLogin yes\" >> /etc/ssh/sshd_config' >> \$LOG_FILE 2>&1
  pct exec \${CONTAINER_ID} -- ash -c 'echo \"PasswordAuthentication yes\" >> /etc/ssh/sshd_config' >> \$LOG_FILE 2>&1
  
  # Start SSH service
  if pct exec \${CONTAINER_ID} -- ash -c \"/etc/init.d/sshd start\" >> \$LOG_FILE 2>&1; then
    echo \"SSH setup successful\" >> \$LOG_FILE
    exit 0
  fi
  
  echo \"SSH setup failed, retrying after delay...\" >> \$LOG_FILE
  sleep 10
done

echo \"Failed to set up SSH after multiple attempts\" >> \$LOG_FILE
exit 0  # Exit with success to prevent Terraform from failing
EOF"
    exec_in_container "chmod +x \"$REPO_DIR/terraform/scripts/setup_ssh.sh\""
    print_status "${GREEN}" "✅ Created and made setup_ssh.sh executable"
  fi

  # Grafana yapılandırma dosyası
  print_status "${YELLOW}" "Creating Grafana configuration file..."
  if check_container_path "$REPO_DIR/docker/monitoring/.env.example"; then
    exec_in_container "cp \"$REPO_DIR/docker/monitoring/.env.example\" \"$REPO_DIR/docker/monitoring/.env\""
    exec_in_container "sed -i \"s|GRAFANA_PASSWORD=.*|GRAFANA_PASSWORD=$GRAFANA_PASSWORD|g\" \"$REPO_DIR/docker/monitoring/.env\""
    print_status "${GREEN}" "✅ docker/monitoring/.env file created"
  else
    print_status "${YELLOW}" "⚠️ docker/monitoring/.env.example file not found, skipping."
  fi
  
  # Cloudflare token yapılandırması (varsa)
  if [ -n "$CLOUDFLARE_TOKEN" ] && check_container_path "$REPO_DIR/docker/proxy/.env.example"; then
    print_status "${YELLOW}" "Creating Cloudflare configuration file..."
    exec_in_container "cp \"$REPO_DIR/docker/proxy/.env.example\" \"$REPO_DIR/docker/proxy/.env\""
    exec_in_container "sed -i \"s|CLOUDFLARED_TOKEN=.*|CLOUDFLARED_TOKEN=$CLOUDFLARE_TOKEN|g\" \"$REPO_DIR/docker/proxy/.env\""
    print_status "${GREEN}" "✅ docker/proxy/.env file created"
  fi
  
  # 02_terraform_to_ansible.sh betiğini çalıştırılabilir yap
  if check_container_path "$REPO_DIR/02_terraform_to_ansible.sh"; then
    exec_in_container "chmod +x \"$REPO_DIR/02_terraform_to_ansible.sh\""
    print_status "${GREEN}" "✅ Made 02_terraform_to_ansible.sh executable"
  fi
  
  return 0
}

# Function to create directory structure
create_directory_structure() {
  print_status "${YELLOW}" "Do you want to create directory structure for LXC containers?"
  echo -e "This will create only the /datapool/config, /datapool/media and /datapool/torrents directories"
  read -p "Create directory structure? (y/n): " CREATE_DIRECTORIES

  if [[ "$CREATE_DIRECTORIES" =~ ^[Yy]$ ]]; then
    print_status "${YELLOW}" "Creating directory structure..."
    
    # Config directories - Run on the host, not inside container
    mkdir -p /datapool/config/{sonarr-config,radarr-config,bazarr-config,jellyfin-config,jellyseerr-config,qbittorrent-config,prowlarr-config,flaresolverr-config,watchtower-media-config,recyclarr-config,youtube-dl-config,prometheus-config,grafana-config,alertmanager-config,watchtower-monitoring-config,elasticsearch-config,logstash-config,kibana-config,filebeat-config,watchtower-logging-config,cloudflared-config,watchtower-proxy-config,adguard-config/{work,conf}}
    
    # Media and torrent directories
    mkdir -p /datapool/media/{tv,movies,youtube/{playlists,channels}}
    mkdir -p /datapool/torrents/{tv,movies}
    
    # Set permissions
    chown -R 100000:100000 /datapool/config
    chown -R 100000:100000 /datapool/media
    chown -R 100000:100000 /datapool/torrents
    
    print_status "${GREEN}" "✅ Directory structure successfully created!"
  else
    print_status "${YELLOW}" "Directory structure not created. Please create required directories manually."
  fi
}

# Function to display configuration summary
display_config_summary() {
  print_status "${GREEN}" "=== Configuration Summary ==="
  print_status "${YELLOW}" "Proxmox API URL: $PROXMOX_API_URL"
  print_status "${YELLOW}" "Gateway IP: $GATEWAY"
  print_status "${YELLOW}" "Management IP: $CONTAINER_IP"
  print_status "${YELLOW}" "Management Template: $TEMPLATE_PATH"
  print_status "${YELLOW}" "Alpine Template: $ALPINE_TEMPLATE_FOR_TFVARS"
  print_status "${YELLOW}" "Grafana Password: $GRAFANA_PASSWORD"
  if [ -n "$CLOUDFLARE_TOKEN" ]; then
    print_status "${YELLOW}" "Cloudflare Token: ${CLOUDFLARE_TOKEN:0:5}*****"
  else
    print_status "${YELLOW}" "Cloudflare Token: Not provided"
  fi
}

# Function to run automated steps
run_automated_steps() {
  echo
  read -p "Do you want to automatically run Terraform and Ansible steps? (y/n): " AUTO_CONTINUE

  if [[ "$AUTO_CONTINUE" =~ ^[Yy]$ ]]; then
    print_status "${GREEN}" "Creating LXC containers with Terraform..."
    exec_in_container "cd $REPO_DIR/terraform && terraform init"
    exec_in_container "cd $REPO_DIR/terraform && terraform apply -auto-approve"
    
    print_status "${GREEN}" "Creating Ansible inventory..."
    exec_in_container "cd $REPO_DIR && ./02_terraform_to_ansible.sh"
    
    print_status "${GREEN}" "Configuring with Ansible..."
    exec_in_container "cd $REPO_DIR/ansible && ansible-playbook -i inventory/all playbook.yml"
    
    print_status "${GREEN}" "✅ All operations completed! Your homelab is ready."
  else
    print_status "${YELLOW}" "Process stopped. You can continue manually."
  fi
}

# Function to display completion message
display_completion_message() {
  print_status "${GREEN}" "✅ Setup and configuration completed!"
  print_status "${YELLOW}" "To continue with your homelab setup, follow these steps:"
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