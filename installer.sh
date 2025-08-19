#!/bin/bash
# =================================================================
#         Proxmox Homelab Automation - Unified Installer & Menu
# =================================================================
# This script is the single entry point for the entire automation.
# - On first run, it bootstraps the Ansible Control Node (LXC 151).
# - On subsequent runs, it acts as a menu to manage the homelab.

set -e

# --- Configuration ---
API_USER="ansible-bot@pve"
API_TOKEN_ID="ansible-token"
REPO_URL="https://github.com/Yakrel/proxmox-homelab-automation.git"
REPO_DIR="/root/proxmox-homelab-automation"
PLAYBOOK_DIR="/root/proxmox-homelab-automation" # Inside the LXC

# Control LXC Config
CONTROL_CT_ID="151"
CONTROL_HOSTNAME="lxc-ansible-control"
CONTROL_IP_OCTET="151"
CONTROL_CORES="2"
CONTROL_MEMORY="2048"
CONTROL_DISK="10"

# General Config
NETWORK_GATEWAY="192.168.1.1"
NETWORK_BRIDGE="vmbr0"
NETWORK_IP_BASE="192.168.1"
STORAGE_POOL="datapool"
PROXMOX_NODE="pve01"

# --- Helper Functions ---
print_info() { echo -e "\033[36m[INFO]\033[0m $1"; }
print_success() { echo -e "\033[32m[SUCCESS]\033[0m $1"; }
print_error() { echo -e "\033[31m[ERROR]\033[0m $1"; }
print_warning() { echo -e "\033[33m[WARNING]\033[0m $1"; }

# --- Core Functions ---

run_first_time_setup() {
    print_info "Ansible Control LXC not found. Starting first-time setup..."

    # Step 1: Create Proxmox API User and Token
    print_info "Ensuring Proxmox API user '$API_USER' exists..."
    if ! pveum user show "$API_USER" >/dev/null 2>&1; then
        if ! pveum user add "$API_USER" --comment "Ansible Automation User" 2>/dev/null; then
            print_warning "User creation failed - user '$API_USER' may already exist."
        fi
        if ! pveum acl modify / --user "$API_USER" --role Administrator 2>/dev/null; then
            print_warning "ACL modification failed - permissions may already be set."
        fi
        print_success "User '$API_USER' configured."
    else
        print_success "User '$API_USER' already exists."
    fi

    print_info "Ensuring API token '$API_TOKEN_ID' exists for user '$API_USER'..."
    local TOKEN_SECRET=""
    if ! pveum user token list "$API_USER" | grep -q "tokenid=$API_TOKEN_ID"; then
        local TOKEN_OUTPUT
        TOKEN_OUTPUT=$(pveum user token add "$API_USER" "$API_TOKEN_ID" --comment "Token for Ansible automation")
        TOKEN_SECRET=$(echo "$TOKEN_OUTPUT" | sed -n 's/.*secret: *\(.*\)/\1/p')
        [ -z "$TOKEN_SECRET" ] && { print_error "Failed to extract token secret."; exit 1; }
        print_success "Token '$API_TOKEN_ID' created and secret captured."
    else
        print_warning "Token '$API_TOKEN_ID' already exists. Cannot retrieve secret."
        print_warning "Removing existing token to create a new one with known secret..."
        pveum user token remove "$API_USER" "$API_TOKEN_ID" 2>/dev/null || true
        local TOKEN_OUTPUT
        TOKEN_OUTPUT=$(pveum user token add "$API_USER" "$API_TOKEN_ID" --comment "Token for Ansible automation")
        TOKEN_SECRET=$(echo "$TOKEN_OUTPUT" | sed -n 's/.*secret: *\(.*\)/\1/p')
        [ -z "$TOKEN_SECRET" ] && { print_error "Failed to extract token secret."; exit 1; }
        print_success "Token '$API_TOKEN_ID' recreated and secret captured."
    fi

    # Step 2: Create and Provision Control LXC
    print_info "Creating Ansible Control LXC ($CONTROL_CT_ID)..."
    local LATEST_DEBIAN_TEMPLATE
    LATEST_DEBIAN_TEMPLATE=$(pveam list "$STORAGE_POOL" | awk '/debian-.*-standard/ {print $1}' | sort -V | tail -n 1)
    if [ -z "$LATEST_DEBIAN_TEMPLATE" ]; then
        print_warning "No local Debian template found; downloading..."
        local DOWNLOAD_TEMPLATE
        DOWNLOAD_TEMPLATE=$(pveam available | awk '/debian-[0-9.]+(-[0-9]+)?-standard/ {print $NF}' | sort -V | tail -n 1)
        pveam download "$STORAGE_POOL" "$DOWNLOAD_TEMPLATE"
        LATEST_DEBIAN_TEMPLATE=$(pveam list "$STORAGE_POOL" | awk '/debian-.*-standard/ {print $1}' | sort -V | tail -n 1)
    fi
    print_success "Using Debian template: $LATEST_DEBIAN_TEMPLATE"

    local CONTROL_IP_CIDR="$NETWORK_IP_BASE.$CONTROL_IP_OCTET/24"
    pct create "$CONTROL_CT_ID" "$LATEST_DEBIAN_TEMPLATE" \
        --hostname "$CONTROL_HOSTNAME" --storage "$STORAGE_POOL" \
        --cores "$CONTROL_CORES" --memory "$CONTROL_MEMORY" --swap 0 \
        --features keyctl=1,nesting=1 \
        --net0 name=eth0,bridge=$NETWORK_BRIDGE,ip=$CONTROL_IP_CIDR,gw=$NETWORK_GATEWAY \
        --onboot 1 --unprivileged 1 --rootfs "${STORAGE_POOL}:${CONTROL_DISK}"
    
    pct start "$CONTROL_CT_ID"
    print_info "Waiting for container to boot..."
    sleep 10

    # Step 3: Provision Control Node with Ansible and Git
    print_info "Provisioning Control Node with Ansible, Git, and credentials..."
    pct exec "$CONTROL_CT_ID" -- apt-get update
    pct exec "$CONTROL_CT_ID" -- apt-get install -y git ansible python3-pip
    pct exec "$CONTROL_CT_ID" -- pip3 install proxmoxer
    pct exec "$CONTROL_CT_ID" -- git clone "$REPO_URL" "$REPO_DIR"
    
    # Install required Ansible collections
    print_info "Installing required Ansible collections..."
    pct exec "$CONTROL_CT_ID" -- ansible-galaxy collection install community.general community.proxmox community.docker
    
    # Inject credentials into a vault file
    local VAULT_CONTENT
    VAULT_CONTENT=$(cat <<EOF
proxmox_api_user: $API_USER
proxmox_api_token_id: $API_TOKEN_ID
proxmox_api_token_secret: $TOKEN_SECRET
proxmox_node: $PROXMOX_NODE
EOF
)
    # Use pct push to create the file
    echo "$VAULT_CONTENT" | pct push "$CONTROL_CT_ID" - "/root/proxmox-homelab-automation/secrets.yml"

    print_warning "It is highly recommended to encrypt the new secrets.yml file."
    print_warning "Run this command from the host: pct exec $CONTROL_CT_ID -- ansible-vault encrypt $PLAYBOOK_DIR/secrets.yml"

    print_success "================================================="
    print_success "  First-time setup complete!"
    print_success "  Re-run this script to access the management menu."
    print_success "================================================="
    exit 0
}

