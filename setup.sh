#!/bin/bash

# Error handling
set -e
trap 'echo "An error occurred at line $LINENO. Command: $BASH_COMMAND"; exit 1' ERR

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
DEFAULT_GRAFANA_PASSWORD="admin"
PROXMOX_PASSWORD=""

# Hardcoded template yerine boş bırakıyoruz, otomatik tespit edeceğiz
ALPINE_TEMPLATE=""

echo -e "${GREEN}===== Proxmox Homelab Automation Setup =====${NC}"

# --------------------------------------
# Check prerequisites
# --------------------------------------
echo -e "${YELLOW}[1/10] Checking prerequisites${NC}"

# Check if git is installed
if ! command -v git &> /dev/null; then
    echo -e "${RED}Git is not installed. Please install Git first.${NC}"
    exit 1
fi

# Check if terraform is installed
if ! command -v terraform &> /dev/null; then
    echo -e "${RED}Terraform is not installed. Please install Terraform first.${NC}"
    exit 1
fi

# Check if ansible is installed
if ! command -v ansible &> /dev/null; then
    echo -e "${RED}Ansible is not installed. Please install Ansible first.${NC}"
    exit 1
fi

echo -e "${GREEN}All prerequisites are met.${NC}"

# --------------------------------------
# SSH key setup FIRST (before repository clone)
# --------------------------------------
echo -e "${YELLOW}[2/10] Setting up SSH keys${NC}"

if [ ! -f ~/.ssh/id_rsa ]; then
    echo "SSH key not found. Generating a new SSH key..."
    ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N ""
    echo -e "${GREEN}SSH key generated successfully.${NC}"
fi
    
# Display the public key and GitHub instructions
echo -e "${YELLOW}IMPORTANT: You need to add this SSH key to your GitHub account${NC}"
echo -e "${YELLOW}Here is your public key:${NC}"
echo ""
cat ~/.ssh/id_rsa.pub
echo ""
echo -e "${YELLOW}Instructions to add SSH key to GitHub:${NC}"
echo "1. Go to GitHub > Settings > SSH and GPG keys"
echo "2. Click 'New SSH key'"
echo "3. Copy the key above and paste it into GitHub"
echo "4. Save the key"

# Wait for user confirmation
read -p "Have you added the SSH key to GitHub? (y/n): " added_key
if [ "$added_key" != "y" ]; then
    echo -e "${RED}Please add the SSH key to GitHub before continuing.${NC}"
    exit 1
fi
echo -e "${GREEN}SSH key is ready for use.${NC}"

# --------------------------------------
# Clone repository (AFTER SSH key is ready)
# --------------------------------------
echo -e "${YELLOW}[3/10] Cloning repository${NC}"

# Create a directory for the project
PROJECT_DIR="proxmox-homelab-automation"
if [ ! -d "$PROJECT_DIR" ]; then
    echo "Cloning repository..."
    git clone git@github.com:Yakrel/proxmox-homelab-automation.git $PROJECT_DIR
    if [ $? -ne 0 ]; then
        echo -e "${RED}Failed to clone repository. Please check your SSH key and permissions.${NC}"
        exit 1
    fi
    echo -e "${GREEN}Repository cloned successfully.${NC}"
else
    echo "Repository directory already exists. Updating..."
    cd $PROJECT_DIR
    git pull || echo "Warning: Could not update repository but continuing..."
    cd ..
    echo -e "${GREEN}Repository updated successfully.${NC}"
fi

# Move into the project directory
cd $PROJECT_DIR

# --------------------------------------
# Ask Proxmox password once
# --------------------------------------
echo -e "${YELLOW}[4/10] Proxmox connection information${NC}"
echo -e "${BLUE}We'll ask for your Proxmox details once and use them throughout the script${NC}"
read -p "Enter Proxmox server IP [$DEFAULT_PROXMOX_IP]: " proxmox_ip
proxmox_ip=${proxmox_ip:-$DEFAULT_PROXMOX_IP}

read -p "Enter Proxmox username [$DEFAULT_PROXMOX_USER]: " proxmox_user
proxmox_user=${proxmox_user:-$DEFAULT_PROXMOX_USER}

echo -e "${BLUE}Enter Proxmox password (will be used for SSH and other connections):${NC}"
read -s PROXMOX_PASSWORD
echo ""

# --------------------------------------
# Setup SSH key authentication to Proxmox (optional)
# --------------------------------------
echo -e "${YELLOW}[5/10] Setting up SSH key authentication to Proxmox${NC}"
echo -e "${BLUE}This will let us connect to Proxmox without asking for a password each time${NC}"
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
        echo -e "${GREEN}SSH key copied to Proxmox server.${NC}"
    else
        echo -e "${YELLOW}Expect utility not found, using manual method.${NC}"
        ssh-copy-id -o StrictHostKeyChecking=no ${proxmox_user%@*}@${proxmox_ip}
    fi
fi

# --------------------------------------
# Proxmox configuration scripts
# --------------------------------------
echo -e "${YELLOW}[6/10] Running Proxmox configuration scripts${NC}"

read -p "Do you want to run storage.sh and security.sh scripts on your Proxmox server? (y/n): " run_scripts

if [ "$run_scripts" == "y" ]; then
    echo "Copying scripts to Proxmox server..."
    
    # Use expect script for SCP if password still needed
    if [ "$setup_ssh" != "y" ]; then
        if command -v expect &> /dev/null; then
            cat > /tmp/scp_scripts.exp << EOF
#!/usr/bin/expect -f
spawn scp scripts/storage.sh scripts/security.sh ${proxmox_user%@*}@${proxmox_ip}:/tmp/
expect "password:"
send "${PROXMOX_PASSWORD}\r"
expect eof
EOF
            chmod +x /tmp/scp_scripts.exp
            /tmp/scp_scripts.exp
            rm -f /tmp/scp_scripts.exp
        else
            echo -e "${YELLOW}Expect utility not found. You'll need to enter the password manually.${NC}"
            scp scripts/storage.sh scripts/security.sh ${proxmox_user%@*}@${proxmox_ip}:/tmp/
        fi
    else
        scp scripts/storage.sh scripts/security.sh ${proxmox_user%@*}@${proxmox_ip}:/tmp/
    fi
    
    echo "Running scripts on Proxmox server..."
    # Use expect script for SSH if password still needed
    if [ "$setup_ssh" != "y" ]; then
        if command -v expect &> /dev/null; then
            cat > /tmp/run_storage.exp << EOF
#!/usr/bin/expect -f
spawn ssh ${proxmox_user%@*}@${proxmox_ip} "bash /tmp/storage.sh"
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
            
            cat > /tmp/run_security.exp << EOF
#!/usr/bin/expect -f
spawn ssh ${proxmox_user%@*}@${proxmox_ip} "bash /tmp/security.sh"
expect "password:"
send "${PROXMOX_PASSWORD}\r"
expect eof
EOF
            chmod +x /tmp/run_security.exp
            /tmp/run_security.exp
            rm -f /tmp/run_security.exp
        else
            echo -e "${YELLOW}Expect utility not found. You'll need to enter passwords manually.${NC}"
            ssh ${proxmox_user%@*}@${proxmox_ip} "bash /tmp/storage.sh"
            ssh ${proxmox_user%@*}@${proxmox_ip} "bash /tmp/security.sh"
        fi
    else
        ssh ${proxmox_user%@*}@${proxmox_ip} "bash /tmp/storage.sh"
        ssh ${proxmox_user%@*}@${proxmox_ip} "bash /tmp/security.sh"
    fi
    
    echo -e "${GREEN}Proxmox configuration scripts executed.${NC}"
else
    echo "Skipping Proxmox configuration scripts."
fi

# --------------------------------------
# Check available storage and update template
# --------------------------------------
echo -e "${YELLOW}[7/10] Checking available storage on Proxmox${NC}"

# Function to run command on Proxmox via SSH
run_proxmox_command() {
    local command="$1"
    local prompt_pattern="${2:-password:}"
    local response="${3:-$PROXMOX_PASSWORD}"
    
    if [ "$setup_ssh" == "y" ]; then
        ssh ${proxmox_user%@*}@${proxmox_ip} "$command"
    else
        if command -v expect &> /dev/null; then
            cat > /tmp/run_command.exp << EOF
#!/usr/bin/expect -f
spawn ssh ${proxmox_user%@*}@${proxmox_ip} "$command"
expect "$prompt_pattern"
send "$response\r"
expect eof
EOF
            chmod +x /tmp/run_command.exp
            output=$(/tmp/run_command.exp | tail -n +2)
            rm -f /tmp/run_command.exp
            echo "$output"
        else
            echo -e "${YELLOW}Expect utility not found. Using manual method.${NC}"
            ssh ${proxmox_user%@*}@${proxmox_ip} "$command"
        fi
    fi
}

echo "Checking available storage on Proxmox server..."
STORAGE_INFO=$(run_proxmox_command "pvesm status | grep -v container | grep -v Disabled")

echo -e "${BLUE}Available storage pools on Proxmox:${NC}"
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
    echo -e "${RED}No storage pools found on Proxmox. Please create at least one storage pool.${NC}"
    exit 1
fi

# Display options and ask user to select
echo -e "${YELLOW}Please select a storage pool to use for LXC containers:${NC}"
select STORAGE_POOL in "${STORAGE_OPTIONS[@]}"; do
    if [ -n "$STORAGE_POOL" ]; then
        echo "Selected storage pool: $STORAGE_POOL"
        break
    else
        echo -e "${RED}Invalid selection. Please try again.${NC}"
    fi
done

# Determine storage type
STORAGE_TYPE=$(run_proxmox_command "pvesm status $STORAGE_POOL" | grep -v Name | awk '{print $2}')
STORAGE_POOL_TYPE="dir"  # Default

case "$STORAGE_TYPE" in
    zfspool)
        STORAGE_POOL_TYPE="zfs"
        ;;
    lvmthin)
        STORAGE_POOL_TYPE="lvm-thin"
        ;;
    dir)
        STORAGE_POOL_TYPE="dir"
        ;;
    *)
        STORAGE_POOL_TYPE="dir"  # Default fallback
        ;;
esac

echo "Storage pool type detected: $STORAGE_POOL_TYPE"

# Update template repos and check if Alpine template exists
echo -e "${YELLOW}Updating container template repositories...${NC}"
run_proxmox_command "pveam update"

# Otomatik olarak en son Alpine template'ini tespit et
echo -e "${YELLOW}Finding the latest Alpine template...${NC}"
ALPINE_TEMPLATES=$(run_proxmox_command "pveam available | grep alpine | grep -v edge | sort -V")

if [ -z "$ALPINE_TEMPLATES" ]; then
    echo -e "${RED}No Alpine templates found in repository. Please check your Proxmox repositories.${NC}"
    exit 1
fi

# En son Alpine sürümlerini göster
echo -e "${BLUE}Available Alpine templates:${NC}"
echo "$ALPINE_TEMPLATES" | tail -n 5

# En son sürümü otomatik seç (non-edge, non-RC)
ALPINE_TEMPLATE=$(echo "$ALPINE_TEMPLATES" | grep -i default | grep -v edge | grep -v rc | tail -n 1 | awk '{print $2}')

# Eğer bulunamazsa, herhangi bir Alpine sürümü seç
if [ -z "$ALPINE_TEMPLATE" ]; then
    ALPINE_TEMPLATE=$(echo "$ALPINE_TEMPLATES" | tail -n 1 | awk '{print $2}')
fi

echo -e "${GREEN}Selected latest Alpine template: $ALPINE_TEMPLATE${NC}"

# Kullanıcıya farklı bir template seçme şansı ver
read -p "Do you want to use this template or select a different one? (use/select): " template_choice

if [ "$template_choice" == "select" ]; then
    echo -e "${BLUE}Available Alpine templates:${NC}"
    echo "$ALPINE_TEMPLATES"
    
    echo -e "${YELLOW}Please enter the name of the Alpine template to use:${NC}"
    read -p "Template name: " user_template
    
    if [ -n "$user_template" ]; then
        ALPINE_TEMPLATE=$user_template
        echo -e "${GREEN}Using template: $ALPINE_TEMPLATE${NC}"
    else
        echo -e "${YELLOW}No template entered, using previously selected: $ALPINE_TEMPLATE${NC}"
    fi
fi

# Check if the template is downloaded
echo -e "${YELLOW}Checking if template is downloaded...${NC}"
TEMPLATE_DOWNLOADED=$(run_proxmox_command "pveam list $STORAGE_POOL | grep $ALPINE_TEMPLATE" || echo "")

if [ -z "$TEMPLATE_DOWNLOADED" ]; then
    echo -e "${YELLOW}Downloading Alpine template to $STORAGE_POOL...${NC}"
    run_proxmox_command "pveam download $STORAGE_POOL $ALPINE_TEMPLATE"
    
    # Make sure download was successful
    TEMPLATE_VERIFY=$(run_proxmox_command "pveam list $STORAGE_POOL | grep $ALPINE_TEMPLATE" || echo "")
    if [ -z "$TEMPLATE_VERIFY" ]; then
        echo -e "${RED}Failed to download template. Please check Proxmox logs.${NC}"
        exit 1
    fi
else
    echo -e "${GREEN}Template already downloaded.${NC}"
fi

# --------------------------------------
# Prepare environment files
# --------------------------------------
echo -e "${YELLOW}[8/10] Setting up environment files${NC}"

# Set up monitoring .env file
if [ -f docker/monitoring/.env.example ]; then
    if [ ! -f docker/monitoring/.env ]; then
        echo "Setting up monitoring environment file..."
        read -p "Enter Grafana password [$DEFAULT_GRAFANA_PASSWORD]: " grafana_password
        grafana_password=${grafana_password:-$DEFAULT_GRAFANA_PASSWORD}
        
        cp docker/monitoring/.env.example docker/monitoring/.env
        sed -i "s/secure_password_here/${grafana_password}/g" docker/monitoring/.env
        
        echo -e "${GREEN}Monitoring environment file created.${NC}"
    else
        echo "Monitoring environment file already exists."
    fi
fi

# Set up proxy .env file
if [ -f docker/proxy/.env.example ]; then
    if [ ! -f docker/proxy/.env ]; then
        echo "Setting up proxy environment file..."
        echo -e "${BLUE}The Cloudflare Tunnel Token is needed if you want to expose services to the internet.${NC}"
        echo -e "${BLUE}If you don't have one, you can leave it blank for now and update it later.${NC}"
        read -p "Enter Cloudflare Tunnel Token (can be blank): " cloudflare_token
        
        cp docker/proxy/.env.example docker/proxy/.env
        sed -i "s/your_cloudflare_tunnel_token_here/${cloudflare_token:-your_token_here}/g" docker/proxy/.env
        
        echo -e "${GREEN}Proxy environment file created.${NC}"
    else
        echo "Proxy environment file already exists."
    fi
fi

# --------------------------------------
# Fix Terraform configuration
# --------------------------------------
echo -e "${YELLOW}[9/10] Setting up Terraform configuration${NC}"

echo -e "${RED}IMPORTANT: API token authentication causes permission issues${NC}"
echo -e "${BLUE}Using direct username/password authentication which has full permissions${NC}"

# Fix variables.tf to handle both authentication methods
cat > terraform/variables.tf << EOF
# Proxmox connection variables
variable "proxmox_api_url" {
  description = "The URL of the Proxmox API"
  type        = string
}

variable "proxmox_api_token_id" {
  description = "The token ID for Proxmox API authentication"
  type        = string
  default     = ""
}

variable "proxmox_api_token_secret" {
  description = "The token secret for Proxmox API authentication"
  type        = string
  sensitive   = true
  default     = ""
}

# Username/password variables
variable "proxmox_user" {
  description = "The username for Proxmox authentication"
  type        = string
  default     = "root@pam"
}

variable "proxmox_password" {
  description = "The password for Proxmox authentication"
  type        = string
  sensitive   = true
  default     = ""
}

