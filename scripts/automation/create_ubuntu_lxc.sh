#!/bin/bash

# Ubuntu Development LXC Creation using unified common functions
# Creates Ubuntu LXC with development tools - refactored for maintainability

set -e

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -f "$SCRIPT_DIR/../utils/common.sh" ]; then
    source "$SCRIPT_DIR/../utils/common.sh"
else
    echo "ERROR: common.sh not found!" >&2
    exit 1
fi

# Main Ubuntu LXC creation function using unified approach
create_ubuntu_lxc_unified() {
    local stack_type=$1
    
    print_info "Creating $stack_type environment using unified LXC creation..."
    
    # Get LXC ID and specifications from common.sh
    local lxc_id=$(get_stack_lxc_id "$stack_type")
    if [ $? -ne 0 ]; then
        return 1
    fi
    
    local specs=$(get_stack_specifications "$stack_type")
    local template_type=$(echo "$specs" | grep -o 'template=[a-z]*' | cut -d'=' -f2)
    
    print_info "Stack: $stack_type, LXC ID: $lxc_id, Template: $template_type"
    
    # Check current LXC status (idempotent)
    local lxc_status=$(check_lxc_status "$lxc_id")
    
    case "$lxc_status" in
        "not_exists")
            print_info "LXC $lxc_id does not exist, creating new container..."
            ;;
        "running")
            print_info "LXC $lxc_id already running, development environment ready!"
            print_success "✓ LXC $lxc_id verified!"
            return 0
            ;;
        "stopped")
            print_info "LXC $lxc_id exists but stopped, starting..."
            pct start "$lxc_id"
            wait_for_container_ready "$lxc_id"
            print_success "✓ LXC $lxc_id started!"
            return 0
            ;;
        *)
            print_warning "LXC $lxc_id in unknown state: $lxc_status, attempting recovery..."
            pct start "$lxc_id" >/dev/null 2>&1 || true
            wait_for_container_ready "$lxc_id"
            print_success "✓ LXC $lxc_id recovered!"
            return 0
            ;;
    esac
    
    # Download template
    local template_path=$(download_and_prepare_template "$template_type")
    if [ $? -ne 0 ]; then
        print_error "Failed to prepare template"
        return 1
    fi
    
    # Create LXC container
    if create_lxc_container "$stack_type" "$lxc_id" "$specs" "$template_path"; then
        print_info "✓ Container created, configuring..."
        
        # Configure container post-creation
        configure_container_post_creation "$lxc_id" "$stack_type" "$template_type"
        
        print_success "✓ $stack_type LXC ($lxc_id) created and configured successfully!"
        return 0
    else
        print_error "Failed to create LXC container"
        return 1
    fi
}

# Input validation
if [ $# -ne 1 ]; then
    print_error "Usage: $0 <stack_type>"
    print_info "Available stack types:"
    print_info "  - development (LXC 150): Ubuntu development environment"
    exit 1
fi

# Validate stack type
STACK_TYPE=$1
case "$STACK_TYPE" in
    development)
        ;;
    *)
        print_error "Invalid stack type: $STACK_TYPE"
        print_info "Valid types: development"
        exit 1
        ;;
esac

# Root check
check_root

# Execute unified creation
print_info "=== Ubuntu LXC Creation - $STACK_TYPE Environment ==="
print_info "Using unified creation functions from common.sh"

if create_ubuntu_lxc_unified "$STACK_TYPE"; then
    print_success "🎉 $STACK_TYPE LXC created successfully!"
    print_info ""
    print_info "✓ Ubuntu LTS with development tools"
    print_info "✓ Node.js LTS and Claude Code CLI"
    print_info "✓ Git, nano, vim, htop, build tools"
    print_info "✓ SSH with secure configuration"
    print_info "✓ /datapool mount point with correct permissions"
    print_info "✓ Development environment ready"
    print_info ""
    
    # Show next steps
    local lxc_id=$(get_stack_lxc_id "$STACK_TYPE")
    print_info "Next steps:"
    print_info "  1. Access container: pct enter $lxc_id"
    print_info "  2. SSH access: ssh root@192.168.1.$lxc_id"
    print_info "  3. Start Claude Code: cd /root/projects && claude-code"
    print_info "  4. Deploy services: bash scripts/automation/deploy_development.sh"
else
    print_error "Failed to create $STACK_TYPE LXC"
    exit 1
fi