#!/bin/bash

# Development Environment Post-Install Script
# Installs development tools after Ubuntu LXC creation

set -e

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# Install development tools
install_development_tools() {
    print_info "Installing development tools..."
    
    # Update package lists
    apt-get update
    
    # Install essential development tools
    print_info "Installing git, curl, build-essential..."
    apt-get install -y \
        git \
        curl \
        build-essential \
        software-properties-common \
        ca-certificates \
        gnupg \
        lsb-release \
        unzip \
        wget \
        nano \
        vim \
        htop \
        tree
    
    print_success "✓ Essential development tools installed"
}

# Install Node.js LTS
install_nodejs() {
    print_info "Installing Node.js LTS..."
    
    # Add NodeSource repository
    curl -fsSL https://deb.nodesource.com/setup_lts.x | bash -
    
    # Install Node.js
    apt-get install -y nodejs
    
    # Verify installation
    local node_version=$(node --version 2>/dev/null || echo "none")
    local npm_version=$(npm --version 2>/dev/null || echo "none")
    
    if [ "$node_version" != "none" ] && [ "$npm_version" != "none" ]; then
        print_success "✓ Node.js installed: $node_version"
        print_success "✓ npm installed: $npm_version"
    else
        print_error "Node.js installation failed"
        return 1
    fi
}

# Install Claude Code CLI
install_claude_code() {
    print_info "Installing Claude Code CLI..."
    
    # Install Claude Code globally
    if npm install -g @anthropic-ai/claude-code; then
        print_success "✓ Claude Code CLI installed"
        
        # Verify installation
        if command -v claude-code >/dev/null 2>&1; then
            local claude_version=$(claude-code --version 2>/dev/null || echo "unknown")
            print_success "✓ Claude Code CLI ready: $claude_version"
        else
            print_warning "Claude Code installed but not in PATH"
        fi
    else
        print_error "Failed to install Claude Code CLI"
        return 1
    fi
}

# Disable SSH service
disable_ssh() {
    print_info "Disabling SSH service for security..."
    
    if systemctl is-active --quiet ssh; then
        systemctl stop ssh
        print_info "SSH service stopped"
    fi
    
    if systemctl is-enabled --quiet ssh; then
        systemctl disable ssh
        print_info "SSH service disabled"
    fi
    
    print_success "✓ SSH service disabled"
}

# Configure git (basic setup)
configure_git() {
    print_info "Configuring git with basic settings..."
    
    # Set basic git configuration
    git config --global init.defaultBranch main
    git config --global pull.rebase false
    git config --global core.editor nano
    
    print_success "✓ Git configured with basic settings"
}

# Clean up after installation
cleanup_installation() {
    print_info "Cleaning up installation files..."
    
    # Clean package cache
    apt-get autoremove -y
    apt-get autoclean
    
    print_success "✓ Installation cleanup completed"
}

# Main installation function
main() {
    print_info "=== Development Environment Setup ==="
    print_info "Installing development tools for Ubuntu LXC..."
    echo ""
    
    # Check if running as root
    if [ "$(id -u)" -ne 0 ]; then
        print_error "This script must be run as root"
        exit 1
    fi
    
    # Install components
    install_development_tools
    install_nodejs
    install_claude_code
    disable_ssh
    configure_git
    cleanup_installation
    
    echo ""
    print_success "🎉 Development environment setup completed!"
    print_info ""
    print_info "Installed components:"
    print_info "  ✓ Git and development tools"
    print_info "  ✓ Node.js LTS and npm"
    print_info "  ✓ Claude Code CLI (@anthropic-ai/claude-code)"
    print_info "  ✓ SSH service disabled"
    print_info ""
    print_info "Usage:"
    print_info "  claude-code"
    print_info ""
    print_info "Access container:"
    print_info "  pct enter 150"
    print_info ""
}

# Run main function
main "$@"