# Node settings
variable "target_node" {
  description = "The target Proxmox node name"
  type        = string
}

# Storage settings
variable "storage_pool" {
  description = "The storage pool to use for LXC containers"
  type        = string
  default     = "local-lvm"
}

variable "storage_pool_type" {
  description = "The type of storage pool"
  type        = string
  default     = "lvm-thin"
}

# Network settings
variable "network_bridge" {
  description = "The network bridge to use for LXC containers"
  type        = string
  default     = "vmbr0"
}

variable "private_network" {
  description = "The private network prefix (e.g., 192.168.1)"
  type        = string
  default     = "192.168.1"
}

# LXC template
variable "ostemplate" {
  description = "The OS template to use for LXC containers"
  type        = string
}

# LXC container configuration
variable "lxc_containers" {
  description = "Configuration for LXC containers"
  type = map(object({
    id       = number
    hostname = string
    ip       = string
    cores    = number
    memory   = number
    storage  = number
  }))
}
EOF

# Fix main.tf provider section to use username/password
cat > terraform/main.tf << EOF
terraform {
  required_providers {
    proxmox = {
      source = "telmate/proxmox"
      version = "2.9.14"
    }
  }
}

provider "proxmox" {
  pm_api_url = var.proxmox_api_url
  pm_user = var.proxmox_user
  pm_password = var.proxmox_password
  pm_tls_insecure = true
}

resource "proxmox_lxc" "lxc_container" {
  for_each = var.lxc_containers

  target_node = var.target_node
  vmid = each.value.id
  hostname = each.value.hostname
  ostemplate = "${var.storage_pool}:vztmpl/${var.ostemplate}"
  password = "changeme"  # Will be removed after SSH key is added
  unprivileged = true

  memory = each.value.memory
  swap = 512
  cores = each.value.cores

  rootfs {
    storage = var.storage_pool
    size = "\${each.value.storage}G"
  }

  network {
    name = "eth0"
    bridge = var.network_bridge
    ip = "\${each.value.ip}/24"
    gw = "\${var.private_network}.1"
  }

  start = true
  onboot = true

  features {
    nesting = true
    # Removed fuse = true that caused permission issues
  }

  # Only add datapool mountpoint if it exists
  dynamic "mountpoint" {
    for_each = run_command("ssh ${proxmox_user%@*}@${proxmox_ip} '[ -d /datapool ] && echo exists'") == "exists" ? [1] : []
    content {
      key = "0"
      slot = 0
      storage = "/datapool"
      mp = "/datapool"
      size = "0G"
    }
  }

  ssh_public_keys = file("~/.ssh/id_rsa.pub")

  # Install required packages and setup SSH
  provisioner "local-exec" {
    command = <<-EOT
      sleep 30
      ssh -o StrictHostKeyChecking=no root@\${each.value.ip} "apk update && \\
      apk add --no-cache openssh bash curl docker docker-compose && \\
      rc-update add sshd && \\
      rc-update add docker && \\
      rc-service sshd start && \\
      rc-service docker start"
    EOT
  }
}

output "lxc_ips" {
  value = {
    for name, container in proxmox_lxc.lxc_container : name => container.network[0].ip
  }
}
EOF

# Create terraform.tfvars with username/password and selected storage
cat > terraform/terraform.tfvars << EOF
# Proxmox connection settings
proxmox_api_url = "https://${proxmox_ip}:8006/api2/json"
proxmox_user = "${proxmox_user}"
proxmox_password = "${PROXMOX_PASSWORD}"

# Node settings
target_node = "${DEFAULT_PROXMOX_NODE}"

# Storage settings
storage_pool = "${STORAGE_POOL}"
storage_pool_type = "${STORAGE_POOL_TYPE}"

# OS template - automatically detected latest version
ostemplate = "${ALPINE_TEMPLATE}"

# Network settings
network_bridge = "vmbr0" 
private_network = "192.168.1"

