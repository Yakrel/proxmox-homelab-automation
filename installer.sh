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
CONTROL_HOSTNAME="lxc-ansible-control"
CONTROL_IP_OCTET="151"
CONTROL_CORES="2"
CONTROL_MEMORY="2048"
CONTROL_DISK="10"

# Network & Storage (Static for homelab)
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

prompt_vault_password() {
    local vault_password=""
    print_info "Ansible Vault password is required to access encrypted secrets."
    
    while [ -z "$vault_password" ]; do
        read -s -p "Enter Vault password: " vault_password
        echo
        if [ -z "$vault_password" ]; then
            print_warning "Password cannot be empty. Please try again."
        fi
    done
    
    echo "$vault_password"
}

ensure_templates_available() {
    # Ensure the latest Alpine and Debian templates are downloaded to the storage pool
    print_info "Checking and downloading latest templates if needed..."
    
    # Download latest Alpine template if needed
    local ALPINE_PATTERN="alpine-.*-default"
    local LATEST_ALPINE=$(pveam available | awk "/$ALPINE_PATTERN/ {print \$NF}" | sort -V | tail -n 1)
    if [ -n "$LATEST_ALPINE" ]; then
        local LOCAL_ALPINE=$(pveam list "$STORAGE_POOL" | awk "/$ALPINE_PATTERN/ {print \$1}" | sort -V | tail -n 1)
        if [ -z "$LOCAL_ALPINE" ]; then
            print_info "Downloading $LATEST_ALPINE to $STORAGE_POOL..."
            pveam download "$STORAGE_POOL" "$LATEST_ALPINE"
        else
            print_info "Alpine template already available: $LOCAL_ALPINE"
        fi
    fi
    
    # Download latest Debian template if needed
    local DEBIAN_PATTERN="debian-.*-standard"
    local LATEST_DEBIAN=$(pveam available | awk "/$DEBIAN_PATTERN/ {print \$NF}" | sort -V | tail -n 1)
    if [ -n "$LATEST_DEBIAN" ]; then
        local LOCAL_DEBIAN=$(pveam list "$STORAGE_POOL" | awk "/$DEBIAN_PATTERN/ {print \$1}" | sort -V | tail -n 1)
        if [ -z "$LOCAL_DEBIAN" ]; then
            print_info "Downloading $LATEST_DEBIAN to $STORAGE_POOL..."
            pveam download "$STORAGE_POOL" "$LATEST_DEBIAN"
        else
            print_info "Debian template already available: $LOCAL_DEBIAN"
        fi
    fi
}

get_latest_template() {
    local template_type="$1"
    local pattern=""
    
    if [ "$template_type" = "alpine" ]; then
        pattern="alpine-.*-default"
    elif [ "$template_type" = "debian" ]; then
        pattern="debian-.*-standard"
    else
        print_error "Unknown template type: $template_type"
        return 1
    fi
    
    # Find the latest local template of the specified type
    pveam list "$STORAGE_POOL" | awk "/$pattern/ {print \$1}" | sort -V | tail -n 1
}

