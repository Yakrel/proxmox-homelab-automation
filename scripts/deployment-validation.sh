#!/bin/bash

# =================================================================
#                    Deployment Validation Scripts
# =================================================================
# Comprehensive validation utilities for verifying successful deployments
# Container status, service health, and network connectivity checks
set -euo pipefail

WORK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)"

# Load shared functions
source "$WORK_DIR/scripts/helper-functions.sh"
source "$WORK_DIR/scripts/logger.sh"

# Validate LXC container status
validate_container_status() {
    local ct_id="$1"
    local expected_status="${2:-running}"
    
    log_info "Validating container $ct_id status"
    
    if ! pct status "$ct_id" >/dev/null; then
        log_error "Container $ct_id does not exist"
        return 1
    fi
    
    local current_status
    current_status=$(pct status "$ct_id" | awk '{print $2}')
    
    if [[ "$current_status" != "$expected_status" ]]; then
        log_error "Container $ct_id status: $current_status (expected: $expected_status)"
        return 1
    fi
    
    log_success "Container $ct_id is $current_status"
    return 0
}

# Validate container network connectivity
validate_container_network() {
    local ct_id="$1"
    local ct_ip="$2"
    
    log_info "Validating container $ct_id network connectivity"
    
    # Test ping to container
    if ! ping -c 1 -W 2 "$ct_ip" >/dev/null 2>&1; then
        log_error "Container $ct_id not reachable at $ct_ip"
        return 1
    fi
    
    # Test container can reach gateway
    local gateway="192.168.1.1"
    if ! pct exec "$ct_id" -- ping -c 1 -W 2 "$gateway" >/dev/null 2>&1; then
        log_warning "Container $ct_id cannot reach gateway $gateway"
        # Don't fail deployment for gateway connectivity
    fi
    
    # Test container can resolve DNS
    if ! pct exec "$ct_id" -- nslookup google.com >/dev/null 2>&1; then
        log_warning "Container $ct_id DNS resolution issues"
        # Don't fail deployment for DNS issues
    fi
    
    log_success "Container $ct_id network validation passed"
    return 0
}

# Validate Docker services in container (for Docker stacks)
validate_docker_services() {
    local ct_id="$1"
    local stack_name="$2"
    
    log_info "Validating Docker services in container $ct_id ($stack_name)"
    
    # Skip validation for non-Docker stacks
    if [[ "$stack_name" == "backup" || "$stack_name" == "development" ]]; then
        log_info "Skipping Docker validation for $stack_name stack"
        return 0
    fi
    
    # Check if Docker is running
    if ! pct exec "$ct_id" -- docker info >/dev/null 2>&1; then
        log_error "Docker not running in container $ct_id"
        return 1
    fi
    
    # Check if docker-compose.yml exists
    if ! pct exec "$ct_id" -- test -f /root/docker-compose.yml; then
        log_error "docker-compose.yml not found in container $ct_id"
        return 1
    fi
    
    # Get list of expected services
    local services
    services=$(pct exec "$ct_id" -- docker-compose config --services 2>/dev/null || echo "")
    
    if [[ -z "$services" ]]; then
        log_warning "No Docker services found in $stack_name stack"
        return 0
    fi
    
    # Validate each service is running
    local failed_services=()
    while IFS= read -r service; do
        [[ -z "$service" ]] && continue
        
        if ! pct exec "$ct_id" -- docker-compose ps -q "$service" | grep -q .; then
            failed_services+=("$service")
            log_warning "Service not running: $service"
        else
            log_info "✓ Service running: $service"
        fi
    done <<< "$services"
    
    if [[ ${#failed_services[@]} -gt 0 ]]; then
        log_warning "${#failed_services[@]} services not running in $stack_name: ${failed_services[*]}"
        # Don't fail deployment - services might still be starting
    fi
    
    log_success "Docker services validation completed for $stack_name"
    return 0
}

# Validate specific service endpoints
validate_service_endpoints() {
    local ct_ip="$1"
    local stack_name="$2"
    
    log_info "Validating service endpoints for $stack_name at $ct_ip"
    
    case "$stack_name" in
        "monitoring")
            # Grafana
            if curl -s -f "http://$ct_ip:3000/api/health" >/dev/null 2>&1; then
                log_success "Grafana endpoint responding"
            else
                log_warning "Grafana endpoint not responding (may still be starting)"
            fi
            
            # Prometheus  
            if curl -s -f "http://$ct_ip:9090/-/ready" >/dev/null 2>&1; then
                log_success "Prometheus endpoint responding"
            else
                log_warning "Prometheus endpoint not responding (may still be starting)"
            fi
            ;;
        "backup")
            # PBS Web Interface
            if curl -s -k -f "https://$ct_ip:8007/" >/dev/null 2>&1; then
                log_success "PBS web interface responding"
            else
                log_warning "PBS web interface not responding (may still be starting)"
            fi
            ;;
        "webtools")
            # Homepage
            if curl -s -f "http://$ct_ip:3000/" >/dev/null 2>&1; then
                log_success "Homepage endpoint responding"
            else
                log_warning "Homepage endpoint not responding (may still be starting)"
            fi
            ;;
        *)
            log_info "No specific endpoints to validate for $stack_name"
            ;;
    esac
    
    return 0
}

