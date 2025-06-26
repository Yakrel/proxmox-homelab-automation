#!/bin/bash

# Alpine Docker LXC Creation using unified common functions
# Creates Alpine LXC with Docker installed - refactored for maintainability

set -e

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -f "$SCRIPT_DIR/../utils/common.sh" ]; then
    source "$SCRIPT_DIR/../utils/common.sh"
else
    echo "ERROR: common.sh not found!" >&2
    exit 1
fi

# Main Alpine LXC creation function using unified approach
create_alpine_lxc_unified() {
    local stack_type=$1
    
    print_info "Creating $stack_type stack using unified LXC creation..."
    
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
            print_info "LXC $lxc_id already running, verifying configuration..."
            ensure_datapool_mount "$lxc_id"
            ensure_datapool_permissions "$stack_type"
            print_success "✓ LXC $lxc_id verified and updated!"
            return 0
            ;;
        "stopped")
            print_info "LXC $lxc_id exists but stopped, starting and updating..."
            pct start "$lxc_id"
            ensure_datapool_mount "$lxc_id"
            ensure_datapool_permissions "$stack_type"
            print_success "✓ LXC $lxc_id started and updated!"
            return 0
            ;;
        *)
            print_warning "LXC $lxc_id in unknown state: $lxc_status, attempting recovery..."
            pct start "$lxc_id" >/dev/null 2>&1 || true
            ensure_datapool_mount "$lxc_id"
            ensure_datapool_permissions "$stack_type"
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
    print_info "  - proxy     (LXC 100): Cloudflare tunnels"
    print_info "  - media     (LXC 101): Media automation stack"
    print_info "  - files     (LXC 102): File management tools"
    print_info "  - webtools  (LXC 103): Homepage and web tools"
    print_info "  - monitoring(LXC 104): Monitoring and alerting"
    print_info "  - content   (LXC 105): Content management (reserved)"
    exit 1
fi

# Validate stack type
STACK_TYPE=$1
case "$STACK_TYPE" in
    proxy|media|files|webtools|monitoring|content)
        ;;
    *)
        print_error "Invalid stack type: $STACK_TYPE"
        print_info "Valid types: proxy, media, files, webtools, monitoring, content"
        exit 1
        ;;
esac

# Root check
check_root

# Execute unified creation
print_info "=== Alpine LXC Creation - $STACK_TYPE Stack ==="
print_info "Using unified creation functions from common.sh"

if create_alpine_lxc_unified "$STACK_TYPE"; then
    print_success "🎉 $STACK_TYPE LXC created successfully!"
    print_info ""
    print_info "✓ Alpine Linux with Docker and Docker Compose"
    print_info "✓ Unprivileged container with proper security"
    print_info "✓ /datapool mount point with correct permissions"
    print_info "✓ Container ready for stack deployment"
    print_info ""
    
    # Show next steps
    lxc_id=$(get_stack_lxc_id "$STACK_TYPE")
    print_info "Next steps:"
    print_info "  1. Deploy stack: bash scripts/automation/deploy_stack.sh $STACK_TYPE"
    print_info "  2. Access container: pct enter $lxc_id"
    print_info "  3. Check services: pct exec $lxc_id -- docker compose ps"
else
    print_error "Failed to create $STACK_TYPE LXC"
    exit 1
fi