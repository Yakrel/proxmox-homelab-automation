#!/bin/bash
# =================================================================
#         PBS Backup System Validation Script
# =================================================================
# This script validates that the PBS backup system has been
# correctly deployed and configured.

set -e

# --- Configuration ---
PBS_CT_ID="150"
PBS_HOSTNAME="lxc-backup-01"
PBS_IP="192.168.1.150"
PBS_PORT="8007"
DATASTORE_NAME="backup-datastore"
DATASTORE_PATH="/datapool/backups"
BACKUP_JOB_ID="pbs-homelab-backup"
STORAGE_NAME="pbs-backup"

# --- Helper Functions ---
print_info() { echo -e "\033[36m[INFO]\033[0m $1"; }
print_success() { echo -e "\033[32m[SUCCESS]\033[0m $1"; }
print_error() { echo -e "\033[31m[ERROR]\033[0m $1"; }
print_warning() { echo -e "\033[33m[WARNING]\033[0m $1"; }

# --- Validation Functions ---

validate_lxc_container() {
    print_info "Validating PBS LXC container..."
    
    if pct status "$PBS_CT_ID" >/dev/null 2>&1; then
        local status=$(pct status "$PBS_CT_ID" | awk '{print $2}')
        if [ "$status" = "running" ]; then
            print_success "LXC container $PBS_CT_ID is running"
        else
            print_error "LXC container $PBS_CT_ID exists but is not running (status: $status)"
            return 1
        fi
    else
        print_error "LXC container $PBS_CT_ID does not exist"
        return 1
    fi
    
    # Check mount point
    if pct exec "$PBS_CT_ID" -- test -d "$DATASTORE_PATH"; then
        print_success "Datastore path $DATASTORE_PATH is mounted in container"
    else
        print_error "Datastore path $DATASTORE_PATH is not accessible in container"
        return 1
    fi
}

validate_pbs_service() {
    print_info "Validating PBS service..."
    
    if pct exec "$PBS_CT_ID" -- systemctl is-active proxmox-backup >/dev/null 2>&1; then
        print_success "Proxmox Backup Server service is running"
    else
        print_error "Proxmox Backup Server service is not running"
        return 1
    fi
    
    # Check if PBS web interface is accessible
    if curl -k -s -o /dev/null -w "%{http_code}" "https://$PBS_IP:$PBS_PORT/" | grep -q "200\|401\|302"; then
        print_success "PBS web interface is accessible at https://$PBS_IP:$PBS_PORT/"
    else
        print_error "PBS web interface is not accessible"
        return 1
    fi
}

validate_pbs_datastore() {
    print_info "Validating PBS datastore configuration..."
    
    if pct exec "$PBS_CT_ID" -- proxmox-backup-manager datastore list 2>/dev/null | grep -q "$DATASTORE_NAME"; then
        print_success "PBS datastore '$DATASTORE_NAME' exists"
    else
        print_error "PBS datastore '$DATASTORE_NAME' not found"
        return 1
    fi
}

validate_pbs_schedules() {
    print_info "Validating PBS schedules and jobs..."
    
    # Check prune job
    if pct exec "$PBS_CT_ID" -- proxmox-backup-manager prune-job list 2>/dev/null | grep -q "$DATASTORE_NAME"; then
        print_success "PBS prune job configured for datastore"
    else
        print_warning "PBS prune job not found - this may be normal on first run"
    fi
    
    # Check verification job
    if pct exec "$PBS_CT_ID" -- proxmox-backup-manager verification-job list 2>/dev/null | grep -q "$DATASTORE_NAME"; then
        print_success "PBS verification job configured for datastore"
    else
        print_warning "PBS verification job not found - this may be normal on first run"
    fi
}

validate_pbs_user() {
    print_info "Validating PBS user configuration..."
    
    if pct exec "$PBS_CT_ID" -- proxmox-backup-manager user list 2>/dev/null | grep -q "proxmox-backup@pbs"; then
        print_success "PBS backup user 'proxmox-backup@pbs' exists"
    else
        print_error "PBS backup user 'proxmox-backup@pbs' not found"
        return 1
    fi
}

validate_proxmox_storage() {
    print_info "Validating Proxmox VE storage configuration..."
    
    if grep -q "^pbs: $STORAGE_NAME" /etc/pve/storage.cfg 2>/dev/null; then
        print_success "PBS storage '$STORAGE_NAME' configured in Proxmox VE"
    else
        print_error "PBS storage '$STORAGE_NAME' not found in Proxmox VE configuration"
        return 1
    fi
}

validate_backup_job() {
    print_info "Validating Proxmox VE backup job..."
    
    if [ -f /etc/pve/jobs.cfg ] && grep -q "^jobs: $BACKUP_JOB_ID" /etc/pve/jobs.cfg; then
        print_success "Backup job '$BACKUP_JOB_ID' configured"
    else
        print_error "Backup job '$BACKUP_JOB_ID' not found"
        return 1
    fi
}

validate_host_preparation() {
    print_info "Validating host preparation..."
    
    if [ -d "$DATASTORE_PATH" ]; then
        print_success "Backup directory $DATASTORE_PATH exists on host"
        
        # Check ownership
        local owner=$(stat -c %U "$DATASTORE_PATH" 2>/dev/null || echo "unknown")
        if [ "$owner" = "101000" ] || [ "$owner" = "root" ]; then
            print_success "Backup directory has correct ownership"
        else
            print_warning "Backup directory ownership may need adjustment (current: $owner)"
        fi
    else
        print_error "Backup directory $DATASTORE_PATH does not exist on host"
        return 1
    fi
}

# --- Main Validation ---
main() {
    echo
    print_info "=================================================="
    print_info "         PBS Backup System Validation"
    print_info "=================================================="
    echo
    
    local failed=0
    
    validate_host_preparation || failed=$((failed + 1))
    echo
    validate_lxc_container || failed=$((failed + 1))
    echo
    validate_pbs_service || failed=$((failed + 1))
    echo
    validate_pbs_datastore || failed=$((failed + 1))
    echo
    validate_pbs_schedules || failed=$((failed + 1))
    echo
    validate_pbs_user || failed=$((failed + 1))
    echo
    validate_proxmox_storage || failed=$((failed + 1))
    echo
    validate_backup_job || failed=$((failed + 1))
    echo
    
    print_info "=================================================="
    if [ $failed -eq 0 ]; then
        print_success "All validations passed! PBS backup system is ready."
        print_info "Web Interface: https://$PBS_IP:$PBS_PORT/"
        print_info "Next steps:"
        print_info "  1. Access PBS web interface to set admin password"
        print_info "  2. Monitor first backup job execution"
        print_info "  3. Test restore functionality"
    else
        print_error "$failed validation(s) failed. Please review and fix issues."
        exit 1
    fi
    print_info "=================================================="
    echo
}

# Run validation if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi