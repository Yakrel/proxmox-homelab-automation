#!/bin/bash

# Development Tools Deployment Script for Ubuntu LXC
# Installs Node.js, npm, Git, and Claude Code

set -e

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Check if common.sh exists in the same directory (for setup.sh execution)
if [ -f "$SCRIPT_DIR/common.sh" ]; then
    source "$SCRIPT_DIR/common.sh"
elif [ -f "$SCRIPT_DIR/../utils/common.sh" ]; then
    source "$SCRIPT_DIR/../utils/common.sh"
else
    echo "ERROR: common.sh not found!"
    exit 1
fi

# Configuration
DEVELOPMENT_LXC_ID=150

# Function to check if LXC exists and is running
check_development_lxc() {
    local lxc_id=$1
    
    if ! pct status "$lxc_id" &>/dev/null; then
        print_error "Development LXC $lxc_id does not exist!"
        print_error "Please create it first using: create_ubuntu_lxc.sh development"
        return 1
    fi
    
    # Start container if not running
    if ! pct status "$lxc_id" | grep -q "running"; then
        print_info "Starting development container $lxc_id..."
        pct start "$lxc_id"
        sleep 5
    fi
    
    # Wait for container readiness
    local max_attempts=15
    local attempt=1
    
    print_info "Waiting for container to be ready..."
    while [ $attempt -le $max_attempts ]; do
        if pct exec "$lxc_id" -- echo "ready" >/dev/null 2>&1; then
            print_info "✓ Container is ready"
            return 0
        fi
        sleep 3
        attempt=$((attempt + 1))
    done
    
    print_warning "Container readiness check timeout, continuing anyway..."
    return 0
}

# Function to install Node.js and npm
install_nodejs() {
    local lxc_id=$1
    
    print_step "Installing Node.js and npm..."
    
    pct exec "$lxc_id" -- bash -c '
        # Install Node.js LTS via NodeSource repository
        export DEBIAN_FRONTEND=noninteractive
        
        # Update package list
        apt-get update -qq >/dev/null 2>&1
        
        # Install prerequisites
        apt-get install -y -qq ca-certificates curl gnupg >/dev/null 2>&1
        
        # Add NodeSource repository for Node.js LTS
        curl -fsSL https://deb.nodesource.com/setup_lts.x | bash - >/dev/null 2>&1
        
        # Install Node.js and npm
        apt-get install -y -qq nodejs >/dev/null 2>&1
        
        # Verify installation
        node_version=$(node --version 2>/dev/null)
        npm_version=$(npm --version 2>/dev/null)
        
        echo "Node.js version: $node_version"
        echo "npm version: $npm_version"
    '
    
    if [ $? -eq 0 ]; then
        print_info "✓ Node.js and npm installed successfully"
        return 0
    else
        print_error "Failed to install Node.js and npm"
        return 1
    fi
}

# Function to install additional development tools
install_dev_tools() {
    local lxc_id=$1
    
    print_step "Installing additional development tools..."
    
    pct exec "$lxc_id" -- bash -c '
        export DEBIAN_FRONTEND=noninteractive
        
        # Install development essentials
        apt-get install -y -qq \
            build-essential \
            python3 \
            python3-pip \
            tree \
            jq \
            unzip \
            zip \
            rsync \
            screen \
            tmux >/dev/null 2>&1
        
        # Set up git global configuration placeholders
        git config --global init.defaultBranch main >/dev/null 2>&1 || true
        
        echo "Development tools installed successfully"
    '
    
    if [ $? -eq 0 ]; then
        print_info "✓ Development tools installed successfully"
        return 0
    else
        print_warning "Some development tools may have failed to install"
        return 0
    fi
}

# Function to install Claude Code
install_claude_code() {
    local lxc_id=$1
    
    print_step "Installing Claude Code..."
    
    pct exec "$lxc_id" -- bash -c '
        # Install Claude Code via npm globally
        echo "Installing Claude Code via npm..."
        
        # Install Claude Code
        npm install -g @anthropics/claude-code >/dev/null 2>&1
        
        # Verify installation
        if command -v claude-code >/dev/null 2>&1; then
            claude_version=$(claude-code --version 2>/dev/null || echo "installed")
            echo "Claude Code version: $claude_version"
            return 0
        else
            echo "Claude Code installation verification failed"
            return 1
        fi
    '
    
    if [ $? -eq 0 ]; then
        print_info "✓ Claude Code installed successfully"
        return 0
    else
        print_error "Failed to install Claude Code"
        print_info "You can install it manually later with: npm install -g @anthropics/claude-code"
        return 1
    fi
}

