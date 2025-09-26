#!/bin/bash

# =================================================================
#                  Proxmox Environment Validation
# =================================================================
# Validates Proxmox VE environment prerequisites before deployment
# Follows fail-fast approach - exits immediately on any validation failure
set -euo pipefail

WORK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)"

# Load logging utilities
source "$WORK_DIR/scripts/logger.sh"

# Required Proxmox tools and features
readonly REQUIRED_COMMANDS=("pct" "pvesm" "qm")
readonly REQUIRED_STORAGE="datapool"
readonly REQUIRED_BRIDGE="vmbr0" 
readonly EXPECTED_GATEWAY="192.168.1.1"

# Validate Proxmox VE is running
validate_proxmox_host() {
    log_info "Validating Proxmox VE host environment"
    
    # Check if we're on a PVE host
    if [[ ! -f /etc/pve/local/pve-ssl.pem ]]; then
        fail_fast "Not running on Proxmox VE host - /etc/pve not found"
    fi
    
    # Check if PVE services are running
    if ! systemctl is-active pveproxy >/dev/null 2>&1; then
        fail_fast "Proxmox VE services not running - pveproxy inactive"
    fi
    
    log_success "Proxmox VE host validated"
}

# Validate required commands are available
validate_commands() {
    log_info "Validating required Proxmox commands"
    
    for cmd in "${REQUIRED_COMMANDS[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            fail_fast "Required command not found: $cmd"
        fi
        log_info "✓ Command available: $cmd"
    done
    
    log_success "All required commands available"
}

# Validate datapool storage exists and is accessible
validate_storage() {
    log_info "Validating storage pool: $REQUIRED_STORAGE"
    
    # Check if storage pool exists in PVE configuration
    if ! pvesm status | grep -q "^$REQUIRED_STORAGE"; then
        fail_fast "Storage pool not found: $REQUIRED_STORAGE"
    fi
    
    # Check if storage is enabled and available
    local storage_status
    storage_status=$(pvesm status | grep "^$REQUIRED_STORAGE" | awk '{print $2}')
    if [[ "$storage_status" != "active" ]]; then
        fail_fast "Storage pool not active: $REQUIRED_STORAGE (status: $storage_status)"
    fi
    
    # Test storage write access
    local test_file="/$REQUIRED_STORAGE/.homelab-test-$$"
    if ! touch "$test_file" 2>/dev/null; then
        fail_fast "Storage pool not writable: $REQUIRED_STORAGE"
    fi
    rm -f "$test_file"
    
    log_success "Storage pool validated: $REQUIRED_STORAGE"
}

# Validate network bridge exists and is configured
validate_network() {
    log_info "Validating network bridge: $REQUIRED_BRIDGE"
    
    # Check if bridge exists
    if ! ip link show "$REQUIRED_BRIDGE" >/dev/null 2>&1; then
        fail_fast "Network bridge not found: $REQUIRED_BRIDGE"
    fi
    
    # Check if bridge is up
    local bridge_state
    bridge_state=$(ip link show "$REQUIRED_BRIDGE" | grep -o "state [A-Z]*" | cut -d' ' -f2)
    if [[ "$bridge_state" != "UP" ]]; then
        fail_fast "Network bridge not up: $REQUIRED_BRIDGE (state: $bridge_state)"
    fi
    
    # Check gateway connectivity (best effort - don't fail deployment)
    if ping -c 1 -W 2 "$EXPECTED_GATEWAY" >/dev/null 2>&1; then
        log_success "Gateway reachable: $EXPECTED_GATEWAY"
    else
        log_warning "Gateway not reachable: $EXPECTED_GATEWAY (continuing anyway)"
    fi
    
    log_success "Network bridge validated: $REQUIRED_BRIDGE"
}