# Validate storage mounts
validate_storage_mounts() {
    local ct_id="$1"
    
    log_info "Validating storage mounts in container $ct_id"
    
    # Check datapool mount
    if ! pct exec "$ct_id" -- test -d /datapool; then
        log_error "Datapool not mounted in container $ct_id"
        return 1
    fi
    
    # Test write access to datapool
    local test_file="/datapool/.test-write-$$"
    if ! pct exec "$ct_id" -- touch "$test_file" 2>/dev/null; then
        log_error "Datapool not writable in container $ct_id"
        return 1
    fi
    
    # Cleanup test file
    pct exec "$ct_id" -- rm -f "$test_file" 2>/dev/null || true
    
    log_success "Storage mounts validated for container $ct_id"
    return 0
}

# Complete validation for a deployed stack
validate_stack_deployment() {
    local stack_name="$1"
    
    log_info "Running complete validation for stack: $stack_name"
    log_info "================================================"
    
    # Load stack configuration
    get_stack_config "$stack_name"
    
    local validation_failed=false
    
    # Container status validation
    if ! validate_container_status "$CT_ID"; then
        validation_failed=true
    fi
    
    # Network connectivity validation
    if ! validate_container_network "$CT_ID" "$CT_IP"; then
        validation_failed=true
    fi
    
    # Storage validation
    if ! validate_storage_mounts "$CT_ID"; then
        validation_failed=true
    fi
    
    # Docker services validation (if applicable)
    if ! validate_docker_services "$CT_ID" "$stack_name"; then
        validation_failed=true
    fi
    
    # Service endpoints validation
    validate_service_endpoints "$CT_IP" "$stack_name"
    
    # Summary
    if [[ "$validation_failed" == "true" ]]; then
        log_error "Validation failed for stack: $stack_name"
        return 1
    else
        log_success "Validation passed for stack: $stack_name"
        log_info "Stack access: http://$CT_IP (services may take a moment to fully start)"
        return 0
    fi
}

# Validate all deployed stacks
validate_all_stacks() {
    log_info "Validating all deployed stacks"
    log_info "=============================="
    
    local failed_stacks=()
    local validated_stacks=()
    
    # Get list of available stacks
    while IFS= read -r stack; do
        # Check if stack container exists and is running
        get_stack_config "$stack"
        
        if pct status "$CT_ID" >/dev/null 2>&1; then
            local status
            status=$(pct status "$CT_ID" 2>/dev/null | awk '{print $2}')
            
            if [[ "$status" == "running" ]]; then
                log_info "Validating deployed stack: $stack"
                if validate_stack_deployment "$stack"; then
                    validated_stacks+=("$stack")
                else
                    failed_stacks+=("$stack")
                fi
            else
                log_info "Skipping $stack (container not running)"
            fi
        else
            log_info "Skipping $stack (container not found)"
        fi
    done < <(get_available_stacks)
    
    # Summary report
    log_info "=============================="
    log_info "Validation Summary:"
    log_success "Validated stacks (${#validated_stacks[@]}): ${validated_stacks[*]:-none}"
    
    if [[ ${#failed_stacks[@]} -gt 0 ]]; then
        log_warning "Failed stacks (${#failed_stacks[@]}): ${failed_stacks[*]}"
        return 1
    fi
    
    log_success "All deployed stacks validated successfully"
    return 0
}

# Quick health check for a stack
quick_health_check() {
    local stack_name="$1"
    
    get_stack_config "$stack_name"
    
    echo "Stack: $stack_name (Container: $CT_ID, IP: $CT_IP)"
    echo "Status: $(pct status "$CT_ID" 2>/dev/null || echo "not found")"
    
    if pct status "$CT_ID" >/dev/null 2>&1; then
        echo "Ping: $(ping -c 1 -W 2 "$CT_IP" >/dev/null 2>&1 && echo "OK" || echo "FAIL")"
        
        if [[ "$stack_name" != "backup" && "$stack_name" != "development" ]]; then
            local docker_status="N/A"
            if pct exec "$CT_ID" -- docker info >/dev/null 2>&1; then
                docker_status="Running"
            else
                docker_status="Not running"
            fi
            echo "Docker: $docker_status"
        fi
    fi
    echo ""
}

# Main entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-}" in
        "stack")
            [[ -z "${2:-}" ]] && { log_error "Stack name required"; exit 1; }
            validate_stack_deployment "$2"
            ;;
        "all")
            validate_all_stacks
            ;;
        "quick")
            if [[ -n "${2:-}" ]]; then
                quick_health_check "$2"
            else
                # Quick check for all stacks
                while IFS= read -r stack; do
                    quick_health_check "$stack"
                done < <(get_available_stacks)
            fi
            ;;
        "container")
            [[ -z "${2:-}" ]] && { log_error "Container ID required"; exit 1; }
            validate_container_status "$2"
            ;;
        "network")
            [[ -z "${2:-}" || -z "${3:-}" ]] && { log_error "Container ID and IP required"; exit 1; }
            validate_container_network "$2" "$3"
            ;;
        *)
            echo "Usage: $0 {stack|all|quick|container|network} [arguments]"
            echo ""
            echo "Validation modes:"
            echo "  stack <name>     - Validate specific stack deployment"
            echo "  all              - Validate all deployed stacks"
            echo "  quick [name]     - Quick health check for stack(s)"
            echo ""
            echo "Individual checks:"
            echo "  container <id>   - Validate container status"
            echo "  network <id> <ip> - Validate container network"
            echo ""
            echo "Examples:"
            echo "  $0 stack monitoring     # Validate monitoring stack"
            echo "  $0 all                  # Validate all stacks"
            echo "  $0 quick                # Quick check all stacks"
            echo "  $0 quick media          # Quick check media stack"
            exit 1
            ;;
    esac
fi