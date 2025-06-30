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
    
    # Get LXC ID and specifications from common.sh
    local lxc_id=$(get_stack_lxc_id "$stack_type")
    if [ $? -ne 0 ]; then
        return 1
    fi
    
    local specs=$(get_stack_specifications "$stack_type")
    local template_type=$(echo "$specs" | grep -o 'template=[a-z]*' | cut -d'=' -f2)
    
    # Check current LXC status (idempotent)
    local lxc_status=$(check_lxc_status "$lxc_id")
    
    case "$lxc_status" in
        "not_exists")
            print_long_operation "Creating LXC $lxc_id..."
            ;;
        "running")
            ensure_datapool_mount "$lxc_id"
            ensure_datapool_permissions "$stack_type"
            return 0
            ;;
        "stopped")
            pct start "$lxc_id"
            ensure_datapool_mount "$lxc_id"
            ensure_datapool_permissions "$stack_type"
            return 0
            ;;
        *)
            pct start "$lxc_id" >/dev/null 2>&1 || true
            ensure_datapool_mount "$lxc_id"
            ensure_datapool_permissions "$stack_type"
            return 0
            ;;
    esac
    
    # Download template
    print_long_operation "Getting latest $template_type template..."
    local template_path=$(download_and_prepare_template "$template_type")
    if [ $? -ne 0 ]; then
        print_error "Failed to prepare template"
        return 1
    fi
    
    # Create LXC container
    if create_lxc_container "$stack_type" "$lxc_id" "$specs" "$template_path"; then
        # Configure container post-creation
        configure_container_post_creation "$lxc_id" "$stack_type" "$template_type"
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
if ! create_alpine_lxc_unified "$STACK_TYPE"; then
    print_error "Failed to create $STACK_TYPE LXC"
    exit 1
fi