# Validate LXC container capabilities
validate_lxc() {
    log_info "Validating LXC container support"
    
    # Check if LXC is properly installed
    if ! systemctl is-active lxc >/dev/null 2>&1; then
        log_warning "LXC service not active - may be normal on PVE"
    fi
    
    # Test basic pct functionality
    if ! pct list >/dev/null 2>&1; then
        fail_fast "PCT command not working - LXC not properly configured"
    fi
    
    # Check for available LXC templates
    local template_count
    template_count=$(pveam available | grep -c "template" || echo "0")
    if [[ "$template_count" -eq 0 ]]; then
        log_warning "No LXC templates available - will download during deployment"
    else
        log_info "Available LXC templates: $template_count"
    fi
    
    log_success "LXC container support validated"
}

# Validate system resources
validate_resources() {
    log_info "Validating system resources"
    
    # Check available memory (minimum 4GB for homelab)
    local total_mem_kb
    total_mem_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local total_mem_gb=$((total_mem_kb / 1024 / 1024))
    
    if [[ $total_mem_gb -lt 4 ]]; then
        fail_fast "Insufficient memory: ${total_mem_gb}GB (minimum 4GB required)"
    fi
    log_info "✓ Available memory: ${total_mem_gb}GB"
    
    # Check available CPU cores (minimum 2 for homelab)
    local cpu_cores
    cpu_cores=$(nproc)
    if [[ $cpu_cores -lt 2 ]]; then
        fail_fast "Insufficient CPU cores: $cpu_cores (minimum 2 required)"
    fi
    log_info "✓ Available CPU cores: $cpu_cores"
    
    # Check disk space on datapool (minimum 50GB free)
    if [[ -d "/$REQUIRED_STORAGE" ]]; then
        local available_gb
        available_gb=$(df -BG "/$REQUIRED_STORAGE" | tail -1 | awk '{print $4}' | tr -d 'G')
        if [[ $available_gb -lt 50 ]]; then
            fail_fast "Insufficient disk space on $REQUIRED_STORAGE: ${available_gb}GB (minimum 50GB required)"
        fi
        log_info "✓ Available disk space: ${available_gb}GB"
    fi
    
    log_success "System resources validated"
}

# Validate Docker support for containers
validate_docker_support() {
    log_info "Validating Docker support for LXC containers"
    
    # Check if Docker can be installed (test with package availability)
    if apt-cache search docker.io | grep -q docker.io; then
        log_info "✓ Docker packages available"
    else
        log_warning "Docker packages not found in repository - may need to update apt cache"
    fi
    
    # Check kernel features needed for Docker in LXC
    if [[ -f /proc/config.gz ]]; then
        if zcat /proc/config.gz | grep -q "CONFIG_CGROUPS=y"; then
            log_info "✓ Kernel cgroups support available"
        else
            log_warning "Kernel cgroups support not detected"
        fi
    fi
    
    log_success "Docker support validated"
}

# Run comprehensive validation
run_validation() {
    log_info "Starting Proxmox environment validation"
    log_info "========================================"
    
    validate_proxmox_host
    validate_commands  
    validate_storage
    validate_network
    validate_lxc
    validate_resources
    validate_docker_support
    
    log_success "========================================"
    log_success "All validations passed - environment ready for deployment"
}

# Quick validation (skip resource checks)
run_quick_validation() {
    log_info "Running quick environment validation"
    
    validate_proxmox_host
    validate_commands
    validate_storage
    validate_network
    
    log_success "Quick validation passed"
}

# Main entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-full}" in
        "full")
            run_validation
            ;;
        "quick")
            run_quick_validation
            ;;
        "host")
            validate_proxmox_host
            ;;
        "commands")
            validate_commands
            ;;
        "storage")
            validate_storage
            ;;
        "network")
            validate_network
            ;;
        "lxc")
            validate_lxc
            ;;
        "resources")
            validate_resources
            ;;
        *)
            echo "Usage: $0 {full|quick|host|commands|storage|network|lxc|resources}"
            echo ""
            echo "Validation modes:"
            echo "  full      - Complete validation (default)"
            echo "  quick     - Skip resource validation"
            echo ""
            echo "Individual checks:"
            echo "  host      - Proxmox VE host validation"
            echo "  commands  - Required commands availability"  
            echo "  storage   - Storage pool validation"
            echo "  network   - Network bridge validation"
            echo "  lxc       - LXC container support"
            echo "  resources - System resource validation"
            exit 1
            ;;
    esac
fi