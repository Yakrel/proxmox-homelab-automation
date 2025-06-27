#!/bin/bash

# Interactive Setup Script for Stack Environment Configuration
# This script is now deprecated - unified environment management moved to deploy_stack.sh

# Load common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_SCRIPT="$SCRIPT_DIR/../utils/common.sh"

if [ -f "$COMMON_SCRIPT" ]; then
    source "$COMMON_SCRIPT"
else
    echo "[ERROR] common.sh not found!" >&2
    exit 1
fi

# Main function
main() {
    local stack_type=${1:-"all"}
    local base_dir=${2:-"/opt"}
    
    print_info "🔧 Interactive Stack Configuration Setup"
    print_info "Environment setup has been moved to unified system in deploy_stack.sh"
    print_info "This script is deprecated and will be removed in future versions"
    
    return 0
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi