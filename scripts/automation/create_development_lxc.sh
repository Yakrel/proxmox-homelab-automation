#!/bin/bash

# Development LXC Creation and Setup Script
# Creates Ubuntu LXC with development tools, Git, and Claude Code

set -e

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../utils/common.sh"

# Development LXC Configuration
LXC_ID=150
LXC_NAME="lxc-development-01"
CPU_CORES=2
RAM_MB=4096
DISK_GB=12

# Function to check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "This script must be run as root"
        exit 1
    fi
}

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
    
    print_step "Creating Ubuntu LXC using Proxmox commands..."
    
    # Use datapool storage
    local template_storage="datapool"
    local disk_storage="datapool"
    
    # Get latest Ubuntu template
    print_step "Finding latest Ubuntu template..."
    local template_name=$(pveam available | grep ubuntu | grep 22.04 | head -1 | awk '{print $2}')
    if [ -z "$template_name" ]; then
        template_name="ubuntu-22.04-standard_22.04-1_amd64.tar.zst"
    fi
    
    # Download template if not exists
    print_step "Downloading Ubuntu template: $template_name"
    if ! pveam list "$template_storage" | grep -q "$template_name"; then
        print_info "Downloading template to $template_storage..."
        pveam download "$template_storage" "$template_name"
    else
        print_info "Template already exists in $template_storage"
    fi
    
    # Create LXC container
    print_step "Creating LXC container $LXC_ID..."
    if pct create "$LXC_ID" "$template_storage:vztmpl/$template_name" \
        --hostname "$LXC_NAME" \
        --cores "$CPU_CORES" \
        --memory "$RAM_MB" \
        --rootfs "$disk_storage:$DISK_GB" \
        --net0 "name=eth0,bridge=vmbr0,ip=192.168.1.${LXC_ID}/24,gw=192.168.1.1" \
        --nameserver "192.168.1.1" \
        --onboot 1 \
        --unprivileged 1 \
        --features "nesting=1"; then
        
        print_info "✓ LXC container created successfully!"
        
        # Start the container
        print_step "Starting LXC container..."
        pct start "$LXC_ID"
        wait_for_container_ready "$LXC_ID"
        
        return 0
    else
        print_error "Failed to create LXC container!"
        return 1
    fi
}

# Function to setup development environment
setup_development_environment() {
    print_step "Setting up development environment..."
    
    # Update system and install basic packages
    print_info "Updating system and installing basic packages..."
    pct exec "$LXC_ID" -- bash -c "
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -y
        apt-get upgrade -y
        apt-get install -y curl wget git nano vim tree jq tmux screen \
            build-essential python3 python3-pip unzip ca-certificates \
            gnupg lsb-release software-properties-common
    "
    
    # Install Node.js LTS
    print_info "Installing Node.js LTS..."
    pct exec "$LXC_ID" -- bash -c "
        curl -fsSL https://deb.nodesource.com/setup_lts.x | bash -
        apt-get install -y nodejs
        npm install -g npm@latest
    "
    
    # Install Claude Code
    print_info "Installing Claude Code..."
    pct exec "$LXC_ID" -- bash -c "
        npm install -g @anthropic/claude-code
    "
    
    # Configure Git with helpful aliases
    print_info "Configuring Git with helpful aliases..."
    pct exec "$LXC_ID" -- bash -c "
        git config --global alias.st status
        git config --global alias.co checkout
        git config --global alias.br branch
        git config --global alias.ci commit
        git config --global alias.lg 'log --oneline --graph --decorate --all'
        git config --global alias.last 'log -1 HEAD'
        git config --global alias.unstage 'reset HEAD --'
        git config --global init.defaultBranch main
    "
    
    # Create development directories
    print_info "Creating development directories..."
    pct exec "$LXC_ID" -- bash -c "
        mkdir -p /root/projects
        mkdir -p /root/development
        mkdir -p /root/.local/bin
    "
    
    # Setup useful bash aliases and environment
    print_info "Configuring bash environment..."
    pct exec "$LXC_ID" -- bash -c "
        cat >> /root/.bashrc << 'EOF'

# Development environment aliases
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
alias gs='git status'
alias ga='git add'
alias gc='git commit'
alias gp='git push'
alias gl='git log --oneline --graph --decorate'
alias ..='cd ..'
alias ...='cd ../..'
alias grep='grep --color=auto'
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'

# Useful functions
mkcd() { mkdir -p \"\$1\" && cd \"\$1\"; }
extract() {
    if [ -f \$1 ] ; then
        case \$1 in
            *.tar.bz2)   tar xjf \$1     ;;
            *.tar.gz)    tar xzf \$1     ;;
            *.bz2)       bunzip2 \$1     ;;
            *.rar)       unrar e \$1     ;;
            *.gz)        gunzip \$1      ;;
            *.tar)       tar xf \$1      ;;
            *.tbz2)      tar xjf \$1     ;;
            *.tgz)       tar xzf \$1     ;;
            *.zip)       unzip \$1       ;;
            *.Z)         uncompress \$1  ;;
            *.7z)        7z x \$1        ;;
            *)     echo \"'\$1' cannot be extracted via extract()\" ;;
        esac
    else
        echo \"'\$1' is not a valid file\"
    fi
}

