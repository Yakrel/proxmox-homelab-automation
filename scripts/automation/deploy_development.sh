#!/bin/bash

# Development Tools Deployment Script for Ubuntu LXC
# Installs Node.js, npm, Git, and Claude Code

set -e

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -f "$SCRIPT_DIR/../utils/common.sh" ]; then
    source "$SCRIPT_DIR/../utils/common.sh"
else
    echo "ERROR: common.sh not found!" >&2
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
    ' >/dev/null 2>&1
    
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
        # Install Claude Code CLI via npm globally
        npm install -g @anthropic-ai/claude-code >/dev/null 2>&1
        
        # Verify installation
        if command -v claude-code >/dev/null 2>&1; then
            return 0
        else
            echo "Claude Code installation verification failed" >&2
            return 1
        fi
    '
    
    if [ $? -eq 0 ]; then
        print_info "✓ Claude Code installed successfully"
        return 0
    else
        print_error "Failed to install Claude Code"
        print_info "You can install it manually later with: npm install -g @anthropic-ai/claude-code"
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
║     • Claude Code CLI (AI-powered coding assistant)         ║
║     • Python3 & build tools                                 ║
║                                                              ║
║  📁 Directories:                                            ║
║     /root/projects  - Your project workspace                ║
║     /root/development - Development utilities               ║
║                                                              ║
║  🔧 Quick Commands:                                         ║
║     projects - cd to projects directory                     ║
║     dev      - cd to development directory                  ║
║     claude-cli - Start Claude Code CLI                      ║
║                                                              ║
║  💡 Git is ready - configure with:                          ║
║     git config --global user.name "Your Name"               ║
║     git config --global user.email "your@email.com"         ║
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
    print_info "✓ Tools: Node.js, npm, Git, Claude Code CLI, Python3"
    print_info "✓ Access: pct enter $lxc_id or ssh root@192.168.1.$lxc_id"
    print_info "✓ Getting Started: cd /root/projects && claude-cli"
    print_info ""
    print_info "📖 See /etc/motd for more details."
}

# Main deployment function
deploy_development_stack() {
    local lxc_id=$1
    
    print_info "🚀 Deploying development stack to LXC $lxc_id..."
    
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
print_step "Development Tools Deployment"

if deploy_development_stack "$DEVELOPMENT_LXC_ID"; then
    print_success "✅ Development environment deployed successfully!"
    exit 0
else
    print_error "❌ Development environment deployment failed!"
    exit 1
fi
