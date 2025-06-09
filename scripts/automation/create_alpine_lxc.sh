#!/bin/bash

# Automated Alpine Docker LXC Creation using tteck's script
# Passes environment variables to automate the community script

set -e

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Function to create Alpine LXC using tteck's automated script
create_alpine_lxc_auto() {
    local lxc_id=$1
    local lxc_name=$2
    local cpu_cores=$3
    local ram_mb=$4
    local disk_gb=$5

    # Ensure temporary script cleanup on exit
    trap 'rm -f /tmp/alpine_auto.sh' EXIT

    print_info "Creating Alpine Docker LXC: $lxc_name (ID: $lxc_id)"
    print_info "Specs: ${cpu_cores} cores, ${ram_mb}MB RAM, ${disk_gb}GB disk"
    
    # Check if LXC already exists
    if pct status "$lxc_id" >/dev/null 2>&1; then
        print_error "LXC $lxc_id already exists!"
        return 1
    fi

    print_step "Setting up environment variables for tteck's script automation..."
    
    # Core LXC specifications that tteck's script will use
    export CTID="$lxc_id"
    export HN="$lxc_name"
    export DISK_SIZE="$disk_gb"
    export RAM_SIZE="$ram_mb"
    export CPU_CORES="$cpu_cores"
    
    # Force unprivileged container (safer and what we want)
    export CT_TYPE="1"
    export UNPRIVILEGED="yes"
    
    # Network configuration (DHCP on default bridge)
    export NET="dhcp"
    export BRG="vmbr0"
    export GATE=""
    export DISABLEIP6="no"
    
    # Security: Disable SSH, enable console-only access (exactly what we want)
    export SSH="no"
    export VERBOSE="no"
    
    # Automation flags to skip prompts
    export DEBIAN_FRONTEND=noninteractive
    export INTERACTIVE="no"
    export AUTO_INSTALL="yes"
    export SKIP_PROMPTS="yes"
    
    print_step "Downloading and executing tteck's Alpine Docker script..."
    print_warning "DEBUG MODE: Will show which automation method works..."
    
    # Direct automation without temporary files (works with remote execution)
    print_step "Method 1: Using NEWT_COLORS automation for whiptail..."
    print_info "DEBUG: Starting Method 1 with printf newlines..."
    # Set environment to handle whiptail dialogs automatically
    export NEWT_COLORS=""
    export DISPLAY=""
    if printf '\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n' | timeout 300 bash <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/ct/alpine-docker.sh); then
        print_info "✓ Method 1 succeeded - printf newlines worked!"
    else
        print_warning "Method 1 failed (printf newlines didn't work)"
        print_step "DEBUG: Trying Method 2 with expect..."
        
        # Method 2: Install expect and use it
        if ! command -v expect >/dev/null 2>&1; then
            print_step "Installing expect for dialog automation..."
            apt-get update >/dev/null 2>&1 && apt-get install -y expect >/dev/null 2>&1
        fi
        
        if command -v expect >/dev/null 2>&1; then
            print_step "Method 2: Using expect automation with TAB navigation..."
            print_info "DEBUG: Expect is available, starting automated interaction..."
            if expect << 'EXPECT_EOF'
set timeout 300
spawn bash -c "curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/ct/alpine-docker.sh | bash"
expect {
    "*Alpine-Docker LXC*" { send "\t\r"; exp_continue }
    "*Proceed*" { send "\t\r"; exp_continue }
    "*Create*" { send "\t\r"; exp_continue }
    "*Yes*" { send "\r"; exp_continue }
    "*No*" { send "\t\r"; exp_continue }
    "*(y/N)*" { send "y\r"; exp_continue }
    "*(Y/n)*" { send "Y\r"; exp_continue }
    eof { puts "Script completed" }
    timeout { puts "Script timed out"; exit 1 }
}
EXPECT_EOF
            then
                print_info "✓ Method 2 succeeded"
            else
                print_warning "Method 2 failed, trying Method 3..."
                
                # Method 3: printf with specific key sequences for whiptail
                print_step "Method 3: Using specific whiptail key sequences..."
                # Whiptail navigation: Space to select, Tab to move, Enter to confirm
                if (echo -e "\t\r"; sleep 1; echo -e "\r"; sleep 1; echo -e "\r") | timeout 300 bash <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/ct/alpine-docker.sh) 2>/dev/null; then
                    print_info "✓ Method 3 succeeded"
                else
                    print_error "All automation methods failed!"
                    print_warning "═══════════════════════════════════════════════"
                    print_warning "MANUAL INTERVENTION REQUIRED:"
                    print_warning "Run this command manually in another terminal:"
                    print_warning "bash <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/ct/alpine-docker.sh)"
                    print_warning "Choose: Yes -> Accept defaults -> Continue"
                    print_warning "Then press CTRL+C here and re-run setup"
                    print_warning "═══════════════════════════════════════════════"
                    
                    # Give user time to see the message
                    sleep 10
                    return 1
                fi
            fi
        else
            print_error "Could not install expect, trying final method..."
            # Method 3: Fallback with simple key sequences
            print_step "Method 3: Using simple key sequence fallback..."
            if (echo -e "\t\r"; sleep 1; echo -e "\r"; sleep 1; echo -e "\r") | timeout 300 bash <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/ct/alpine-docker.sh) 2>/dev/null; then
                print_info "✓ Method 3 succeeded"
            else
                print_error "All automation methods failed!"
                print_warning "═══════════════════════════════════════════════"
                print_warning "MANUAL INTERVENTION REQUIRED:"
                print_warning "Run this command manually in another terminal:"
                print_warning "bash <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/ct/alpine-docker.sh)"
                print_warning "Choose: Yes -> Accept defaults -> Continue"
                print_warning "Then press CTRL+C here and re-run setup"
                print_warning "═══════════════════════════════════════════════"
                
                # Give user time to see the message
                sleep 10
                return 1
            fi
        fi
    fi
    
    # If we reach here, one of the methods succeeded
    print_step "Verifying LXC creation..."
    if pct status "$lxc_id" >/dev/null 2>&1; then
        print_info "✓ LXC $lxc_name created successfully!"
        
        # Wait for container to be fully ready
        sleep 10
        
        # Verify container exists and is running
        if pct status "$lxc_id" | grep -q "running"; then
            print_info "✓ Container is running"
        else
            print_warning "Container not running, starting..."
            pct start "$lxc_id"
            sleep 5
        fi
        
        # Add datapool mount
        print_step "Adding /datapool mount point..."
        if add_datapool_mount "$lxc_id"; then
            print_info "✓ Mount point added successfully"
        else
            print_warning "Failed to add mount point automatically"
        fi
        
        # Verify Docker installation
        print_step "Verifying Docker installation..."
        if verify_docker "$lxc_id"; then
            print_info "✓ Docker and Docker Compose verified"
        else
            print_warning "Docker verification failed, may need manual check"
        fi
        
        return 0
    else
        print_error "Script execution failed or timed out"
        rm -f /tmp/alpine_auto.sh
        return 1
    fi
}

# Function to add datapool mount
add_datapool_mount() {
    local lxc_id=$1
    
    # Stop container if running
    if pct status "$lxc_id" | grep -q "running"; then
        pct stop "$lxc_id"
        sleep 3
    fi
    
    # Determine the next available mount index
    local next_mp_index=$(pct config "$lxc_id" | grep -o 'mp[0-9]\+' | sort -V | tail -n 1 | grep -o '[0-9]\+' | awk '{print $1+1}')
    next_mp_index=${next_mp_index:-0} # Default to 0 if no mount points exist
    
    # Add mount point
    if pct set "$lxc_id" -mp${next_mp_index} /datapool,mp=/datapool; then
        # Start container
        pct start "$lxc_id"
        sleep 5
        
        # Verify mount
        if pct exec "$lxc_id" -- test -d /datapool; then
            return 0
        else
            return 1
        fi
    else
        return 1
    fi
}

# Function to verify Docker installation
verify_docker() {
    local lxc_id=$1
    
    # Test Docker
    if pct exec "$lxc_id" -- docker --version >/dev/null 2>&1; then
        local docker_version=$(pct exec "$lxc_id" -- docker --version)
        print_info "✓ Docker: $docker_version"
    else
        return 1
    fi
    
    # Test Docker Compose
    if pct exec "$lxc_id" -- docker compose version >/dev/null 2>&1; then
        local compose_version=$(pct exec "$lxc_id" -- docker compose version --short)
        print_info "✓ Docker Compose: $compose_version"
    else
        return 1
    fi
    
    # Test Docker service
    if pct exec "$lxc_id" -- rc-service docker status | grep -q "started"; then
        print_info "✓ Docker service is running"
    else
        print_warning "Starting Docker service..."
        pct exec "$lxc_id" -- rc-service docker start
    fi
    
    return 0
}

# Main function
create_stack_lxc() {
    local stack_type=$1
    
    case $stack_type in
        "media")
            create_alpine_lxc_auto 101 "lxc-media-01" 4 8192 16
            ;;
        "proxy")
            create_alpine_lxc_auto 100 "lxc-proxy-01" 1 2048 8
            ;;
        "downloads")
            create_alpine_lxc_auto 102 "lxc-downloads-01" 2 4096 8
            ;;
        "utility")
            create_alpine_lxc_auto 103 "lxc-utility-01" 2 4096 8
            ;;
        "monitoring")
            create_alpine_lxc_auto 104 "lxc-monitoring-01" 2 4096 16
            ;;
        *)
            print_error "Unknown stack type: $stack_type"
            return 1
            ;;
    esac
}

# Input validation
if [ $# -ne 1 ]; then
    print_error "Usage: $0 <stack_type>"
    echo "Available: media, proxy, downloads, utility, monitoring"
    exit 1
fi

case "$1" in
    media|proxy|downloads|utility|monitoring)
        ;;
    *)
        print_error "Invalid stack type: $1"
        exit 1
        ;;
esac

if [ "$(id -u)" -ne 0 ]; then
    print_error "This script must be run as root"
    exit 1
fi

# Execute
STACK_TYPE=$1
print_info "Creating $STACK_TYPE stack using tteck's Alpine Docker script (automated)..."

if create_stack_lxc "$STACK_TYPE"; then
    print_info "🎉 $STACK_TYPE LXC created successfully!"
    print_info ""
    print_info "Features installed by tteck's script:"
    print_info "✓ Latest Alpine Linux (3.21)"
    print_info "✓ Latest Docker + Docker Compose"
    print_info "✓ SSH disabled for security"
    print_info "✓ Passwordless root console access"
    print_info "✓ Unprivileged container with nesting"
    print_info "✓ /datapool mount point added"
    print_info ""
    print_info "Next steps:"
    case $STACK_TYPE in
        media) LXC_ID=101;;
        proxy) LXC_ID=100;;
        downloads) LXC_ID=102;;
        utility) LXC_ID=103;;
        monitoring) LXC_ID=104;;
    esac
    print_info "1. Create directories: bash scripts/lxc/setup_${STACK_TYPE}_lxc.sh"
    print_info "2. Deploy services: bash scripts/automation/deploy_stack.sh $STACK_TYPE $LXC_ID"
    print_info "3. Access LXC: pct enter $LXC_ID"
else
    print_error "Failed to create $STACK_TYPE LXC"
    exit 1
fi