# Function to configure development environment
configure_dev_environment() {
    local lxc_id=$1
    
    print_step "Configuring development environment..."
    
    pct exec "$lxc_id" -- bash -c '
        # Create development directories
        mkdir -p /root/development /root/projects >/dev/null 2>&1
        
        # Add useful aliases to bashrc
        cat >> /root/.bashrc << "EOF"

# Development aliases
alias ll="ls -alF"
alias la="ls -A"
alias l="ls -CF"
alias ..="cd .."
alias ...="cd ../.."
alias grep="grep --color=auto"
alias fgrep="fgrep --color=auto"
alias egrep="egrep --color=auto"

# Git aliases
alias gs="git status"
alias ga="git add"
alias gc="git commit"
alias gp="git push"
alias gl="git pull"
alias gd="git diff"
alias gb="git branch"
alias gco="git checkout"

# Development shortcuts
alias projects="cd /root/projects"
alias dev="cd /root/development"

# Show git branch in prompt
parse_git_branch() {
    git branch 2> /dev/null | sed -e "/^[^*]/d" -e "s/* \(.*\)/(\1)/"
}
export PS1="\[\033[32m\]\u@\h\[\033[00m\]:\[\033[34m\]\w\[\033[33m\]\$(parse_git_branch)\[\033[00m\]\$ "

EOF
        
        # Create a welcome message
        cat > /etc/motd << "EOF"
╔══════════════════════════════════════════════════════════════╗
║                    Development Environment                    ║
║                        LXC-150                              ║
╠══════════════════════════════════════════════════════════════╣
║                                                              ║
║  🚀 Development Tools Ready:                                ║
║     • Node.js & npm                                         ║
║     • Git with useful aliases                               ║
║     • Claude Code (AI-powered coding assistant)            ║
║     • Python3 & build tools                                ║
║                                                              ║
║  📁 Directories:                                            ║
║     /root/projects  - Your project workspace               ║
║     /root/development - Development utilities               ║
║                                                              ║
║  🔧 Quick Commands:                                         ║
║     projects - cd to projects directory                     ║
║     dev      - cd to development directory                  ║
║     claude-code - Start Claude Code                        ║
║                                                              ║
║  💡 Git is ready - configure with:                         ║
║     git config --global user.name "Your Name"              ║
║     git config --global user.email "your@email.com"        ║
║                                                              ║
╚══════════════════════════════════════════════════════════════╝

EOF
        
        echo "Development environment configured successfully"
    '
    
    if [ $? -eq 0 ]; then
        print_info "✓ Development environment configured successfully"
        return 0
    else
        print_warning "Some environment configuration may have failed"
        return 0
    fi
}

# Function to show post-installation information
show_post_install_info() {
    local lxc_id=$1
    
    print_info "🎉 Development environment setup completed!"
    print_info ""
    print_info "📋 Installation Summary:"
    print_info "✓ Ubuntu LTS base system"
    print_info "✓ Node.js and npm (latest LTS)"
    print_info "✓ Git with helpful aliases"
    print_info "✓ Claude Code (AI coding assistant)"
    print_info "✓ Python3 and build tools"
    print_info "✓ Development utilities (tree, jq, tmux, screen)"
    print_info ""
    print_info "🔗 Access Information:"
    print_info "• LXC ID: $lxc_id"
    print_info "• Hostname: lxc-development-01"
    print_info "• IP Address: 192.168.1.$lxc_id"
    print_info "• SSH: ssh root@192.168.1.$lxc_id (key-based auth only)"
    print_info "• Console: pct enter $lxc_id"
    print_info ""
    print_info "🚀 Getting Started:"
    print_info "1. Enter the container: pct enter $lxc_id"
    print_info "2. Configure Git: git config --global user.name \"Your Name\""
    print_info "3. Configure Git: git config --global user.email \"your@email.com\""
    print_info "4. Start coding: cd /root/projects && claude-code"
    print_info ""
    print_info "📖 Claude Code Documentation: https://www.anthropic.com/claude-code"
}

# Main deployment function
deploy_development_stack() {
    local lxc_id=$1
    
    print_info "🚀 Starting development tools deployment for LXC $lxc_id"
    
    # Check if LXC exists and is ready
    if ! check_development_lxc "$lxc_id"; then
        return 1
    fi
    
    # Install Node.js and npm
    if ! install_nodejs "$lxc_id"; then
        print_error "Failed to install Node.js and npm"
        return 1
    fi
    
    # Install additional development tools
    install_dev_tools "$lxc_id"
    
    # Install Claude Code
    install_claude_code "$lxc_id"
    
    # Configure development environment
    configure_dev_environment "$lxc_id"
    
    # Show post-installation information
    show_post_install_info "$lxc_id"
    
    return 0
}

# Check if running as root
check_root

# Main execution
print_info "Development Tools Deployment for Proxmox Homelab"
print_info "Target: LXC $DEVELOPMENT_LXC_ID (lxc-development-01)"

if deploy_development_stack "$DEVELOPMENT_LXC_ID"; then
    print_success "✅ Development environment deployed successfully!"
    exit 0
else
    print_error "❌ Development environment deployment failed!"
    exit 1
fi