run_ansible_playbook() {
    local playbook_command="$1"
    local vault_password
    
    # Ensure templates are available and determine template names for deployment commands
    if [[ "$playbook_command" =~ deploy\.yml ]]; then
        ensure_templates_available
        
        # Extract stack name from the command
        local stack_name=$(echo "$playbook_command" | sed -n "s/.*stack_name=\([^']*\).*/\1/p")
        if [ -n "$stack_name" ]; then
            # Determine template type based on stack (most use alpine, some use debian)
            local template_type="alpine"
            if [ "$stack_name" = "ansible-control" ] || [ "$stack_name" = "backup" ]; then
                template_type="debian"
            fi
            
            # Get the actual template name
            local template_name=$(get_latest_template "$template_type")
            if [ -n "$template_name" ]; then
                # Add template name as an extra variable
                playbook_command="${playbook_command} --extra-vars 'lxc_template=$template_name'"
                print_info "Using template: $template_name"
            else
                print_error "Could not find $template_type template in storage pool $STORAGE_POOL"
                return 1
            fi
        fi
    fi
    
    # Get vault password from user
    vault_password=$(prompt_vault_password)
    
    # Run the playbook by piping the vault password directly to ansible-playbook
    print_info "Executing playbook with vault password..."
    if pct exec "$CONTROL_CT_ID" -- bash -l -c "cd $PLAYBOOK_DIR && echo '$vault_password' | ansible-playbook --vault-password-file /dev/stdin $playbook_command"; then
        print_success "Playbook execution completed successfully."
    else
        print_error "Playbook execution failed. Please check the logs."
    fi
    
    # Clear password from memory
    unset vault_password
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

    print_info "Configuring autologin for root user in web console..."
    pct exec "$CONTROL_CT_ID" -- bash -c "mkdir -p /etc/systemd/system/getty@tty1.service.d"
    pct exec "$CONTROL_CT_ID" -- bash -c "echo -e '[Service]\nExecStart=\nExecStart=-/sbin/agetty --autologin root --noclear %I \$TERM' > /etc/systemd/system/getty@tty1.service.d/override.conf"
    pct exec "$CONTROL_CT_ID" -- systemctl daemon-reload
    pct exec "$CONTROL_CT_ID" -- systemctl restart getty@tty1.service >/dev/null 2>&1 || true # Restart may fail if not fully booted, but that's okay

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
    
    # Step 4: Create/Update credentials (idempotent)
    local secrets_file_path="/root/proxmox-homelab-automation/secrets.yml"
    local create_new_secrets=false
    
    # Check if secrets.yml already exists (encrypted or unencrypted)
    if pct exec "$CONTROL_CT_ID" -- test -f "$secrets_file_path"; then
        print_warning "Secrets file already exists. Checking if it needs updating..."
        
        # Check if it's encrypted
        if pct exec "$CONTROL_CT_ID" -- head -1 "$secrets_file_path" | grep -q "ANSIBLE_VAULT"; then
            print_info "Secrets file is already encrypted. Skipping secrets creation."
            print_info "If you need to update secrets, please do so manually using:"
            print_info "pct exec $CONTROL_CT_ID -- ansible-vault edit $secrets_file_path"
        else
            print_warning "Secrets file exists but is not encrypted. This may be from a previous failed setup."
            print_info "Backing up existing file and creating new one..."
            pct exec "$CONTROL_CT_ID" -- mv "$secrets_file_path" "${secrets_file_path}.backup.$(date +%s)"
            create_new_secrets=true
        fi
    else
        print_info "No secrets file found. Creating new one..."
        create_new_secrets=true
    fi
    
    if [ "$create_new_secrets" = true ]; then
        # Create new secrets file
        local VAULT_CONTENT
        VAULT_CONTENT=$(cat <<EOF
# Proxmox API Configuration
proxmox_api_user: $API_USER
proxmox_api_token_id: $API_TOKEN_ID
proxmox_api_token_secret: $TOKEN_SECRET
proxmox_node: $PROXMOX_NODE

# Stack Environment Variables
# Proxy Stack
cloudflared_token: "REPLACE_WITH_YOUR_CLOUDFLARE_TUNNEL_TOKEN"

# Monitoring Stack  
grafana_admin_user: "admin"
grafana_admin_password: "REPLACE_WITH_SECURE_PASSWORD"
pve_exporter_user: "pve-exporter@pve"
pve_exporter_password: "REPLACE_WITH_SECURE_PASSWORD"
pve_url: "https://192.168.1.10:8006"
pve_verify_ssl: "false"

# Files Stack
jdownloader_vnc_password: "REPLACE_WITH_SECURE_PASSWORD"
palmr_encryption_key: "REPLACE_WITH_SECURE_KEY"
palmr_app_url: "REPLACE_WITH_YOUR_PALMR_URL"

# Webtools Stack
firefox_vnc_password: "REPLACE_WITH_SECURE_PASSWORD"
homepage_sonarr_api_key: "REPLACE_WITH_SONARR_API_KEY"
homepage_radarr_api_key: "REPLACE_WITH_RADARR_API_KEY"
homepage_prowlarr_api_key: "REPLACE_WITH_PROWLARR_API_KEY"
homepage_bazarr_api_key: "REPLACE_WITH_BAZARR_API_KEY" 
homepage_jellyfin_api_key: "REPLACE_WITH_JELLYFIN_API_KEY"
homepage_jellyseerr_api_key: "REPLACE_WITH_JELLYSEERR_API_KEY"
homepage_qb_username: "REPLACE_WITH_QB_USERNAME"
homepage_qb_password: "REPLACE_WITH_QB_PASSWORD"
homepage_grafana_username: "admin"
homepage_grafana_password: "REPLACE_WITH_GRAFANA_PASSWORD"

# Common Settings
timezone: "Europe/Istanbul"
EOF
)
        # Use pct push to create the file
        echo "$VAULT_CONTENT" | pct push "$CONTROL_CT_ID" - "$secrets_file_path"

        # Prompt user for vault password to encrypt secrets.yml
        print_info "Creating encrypted secrets.yml file..."
        print_info "Please set a secure password for the Ansible Vault."
        print_warning "IMPORTANT: Remember this password! You'll need it for all future operations."
        
        local VAULT_PASSWORD=""
        while [ -z "$VAULT_PASSWORD" ]; do
            read -s -p "Enter Vault password: " VAULT_PASSWORD
            echo
            if [ -z "$VAULT_PASSWORD" ]; then
                print_warning "Password cannot be empty. Please try again."
                continue
            fi
            
            local VAULT_PASSWORD_CONFIRM=""
            read -s -p "Confirm Vault password: " VAULT_PASSWORD_CONFIRM
            echo
            
            if [ "$VAULT_PASSWORD" != "$VAULT_PASSWORD_CONFIRM" ]; then
                print_warning "Passwords do not match. Please try again."
                VAULT_PASSWORD=""
            fi
        done

        # Encrypt the secrets file inside the LXC
        if pct exec "$CONTROL_CT_ID" -- bash -c "echo '$VAULT_PASSWORD' | ansible-vault encrypt --vault-password-file /dev/stdin $secrets_file_path" 2>/dev/null; then
            print_success "secrets.yml file encrypted successfully."
        else
            print_error "Failed to encrypt secrets.yml file."
            print_warning "The file was created as plaintext. Please encrypt it manually:"
            print_info "pct exec $CONTROL_CT_ID -- ansible-vault encrypt $secrets_file_path"
            exit 1
        fi
        
        # Clear password from memory
        unset VAULT_PASSWORD
        unset VAULT_PASSWORD_CONFIRM
    fi

    print_success "================================================="
    print_success "  First-time setup complete!"
    print_success "  Re-run this script to access the management menu."
    print_success "================================================="
    exit 0
}

show_management_menu() {
    # On subsequent runs, update the repo before showing the menu
    print_info "Updating repository in Control Node..."
    ensure_repository_exists_and_update
    
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
  [1;32m7[0m) Deploy Ansible Control Stack
  [1;32m8[0m) Deploy Backup Stack

[1;31mQ[0m) Quit

EOF

        read -p "Enter your choice [1-8, Q]: " choice

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
                print_info "Deploying Ansible Control Stack..."
                run_ansible_playbook "deploy.yml --extra-vars 'stack_name=ansible-control'"
                ;;
            8)
                print_info "Deploying Backup Stack..."
                run_ansible_playbook "deploy.yml --extra-vars 'stack_name=backup'"
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
