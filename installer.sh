#!/bin/bash
# =================================================================
#         Proxmox Homelab Automation - v3 Installer (Secure)
# =================================================================
# This script bootstraps the Ansible control node. It ONLY handles
# creating the API credentials and the control LXC itself.
# Application secrets are NOT handled by this script.

set -e

# --- Configuration ---
API_USER="ansible-bot@pve"
API_TOKEN_ID="ansible-token"
REPO_URL="https://github.com/Yakrel/proxmox-homelab-automation.git"
REPO_DIR="/root/proxmox-homelab-automation"

# LXC Credentials file (outside the repo)
API_SECRETS_DIR="/etc/ansible_secrets"
API_SECRETS_FILE="$API_SECRETS_DIR/credentials.yml"

# Development LXC Config
DEV_CT_ID="151"
DEV_HOSTNAME="lxc-development-01"
DEV_IP_OCTET="151"
DEV_CORES="4"
DEV_MEMORY="6144"
DEV_DISK="15"

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

# --- Main Logic ---

# Step 1: Create Proxmox API User and Token (Idempotent)
# ---------------------------------------------------------
print_info "Ensuring Proxmox API user '$API_USER' exists..."
if ! pveum user show "$API_USER" >/dev/null 2>&1; then
    print_info "  -> User not found. Creating..."
    pveum user add "$API_USER" --comment "Ansible Automation User"
    # Assign top-level permissions to the user so it can create tokens
    pveum acl modify / --user "$API_USER" --role Administrator
    print_success "  -> User '$API_USER' created."
else
    print_success "  -> User '$API_USER' already exists."
fi

print_info "Ensuring API token '$API_TOKEN_ID' exists for user '$API_USER'..."
TOKEN_SECRET=""
if ! pveum user token list "$API_USER" | grep -q "tokenid=$API_TOKEN_ID"; then
    print_info "  -> Token not found. Creating..."
    TOKEN_OUTPUT=$(pveum user token add "$API_USER" "$API_TOKEN_ID" --comment "Token for Ansible automation" 2>&1)
    TOKEN_SECRET=$(echo "$TOKEN_OUTPUT" | sed -n 's/.*secret: *\(.*\)/\1/p')
    
    if [ -z "$TOKEN_SECRET" ]; then
        print_error "Failed to extract token secret from pveum output."
        exit 1
    fi
    print_success "  -> Token '$API_TOKEN_ID' created and secret captured."
else
    print_warning "  -> Token '$API_TOKEN_ID' already exists. Cannot retrieve secret."
    print_warning "  -> The script will assume the secret is already correctly configured in the control node."
fi

# Step 2: Create Development LXC (Idempotent)
# ---------------------------------------------------------
print_info "Ensuring Ansible Control LXC ($DEV_CT_ID - $DEV_HOSTNAME) exists..."
if ! pct status "$DEV_CT_ID" >/dev/null 2>&1; then
    print_info "  -> LXC not found. Creating..."
    
    print_info "  -> Locating latest Debian template..."
    pveam update > /dev/null || true
    LATEST_DEBIAN_TEMPLATE=$(pveam list "$STORAGE_POOL" | awk '/debian-.*-standard/ {print $1}' | sort -V | tail -n 1)
    if [ -z "$LATEST_DEBIAN_TEMPLATE" ]; then
        print_warning "  -> No local Debian template found; downloading..."
        DOWNLOAD_TEMPLATE=$(pveam available | awk '/debian-[0-9.]+(-[0-9]+)?-standard/ {print $NF}' | sort -V | tail -n 1)
        pveam download "$STORAGE_POOL" "$DOWNLOAD_TEMPLATE"
        LATEST_DEBIAN_TEMPLATE=$(pveam list "$STORAGE_POOL" | awk '/debian-.*-standard/ {print $1}' | sort -V | tail -n 1)
    fi
    print_success "  -> Using Debian template: $LATEST_DEBIAN_TEMPLATE"

    DEV_IP_CIDR="$NETWORK_IP_BASE.$DEV_IP_OCTET/24"
    pct create "$DEV_CT_ID" "$LATEST_DEBIAN_TEMPLATE" \
        --hostname "$DEV_HOSTNAME" \
        --storage "$STORAGE_POOL" \
        --cores "$DEV_CORES" \
        --memory "$DEV_MEMORY" \
        --swap 0 \
        --features keyctl=1,nesting=1 \
        --net0 name=eth0,bridge=$NETWORK_BRIDGE,ip=$DEV_IP_CIDR,gw=$NETWORK_GATEWAY \
        --onboot 1 \
        --unprivileged 1 \
        --rootfs "${STORAGE_POOL}:${DEV_DISK}"
    
    print_info "  -> Starting container..."
    pct start "$DEV_CT_ID"
    sleep 5 # Give container time to boot
else
    print_success "  -> LXC $DEV_CT_ID ($DEV_HOSTNAME) already exists."
    if ! pct status "$DEV_CT_ID" | grep -q "status: running"; then
        print_info "  -> Container is stopped. Starting..."
        pct start "$DEV_CT_ID"
        sleep 5
    fi
fi

# Step 3: Provision Control Node
# ---------------------------------------------------------
print_info "Provisioning Ansible Control Node..."

PROVISION_SCRIPT=$(mktemp /tmp/provision_script.XXXXXX.sh)
trap 'rm -f "$PROVISION_SCRIPT"' EXIT

cat > "$PROVISION_SCRIPT" <<EOF
#!/bin/bash
set -e

print_info() { echo -e "\033[36m[LXC-INFO]\033[0m $1"; }

print_info "Updating package lists and installing dependencies..."
apt-get update >/dev/null
apt-get install -y git ansible curl >/dev/null

print_info "Cloning/updating repository at $REPO_DIR..."
if [ ! -d "$REPO_DIR" ]; then
    git clone "$REPO_URL" "$REPO_DIR"
else
    cd "$REPO_DIR"
    git pull
fi

# Only create the API secrets file if a new secret was generated.
if [ -n "$TOKEN_SECRET" ]; then
    print_info "Injecting Proxmox API credentials into $API_SECRETS_FILE..."
    mkdir -p "$API_SECRETS_DIR"
    cat > "$API_SECRETS_FILE" <<SECRETS_EOF
# This file is managed by installer.sh and is NOT in version control.
proxmox_api_user: "$API_USER"
proxmox_api_token_id: "$API_TOKEN_ID"
proxmox_api_token_secret: "$TOKEN_SECRET"
proxmox_node: "$PROXMOX_NODE"
SECRETS_EOF
    chmod 600 "$API_SECRETS_FILE"
fi
EOF

pct push "$DEV_CT_ID" "$PROVISION_SCRIPT" "/root/provision.sh" --mode 755
pct exec "$DEV_CT_ID" -- bash -c "export API_USER='$API_USER' API_TOKEN_ID='$API_TOKEN_ID' TOKEN_SECRET='$TOKEN_SECRET' REPO_DIR='$REPO_DIR' REPO_URL='$REPO_URL' API_SECRETS_DIR='$API_SECRETS_DIR' API_SECRETS_FILE='$API_SECRETS_FILE' PROXMOX_NODE='$PROXMOX_NODE' && /root/provision.sh"

print_success "================================================="
print_success "  Homelab setup complete!"
print_success "  Enter the control node with: pct enter $DEV_CT_ID"
print_success "================================================="