# LXC containers configuration
lxc_containers = {
  "media" = {
    id = 102
    hostname = "media"
    ip = "192.168.1.102"
    cores = 4
    memory = 16384
    storage = 32
  },
  "monitoring" = {
    id = 103
    hostname = "monitoring"
    ip = "192.168.1.103"
    cores = 2
    memory = 4096
    storage = 16
  },
  "logging" = {
    id = 104
    hostname = "logging"
    ip = "192.168.1.104"
    cores = 2
    memory = 4096
    storage = 16
  },
  "proxy" = {
    id = 125
    hostname = "proxy"
    ip = "192.168.1.125"
    cores = 2
    memory = 2048
    storage = 8
  }
}
EOF

echo -e "${GREEN}Terraform configuration completely rebuilt with username/password authentication and automatically detected Alpine template.${NC}"

# --------------------------------------
# Run Terraform
# --------------------------------------
echo -e "${YELLOW}[10/10] Running Terraform${NC}"

# Fix main.tf to handle the run_command function
cat > /tmp/terraform_provider_fix.tf << EOF
# Function to run a command
locals {
  run_command_result = null
}

# Dummy resource to run commands
resource "null_resource" "command_runner" {
  triggers = {
    always_run = timestamp()
  }

  provisioner "local-exec" {
    command = "echo 'Command runner initialized'"
  }
}
EOF

# Copy the fix to the terraform directory
cp /tmp/terraform_provider_fix.tf terraform/

cd terraform
terraform init -reconfigure || {
    echo -e "${RED}Terraform initialization failed.${NC}"
    exit 1
}

echo -e "${BLUE}Terraform will now create the LXC containers on your Proxmox server.${NC}"
echo -e "${BLUE}This may take several minutes to complete.${NC}"
read -p "Press Enter to continue..." confirm

terraform apply -auto-approve || {
    echo -e "${RED}Terraform apply failed.${NC}"
    
    # Show troubleshooting help
    echo -e "${YELLOW}Terraform troubleshooting:${NC}"
    echo -e "1. You may need to manually create the LXC containers through the Proxmox UI"
    echo -e "2. After manual creation, continue with the Ansible part of this script"
    
    # Ask if they want to proceed with Ansible setup anyway
    read -p "Do you want to proceed with Ansible setup anyway (assuming containers exist)? (y/n): " proceed_ansible
    
    if [ "$proceed_ansible" != "y" ]; then
        exit 1
    fi
}
cd ..

echo -e "${GREEN}Terraform execution completed.${NC}"

# --------------------------------------
# Ansible Inventory setup
# --------------------------------------
echo -e "${YELLOW}Ansible deployment phase${NC}"

if [ ! -f ansible/inventory.ini ]; then
    echo "Setting up Ansible inventory..."
    cp ansible/inventory.ini.example ansible/inventory.ini
    echo -e "${GREEN}Ansible inventory file created.${NC}"
else
    echo "Ansible inventory file already exists."
fi

# --------------------------------------
# Run Ansible
# --------------------------------------
echo -e "${YELLOW}Running Ansible${NC}"

echo "Waiting for LXC containers to start..."
echo -e "${BLUE}This may take up to a minute...${NC}"
sleep 60

cd ansible
ansible-playbook -i inventory.ini deploy.yml || {
    echo -e "${RED}Ansible playbook execution failed.${NC}"
    exit 1
}
cd ..

echo -e "${GREEN}Ansible execution completed successfully.${NC}"

# --------------------------------------
# Final status check
# --------------------------------------
echo -e "${YELLOW}Checking container status...${NC}"

cd ansible
# Use set +e to prevent status check from stopping the script
set +e
ansible -i inventory.ini all -a "docker ps"
set -e
cd ..

echo -e "${GREEN}===== Homelab setup completed successfully! =====${NC}"
echo ""
echo "You can access your services at the following addresses:"
echo "- Media services: http://192.168.1.102:{8989,7878,6767,8096,5055,8080,9696,8191,8998}"
echo "- Monitoring: http://192.168.1.103:{9090,3000,9093,9100}"
echo "- Logging: http://192.168.1.104:{9200,5601}"
echo "- Proxy: http://192.168.1.125:{3000,80}"
echo ""
echo "Enjoy your homelab!"

exit 0