# Add local bin to PATH
export PATH=\"\$HOME/.local/bin:\$PATH\"

# Development environment info
echo \"🚀 Development Environment Ready!\"
echo \"📂 Project directories: /root/projects, /root/development\"
echo \"🤖 Claude Code available: run 'claude-code' in your project directory\"
echo \"📝 Git configured with helpful aliases (gs, ga, gc, gp, gl)\"
echo \"🛠️  Development tools: Node.js \$(node --version), Python3 \$(python3 --version)\"
EOF
    "
    
    # Create a welcome script
    print_info "Creating welcome script..."
    pct exec "$LXC_ID" -- bash -c "
        cat > /root/development/README.md << 'EOF'
# Development Environment

Welcome to your Ubuntu development environment!

## Available Tools

- **Node.js & npm**: Latest LTS version
- **Git**: With helpful aliases (gs, ga, gc, gp, gl)
- **Claude Code**: AI-powered coding assistant
- **Python3**: Latest version with pip
- **Development Tools**: build-essential, tree, jq, tmux, screen

## Getting Started

1. **Configure Git** (if not done already):
   \`\`\`bash
   git config --global user.name \"Your Name\"
   git config --global user.email \"your@email.com\"
   \`\`\`

2. **Start a new project**:
   \`\`\`bash
   cd /root/projects
   mkdir my-project
   cd my-project
   git init
   \`\`\`

3. **Use Claude Code**:
   \`\`\`bash
   claude-code
   \`\`\`

4. **Useful aliases**:
   - \`gs\` = git status
   - \`ga\` = git add
   - \`gc\` = git commit
   - \`gp\` = git push
   - \`gl\` = git log (graph view)
   - \`ll\` = ls -alF
   - \`mkcd folder\` = mkdir + cd

## Project Directories

- \`/root/projects\` - Your main projects
- \`/root/development\` - Development workspace
- \`/root/.local/bin\` - Local binaries (in PATH)

## Access

- **Console**: \`pct enter 150\` from Proxmox host
- **SSH**: \`ssh root@192.168.1.150\` (configure SSH keys)

Happy coding! 🎉
EOF
    "
    
    print_info "✓ Development environment setup completed!"
}

# Function to display completion message
show_completion_message() {
    print_success "🎉 Development LXC created successfully!"
    echo
    print_info "Container Details:"
    print_info "  📍 LXC ID: $LXC_ID"
    print_info "  🏷️  Name: $LXC_NAME"
    print_info "  🌐 IP: 192.168.1.$LXC_ID"
    print_info "  💾 Resources: ${CPU_CORES} cores, ${RAM_MB}MB RAM, ${DISK_GB}GB storage"
    echo
    print_info "Installed Tools:"
    print_info "  ✓ Ubuntu LTS (Latest)"
    print_info "  ✓ Node.js & npm (Latest LTS)"
    print_info "  ✓ Git (with helpful aliases)"
    print_info "  ✓ Claude Code (AI coding assistant)"
    print_info "  ✓ Python3 & development tools"
    print_info "  ✓ Useful bash aliases and functions"
    echo
    print_info "Access Methods:"
    print_info "  🖥️  Console: pct enter $LXC_ID"
    print_info "  🔑 SSH: ssh root@192.168.1.$LXC_ID (configure SSH keys)"
    echo
    print_info "Project Directories:"
    print_info "  📂 /root/projects - Main projects"
    print_info "  📂 /root/development - Development workspace"
    echo
    print_info "Getting Started:"
    print_info "  1. pct enter $LXC_ID"
    print_info "  2. cd /root/projects"
    print_info "  3. Configure Git credentials"
    print_info "  4. Start coding with Claude Code!"
    echo
    print_info "📖 Read /root/development/README.md for detailed instructions"
}

# Main execution
main() {
    print_info "🚀 Starting Development LXC Creation and Setup..."
    
    # Check prerequisites
    check_root
    
    # Create Ubuntu LXC
    if create_ubuntu_lxc; then
        print_info "✓ LXC creation completed"
    else
        print_error "Failed to create LXC"
        exit 1
    fi
    
    # Setup development environment
    if setup_development_environment; then
        print_info "✓ Development environment setup completed"
    else
        print_error "Failed to setup development environment"
        exit 1
    fi
    
    # Show completion message
    show_completion_message
}

# Input validation
if [ $# -gt 1 ]; then
    print_error "Usage: $0 [development]"
    exit 1
fi

# Accept 'development' parameter for consistency with other scripts
if [ $# -eq 1 ] && [ "$1" != "development" ]; then
    print_error "Invalid parameter: $1"
    print_error "Usage: $0 [development]"
    exit 1
fi

# Execute main function
main "$@"