show_management_menu() {
    # On subsequent runs, update the repo before showing the menu
    print_info "Updating repository in Control Node..."
    pct exec "$CONTROL_CT_ID" -- bash -c "cd $REPO_DIR && git pull"
    
    while true; do
        clear
        cat << EOF

[1;36m=================================================[0m
[1;37m       Proxmox Homelab Automation - Main Menu[0m
[1;36m=================================================[0m

[1;33mHost Management:[0m
  [1;32m1[0m) Configure Proxmox Host (Timezone, Security, etc.)

[1;33mDeploy Stacks:[0m
  [1;32m2[0m) Deploy Proxy Stack
  [1;32m3[0m) Deploy Monitoring Stack
  [1;32m4[0m) Deploy Media Stack
  [1;32m5[0m) Deploy Files Stack
  [1;32m6[0m) Deploy Webtools Stack
  [1;32m7[0m) Deploy Development Stack
  [1;32m8[0m) Deploy Backup Stack

[1;31mQ[0m) Quit

EOF

        read -p "Enter your choice [1-8, Q]: " choice

        case $choice in
            1)
                print_info "Running Proxmox Host Setup..."
                pct exec "$CONTROL_CT_ID" -- ansible-playbook "$PLAYBOOK_DIR/setup-host.yml"
                ;;
            2)
                print_info "Deploying Proxy Stack..."
                pct exec "$CONTROL_CT_ID" -- ansible-playbook "$PLAYBOOK_DIR/deploy.yml" --extra-vars "stack_name=proxy"
                ;;
            3)
                print_info "Deploying Monitoring Stack..."
                pct exec "$CONTROL_CT_ID" -- ansible-playbook "$PLAYBOOK_DIR/deploy.yml" --extra-vars "stack_name=monitoring"
                ;;
            4)
                print_info "Deploying Media Stack..."
                pct exec "$CONTROL_CT_ID" -- ansible-playbook "$PLAYBOOK_DIR/deploy.yml" --extra-vars "stack_name=media"
                ;;
            5)
                print_info "Deploying Files Stack..."
                pct exec "$CONTROL_CT_ID" -- ansible-playbook "$PLAYBOOK_DIR/deploy.yml" --extra-vars "stack_name=files"
                ;;
            6)
                print_info "Deploying Webtools Stack..."
                pct exec "$CONTROL_CT_ID" -- ansible-playbook "$PLAYBOOK_DIR/deploy.yml" --extra-vars "stack_name=webtools"
                ;;
            7)
                print_info "Deploying Development Stack..."
                pct exec "$CONTROL_CT_ID" -- ansible-playbook "$PLAYBOOK_DIR/deploy.yml" --extra-vars "stack_name=development"
                ;;
            8)
                print_info "Deploying Backup Stack..."
                pct exec "$CONTROL_CT_ID" -- ansible-playbook "$PLAYBOOK_DIR/deploy.yml" --extra-vars "stack_name=backup"
                ;;
            [Qq])
                echo "Exiting..."
                exit 0
                ;;
            *)
                print_warning "Invalid option. Please try again."
                ;;
        esac
        print_info "Operation finished. Press Enter to return to the menu..."
        read
    done
}

# --- Main Execution ---
if ! pct status "$CONTROL_CT_ID" >/dev/null 2>&1; then
    run_first_time_setup
else
    # Ensure container is running before showing menu
    if ! pct status "$CONTROL_CT_ID" | grep -q "status: running"; then
        print_info "Control Node ($CONTROL_CT_ID) is stopped. Starting..."
        pct start "$CONTROL_CT_ID"
        sleep 5
    fi
    show_management_menu
fi
