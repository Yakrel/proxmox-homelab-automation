#!/bin/bash
# =================================================================
#         Proxmox Homelab Automation - Unified Installer & Menu
# =================================================================
# Single entry point for homelab automation.
# First run: bootstraps Ansible Control Node (LXC 151)
# Subsequent runs: management menu for homelab operations

set -e

# --- Static Configuration ---
API_USER="ansible-bot@pve"
API_TOKEN_ID="ansible-token"
REPO_URL="https://github.com/Yakrel/proxmox-homelab-automation.git"
REPO_DIR="/root/proxmox-homelab-automation"
PLAYBOOK_DIR="/root/proxmox-homelab-automation" # Inside the LXC

# Ansible Control LXC Config (matches stacks.yaml)
CONTROL_CT_ID="151"
CONTROL_HOSTNAME="lxc-ansible-control-01"
CONTROL_IP_OCTET="151"
CONTROL_CORES="2"
CONTROL_MEMORY="2048"
CONTROL_DISK="10"

# Network & Storage (Static)
NETWORK_GATEWAY="192.168.1.1"
NETWORK_BRIDGE="vmbr0"
NETWORK_IP_BASE="192.168.1"
STORAGE_POOL="datapool"

# --- Helper Functions ---
print_info() { echo -e "\033[36m[INFO]\033[0m $1"; }
print_success() { echo -e "\033[32m[SUCCESS]\033[0m $1"; }
print_error() { echo -e "\033[31m[ERROR]\033[0m $1"; }
print_warning() { echo -e "\033[33m[WARNING]\033[0m $1"; }

# Debug function to help troubleshoot API issues
debug_api_setup() {
    print_info "=== Proxmox API Setup Diagnostics ==="
    
    print_info "Checking API user '$API_USER'..."
    if pveum user list 2>/dev/null | grep -q "^$API_USER"; then
        print_success "API user exists"
    else
        print_error "API user not found"
        return 1
    fi
    
    print_info "Checking user permissions..."
    if pveum acl list / 2>/dev/null | grep -q "$API_USER.*Administrator"; then
        print_success "User has Administrator role"
    else
        print_warning "User may not have Administrator role"
    fi
    
    print_info "Testing token operations..."
    local existing_tokens
    existing_tokens=$(pveum user token list "$API_USER" 2>/dev/null | wc -l)
    print_info "Existing tokens for user: $((existing_tokens - 1))"
    
    print_info "=== Diagnostics complete ==="
}

ensure_repository_exists_and_update() {
    # Ensure repository is always a perfect mirror of the remote branch.
    # This uses git reset --hard to handle force pushes and prevent local change conflicts.
    print_info "Ensuring repository is up-to-date..."

    local git_update_script="
        set -e
        if [ -d '$REPO_DIR/.git' ]; then
            echo '[INFO] Repository exists. Fetching and resetting to origin/main...'
            cd '$REPO_DIR'
            git fetch origin main
            git reset --hard origin/main
            git clean -fdx
        else
            echo '[INFO] Repository not found. Cloning fresh...'
            rm -rf '$REPO_DIR'
            git clone '$REPO_URL' '$REPO_DIR'
        fi
    "
    pct exec "$CONTROL_CT_ID" -- bash -c "$git_update_script"
    print_success "Repository is synchronized with origin/main."
}



ensure_template_available() {
    # Ensure template is available - simplified approach
    local template_type="$1"
    local pattern=""
    
    case "$template_type" in
        "alpine") pattern="alpine-.*-default" ;;
        "debian") pattern="debian-.*-standard" ;;
        *) print_error "Unknown template type: $template_type"; return 1 ;;
    esac
    
    # Check for existing template
    local local_template=$(pveam list "$STORAGE_POOL" | awk "/$pattern/ {print \$1}" | sort -V | tail -n 1)
    
    if [ -z "$local_template" ]; then
        # Download latest available template
        local latest_available=$(pveam available | awk "/$pattern/ {print \$NF}" | sort -V | tail -n 1)
        print_info "Downloading $latest_available..."
        pveam download "$STORAGE_POOL" "$latest_available"
        local_template=$(pveam list "$STORAGE_POOL" | awk "/$pattern/ {print \$1}" | sort -V | tail -n 1)
    fi
    
    echo "$local_template"
}

