#!/bin/bash

# Development LXC Setup Script
# Creates Ubuntu 24.04 LTS LXC with Claude Code and development tools

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

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

# Function to get user input for LXC configuration
get_lxc_config() {
    print_step "Development LXC Configuration"
    echo ""
    
    # LXC ID
    read -p "Enter LXC ID [150]: " lxc_id
    lxc_id=${lxc_id:-150}
    
    # Validate LXC ID
    if ! [[ "$lxc_id" =~ ^[0-9]+$ ]] || [ "$lxc_id" -lt 100 ] || [ "$lxc_id" -gt 999 ]; then
        print_error "Invalid LXC ID: $lxc_id (must be 100-999)"
        exit 1
    fi
    
    # Check if LXC already exists
    if pct status "$lxc_id" >/dev/null 2>&1; then
        print_error "LXC $lxc_id already exists!"
        exit 1
    fi
    
    # IP Address - use a reasonable default
    local suggested_ip="192.168.1.150"
    read -p "Enter IP address [$suggested_ip]: " ip_address
    ip_address=${ip_address:-$suggested_ip}
    
    # Gateway
    read -p "Enter gateway [192.168.1.1]: " gateway
    gateway=${gateway:-192.168.1.1}
    
    # Hostname
    read -p "Enter hostname [lxc-dev-01]: " hostname
    hostname=${hostname:-lxc-dev-01}
    
    # Resources
    read -p "Enter CPU cores [2]: " cpu_cores
    cpu_cores=${cpu_cores:-2}
    
    read -p "Enter RAM in MB [4096]: " ram_mb
    ram_mb=${ram_mb:-4096}
    
    read -p "Enter disk size in GB [20]: " disk_gb
    disk_gb=${disk_gb:-20}
    
    echo ""
    print_info "Configuration Summary:"
    print_info "  LXC ID: $lxc_id"
    print_info "  Hostname: $hostname"
    print_info "  IP: $ip_address"
    print_info "  Gateway: $gateway"
    print_info "  Resources: ${cpu_cores} cores, ${ram_mb}MB RAM, ${disk_gb}GB disk"
    echo ""
    
    read -p "Continue with this configuration? (y/N): " confirm
    if [[ ! "$confirm" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        print_info "Setup cancelled"
        exit 0
    fi
}

# Function to detect storage
detect_storage() {
    print_step "Detecting available storage..."
    
    # Get active storages
    local active_storages=$(pvesm status 2>/dev/null | awk 'NR>1 && $3=="active" {print $1}' | grep -v "^$")
    
    # Find template storage
    template_storage=""
    for storage in $active_storages; do
        if pvesm status -content vztmpl 2>/dev/null | grep -q "^$storage"; then
            template_storage="$storage"
            break
        fi
    done
    
    # Find disk storage
    disk_storage=""
    for storage in $active_storages; do
        if pvesm status -content images 2>/dev/null | grep -q "^$storage"; then
            disk_storage="$storage"
            break
        fi
    done
    
    if [ -z "$template_storage" ] || [ -z "$disk_storage" ]; then
        print_error "Could not find suitable storage"
        print_info "Available storages:"
        pvesm status
        exit 1
    fi
    
    print_info "Using template storage: $template_storage"
    print_info "Using disk storage: $disk_storage"
}

# Function to download Ubuntu template
download_ubuntu_template() {
    print_step "Downloading Ubuntu 24.04 LTS template..."
    
    # Get latest Ubuntu 24.04 template
    local template_name=$(pveam available | grep ubuntu-24.04 | grep standard | sort -V | tail -1 | awk '{print $2}')
    
    if [ -z "$template_name" ]; then
        template_name="ubuntu-24.04-standard_24.04-2_amd64.tar.zst"
        print_warning "Using fallback template: $template_name"
    fi
    
    # Download if not exists
    if ! pveam list "$template_storage" | grep -q "$template_name"; then
        print_info "Downloading $template_name to $template_storage..."
        pveam download "$template_storage" "$template_name"
    else
        print_info "Template already exists: $template_name"
    fi
    
    ubuntu_template="$template_storage:vztmpl/$template_name"
}

# Function to create Ubuntu LXC
create_ubuntu_lxc() {
    print_step "Creating Ubuntu LXC container..."
    
    # Create LXC container
    pct create "$lxc_id" "$ubuntu_template" \
        --hostname "$hostname" \
        --cores "$cpu_cores" \
        --memory "$ram_mb" \
        --rootfs "$disk_storage:$disk_gb" \
        --net0 "name=eth0,bridge=vmbr0,ip=${ip_address}/24,gw=${gateway}" \
        --nameserver "${gateway}" \
        --onboot 0 \
        --unprivileged 1 \
        --features "nesting=1"
    
    if [ $? -eq 0 ]; then
        print_success "LXC container created successfully"
    else
        print_error "Failed to create LXC container"
        exit 1
    fi
}

# Function to start and configure LXC
configure_lxc() {
    print_step "Starting and configuring LXC container..."
    
    # Start container
    pct start "$lxc_id"
    sleep 10
    
    # Configure locale and passwordless root access
    print_info "Configuring locale settings and passwordless root access..."
    pct exec "$lxc_id" -- bash -c 'echo "LC_ALL=en_US.UTF-8" >> /etc/environment'
    pct exec "$lxc_id" -- bash -c 'echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen'
    pct exec "$lxc_id" -- locale-gen en_US.UTF-8 >/dev/null 2>&1 || true
    
    # Set empty password for root (passwordless login)
    pct exec "$lxc_id" -- passwd -d root
    
    # Allow empty passwords in SSH (if needed)
    pct exec "$lxc_id" -- sed -i 's/#PermitEmptyPasswords no/PermitEmptyPasswords yes/' /etc/ssh/sshd_config 2>/dev/null || true
    
    # Wait for container to be ready
    local retries=0
    while ! pct exec "$lxc_id" -- systemctl is-system-running --wait >/dev/null 2>&1; do
        retries=$((retries + 1))
        if [ $retries -gt 30 ]; then
            print_warning "Container startup taking longer than expected, continuing..."
            break
        fi
        sleep 2
    done
    
    print_success "Container started successfully"
}

# Function to install development tools
install_development_tools() {
    print_step "Installing development tools..."
    
    # Update system
    print_info "Updating package lists..."
    pct exec "$lxc_id" -- apt update
    
    print_info "Installing base development tools..."
    pct exec "$lxc_id" -- apt install -y \
        curl \
        wget \
        git \
        vim \
        nano \
        htop \
        tree \
        unzip \
        build-essential \
        ca-certificates \
        gnupg \
        lsb-release
    
    print_success "Base tools installed"
}

# Function to install Node.js and npm
install_nodejs() {
    print_step "Installing Node.js and npm..."
    
    # Install Node.js 20.x LTS with latest npm
    print_info "Adding NodeSource repository..."
    pct exec "$lxc_id" -- bash -c 'curl -fsSL https://deb.nodesource.com/setup_20.x | bash -'
    
    print_info "Installing Node.js and updating npm to latest..."
    pct exec "$lxc_id" -- apt install -y nodejs
    pct exec "$lxc_id" -- npm install -g npm@latest
    
    # Verify installation
    local node_version=$(pct exec "$lxc_id" -- node --version 2>/dev/null || echo "failed")
    local npm_version=$(pct exec "$lxc_id" -- npm --version 2>/dev/null || echo "failed")
    
    if [[ "$node_version" == "failed" ]] || [[ "$npm_version" == "failed" ]]; then
        print_error "Node.js installation failed"
        exit 1
    fi
    
    print_success "Node.js $node_version and npm $npm_version installed"
}

# Function to install Claude Code
install_claude_code() {
    print_step "Installing Claude Code..."
    
    # Clear npm cache and install Claude Code with proper environment
    print_info "Clearing npm cache and installing @anthropic-ai/claude-code..."
    pct exec "$lxc_id" -- npm cache clean --force
    pct exec "$lxc_id" -- bash -c 'export LC_ALL=en_US.UTF-8 && export LANG=en_US.UTF-8 && export PATH="/usr/local/bin:/usr/bin:/bin:$PATH" && npm install -g @anthropic-ai/claude-code --verbose'
    
    # Wait for installation to complete
    sleep 5
    
    # Check if installation was successful by looking for the package
    if pct exec "$lxc_id" -- npm list -g @anthropic-ai/claude-code >/dev/null 2>&1; then
        print_info "Package installed, checking binary availability..."
        
        # Find where npm installed the binary
        local npm_bin_path=$(pct exec "$lxc_id" -- npm bin -g 2>/dev/null || echo "/usr/lib/node_modules/.bin")
        local claude_installed=false
        
        # Check common binary locations
        local claude_paths=("$npm_bin_path/claude-code" "/usr/local/bin/claude-code" "/usr/bin/claude-code" "/usr/lib/node_modules/.bin/claude-code")
        
        for path in "${claude_paths[@]}"; do
            if pct exec "$lxc_id" -- test -f "$path" && pct exec "$lxc_id" -- test -x "$path"; then
                claude_installed=true
                local claude_version=$(pct exec "$lxc_id" -- "$path" --version 2>/dev/null || echo "installed")
                print_success "Claude Code found at $path (version: $claude_version)"
                
                # Ensure it's in PATH by creating symlink if needed
                if [[ "$path" != "/usr/local/bin/claude-code" ]]; then
                    pct exec "$lxc_id" -- ln -sf "$path" /usr/local/bin/claude-code 2>/dev/null || true
                fi
                break
            fi
        done
        
        if [ "$claude_installed" = false ]; then
            # Try npx approach as fallback
            if pct exec "$lxc_id" -- bash -c 'npx --yes @anthropic-ai/claude-code --version' >/dev/null 2>&1; then
                print_success "Claude Code accessible via npx"
                # Create wrapper script
                pct exec "$lxc_id" -- bash -c 'cat > /usr/local/bin/claude-code << "EOF"
#!/bin/bash
npx --yes @anthropic-ai/claude-code "$@"
EOF'
                pct exec "$lxc_id" -- chmod +x /usr/local/bin/claude-code
                claude_installed=true
            fi
        fi
        
        if [ "$claude_installed" = false ]; then
            print_warning "Claude Code package installed but binary not accessible"
            print_info "Manual installation may be needed after container access"
        fi
    else
        print_error "Claude Code package installation failed"
        print_info "You can install it manually later with: npm install -g @anthropic-ai/claude-code"
    fi
}

# Function to configure development environment
configure_dev_environment() {
    print_step "Configuring development environment..."
    
    # Development workspace setup (using root directory)
    print_info "Setting up development workspace in /root..."
    
    # Configure Git (basic setup)
    print_info "Setting up Git configuration..."
    pct exec "$lxc_id" -- git config --global init.defaultBranch main
    pct exec "$lxc_id" -- git config --global core.editor nano
    
    # Create useful aliases
    print_info "Setting up shell aliases..."
    pct exec "$lxc_id" -- bash -c 'cat >> /root/.bashrc << EOF

# Development aliases
alias ll="ls -la"
alias la="ls -A"
alias l="ls -CF"
alias ..="cd .."
alias ...="cd ../.."
alias grep="grep --color=auto"
alias fgrep="fgrep --color=auto"
alias egrep="egrep --color=auto"

# Claude Code alias
alias cc="claude-code"

# Development shortcuts  
alias dev="cd /root"
alias reload="source /root/.bashrc"

# Show current directory in prompt
PS1="\${debian_chroot:+(\$debian_chroot)}\\[\\033[01;32m\\]\\u@\\h\\[\\033[00m\\]:\\[\\033[01;34m\\]\\w\\[\\033[00m\\]\\$ "
EOF'
    
    # Set timezone to Turkey
    print_info "Setting timezone to Europe/Istanbul..."
    pct exec "$lxc_id" -- timedatectl set-timezone Europe/Istanbul
    
    print_success "Development environment configured"
}

# Function to show setup summary
show_setup_summary() {
    print_step "Development LXC Setup Complete!"
    echo ""
    
    print_success "✅ Ubuntu 24.04 LTS LXC created successfully"
    print_success "✅ Development tools installed"
    print_success "✅ Node.js and npm installed"
    print_success "✅ Claude Code installed"
    print_success "✅ Development environment configured"
    
    echo ""
    print_info "📋 Container Details:"
    print_info "  LXC ID: $lxc_id"
    print_info "  Hostname: $hostname"
    print_info "  IP Address: $ip_address"
    print_info "  Access: pct enter $lxc_id"
    echo ""
    
    print_info "🔧 Installed Tools:"
    local node_version=$(pct exec "$lxc_id" -- node --version 2>/dev/null || echo "unknown")
    local npm_version=$(pct exec "$lxc_id" -- npm --version 2>/dev/null || echo "unknown")
    # Get Claude Code version with better detection
    local claude_version="unknown"
    if pct exec "$lxc_id" -- which claude-code >/dev/null 2>&1; then
        claude_version=$(pct exec "$lxc_id" -- claude-code --version 2>/dev/null || echo "installed")
    elif pct exec "$lxc_id" -- bash -c 'npx --yes @anthropic-ai/claude-code --version' >/dev/null 2>&1; then
        claude_version="via npx"
    fi
    
    print_info "  Node.js: $node_version"
    print_info "  npm: $npm_version"
    print_info "  Claude Code: $claude_version"
    echo ""
    
    print_info "🚀 Getting Started:"
    print_info "  1. Access container: pct enter $lxc_id"
    print_info "  2. Start Claude Code: claude-code (or use alias 'cc')"
    print_info "  3. Development workspace: /root (default directory)"
    echo ""
    
    print_warning "⚠️  Note: Container is set to NOT auto-start on boot"
    print_info "To start manually: pct start $lxc_id"
    print_info "To enable auto-start: pct set $lxc_id --onboot 1"
}

# Main function
main() {
    print_info "🛠️  Development LXC Setup"
    print_info "This will create an Ubuntu 24.04 LTS container with Claude Code"
    echo ""
    
    # Check if running as root
    if [ "$(id -u)" -ne 0 ]; then
        print_error "This script must be run as root"
        exit 1
    fi
    
    # Get configuration from user
    get_lxc_config
    
    # Detect storage
    detect_storage
    
    # Download Ubuntu template
    download_ubuntu_template
    
    # Create LXC
    create_ubuntu_lxc
    
    # Configure LXC
    configure_lxc
    
    # Install development tools
    install_development_tools
    
    # Install Node.js
    install_nodejs
    
    # Install Claude Code
    install_claude_code
    
    # Configure development environment
    configure_dev_environment
    
    # Show summary
    show_setup_summary
}

# Execute main function
main "$@"