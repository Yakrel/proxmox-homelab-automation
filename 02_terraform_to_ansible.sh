#!/bin/bash
# This script converts Terraform outputs to Ansible inventory

set -e

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

PROJECT_DIR=$(pwd)

# Function to check terraform state
check_terraform_state() {
  echo -e "${GREEN}🔄 Creating Ansible Inventory...${NC}"

  # Change to Terraform directory
  cd "${PROJECT_DIR}/terraform"

  # Check terraform state
  if [ ! -f terraform.tfstate ]; then
      echo -e "${RED}❌ Terraform state file not found!${NC}"
      echo -e "${YELLOW}Please run 'terraform apply' first.${NC}"
      return 1
  fi
  
  return 0
}

# Function to get terraform outputs
get_terraform_outputs() {
  echo -e "${GREEN}🔄 Getting Terraform outputs...${NC}"
  
  # Try multiple times if the first attempt fails (sometimes outputs aren't ready)
  local attempts=0
  local max_attempts=3
  
  while [ $attempts -lt $max_attempts ]; do
    if terraform output -json lxc_containers > "${PROJECT_DIR}/containers.json" 2>/dev/null; then
      break
    fi
    attempts=$((attempts+1))
    echo -e "${YELLOW}⚠️ Terraform output attempt $attempts failed, retrying...${NC}"
    sleep 5
  done
  
  # Check if the command ultimately succeeded
  if [ $attempts -eq $max_attempts ]; then
    echo -e "${RED}❌ Failed to get Terraform outputs after $max_attempts attempts!${NC}" 
    echo -e "${YELLOW}Creating a basic inventory from the container definitions...${NC}"
    
    # Create a basic inventory if Terraform output fails
    create_fallback_inventory
    return 1
  fi

  # Check if output file exists and is not empty
  if [ ! -s "${PROJECT_DIR}/containers.json" ]; then
      echo -e "${RED}❌ Terraform output is empty or could not be created.${NC}"
      echo -e "${YELLOW}Creating a basic inventory from the container definitions...${NC}"
      
      # Create a basic inventory if Terraform output is empty
      create_fallback_inventory
      return 1
  fi
  
  return 0
}

# Fallback function to create inventory without Terraform output
create_fallback_inventory() {
  echo -e "${YELLOW}Creating fallback inventory file...${NC}"
  
  {
    echo "[proxy]"
    echo "lxc-proxy-01 ansible_host=192.168.1.125"
    echo ""
    echo "[media]"
    echo "lxc-media-01 ansible_host=192.168.1.102"
    echo ""
    echo "[monitoring]"
    echo "lxc-monitoring-01 ansible_host=192.168.1.103"
    echo ""
    echo "[logging]"
    echo "lxc-logging-01 ansible_host=192.168.1.104"
    echo ""
    echo "[lxc:children]"
    echo "proxy"
    echo "media"
    echo "monitoring"
    echo "logging"
    echo ""
    echo "[lxc:vars]"
    echo "ansible_user=root"
    echo "ansible_ssh_common_args='-o StrictHostKeyChecking=no -o ConnectTimeout=30'"
  } > "${PROJECT_DIR}/ansible/inventory/all"
  
  echo -e "${GREEN}✅ Basic inventory file created at: ${PROJECT_DIR}/ansible/inventory/all${NC}"
}

# Function to wait for SSH
wait_for_ssh() {
    local host=$1
    local max_attempts=30
    local delay=5
    local attempt=1

    echo -e "  ${YELLOW}🖥️ Checking SSH connectivity for $host...${NC}"
    while [ $attempt -le $max_attempts ]; do
        if nc -z -w5 $host 22 &> /dev/null; then
            echo -e "  ${GREEN}✅ $host SSH ready! (attempt $attempt)${NC}"
            return 0
        fi
        echo -e "  ${YELLOW}⏳ $host not ready yet, waiting... ($attempt/$max_attempts)${NC}"
        sleep $delay
        attempt=$((attempt+1))
    done
    
    echo -e "  ${RED}❌ SSH timeout for $host! Manual check required.${NC}"
    return 1
}

# Function to create inventory file
create_inventory_file() {
  echo -e "${GREEN}📝 Creating Ansible inventory...${NC}"

  # Create base inventory file
  {
  echo "[proxy]"
  jq -r '.["lxc-proxy-01"].ip' "${PROJECT_DIR}/containers.json" | cut -d'/' -f1 | awk '{print "lxc-proxy-01 ansible_host="$1}'
  echo ""
  echo "[media]"
  jq -r '.["lxc-media-01"].ip' "${PROJECT_DIR}/containers.json" | cut -d'/' -f1 | awk '{print "lxc-media-01 ansible_host="$1}'
  echo ""
  echo "[monitoring]"
  jq -r '.["lxc-monitoring-01"].ip' "${PROJECT_DIR}/containers.json" | cut -d'/' -f1 | awk '{print "lxc-monitoring-01 ansible_host="$1}'
  echo ""
  echo "[logging]"
  jq -r '.["lxc-logging-01"].ip' "${PROJECT_DIR}/containers.json" | cut -d'/' -f1 | awk '{print "lxc-logging-01 ansible_host="$1}'
  echo ""
  echo "[lxc:children]"
  echo "proxy"
  echo "media"
  echo "monitoring"
  echo "logging"
  echo ""
  echo "[lxc:vars]"
  echo "ansible_user=root"
  echo "ansible_ssh_common_args='-o StrictHostKeyChecking=no -o ConnectTimeout=30'"
  } > "${PROJECT_DIR}/ansible/inventory/all"

  return 0
}

# Main execution flow
main() {
  # Create inventory directory
  mkdir -p "${PROJECT_DIR}/ansible/inventory"

  # Check terraform state
  check_terraform_state || {
    # If terraform state check fails, create a fallback inventory and exit
    create_fallback_inventory
    exit 0
  }

  # Get terraform outputs
  get_terraform_outputs || {
    # Function already creates a fallback inventory on failure
    exit 0
  }

  # Extract all IP addresses
  CONTAINER_IPS=($(jq -r '.[] | .ip' "${PROJECT_DIR}/containers.json" | cut -d'/' -f1))

  if [ ${#CONTAINER_IPS[@]} -eq 0 ]; then
      echo -e "${RED}❌ Failed to get IP addresses from Terraform output!${NC}"
      echo -e "${YELLOW}Please check the containers.json file.${NC}"
      create_fallback_inventory
      exit 0
  fi

  # Wait for containers to boot and SSH to be available
  echo -e "${GREEN}🔄 Waiting for containers to complete boot process...${NC}"

  # Check connectivity for each IP
  for host in "${CONTAINER_IPS[@]}"; do
      wait_for_ssh $host
  done

  # Create inventory file
  create_inventory_file || {
    create_fallback_inventory
    exit 0
  }

  # Cleanup
  rm "${PROJECT_DIR}/containers.json"

  echo -e "${GREEN}✅ Ansible inventory successfully created: ${PROJECT_DIR}/ansible/inventory/all${NC}"
  echo -e "${YELLOW}You can now run the Ansible playbook:${NC}"
  echo -e "${GREEN}cd ${PROJECT_DIR}/ansible && ansible-playbook -i inventory/all playbook.yml${NC}"
}

# Run the main function
main