# --- Helper Functions ---

get_current_api_token() {
    # Create or recreate token and return its secret
    print_info "Managing API token '$API_TOKEN_ID'..."

    # Verify API user exists first
    if ! pveum user list 2>/dev/null | awk -v u="$API_USER" '$1==u { found=1 } END { exit !found }'; then
        print_error "API user '$API_USER' not found. Please run first-time setup."
        return 1
    fi

    # Remove existing token if present (with better error handling)
    print_info "Checking for existing tokens..."
    if pveum user token list "$API_USER" 2>/dev/null | awk -v t="$API_TOKEN_ID" '$1==t { found=1 } END { exit !found }'; then
        print_info "Removing existing token '$API_TOKEN_ID'..."
        if ! pveum user token delete "$API_USER" "$API_TOKEN_ID" 2>/dev/null; then
            print_warning "Could not delete existing token (may not exist anymore)"
        fi
    fi

    # Create new token with detailed error handling
    print_info "Creating new API token..."
    local TOKEN_OUTPUT
    if ! TOKEN_OUTPUT=$(pveum user token add "$API_USER" "$API_TOKEN_ID" --comment "Token for Ansible automation" 2>&1); then
        print_error "Failed to create API token:"
        print_error "Command output: $TOKEN_OUTPUT"
        print_error "User: $API_USER, Token ID: $API_TOKEN_ID"
        return 1
    fi

    print_info "Token creation output received, extracting secret..."
    
    # Extract UUID-style secret with improved regex and debugging
    local TOKEN_SECRET
    TOKEN_SECRET=$(echo "$TOKEN_OUTPUT" | grep -oE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' | head -1)

    if [ -z "$TOKEN_SECRET" ]; then
        print_error "Failed to extract token secret from output:"
        print_error "Raw output: $TOKEN_OUTPUT"
        # Try alternative extraction methods
        print_info "Attempting alternative token extraction..."
        TOKEN_SECRET=$(echo "$TOKEN_OUTPUT" | grep -i "value" | grep -oE '[0-9a-f-]{36}' | head -1)
        if [ -z "$TOKEN_SECRET" ]; then
            print_error "All token extraction methods failed"
            return 1
        fi
    fi

    print_success "Token extracted successfully: ${TOKEN_SECRET:0:8}..."
    echo "$TOKEN_SECRET"
}

run_ansible_playbook() {
    local playbook_command="$1"
    
    print_info "Preparing to run playbook: $playbook_command"
    
    # Verify Control Node is accessible
    if ! pct status "$CONTROL_CT_ID" | grep -q "status: running"; then
        print_error "Control Node (LXC $CONTROL_CT_ID) is not running"
        return 1
    fi
    
    # Get API token for this session (capture stderr for diagnostics)
    local CURRENT_TOKEN_SECRET
    local TOKEN_ERR_FILE
    TOKEN_ERR_FILE=$(mktemp)
    print_info "Generating API token for Proxmox communication..."
    
    if ! CURRENT_TOKEN_SECRET=$(get_current_api_token 2>"$TOKEN_ERR_FILE"); then
        print_error "Failed to get API token. Playbook execution aborted."
        print_error "This prevents Ansible from communicating with the Proxmox API."
        
        # Show detailed error information
        if [ -s "$TOKEN_ERR_FILE" ]; then
            print_error "Detailed error output:"
            sed 's/^/    /' "$TOKEN_ERR_FILE" | sed -n '1,200p'
        fi
        
        print_error "Troubleshooting steps:"
        print_error "1. Ensure you have Administrator privileges on Proxmox"
        print_error "2. Check if user '$API_USER' exists: pveum user list"
        print_error "3. Verify token operations: pveum user token list '$API_USER'"
        
        rm -f "$TOKEN_ERR_FILE"
        return 1
    fi
    rm -f "$TOKEN_ERR_FILE"
    
    print_success "API token generated successfully"
    
    # For deployment commands, ensure required template is available
    if [[ "$playbook_command" =~ deploy\.yml ]]; then
        local stack_name=$(echo "$playbook_command" | sed -n "s/.*stack_name=\([^']*\).*/\1/p")
        if [ -n "$stack_name" ]; then
            print_info "Preparing template for stack: $stack_name"
            
            # Determine template type based on stack
            local template_type="alpine"
            if [ "$stack_name" = "ansible_control" ] || [ "$stack_name" = "backup" ]; then
                template_type="debian"
            fi
            
            # Ensure template is available
            local template_name
            if ! template_name=$(ensure_template_available "$template_type"); then
                print_error "Failed to prepare required template for stack '$stack_name'"
                return 1
            fi
            print_success "Template ready: $template_name"
            playbook_command="${playbook_command} --extra-vars 'lxc_template=$template_name'"
        fi
    fi
    
    print_info "Executing playbook inside Control Node..."
    
    # Check vault password file for easier UX
    local vault_param="--ask-vault-pass"
    if pct exec "$CONTROL_CT_ID" -- test -f /root/.vault_pass; then
        vault_param="--vault-password-file /root/.vault_pass"
        print_info "Using stored vault password"
    else
        print_info "Will prompt for vault password"
    fi

    # Test token accessibility before running ansible
    print_info "Verifying token can be passed to Control Node..."
    if ! pct exec "$CONTROL_CT_ID" -- bash -c "echo 'Token length: \${#PROXMOX_API_TOKEN_SECRET}'" PROXMOX_API_TOKEN_SECRET="$CURRENT_TOKEN_SECRET" >/dev/null 2>&1; then
        print_error "Failed to pass token to Control Node"
        return 1
    fi

    # Execute the command with improved error handling
    print_info "Running: cd $PLAYBOOK_DIR && ansible-playbook [options] $playbook_command"
    if ! pct exec "$CONTROL_CT_ID" -- bash -l -c "cd $PLAYBOOK_DIR && PROXMOX_API_TOKEN_SECRET='$CURRENT_TOKEN_SECRET' ansible-playbook $vault_param --extra-vars 'proxmox_api_token_secret=$CURRENT_TOKEN_SECRET' $playbook_command"; then
        print_error "Ansible playbook execution failed"
        return 1
    fi
    
    print_success "Playbook execution completed successfully"
}

# --- Core Functions ---

run_first_time_setup() {
    print_info "Starting first-time setup..."

    # Step 1: Create Proxmox API User
    print_info "Ensuring Proxmox API user '$API_USER' exists..."
    
    # Check if user exists with better error handling
    if ! pveum user list 2>/dev/null | awk -v u="$API_USER" '$1==u { found=1 } END { exit !found }'; then
        print_info "Creating API user '$API_USER'..."
        
        # Create user with proper error handling
        if ! pveum user add "$API_USER" --comment "Ansible Automation User" 2>/dev/null; then
            print_error "Failed to create user '$API_USER'"
            print_error "Please check Proxmox permissions and try again"
            exit 1
        fi
        
        # Set Administrator role with error handling  
        if ! pveum acl modify / --user "$API_USER" --role Administrator 2>/dev/null; then
            print_error "Failed to set Administrator role for '$API_USER'"
            print_error "Please manually assign Administrator role to this user"
            exit 1
        fi
        
        print_success "User '$API_USER' created and configured with Administrator role."
    else
        print_success "User '$API_USER' already exists."
        
        # Verify the user has Administrator role
        print_info "Verifying user permissions..."
        if pveum acl list / 2>/dev/null | grep -q "$API_USER.*Administrator"; then
            print_success "User has Administrator role confirmed."
        else
            print_warning "User may not have Administrator role. Attempting to set it..."
            pveum acl modify / --user "$API_USER" --role Administrator 2>/dev/null || \
                print_warning "Could not verify/set Administrator role. Manual intervention may be needed."
        fi
    fi

    # Step 2: Create Control LXC
    if pct status "$CONTROL_CT_ID" >/dev/null 2>&1; then
        print_info "Control LXC already exists. Ensuring it's running..."
        pct start "$CONTROL_CT_ID" 2>/dev/null || true
        sleep 5
    else
        print_info "Creating Control LXC ($CONTROL_CT_ID)..."
        
        local LATEST_DEBIAN_TEMPLATE
        LATEST_DEBIAN_TEMPLATE=$(ensure_template_available "debian")
        
        local CONTROL_IP_CIDR="$NETWORK_IP_BASE.$CONTROL_IP_OCTET/24"
        pct create "$CONTROL_CT_ID" "$LATEST_DEBIAN_TEMPLATE" \
            --hostname "$CONTROL_HOSTNAME" --storage "$STORAGE_POOL" \
            --cores "$CONTROL_CORES" --memory "$CONTROL_MEMORY" --swap 0 \
            --features keyctl=1,nesting=1 \
            --net0 name=eth0,bridge=$NETWORK_BRIDGE,ip=$CONTROL_IP_CIDR,gw=$NETWORK_GATEWAY \
            --mp0 "${STORAGE_POOL}:0,mp=/datapool,backup=0" \
            --onboot 1 --unprivileged 1 --rootfs "${STORAGE_POOL}:${CONTROL_DISK}"
        
        pct start "$CONTROL_CT_ID"
        sleep 10
    fi

    # Step 3: Provision Control Node
    print_info "Provisioning Control Node..."

    # Configure autologin
    pct exec "$CONTROL_CT_ID" -- systemctl disable getty@tty1.service 2>/dev/null || true
    pct exec "$CONTROL_CT_ID" -- passwd -d root
    pct exec "$CONTROL_CT_ID" -- mkdir -p /etc/systemd/system/getty@tty1.service.d
    pct exec "$CONTROL_CT_ID" -- bash -c "cat > /etc/systemd/system/getty@tty1.service.d/override.conf << 'EOF'
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin root --noclear %I \$TERM
EOF"
    pct exec "$CONTROL_CT_ID" -- systemctl daemon-reload
    pct exec "$CONTROL_CT_ID" -- systemctl enable getty@tty1.service

    # Install packages
    pct exec "$CONTROL_CT_ID" -- apt-get update
    pct exec "$CONTROL_CT_ID" -- apt-get install -y git python3-pip locales
    pct exec "$CONTROL_CT_ID" -- pip3 install --break-system-packages ansible proxmoxer
    
    # Configure environment
    pct exec "$CONTROL_CT_ID" -- bash -c 'echo "export PATH=\"/usr/local/bin:\$PATH\"" >> /root/.bashrc'
    pct exec "$CONTROL_CT_ID" -- locale-gen en_US.UTF-8

    # Setup repository
    ensure_repository_exists_and_update
    
    # Install Ansible collections
    pct exec "$CONTROL_CT_ID" -- bash -c 'export PATH="/usr/local/bin:$PATH" && ansible-galaxy collection install community.general community.proxmox community.docker'
    
    # Verify secrets file
    if pct exec "$CONTROL_CT_ID" -- test -f "/root/proxmox-homelab-automation/secrets.yml"; then
        if pct exec "$CONTROL_CT_ID" -- head -1 "/root/proxmox-homelab-automation/secrets.yml" | grep -q "ANSIBLE_VAULT"; then
            print_success "Encrypted secrets.yml found."
        else
            print_error "secrets.yml exists but is not encrypted!"
            exit 1
        fi
    else
        print_error "secrets.yml not found in repository!"
        exit 1
    fi

    print_success "First-time setup complete! Re-run this script to access the management menu."
    exit 0
}

show_game_server_menu() {
    while true; do
        clear
        cat << EOF
===============================================
          Game Server Management
===============================================

Game Server Options:
  1) Deploy Base Stack (LXC + Watchtower)
  2) Deploy Satisfactory Server
  3) Deploy Palworld Server
  4) Stop All Game Servers
  5) Switch Game (Stop Current, Start Another)

