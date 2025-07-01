#!/bin/bash

# Unified LXC Management Script
# Handles creation, deployment, and management of all LXC stacks

set -e

# Source configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/stack-config.sh"

# Print functions
print_info() { echo -e "\033[36m[INFO]\033[0m $1"; }
print_success() { echo -e "\033[32m[SUCCESS]\033[0m $1"; }
print_error() { echo -e "\033[31m[ERROR]\033[0m $1"; }
print_warning() { echo -e "\033[33m[WARNING]\033[0m $1"; }

# Check if running on Proxmox
check_proxmox_environment() {
    if ! command -v pct >/dev/null 2>&1; then
        print_error "This script must be run on a Proxmox VE host"
        exit 1
    fi
    
    if [ "$(id -u)" -ne 0 ]; then
        print_error "This script must be run as root"
        exit 1
    fi
}

# Create LXC container
create_lxc() {
    local stack_type="$1"
    
    print_info "Creating $stack_type stack LXC container..."
    
    # Validate stack type
    if ! validate_stack_type "$stack_type"; then
        return 1
    fi
    
    # Get stack specifications
    local specs
    specs=$(get_stack_specs "$stack_type")
    
    declare -A config
    parse_stack_specs "$specs" config
    
    # Display configuration
    show_stack_info "$stack_type"
    
    # Check if container already exists
    if pct status "${config[id]}" >/dev/null 2>&1; then
        print_warning "LXC ${config[id]} already exists. Skipping creation."
        return 0
    fi
    
    print_info "Using ${config[template]} template for container creation..."
    
    # Export variables for community script (var_ prefix required)
    export var_cpu="${config[cores]}"
    export var_ram="${config[memory]}"
    export var_disk="${config[disk]}"
    export var_tags="homelab-stack;${config[template]};docker"
    export var_unprivileged="1"
    export SILENT="1"
    
    # Use appropriate community script based on template
    local script_url
    if [[ "${config[template]}" == "alpine" ]]; then
        script_url="https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/ct/alpine-docker.sh"
    else
        script_url="https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/ct/ubuntu.sh"
    fi
    
    print_info "Running community script with exported variables: $script_url"
    bash -c "$(curl -fsSL $script_url)"
    
    # Configure hostname and network (community script doesn't support these via env vars)
    print_info "Configuring hostname and network..."
    pct set "${config[id]}" --hostname "${config[hostname]}"
    pct set "${config[id]}" --net0 name=eth0,bridge=vmbr0,ip="${config[ip]}",gw=192.168.1.1
    
    # Add datapool mount
    print_info "Adding datapool mount..."
    pct set "${config[id]}" -mp0 /datapool,mp=/datapool,acl=1
    
    # Wait for container to be ready
    print_info "Waiting for container to be ready..."
    sleep 5
    
    # Start container if not running
    if ! pct status "${config[id]}" | grep -q "running"; then
        print_info "Starting container..."
        pct start "${config[id]}"
        sleep 10
    fi
    
    print_success "$stack_type stack LXC created successfully!"
}

# Deploy stack services
deploy_stack() {
    local stack_type="$1"
    
    print_info "Deploying $stack_type stack services..."
    
    # Validate stack type
    if ! validate_stack_type "$stack_type"; then
        return 1
    fi
    
    # Get stack specifications
    local specs
    specs=$(get_stack_specs "$stack_type")
    
    declare -A config
    parse_stack_specs "$specs" config
    
    # Check if container exists and is running
    if ! pct status "${config[id]}" | grep -q "running"; then
        print_error "Container ${config[id]} is not running. Please create it first."
        return 1
    fi
    
    # Call the deploy-stack.sh script
    local deploy_script="$SCRIPT_DIR/deploy-stack.sh"
    if [[ -f "$deploy_script" ]]; then
        bash "$deploy_script" "$stack_type"
    else
        print_error "Deploy script not found: $deploy_script"
        return 1
    fi
    
    print_success "$stack_type stack deployed successfully!"
}

