#!/bin/bash

# Development LXC Creation and Setup Script
# Creates Ubuntu LXC with development tools and Claude Code

set -euo pipefail

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -f "$SCRIPT_DIR/../utils/common.sh" ]; then
    source "$SCRIPT_DIR/../utils/common.sh"
else
    echo "ERROR: common.sh not found!" >&2
    exit 1
fi

# Development LXC Configuration
readonly LXC_ID=150
readonly LXC_NAME="lxc-development-01"
readonly CPU_CORES=2
readonly RAM_MB=4096
readonly DISK_GB=12


# Function to create Ubuntu LXC
create_ubuntu_lxc() {
    print_info "Creating Ubuntu Development LXC: $LXC_NAME (ID: $LXC_ID)"
    print_info "Specs: ${CPU_CORES} cores, ${RAM_MB}MB RAM, ${DISK_GB}GB disk"
    
    # Check if LXC already exists
    if pct status "$LXC_ID" >/dev/null 2>&1; then
        local status=$(pct status "$LXC_ID" | awk '{print $2}')
        case "$status" in
            "running")
                print_info "LXC $LXC_ID already running, skipping creation..."
                return 0
                ;;
            "stopped")
                print_info "LXC $LXC_ID exists but stopped, starting..."
                pct start "$LXC_ID"
                wait_for_container_ready "$LXC_ID"
                return 0
                ;;
        esac
    fi
    
    print_step "Creating Ubuntu LXC..."
    
    # Storage configuration
    local template_storage="datapool"
    local disk_storage="datapool"
    
    # Get Ubuntu 24.04 LTS template
    local template_name=$(pveam available 2>/dev/null | grep ubuntu | grep 24.04 | head -1 | awk '{print $2}')
    if [ -z "$template_name" ]; then
        template_name="ubuntu-24.04-standard_24.04-2_amd64.tar.zst"
    fi
    
    # Download template if needed
    if ! pveam list "$template_storage" 2>/dev/null | grep -q "$template_name"; then
        print_info "Downloading template..."
        pveam download "$template_storage" "$template_name" >/dev/null 2>&1
    fi
    
    # Create LXC container
    if pct create "$LXC_ID" "$template_storage:vztmpl/$template_name" \
        --hostname "$LXC_NAME" \
        --cores "$CPU_CORES" \
        --memory "$RAM_MB" \
        --rootfs "$disk_storage:$DISK_GB" \
        --net0 "name=eth0,bridge=vmbr0,ip=192.168.1.${LXC_ID}/24,gw=192.168.1.1" \
        --nameserver "192.168.1.1" \
        --onboot 1 \
        --unprivileged 1 \
        --features "nesting=1" >/dev/null 2>&1; then
        
        print_info "✓ LXC container created successfully"
        pct start "$LXC_ID" >/dev/null 2>&1
        wait_for_container_ready "$LXC_ID"
        return 0
    else
        print_error "Failed to create LXC container"
        return 1
    fi
}

# Function to setup development environment
setup_development_environment() {
    print_step "Setting up development environment..."
    
    # Update system and configure locales (silent)
    print_info "Updating system and configuring locales..."
    pct exec "$LXC_ID" -- bash -c "
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -qq >/dev/null 2>&1
        apt-get upgrade -qq >/dev/null 2>&1
        apt-get install -qq locales >/dev/null 2>&1
        locale-gen en_US.UTF-8 >/dev/null 2>&1
        update-locale LANG=en_US.UTF-8 >/dev/null 2>&1
    "
    
    # Install basic packages (silent)
    print_info "Installing basic development packages..."
    pct exec "$LXC_ID" -- bash -c "
        export DEBIAN_FRONTEND=noninteractive
        export LANG=en_US.UTF-8
        apt-get install -qq curl wget git nano vim tree jq tmux screen \
            build-essential python3 python3-pip unzip ca-certificates \
            gnupg lsb-release >/dev/null 2>&1
    "
    
    # Install Node.js LTS (silent)
    print_info "Installing Node.js LTS..."
    pct exec "$LXC_ID" -- bash -c "
        export DEBIAN_FRONTEND=noninteractive
        export LANG=en_US.UTF-8
        curl -fsSL https://deb.nodesource.com/setup_lts.x | bash - >/dev/null 2>&1
        apt-get install -qq nodejs >/dev/null 2>&1
        npm install -g npm@latest >/dev/null 2>&1
    "
    
    # Install Claude Code CLI (official package)
    print_info "Installing Claude Code CLI..."
    pct exec "$LXC_ID" -- bash -c "
        export LANG=en_US.UTF-8
        npm install -g @anthropic-ai/claude-code >/dev/null 2>&1
    " || print_warning "Claude Code installation failed, continuing..."
    
    # Configure Git aliases
    print_info "Configuring Git..."
    pct exec "$LXC_ID" -- bash -c "
        export LANG=en_US.UTF-8
        git config --global alias.st status
        git config --global alias.lg 'log --oneline --graph --decorate --all'
        git config --global init.defaultBranch main
    "
    

    
    # Setup bash environment
    print_info "Configuring bash environment..."
    pct exec "$LXC_ID" -- bash -c "
        cat >> /root/.bashrc << 'EOF'

# Development environment
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

# Aliases
alias ll='ls -alF'
alias gs='git status'
alias ga='git add'
alias gc='git commit'
alias gp='git push'
alias gl='git log --oneline --graph --decorate'
EOF
    "
    
    # Configure passwordless root and disable SSH (matching other stacks)
    print_info "Configuring passwordless access and SSH security..."
    pct exec "$LXC_ID" -- bash -c "
        # Passwordless root configuration
        passwd -d root >/dev/null 2>&1
        
        # Disable SSH service completely (like Alpine stacks)
        systemctl disable ssh >/dev/null 2>&1 || true
        systemctl stop ssh >/dev/null 2>&1 || true
        
        # Configure console autologin
        mkdir -p /etc/systemd/system/getty@tty1.service.d
        cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf << 'EOF'
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin root --noclear %I \$TERM
EOF
        systemctl daemon-reload >/dev/null 2>&1
    "
    

}

# Function to display completion message
show_completion_message() {
    print_success "🎉 Development LXC created successfully!"
    echo
    print_info "Container Details:"
    print_info "  ✓ ID: $LXC_ID, Name: $LXC_NAME, IP: 192.168.1.$LXC_ID"
    print_info "  ✓ Resources: ${CPU_CORES} cores, ${RAM_MB}MB RAM, ${DISK_GB}GB storage"
    print_info "  ✓ Tools: Node.js, Git, Python3, Claude Code"
    print_info "  ✓ SSH disabled, passwordless console access"
    echo
    print_info "Access:"
    print_info "  ✓ Console: pct enter $LXC_ID (passwordless)"
}

# Main execution
main() {
    print_info "🚀 Starting Development LXC Creation..."
    
    check_root
    
    if create_ubuntu_lxc && setup_development_environment; then
        show_completion_message
    else
        print_error "Failed to create development environment"
        exit 1
    fi
}

# Input validation
if [ $# -gt 1 ]; then
    print_error "Usage: $0 [development]"
    exit 1
fi

if [ $# -eq 1 ] && [ "$1" != "development" ]; then
    print_error "Invalid parameter: $1"
    exit 1
fi

# Execute main function
main "$@"
