#!/bin/bash

# =================================================================
#                 Cleanup and Maintenance Utilities
# =================================================================
# Container cleanup, environment management, and system maintenance
# Provides safe cleanup procedures and maintenance operations
set -euo pipefail

WORK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)"

# Load shared functions
source "$WORK_DIR/scripts/helper-functions.sh"
source "$WORK_DIR/scripts/logger.sh"

# Clean up temporary environment files
cleanup_env_files() {
    log_info "Cleaning up temporary environment files"
    
    local temp_files=(
        "/tmp/.env*"
        "/tmp/monitoring_env_temp*"
        "/tmp/docker-compose*"
        "/tmp/promtail_config*"
    )
    
    local cleaned_count=0
    
    for pattern in "${temp_files[@]}"; do
        # Use shell globbing to expand pattern, and process up to 10 files
        local count=0
        for file in $(compgen -G "$pattern" | head -10); do
            if [[ -f "$file" ]]; then
                rm -f "$file" && log_info "Removed: $file"
                ((cleaned_count++))
                ((count++))
            fi
        done
        # If no files matched, compgen returns nothing, so nothing happens
    done
    
    log_success "Environment cleanup completed"
}

# Stop and remove a stack's container
remove_stack_container() {
    local stack_name="$1"
    local force="${2:-false}"
    
    log_info "Removing container for stack: $stack_name"
    
    # Load stack configuration
    get_stack_config "$stack_name"
    
    # Check if container exists
    if ! pct status "$CT_ID" >/dev/null 2>&1; then
        log_warning "Container $CT_ID ($stack_name) not found"
        return 0
    fi
    
    # Get current status
    local status
    status=$(pct status "$CT_ID" 2>/dev/null | awk '{print $2}')
    
    # Stop container if running
    if [[ "$status" == "running" ]]; then
        log_info "Stopping container $CT_ID"
        if [[ "$force" == "true" ]]; then
            pct stop "$CT_ID" || log_warning "Failed to gracefully stop container $CT_ID"
        else
            if ! pct stop "$CT_ID" 2>/dev/null; then
                log_error "Failed to stop container $CT_ID - use 'force' option if needed"
                return 1
            fi
        fi
    fi
    
    # Remove container
    log_info "Destroying container $CT_ID ($CT_HOSTNAME)"
    if pct destroy "$CT_ID" 2>/dev/null; then
        log_success "Container $CT_ID removed successfully"
    else
        log_error "Failed to destroy container $CT_ID"
        return 1
    fi
    
    return 0
}

# Clean up Docker resources in a container
cleanup_docker_resources() {
    local ct_id="$1"
    local aggressive="${2:-false}"
    
    log_info "Cleaning up Docker resources in container $ct_id"
    
    # Check if container is running
    if ! pct status "$ct_id" | grep -q "running"; then
        log_warning "Container $ct_id not running - skipping Docker cleanup"
        return 0
    fi
    
    # Check if Docker is available
    if ! pct exec "$ct_id" -- docker info >/dev/null 2>&1; then
        log_info "Docker not running in container $ct_id - skipping cleanup"
        return 0
    fi
    
    # Stop all containers
    log_info "Stopping Docker containers"
    pct exec "$ct_id" -- docker stop \$(docker ps -q) 2>/dev/null || log_info "No running containers to stop"
    
    # Remove stopped containers
    log_info "Removing stopped containers"
    pct exec "$ct_id" -- docker container prune -f >/dev/null 2>&1 || true
    
    if [[ "$aggressive" == "true" ]]; then
        # Remove unused images
        log_info "Removing unused Docker images"
        pct exec "$ct_id" -- docker image prune -f >/dev/null 2>&1 || true
        
        # Remove unused volumes
        log_info "Removing unused Docker volumes"  
        pct exec "$ct_id" -- docker volume prune -f >/dev/null 2>&1 || true
        
        # Remove unused networks
        log_info "Removing unused Docker networks"
        pct exec "$ct_id" -- docker network prune -f >/dev/null 2>&1 || true
    fi
    
    log_success "Docker cleanup completed for container $ct_id"
}

# Clean up all containers for multiple stacks
cleanup_multiple_stacks() {
    local stack_names=("$@")
    local failed_stacks=()
    
    log_info "Cleaning up ${#stack_names[@]} stacks: ${stack_names[*]}"
    
    for stack in "${stack_names[@]}"; do
        log_info "Processing stack: $stack"
        
        if remove_stack_container "$stack" "false"; then
            log_success "Successfully cleaned up stack: $stack"
        else
            failed_stacks+=("$stack")
            log_warning "Failed to clean up stack: $stack"
        fi
    done
    
    if [[ ${#failed_stacks[@]} -gt 0 ]]; then
        log_warning "Failed to clean up stacks: ${failed_stacks[*]}"
        return 1
    fi
    
    log_success "All stacks cleaned up successfully"
    return 0
}

# Log rotation and cleanup
cleanup_logs() {
    local max_size="${1:-100M}"
    local max_age="${2:-30}"
    
    log_info "Cleaning up system logs (max size: $max_size, max age: ${max_age} days)"
    
    # Clean journald logs
    if command -v journalctl >/dev/null 2>&1; then
        log_info "Rotating journald logs"
        journalctl --vacuum-size="$max_size" >/dev/null 2>&1 || true
        journalctl --vacuum-time="${max_age}d" >/dev/null 2>&1 || true
    fi
    
    # Clean old log files in /var/log
    log_info "Cleaning old log files"
    find /var/log -name "*.log.*" -type f -mtime +"$max_age" -delete 2>/dev/null || true
    find /var/log -name "*.gz" -type f -mtime +"$max_age" -delete 2>/dev/null || true
    
    # Clean container-specific logs
    if [[ -d /var/lib/lxc ]]; then
        find /var/lib/lxc -name "*.log*" -type f -mtime +"$max_age" -delete 2>/dev/null || true
    fi
    
    log_success "Log cleanup completed"
}

# System maintenance tasks
run_system_maintenance() {
    log_info "Running system maintenance tasks"
    log_info "================================"
    
    # Update package cache
    log_info "Updating package cache"
    apt-get update -q >/dev/null 2>&1 || log_warning "Failed to update package cache"
    
    # Clean package cache
    log_info "Cleaning package cache"
    apt-get autoclean >/dev/null 2>&1 || true
    apt-get autoremove -y >/dev/null 2>&1 || true
    
    # Clean temporary files
    cleanup_env_files
    
    # Log rotation
    cleanup_logs
    
    # Check disk usage
    log_info "Disk usage summary:"
    df -h / /datapool 2>/dev/null || df -h /
    
    log_success "System maintenance completed"
}

# Interactive stack removal menu
interactive_cleanup() {
    log_info "Interactive Stack Cleanup"
    log_info "========================"
    
    # Get list of deployed stacks (containers that exist)
    local deployed_stacks=()
    while IFS= read -r stack; do
        get_stack_config "$stack"
        if pct status "$CT_ID" >/dev/null 2>&1; then
            deployed_stacks+=("$stack")
        fi
    done < <(get_available_stacks)
    
    if [[ ${#deployed_stacks[@]} -eq 0 ]]; then
        log_info "No deployed stacks found"
        return 0
    fi
    
    log_info "Deployed stacks:"
    for i in "${!deployed_stacks[@]}"; do
        local stack="${deployed_stacks[$i]}"
        get_stack_config "$stack"
        local status=$(pct status "$CT_ID" 2>/dev/null | awk '{print $2}')
        echo "$((i+1)). $stack (CT:$CT_ID, Status:$status)"
    done
    
    echo "$((${#deployed_stacks[@]}+1)). Clean all stacks"
    echo "$((${#deployed_stacks[@]}+2)). Cancel"
    
    echo ""
    read -p "Select stack to remove (or option): " choice
    
    if [[ "$choice" =~ ^[0-9]+$ ]]; then
        if [[ "$choice" -ge 1 && "$choice" -le ${#deployed_stacks[@]} ]]; then
            local selected_stack="${deployed_stacks[$((choice-1))]}"
            echo ""
            read -p "Remove stack '$selected_stack'? (y/N): " confirm
            if [[ "$confirm" =~ ^[Yy]$ ]]; then
                remove_stack_container "$selected_stack" "true"
            else
                log_info "Cancelled"
            fi
        elif [[ "$choice" -eq $((${#deployed_stacks[@]}+1)) ]]; then
            echo ""
            read -p "Remove ALL deployed stacks? (y/N): " confirm
            if [[ "$confirm" =~ ^[Yy]$ ]]; then
                cleanup_multiple_stacks "${deployed_stacks[@]}"
            else
                log_info "Cancelled"
            fi
        else
            log_info "Cancelled"
        fi
    else
        log_info "Invalid selection"
    fi
}

# Show cleanup help
show_cleanup_help() {
    cat << 'EOF'
Cleanup and Maintenance Utilities
================================

Usage: cleanup-maintenance.sh <command> [options]

Commands:
  stack <name> [force]     - Remove specific stack container
  multiple <stack1 stack2> - Remove multiple stack containers
  docker <ct_id> [aggr]    - Clean Docker resources in container
  env                      - Clean temporary environment files
  logs [size] [days]       - Rotate and clean system logs
  maintenance              - Run complete system maintenance
  interactive              - Interactive stack removal menu
  
Examples:
  cleanup-maintenance.sh stack media          # Remove media stack
  cleanup-maintenance.sh stack proxy force    # Force remove proxy stack
  cleanup-maintenance.sh docker 104 aggr     # Aggressive Docker cleanup
  cleanup-maintenance.sh env                  # Clean temp files
  cleanup-maintenance.sh logs 50M 7          # Clean logs >50MB, >7 days
  cleanup-maintenance.sh maintenance         # Full maintenance
  cleanup-maintenance.sh interactive         # Interactive menu

Options:
  force - Force container removal (for stuck containers)
  aggr  - Aggressive Docker cleanup (removes images/volumes)
EOF
}

# Main entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-}" in
        "stack")
            [[ -z "${2:-}" ]] && { log_error "Stack name required"; exit 1; }
            remove_stack_container "$2" "${3:-false}"
            ;;
        "multiple") 
            shift
            [[ $# -eq 0 ]] && { log_error "At least one stack name required"; exit 1; }
            cleanup_multiple_stacks "$@"
            ;;
        "docker")
            [[ -z "${2:-}" ]] && { log_error "Container ID required"; exit 1; }
            cleanup_docker_resources "$2" "${3:-false}"
            ;;
        "env")
            cleanup_env_files
            ;;
        "logs")
            cleanup_logs "${2:-100M}" "${3:-30}"
            ;;
        "maintenance")
            run_system_maintenance
            ;;
        "interactive")
            interactive_cleanup
            ;;
        "help"|"-h"|"--help")
            show_cleanup_help
            ;;
        *)
            show_cleanup_help
            exit 1
            ;;
    esac
fi