# Full deployment (create + deploy)
full_deploy() {
    local stack_type="$1"
    
    print_info "Starting full deployment of $stack_type stack..."
    
    # Create LXC
    if create_lxc "$stack_type"; then
        # Deploy services
        deploy_stack "$stack_type"
    else
        print_error "Failed to create LXC for $stack_type stack"
        return 1
    fi
}

# Show container status
show_status() {
    local stack_type="$1"
    
    if ! validate_stack_type "$stack_type"; then
        return 1
    fi
    
    local specs
    specs=$(get_stack_specs "$stack_type")
    
    declare -A config
    parse_stack_specs "$specs" config
    
    print_info "Status for $stack_type stack (LXC ${config[id]}):"
    
    if pct status "${config[id]}" >/dev/null 2>&1; then
        pct status "${config[id]}"
        
        # Show resource usage if running
        if pct status "${config[id]}" | grep -q "running"; then
            echo ""
            print_info "Resource usage:"
            pct exec "${config[id]}" -- free -h 2>/dev/null || true
            pct exec "${config[id]}" -- df -h / 2>/dev/null || true
        fi
    else
        print_warning "Container ${config[id]} does not exist"
    fi
}

# List all stacks
list_stacks() {
    print_info "Available stacks:"
    echo ""
    
    for stack_type in $(get_available_stacks); do
        local specs
        specs=$(get_stack_specs "$stack_type")
        
        declare -A config
        parse_stack_specs "$specs" config
        
        local status="Not Created"
        if pct status "${config[id]}" >/dev/null 2>&1; then
            status=$(pct status "${config[id]}" | awk '{print $2}')
        fi
        
        printf "  %-12s | LXC %-3s | %-8s | %s cores, %sGB RAM\n" \
            "$stack_type" "${config[id]}" "$status" "${config[cores]}" "$((${config[memory]}/1024))"
    done
}

# Main function
main() {
    local action="$1"
    local stack_type="$2"
    
    # Check environment
    check_proxmox_environment
    
    case "$action" in
        "create")
            if [[ -z "$stack_type" ]]; then
                print_error "Usage: $0 create <stack_type>"
                echo "Available stacks: $(get_available_stacks)"
                exit 1
            fi
            create_lxc "$stack_type"
            ;;
        "deploy")
            if [[ -z "$stack_type" ]]; then
                print_error "Usage: $0 deploy <stack_type>"
                echo "Available stacks: $(get_available_stacks)"
                exit 1
            fi
            deploy_stack "$stack_type"
            ;;
        "full")
            if [[ -z "$stack_type" ]]; then
                print_error "Usage: $0 full <stack_type>"
                echo "Available stacks: $(get_available_stacks)"
                exit 1
            fi
            full_deploy "$stack_type"
            ;;
        "status")
            if [[ -z "$stack_type" ]]; then
                print_error "Usage: $0 status <stack_type>"
                echo "Available stacks: $(get_available_stacks)"
                exit 1
            fi
            show_status "$stack_type"
            ;;
        "list")
            list_stacks
            ;;
        "info")
            if [[ -z "$stack_type" ]]; then
                print_error "Usage: $0 info <stack_type>"
                echo "Available stacks: $(get_available_stacks)"
                exit 1
            fi
            show_stack_info "$stack_type"
            ;;
        *)
            echo "Usage: $0 {create|deploy|full|status|list|info} [stack_type]"
            echo ""
            echo "Commands:"
            echo "  create <stack>  - Create LXC container only"
            echo "  deploy <stack>  - Deploy services to existing container"
            echo "  full <stack>    - Create container and deploy services"
            echo "  status <stack>  - Show container status"
            echo "  list           - List all available stacks"
            echo "  info <stack>   - Show stack configuration"
            echo ""
            echo "Available stacks: $(get_available_stacks)"
            exit 1
            ;;
    esac
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi