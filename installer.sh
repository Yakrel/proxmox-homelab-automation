#!/bin/bash
# =================================================================
#         Proxmox Homelab Automation - Unified Installer & Menu
# =================================================================
# This script is the single entry point for the entire automation.
# - On first run, it bootstraps the Ansible Control Node (LXC 151).
# - On subsequent runs, it acts as a menu to manage the homelab.
# All configuration is hardcoded for homelab simplicity and consistency.
#
# Branch Usage Examples:
#   # Use main branch (default)
#   bash <(curl -s https://raw.githubusercontent.com/Yakrel/proxmox-homelab-automation/main/installer.sh)
#
#   # Use specific branch via environment variable  
#   BRANCH=develop bash <(curl -s https://raw.githubusercontent.com/Yakrel/proxmox-homelab-automation/develop/installer.sh)
#
#   # Use specific branch via command line argument
#   bash <(curl -s https://raw.githubusercontent.com/Yakrel/proxmox-homelab-automation/test/installer.sh) test

set -e

# --- Simple Branch Detection ---
# Default to main branch
REPO_BRANCH="main"

# Simple branch detection from first argument or environment variable
# Usage examples:
#   bash <(curl -s https://raw.githubusercontent.com/Yakrel/proxmox-homelab-automation/main/installer.sh)
#   BRANCH=develop bash <(curl -s https://raw.githubusercontent.com/Yakrel/proxmox-homelab-automation/develop/installer.sh)
#   bash <(curl -s https://raw.githubusercontent.com/Yakrel/proxmox-homelab-automation/test/installer.sh) test

if [ -n "$BRANCH" ]; then
    REPO_BRANCH="$BRANCH"
    print_info() { echo -e "\033[36m[INFO]\033[0m $1"; }
    print_info "Using branch from BRANCH environment variable: $REPO_BRANCH"
elif [ $# -eq 1 ]; then
    REPO_BRANCH="$1"
    print_info() { echo -e "\033[36m[INFO]\033[0m $1"; }
    print_info "Using branch from command line argument: $REPO_BRANCH"
fi

REPO_URL="https://github.com/Yakrel/proxmox-homelab-automation.git"

# --- Hardcoded Configuration (Static for homelab) ---
API_USER="ansible-bot@pve"
API_TOKEN_ID="ansible-token"
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
PROXMOX_NODE="pve01"

# --- Helper Functions ---
print_info() { echo -e "\033[36m[INFO]\033[0m $1"; }
print_success() { echo -e "\033[32m[SUCCESS]\033[0m $1"; }
print_error() { echo -e "\033[31m[ERROR]\033[0m $1"; }
print_warning() { echo -e "\033[33m[WARNING]\033[0m $1"; }



ensure_repository_exists_and_update() {
    # Safely ensure repository exists and is up to date in the Control Node
    # This function handles edge cases where the directory doesn't exist or is corrupted
    # Now supports specific branch checkout
    
    print_info "Using repository: $REPO_URL"
    print_info "Target branch: $REPO_BRANCH"
    
    if ! pct exec "$CONTROL_CT_ID" -- test -d "$REPO_DIR"; then
        print_info "Repository directory doesn't exist. Cloning repository..."
        pct exec "$CONTROL_CT_ID" -- git clone -b "$REPO_BRANCH" "$REPO_URL" "$REPO_DIR"
    elif ! pct exec "$CONTROL_CT_ID" -- test -d "$REPO_DIR/.git"; then
        print_warning "Repository directory exists but is not a git repository. Re-cloning..."
        pct exec "$CONTROL_CT_ID" -- rm -rf "$REPO_DIR"
        pct exec "$CONTROL_CT_ID" -- git clone -b "$REPO_BRANCH" "$REPO_URL" "$REPO_DIR"
    else
        print_info "Repository exists. Updating..."
        
        # Get current branch and remote URL
        local current_branch=$(pct exec "$CONTROL_CT_ID" -- bash -c "cd $REPO_DIR && git branch --show-current" 2>/dev/null || echo "")
        local current_remote=$(pct exec "$CONTROL_CT_ID" -- bash -c "cd $REPO_DIR && git config --get remote.origin.url" 2>/dev/null || echo "")
        
        # Check if we need to change repository or branch
        if [ "$current_remote" != "$REPO_URL" ]; then
            print_info "Repository URL has changed. Re-cloning..."
            pct exec "$CONTROL_CT_ID" -- rm -rf "$REPO_DIR"
            pct exec "$CONTROL_CT_ID" -- git clone -b "$REPO_BRANCH" "$REPO_URL" "$REPO_DIR"
        elif [ "$current_branch" != "$REPO_BRANCH" ]; then
            print_info "Switching from branch '$current_branch' to '$REPO_BRANCH'..."
            # Fetch all branches first
            if ! pct exec "$CONTROL_CT_ID" -- bash -c "cd $REPO_DIR && git fetch origin" 2>/dev/null; then
                print_warning "Failed to fetch from remote. Re-cloning for safety..."
                pct exec "$CONTROL_CT_ID" -- rm -rf "$REPO_DIR"
                pct exec "$CONTROL_CT_ID" -- git clone -b "$REPO_BRANCH" "$REPO_URL" "$REPO_DIR"
                return
            fi
            
            # Check if target branch exists on remote
            if pct exec "$CONTROL_CT_ID" -- bash -c "cd $REPO_DIR && git ls-remote --heads origin $REPO_BRANCH | grep -q $REPO_BRANCH" 2>/dev/null; then
                # Switch to the target branch
                if ! pct exec "$CONTROL_CT_ID" -- bash -c "cd $REPO_DIR && git checkout -B $REPO_BRANCH origin/$REPO_BRANCH" 2>/dev/null; then
                    print_warning "Failed to switch to branch '$REPO_BRANCH'. Re-cloning for safety..."
                    pct exec "$CONTROL_CT_ID" -- rm -rf "$REPO_DIR"
                    pct exec "$CONTROL_CT_ID" -- git clone -b "$REPO_BRANCH" "$REPO_URL" "$REPO_DIR"
                fi
            else
                print_error "Branch '$REPO_BRANCH' does not exist on remote repository"
                print_info "Available branches:"
                pct exec "$CONTROL_CT_ID" -- bash -c "cd $REPO_DIR && git ls-remote --heads origin" 2>/dev/null || echo "Could not list remote branches"
                exit 1
            fi
        else
            # Same branch and repo, just pull updates
            if ! pct exec "$CONTROL_CT_ID" -- bash -c "cd $REPO_DIR && git pull" 2>/dev/null; then
                print_warning "Failed to update repository. Re-cloning for safety..."
                pct exec "$CONTROL_CT_ID" -- rm -rf "$REPO_DIR"
                pct exec "$CONTROL_CT_ID" -- git clone -b "$REPO_BRANCH" "$REPO_URL" "$REPO_DIR"
            fi
        fi
    fi
    
    # Verify we're on the correct branch
    local final_branch=$(pct exec "$CONTROL_CT_ID" -- bash -c "cd $REPO_DIR && git branch --show-current" 2>/dev/null || echo "unknown")
    if [ "$final_branch" = "$REPO_BRANCH" ]; then
        print_success "Repository is ready on branch: $final_branch"
    else
        print_warning "Expected branch '$REPO_BRANCH' but got '$final_branch'"
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

run_ansible_playbook() {
    local playbook_command="$1"
    
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
    local playbook_output_file="/tmp/ansible_output_$"
    local playbook_exit_code=0

    # Execute the command, teeing the output to a file in the host, and also displaying it.
    # We check the exit status of the pct exec command, not tee.
    pct exec "$CONTROL_CT_ID" -- bash -l -c "cd $PLAYBOOK_DIR && ansible-playbook --ask-vault-pass $playbook_command" 2>&1 | tee "$playbook_output_file"
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
    pct exec "$CONTROL_CT_ID" -- bash -c "cat > /etc/systemd/system/getty@tty1.service.d/override.conf << 'EOF'
[Unit]
ConditionPathExists=

[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin root --noclear --keep-baud 115200,38400,9600 tty1 \$TERM
EOF"

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
            print_info "pct exec $CONTROL_CT_ID -- bash -l -c 'ansible-vault edit $secrets_file_path'"
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
        
        if pct exec "$CONTROL_CT_ID" -- bash -l -c "ansible-vault encrypt --ask-vault-pass $secrets_file_path"; then
            print_success "secrets.yml file encrypted successfully."
        else
            print_error "Failed to encrypt secrets.yml file."
            print_warning "The file was created as plaintext. Please encrypt it manually:"
            print_info "pct exec $CONTROL_CT_ID -- bash -l -c 'ansible-vault encrypt $secrets_file_path'"
            exit 1
        fi
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
                run_ansible_playbook "deploy.yml --extra-vars 'stack_name=ansible_control'"
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