B) Back to Main Menu

EOF

        read -p "Enter your choice [1-5, B]: " choice

        case $choice in
            1)
                print_info "Deploying Game Servers Base Stack (LXC + Watchtower)..."
                if run_ansible_playbook "deploy.yml --extra-vars 'stack_name=gameservers'"; then
                    print_success "Base stack deployed successfully!"
                    print_info "You can now deploy individual game servers."
                else
                    print_error "Base stack deployment failed!"
                fi
                ;;
            2)
                print_info "Deploying Satisfactory Server..."
                if run_ansible_playbook "deploy.yml --extra-vars 'stack_name=gameservers game_name=satisfactory'"; then
                    print_success "Satisfactory server deployed successfully!"
                    print_info "Server accessible at: 192.168.1.105:7777"
                else
                    print_error "Satisfactory server deployment failed!"
                fi
                ;;
            3)
                print_info "Deploying Palworld Server..."
                if run_ansible_playbook "deploy.yml --extra-vars 'stack_name=gameservers game_name=palworld'"; then
                    print_success "Palworld server deployed successfully!"
                    print_info "Server accessible at: 192.168.1.105:8211"
                else
                    print_error "Palworld server deployment failed!"
                fi
                ;;
            4)
                print_info "Stopping all game servers..."
                print_info "Note: This will stop game servers but keep Watchtower running."
                read -p "Are you sure? (y/N): " confirm
                if [[ $confirm =~ ^[Yy] ]]; then
                    if run_ansible_playbook "deploy.yml --extra-vars 'stack_name=gameservers game_name=stop_all'"; then
                        print_success "All game servers stopped successfully!"
                    else
                        print_error "Failed to stop game servers!"
                    fi
                else
                    print_info "Operation cancelled."
                fi
                ;;
            5)
                print_info "Game Switching Menu:"
                echo "  1) Stop all games, start Satisfactory"
                echo "  2) Stop all games, start Palworld"  
                echo "  3) Just stop all games"
                read -p "Choose switch option [1-3]: " switch_choice
                
                case $switch_choice in
                    1)
                        print_info "Switching to Satisfactory..."
                        run_ansible_playbook "deploy.yml --extra-vars 'stack_name=gameservers game_name=stop_all'" && \
                        run_ansible_playbook "deploy.yml --extra-vars 'stack_name=gameservers game_name=satisfactory'"
                        ;;
                    2)
                        print_info "Switching to Palworld..."
                        run_ansible_playbook "deploy.yml --extra-vars 'stack_name=gameservers game_name=stop_all'" && \
                        run_ansible_playbook "deploy.yml --extra-vars 'stack_name=gameservers game_name=palworld'"
                        ;;
                    3)
                        print_info "Stopping all games..."
                        run_ansible_playbook "deploy.yml --extra-vars 'stack_name=gameservers game_name=stop_all'"
                        ;;
                    *)
                        print_warning "Invalid switch option."
                        ;;
                esac
                ;;
            [Bb])
                return
                ;;
            *)
                print_warning "Invalid option. Please try again."
                ;;
        esac
        print_info "Operation finished. Press Enter to continue..."
        read
    done
}

show_management_menu() {
    # On subsequent runs, update the repo before showing the menu
    print_info "Updating repository in Control Node..."
    ensure_repository_exists_and_update
    
    while true; do
        clear
        cat << EOF

=================================================
       Proxmox Homelab Automation - Main Menu
=================================================

  1) Configure Proxmox Host (Timezone, Security, etc.)
  2) Deploy Proxy Stack
  3) Deploy Monitoring Stack
  4) Deploy Media Stack
  5) Deploy Files Stack
  6) Deploy Webtools Stack
  7) Deploy Backup Stack

Game Servers:
  9) Game Server Management

Q) Quit

EOF

        read -p "Enter your choice [1-9, Q]: " choice

        case $choice in
            1)
                print_info "Running Proxmox Host Setup..."
                run_ansible_playbook "setup-host.yml"
                ;;
            2)
                print_info "Deploying Proxy Stack..."
                run_ansible_playbook "deploy.yml --extra-vars 'stack_name=proxy'"
                ;;
            3)
                print_info "Deploying Monitoring Stack..."
                run_ansible_playbook "deploy.yml --extra-vars 'stack_name=monitoring'"
                ;;
            4)
                print_info "Deploying Media Stack..."
                run_ansible_playbook "deploy.yml --extra-vars 'stack_name=media'"
                ;;
            5)
                print_info "Deploying Files Stack..."
                run_ansible_playbook "deploy.yml --extra-vars 'stack_name=files'"
                ;;
            6)
                print_info "Deploying Webtools Stack..."
                run_ansible_playbook "deploy.yml --extra-vars 'stack_name=webtools'"
                ;;
            7)
                print_info "Deploying Backup Stack..."
                run_ansible_playbook "deploy.yml --extra-vars 'stack_name=backup'"
                ;;
            9)
                show_game_server_menu
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
    if ! pct status "$CONTROL_CT_ID" | grep -q "status: running"; then
        print_info "Starting Control Node ($CONTROL_CT_ID)..."
        pct start "$CONTROL_CT_ID"
        sleep 5
    fi
    show_management_menu
fi