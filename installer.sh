#!/bin/bash
# =================================================================
#         Proxmox Homelab Automation - Unified Installer & Menu
# =================================================================
# This script is the single entry point for the entire automation.
# - On first run, it bootstraps the Ansible Control Node (LXC 151).
# - On subsequent runs, it acts as a menu to manage the homelab.
# All configuration is hardcoded for homelab simplicity and consistency.

set -e

# --- Hardcoded Configuration (Static for homelab) ---
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

# Network & Storage (Static for homelab)
NETWORK_GATEWAY="192.168.1.1"
NETWORK_BRIDGE="vmbr0"
NETWORK_IP_BASE="192.168.1"
STORAGE_POOL="datapool"

# --- Helper Functions ---
print_info() { echo -e "\033[36m[INFO]\033[0m $1"; }
print_success() { echo -e "\033[32m[SUCCESS]\033[0m $1"; }
print_error() { echo -e "\033[31m[ERROR]\033[0m $1"; }
print_warning() { echo -e "\033[33m[WARNING]\033[0m $1"; }

ensure_repository_exists_and_update() {
    # Safely ensure repository exists and is up to date in the Control Node
    # This function handles edge cases where the directory doesn't exist or is corrupted
    
    if ! pct exec "$CONTROL_CT_ID" -- test -d "$REPO_DIR"; then
        print_info "Repository directory doesn't exist. Cloning repository..."
        pct exec "$CONTROL_CT_ID" -- git clone "$REPO_URL" "$REPO_DIR"
    elif ! pct exec "$CONTROL_CT_ID" -- test -d "$REPO_DIR/.git"; then
        print_warning "Repository directory exists but is not a git repository. Re-cloning..."
        pct exec "$CONTROL_CT_ID" -- rm -rf "$REPO_DIR"
        pct exec "$CONTROL_CT_ID" -- git clone "$REPO_URL" "$REPO_DIR"
    else
        print_info "Repository exists. Updating..."
        if ! pct exec "$CONTROL_CT_ID" -- bash -c "cd $REPO_DIR && git pull" 2>/dev/null; then
            print_warning "Failed to update repository. Re-cloning for safety..."
            pct exec "$CONTROL_CT_ID" -- rm -rf "$REPO_DIR"
            pct exec "$CONTROL_CT_ID" -- git clone "$REPO_URL" "$REPO_DIR"
        fi
    fi
}



ensure_template_available() {
    # Unified template management - downloads and returns template name
    # Static approach: downloads latest available, returns name for use
    local template_type="$1"
    local pattern=""
    
    case "$template_type" in
        "alpine")
            pattern="alpine-.*-default"
            ;;
        "debian")
            pattern="debian-.*-standard"
            ;;
        *)
            print_error "Unknown template type: $template_type"
            return 1
            ;;
    esac
    
    print_info "Ensuring $template_type template is available..."
    
    # Check if template already exists locally
    local local_template=$(pveam list "$STORAGE_POOL" | awk "/$pattern/ {print \$1}" | sort -V | tail -n 1)
    
    if [ -z "$local_template" ]; then
        # Download latest template
        local latest_available=$(pveam available | awk "/$pattern/ {print \$NF}" | sort -V | tail -n 1)
        if [ -n "$latest_available" ]; then
            print_info "Downloading $latest_available to $STORAGE_POOL..."
            pveam download "$STORAGE_POOL" "$latest_available"
            local_template=$(pveam list "$STORAGE_POOL" | awk "/$pattern/ {print \$1}" | sort -V | tail -n 1)
        else
            print_error "No $template_type template available for download"
            return 1
        fi
    fi
    
    if [ -n "$local_template" ]; then
        print_info "$template_type template available: $local_template"
        echo "$local_template"
        return 0
    else
        print_error "Failed to ensure $template_type template availability"
        return 1
    fi
}

# --- Helper Functions ---

get_current_api_token() {
    local TOKEN_SECRET=""
    
    # Check if token already exists
    local token_exists=false
    if pveum user token list "$API_USER" 2>/dev/null | grep -q "$API_TOKEN_ID"; then
        token_exists=true
    elif pveum user token list "$API_USER" --output-format json 2>/dev/null | grep -q '"tokenid": "'$API_TOKEN_ID'"'; then
        token_exists=true
    fi
    
    if [ "$token_exists" = true ]; then
        # Token exists, but we need to recreate it to get the secret
        # (Proxmox doesn't allow retrieving existing token secrets)
        print_info "Refreshing API token '$API_TOKEN_ID'..."
        
        # Remove existing token
        if ! pveum user token remove "$API_USER" "$API_TOKEN_ID" 2>/dev/null; then
            print_error "Failed to remove existing token"
            return 1
        fi
        sleep 1
    fi
    
    # Create new token
    local TOKEN_OUTPUT
    if TOKEN_OUTPUT=$(pveum user token add "$API_USER" "$API_TOKEN_ID" --comment "Token for Ansible automation" 2>&1); then
        # Extract secret using multiple patterns
        TOKEN_SECRET=$(echo "$TOKEN_OUTPUT" | sed -n 's/.*secret: *\(.*\)/\1/p')
        if [ -z "$TOKEN_SECRET" ]; then
            TOKEN_SECRET=$(echo "$TOKEN_OUTPUT" | awk '/'"$API_TOKEN_ID"'/ {for(i=1;i<=NF;i++) if($i ~ /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/) print $i}' | tr -d '│ ')
        fi
        if [ -z "$TOKEN_SECRET" ]; then
            TOKEN_SECRET=$(echo "$TOKEN_OUTPUT" | grep -oE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' | head -1)
        fi
        
        if [ -n "$TOKEN_SECRET" ]; then
            echo "$TOKEN_SECRET"
            return 0
        else
            print_error "Failed to extract token secret"
            return 1
        fi
    else
        print_error "Failed to create API token: $TOKEN_OUTPUT"
        return 1
    fi
}

run_ansible_playbook() {
    local playbook_command="$1"
    
    # Get fresh API token for this session
    local CURRENT_TOKEN_SECRET
    if ! CURRENT_TOKEN_SECRET=$(get_current_api_token); then
        print_error "Failed to get API token. Playbook execution aborted."
        return 1
    fi
    
    # For deployment commands, ensure required template is available
    if [[ "$playbook_command" =~ deploy\.yml ]]; then
        # Extract stack name from the command
        local stack_name=$(echo "$playbook_command" | sed -n "s/.*stack_name=\([^']*\).*/\1/p")
        if [ -n "$stack_name" ]; then
            # Determine template type based on stack (hardcoded for homelab consistency)
            local template_type="alpine"  # Default for most stacks
            if [ "$stack_name" = "ansible_control" ] || [ "$stack_name" = "backup" ]; then
                template_type="debian"  # Static exceptions
            fi
            
            # Ensure template is available and get its name
            local template_name
            if template_name=$(ensure_template_available "$template_type"); then
                # Add template name as an extra variable
                playbook_command="${playbook_command} --extra-vars 'lxc_template=$template_name'"
            else
                print_error "Failed to ensure $template_type template for $stack_name stack"
                return 1
            fi
        fi
    fi
    
    print_info "Executing playbook..."
    
    # Run ansible-playbook, stream output to user, and capture it for error checking
    local playbook_output_file="/tmp/ansible_output_$$"
    local playbook_exit_code=0
    
    # Check if vault password file exists for easier UX
    local vault_param="--ask-vault-pass"
    if pct exec "$CONTROL_CT_ID" -- test -f /root/.vault_pass; then
        vault_param="--vault-password-file /root/.vault_pass"
    fi

    # Execute the command with API token as environment variable
    pct exec "$CONTROL_CT_ID" -- bash -l -c "cd $PLAYBOOK_DIR && PROXMOX_API_TOKEN_SECRET='$CURRENT_TOKEN_SECRET' ansible-playbook $vault_param --extra-vars 'proxmox_api_token_secret=$CURRENT_TOKEN_SECRET' $playbook_command" 2>&1 | tee "$playbook_output_file"
    playbook_exit_code=${PIPESTATUS[0]}

    if [ $playbook_exit_code -eq 0 ]; then
        print_success "Playbook execution completed successfully."
        vault_result=0
    else
        print_error "Playbook execution failed. Please check the logs."
        # Check if it's specifically a vault decryption error
        if grep -q "Decryption failed" "$playbook_output_file"; then
            print_error "Vault decryption failed. Please verify your vault password is correct."
            print_info "You can check/edit your secrets with:"
            print_info "pct exec $CONTROL_CT_ID -- bash -l -c 'ansible-vault edit $PLAYBOOK_DIR/secrets.yml'"
        fi
        vault_result=1
    fi
    
    # Clean up the output file
    rm -f "$playbook_output_file"
    
    return $vault_result
}

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
    
    # Check if token already exists - improved detection logic
    local token_exists=false
    if pveum user token list "$API_USER" 2>/dev/null | grep -q "$API_TOKEN_ID"; then
        token_exists=true
    elif pveum user token list "$API_USER" --output-format json 2>/dev/null | grep -q '"tokenid": "'$API_TOKEN_ID'"'; then
        token_exists=true
    fi
    
    if [ "$token_exists" = true ]; then
        print_warning "Token '$API_TOKEN_ID' already exists. Removing to create a new one with known secret..."
        
        # Remove existing token - retry logic to handle potential failures
        local remove_attempts=0
        while [ $remove_attempts -lt 3 ]; do
            if pveum user token remove "$API_USER" "$API_TOKEN_ID" 2>/dev/null; then
                print_info "Successfully removed existing token."
                sleep 2  # Brief pause to ensure removal is processed
                break
            else
                remove_attempts=$((remove_attempts + 1))
                if [ $remove_attempts -eq 3 ]; then
                    print_error "Failed to remove existing token after 3 attempts. Please manually remove it:"
                    print_error "pveum user token remove '$API_USER' '$API_TOKEN_ID'"
                    exit 1
                fi
                print_warning "Token removal attempt $remove_attempts failed, retrying in 2 seconds..."
                sleep 2
            fi
        done
    else
        print_info "Token '$API_TOKEN_ID' does not exist. Creating new token..."
    fi
    
    # Create new token - with retry logic for idempotency
    print_info "Creating new API token..."
    local TOKEN_OUTPUT
    local create_attempts=0
    while [ $create_attempts -lt 3 ]; do
        if TOKEN_OUTPUT=$(pveum user token add "$API_USER" "$API_TOKEN_ID" --comment "Token for Ansible automation" 2>&1); then
            # Extract secret using multiple patterns to handle different output formats
            TOKEN_SECRET=$(echo "$TOKEN_OUTPUT" | sed -n 's/.*secret: *\(.*\)/\1/p')
            if [ -z "$TOKEN_SECRET" ]; then
                # Try alternative extraction for table format output
                TOKEN_SECRET=$(echo "$TOKEN_OUTPUT" | awk '/'"$API_TOKEN_ID"'/ {for(i=1;i<=NF;i++) if($i ~ /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/) print $i}' | tr -d '│ ')
            fi
            if [ -z "$TOKEN_SECRET" ]; then
                # Try extracting UUID pattern from any line
                TOKEN_SECRET=$(echo "$TOKEN_OUTPUT" | grep -oE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' | head -1)
            fi
            
            if [ -n "$TOKEN_SECRET" ]; then
                print_success "Token '$API_TOKEN_ID' created and secret captured."
                break
            else
                print_error "Failed to extract token secret from output: $TOKEN_OUTPUT"
                exit 1
            fi
        else
            # Check if error is due to existing token (edge case)
            if echo "$TOKEN_OUTPUT" | grep -q "Token already exists"; then
                create_attempts=$((create_attempts + 1))
                if [ $create_attempts -eq 3 ]; then
                    print_error "Token creation failed after 3 attempts due to existing token. Manual intervention required:"
                    print_error "pveum user token remove '$API_USER' '$API_TOKEN_ID'"
                    print_error "Then re-run this installer."
                    exit 1
                fi
                print_warning "Token already exists (attempt $create_attempts). Trying to remove and recreate..."
                pveum user token remove "$API_USER" "$API_TOKEN_ID" 2>/dev/null
                sleep 2
                continue
            else
                print_error "Failed to create API token. Output: $TOKEN_OUTPUT"
                exit 1
            fi
        fi
    done

    # Step 2: Create and Provision Control LXC
    # Check if LXC already exists (should not happen in first-time setup, but added for robustness)
    if pct status "$CONTROL_CT_ID" >/dev/null 2>&1; then
        print_warning "LXC $CONTROL_CT_ID already exists. This should not happen during first-time setup."
        print_info "Checking if it's properly configured..."
        
        # Ensure it's running
        if ! pct status "$CONTROL_CT_ID" | grep -q "status: running"; then
            print_info "Starting existing LXC..."
            pct start "$CONTROL_CT_ID"
            sleep 10
        fi
        
        # Skip to provisioning step
        print_info "Skipping LXC creation, proceeding to provisioning..."
    else
        print_info "Creating Ansible Control LXC ($CONTROL_CT_ID)..."
        
        # Use consolidated template function
        local LATEST_DEBIAN_TEMPLATE
        if LATEST_DEBIAN_TEMPLATE=$(ensure_template_available "debian"); then
            print_success "Using Debian template: $LATEST_DEBIAN_TEMPLATE"
        else
            print_error "Failed to ensure Debian template for Control LXC"
            exit 1
        fi

        local CONTROL_IP_CIDR="$NETWORK_IP_BASE.$CONTROL_IP_OCTET/24"
        if pct create "$CONTROL_CT_ID" "$LATEST_DEBIAN_TEMPLATE" \
            --hostname "$CONTROL_HOSTNAME" --storage "$STORAGE_POOL" \
            --cores "$CONTROL_CORES" --memory "$CONTROL_MEMORY" --swap 0 \
            --features keyctl=1,nesting=1 \
            --net0 name=eth0,bridge=$NETWORK_BRIDGE,ip=$CONTROL_IP_CIDR,gw=$NETWORK_GATEWAY \
            --mp0 "${STORAGE_POOL}:0,mp=/datapool,backup=0" \
            --onboot 1 --unprivileged 1 --rootfs "${STORAGE_POOL}:${CONTROL_DISK}" 2>/dev/null; then
            print_success "LXC $CONTROL_CT_ID created successfully."
        else
            print_error "Failed to create LXC $CONTROL_CT_ID. It may already exist or there's a configuration issue."
            # Try to continue anyway in case the LXC was created but the command failed
            if ! pct status "$CONTROL_CT_ID" >/dev/null 2>&1; then
                exit 1
            fi
        fi
        
        pct start "$CONTROL_CT_ID"
        print_info "Waiting for container to boot..."
        sleep 10
    fi

    # Step 3: Provision Control Node with Ansible and Git (idempotent)
    print_info "Provisioning Control Node with Ansible, Git, and credentials..."

    print_info "Configuring autologin for root user in LXC console..."

    # Step 1: Disable conflicting getty services to prevent login prompt conflicts
    pct exec "$CONTROL_CT_ID" -- bash -c 'systemctl stop container-getty@1.service container-getty@2.service console-getty.service getty@tty1.service 2>/dev/null || true'
    pct exec "$CONTROL_CT_ID" -- bash -c 'systemctl disable container-getty@1.service container-getty@2.service console-getty.service getty@tty1.service 2>/dev/null || true'

    # Step 2: Ensure root account is passwordless and unlocked for autologin
    # This is the key fix for Debian-based LXCs where root can be locked by default.
    pct exec "$CONTROL_CT_ID" -- passwd -d root
    pct exec "$CONTROL_CT_ID" -- sed -i 's/^root:[!*]:/root::/' /etc/shadow

    # Step 3: Create the correct systemd override for getty@tty1.service
    pct exec "$CONTROL_CT_ID" -- mkdir -p /etc/systemd/system/getty@tty1.service.d
    pct exec "$CONTROL_CT_ID" -- bash -c "cat > /etc/systemd/system/getty@tty1.service.d/override.conf << 'EOF'\n[Unit]\nConditionPathExists=\n\n[Service]\nExecStart=\nExecStart=-/sbin/agetty --autologin root --noclear --keep-baud 115200,38400,9600 tty1 \$TERM\nEOF"


    # Step 4: Reload systemd and start the definitive autologin service
    pct exec "$CONTROL_CT_ID" -- systemctl daemon-reload
    pct exec "$CONTROL_CT_ID" -- systemctl enable getty@tty1.service
    pct exec "$CONTROL_CT_ID" -- systemctl restart getty@tty1.service
    
    print_success "Autologin configured successfully."

    print_info "Configuring locale for Ansible compatibility..."
    pct exec "$CONTROL_CT_ID" -- bash -c "apt-get update >/dev/null 2>&1 && apt-get install -y locales >/dev/null 2>&1"
    pct exec "$CONTROL_CT_ID" -- sed -i 's/^# \(en_US.UTF-8\)/\1/' /etc/locale.gen
    pct exec "$CONTROL_CT_ID" -- locale-gen >/dev/null 2>&1
    
    print_info "Disabling SSH for security (LXC console access only)..."
    pct exec "$CONTROL_CT_ID" -- apt-get remove -y openssh-server >/dev/null 2>&1 || true
    pct exec "$CONTROL_CT_ID" -- systemctl disable ssh >/dev/null 2>&1 || true
    pct exec "$CONTROL_CT_ID" -- systemctl stop ssh >/dev/null 2>&1 || true
    
    # Step 3.1: Install base packages and Python pip
    print_info "Installing base packages (git, pip)..."
    pct exec "$CONTROL_CT_ID" -- bash -c 'if [ ! -d /var/lib/apt/lists ] || [ -z "$(ls -A /var/lib/apt/lists)" ] || find /var/lib/apt/lists/* -mtime +1 2>/dev/null | grep -q .; then apt-get update; else echo "[INFO] Skipping apt-get update (package index is fresh)"; fi'
    pct exec "$CONTROL_CT_ID" -- apt-get install -y git python3-pip --no-install-recommends

    # Step 3.2: Install Ansible and required Python libraries via pip
    # This ensures we get a modern version of Ansible that is compatible with the latest collections.
    print_info "Installing Ansible, proxmoxer, and dependencies via pip..."
    pct exec "$CONTROL_CT_ID" -- pip3 install --break-system-packages ansible proxmoxer
    
    # Add /usr/local/bin to PATH permanently for ansible tools
    print_info "Configuring PATH for Ansible tools..."
    pct exec "$CONTROL_CT_ID" -- bash -c 'echo "export PATH=\"/usr/local/bin:\$PATH\"" >> /root/.bashrc'
    pct exec "$CONTROL_CT_ID" -- bash -c 'echo "export PATH=\"/usr/local/bin:\$PATH\"" >> /etc/profile'
    
    # Ensure repository exists and is up to date (idempotent)
    ensure_repository_exists_and_update
    
    # Check if Ansible collections are installed (idempotent check)
    print_info "Ensuring required Ansible collections are installed..."
    pct exec "$CONTROL_CT_ID" -- bash -c '
        # Add /usr/local/bin to PATH to access ansible-galaxy installed via pip
        export PATH="/usr/local/bin:$PATH"
        collections_needed=""
        for collection in community.general community.proxmox community.docker; do
            if ! ansible-galaxy collection list | grep -q "$collection"; then
                collections_needed="$collections_needed $collection"
            fi
        done
        if [ -n "$collections_needed" ]; then
            echo "Installing missing collections: $collections_needed"
            ansible-galaxy collection install $collections_needed
        else
            echo "All required collections already installed."
        fi
    '
    
    # Step 4: Verify encrypted secrets.yml exists (from repository)
    local secrets_file_path="/root/proxmox-homelab-automation/secrets.yml"
    
    # Check if encrypted secrets.yml exists in the repository clone
    if pct exec "$CONTROL_CT_ID" -- test -f "$secrets_file_path"; then
        # Verify it's encrypted
        if pct exec "$CONTROL_CT_ID" -- head -1 "$secrets_file_path" | grep -q "ANSIBLE_VAULT"; then
            print_success "Encrypted secrets.yml found in repository."
            print_info "To edit secrets, use: pct exec $CONTROL_CT_ID -- bash -l -c 'ansible-vault edit $secrets_file_path'"
        else
            print_error "secrets.yml exists but is not encrypted!"
            print_error "The secrets.yml file must be encrypted with ansible-vault."
            print_info "Please encrypt it using: ansible-vault encrypt secrets.yml"
            exit 1
        fi
    else
        print_error "secrets.yml not found in repository!"
        print_error "An encrypted secrets.yml file must exist in the repository."
        print_info "Please ensure the repository contains an encrypted secrets.yml file."
        exit 1
    fi

    # Final step: Restart getty services to ensure autologin is active
    print_info "Finalizing autologin configuration..."
    pct exec "$CONTROL_CT_ID" -- systemctl daemon-reload
    
    # Restart services to apply autologin immediately
    pct exec "$CONTROL_CT_ID" -- systemctl restart getty@tty1.service 2>/dev/null || true
    pct exec "$CONTROL_CT_ID" -- systemctl restart console-getty.service 2>/dev/null || true
    
    # Also restart serial-getty services if they exist (for LXC console access)
    pct exec "$CONTROL_CT_ID" -- systemctl restart serial-getty@ttyS0.service 2>/dev/null || true
    
    print_info "Autologin services restarted. Console should now auto-login as root."

    print_success "================================================="
    print_success "  First-time setup complete!"
    print_success "  Re-run this script to access the management menu."
    print_success "================================================="
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
    # Ensure container is running before showing menu
    if ! pct status "$CONTROL_CT_ID" | grep -q "status: running"; then
        print_info "Control Node ($CONTROL_CT_ID) is stopped. Starting..."
        pct start "$CONTROL_CT_ID"
        sleep 5
    fi
    show_management_menu
fi