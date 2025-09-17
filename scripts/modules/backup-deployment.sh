#!/bin/bash

# =================================================================
#                      Backup Stack Module
# =================================================================
# Specialized deployment for Proxmox Backup Server - fail fast approach
set -euo pipefail

# Configure PBS datastore and settings
configure_pbs_datastore() {
    local ct_id="$1"
    local datastore_name="$2"
    
    print_info "Configuring PBS datastore: $datastore_name"
    
    # Prepare host datastore directory with correct permissions for unprivileged LXC
    # PBS best practice: use /datapool/backups directly for the datastore
    local host_datastore_path="/datapool/backups"
    print_info "Preparing host datastore directory: $host_datastore_path"
    
    # Create directory on host if it doesn't exist
    mkdir -p "$host_datastore_path" || { print_error "Failed to create host datastore directory"; return 1; }
    
    # Set ownership for unprivileged container access
    # backup user inside container (UID 34) maps to host UID 101000
    chown 101000:101000 "$host_datastore_path" || {
        print_error "Failed to set proper ownership on datastore directory"
        return 1
    }
    
    # Set proper permissions
    chmod 755 "$host_datastore_path" || { print_error "Failed to set permissions"; return 1; }
    
    # Configure datastore in PBS using /datapool/backups (mounted as /datapool in container)
    pct exec "$ct_id" -- proxmox-backup-manager datastore create "$datastore_name" "/datapool/backups" 2>/dev/null || {
        print_info "Datastore exists, updating configuration"
        pct exec "$ct_id" -- proxmox-backup-manager datastore update "$datastore_name" \
            --comment "Main backup datastore on ZFS pool" 2>/dev/null || true
    }
    
    print_success "PBS datastore configured"
}

# Setup PBS monitoring user
setup_pbs_monitoring_user() {
    local ct_id="$1"
    local datastore_name="$2"
    
    print_info "Setting up PBS monitoring user"
    
    local prom_user="prometheus@pbs"
    local prom_pass_path="/root/.prometheus_password"
    
    # Get password from .env
    local prom_pass
    prom_pass=$(grep "^PBS_PROMETHEUS_PASSWORD=" "$ENV_DECRYPTED_PATH" | cut -d'=' -f2-)
    [[ -z "$prom_pass" ]] && { print_error "PBS_PROMETHEUS_PASSWORD not found in .env file"; return 1; }
    
    # Check if monitoring user already exists
    if pct exec "$ct_id" -- proxmox-backup-manager user list 2>/dev/null | grep -q "$prom_user"; then
        print_info "Updating existing PBS prometheus user password"
        pct exec "$ct_id" -- proxmox-backup-manager user update "$prom_user" --password "$prom_pass" 2>/dev/null || {
            print_warning "Failed to update prometheus user password"
            return 1
        }
    else
        print_info "Creating new PBS prometheus user"
        
        if ! pct exec "$ct_id" -- proxmox-backup-manager user create "$prom_user" --comment "Read-only user for Prometheus monitoring" 2>/dev/null; then
            print_warning "Failed to create monitoring user (PBS will still work)"
            return 1
        fi
        
        if ! pct exec "$ct_id" -- proxmox-backup-manager acl update /datastore/"$datastore_name" DatastoreAudit --auth-id "$prom_user" 2>/dev/null; then
            print_warning "Failed to set ACL for monitoring user"
            return 1
        fi
        
        if ! pct exec "$ct_id" -- proxmox-backup-manager user update "$prom_user" --password "$prom_pass"; then
            print_warning "Failed to set password for monitoring user"
            return 1
        fi
    fi
    
    # Always update password file for consistency
    if ! printf '%s' "$prom_pass" | pct exec "$ct_id" -- sh -c "cat > $prom_pass_path && chmod 600 $prom_pass_path"; then
        print_warning "Failed to save monitoring user password"
        return 1
    fi
    
    printf '%s' "$prom_pass" | pct exec "$ct_id" -- sh -c "cat > /root/.prometheus-password && chmod 600 /root/.prometheus-password" 2>/dev/null || true
    print_success "PBS prometheus user configured"
    
    return 0
}

# Configure PBS schedules
configure_pbs_schedules() {
    local ct_id="$1"
    local datastore_name="$2"
    local gc_schedule="$3"
    local prune_schedule="$4"
    
    print_info "Configuring PBS schedules"
    
    # Configure schedules - non-critical, continue if they fail
    local schedule_errors=0
    
    if ! pct exec "$ct_id" -- proxmox-backup-manager datastore update "$datastore_name" \
        --gc-schedule "$gc_schedule" 2>/dev/null; then
        print_warning "Failed to set garbage collection schedule"
        schedule_errors=$((schedule_errors + 1))
    fi
    
    if ! pct exec "$ct_id" -- proxmox-backup-manager datastore update "$datastore_name" \
        --prune-schedule "$prune_schedule" 2>/dev/null; then
        print_warning "Failed to set prune schedule"
        schedule_errors=$((schedule_errors + 1))
    fi
    
    # Create verify job (separate command from datastore update)
    if ! pct exec "$ct_id" -- proxmox-backup-manager verify-job create verify-daily --schedule "daily" --store "$datastore_name" --comment "Daily backup verification" 2>/dev/null; then
        print_warning "Failed to create verify job"
        schedule_errors=$((schedule_errors + 1))
    fi
    
    if [[ $schedule_errors -eq 0 ]]; then
        print_success "PBS schedules configured"
        return 0
    else
        print_warning "Some schedule configurations failed (can be set manually later)"
        return 1
    fi
}

# Complete PBS configuration
configure_pbs() {
    local ct_id="$1"
    
    print_info "Configuring Proxmox Backup Server"
    
    # Set PBS root password from .env file
    if [[ -n "${PBS_ADMIN_PASSWORD:-}" ]]; then
        print_info "Setting PBS root password"
        echo "root:$PBS_ADMIN_PASSWORD" | pct exec "$ct_id" -- chpasswd || {
            print_error "Failed to set PBS root password"
            return 1
        }
        print_success "PBS root password set"
    else
        print_warning "PBS_ADMIN_PASSWORD not provided, keeping default root password"
    fi
    
    # Read PBS-specific config from stacks.yaml
    local datastore_name
    local gc_schedule
    local prune_schedule
    local verify_schedule
    datastore_name=$(yq -r ".stacks.backup.pbs_datastore_name" "$WORK_DIR/stacks.yaml")
    gc_schedule=$(yq -r ".stacks.backup.pbs_gc_schedule" "$WORK_DIR/stacks.yaml")
    prune_schedule=$(yq -r ".stacks.backup.pbs_prune_schedule" "$WORK_DIR/stacks.yaml")
    verify_schedule=$(yq -r ".stacks.backup.pbs_verify_schedule" "$WORK_DIR/stacks.yaml")
    
    print_info "Checking PBS service status"
    if ! pct exec "$ct_id" -- systemctl is-active --quiet proxmox-backup; then
        print_info "Starting PBS service"
        if ! pct exec "$ct_id" -- systemctl start proxmox-backup; then
            print_error "Failed to start proxmox-backup service"
            return 1
        fi
        pct exec "$ct_id" -- systemctl enable proxmox-backup
        
        # Verify service started successfully - fail fast
        if ! pct exec "$ct_id" -- systemctl is-active --quiet proxmox-backup; then
            print_error "PBS service failed to start properly"
            print_info "Check logs: pct exec $ct_id -- journalctl -u proxmox-backup"
            return 1
        fi
    fi
    
    # Configure datastore
    if ! configure_pbs_datastore "$ct_id" "$datastore_name"; then
        print_error "Failed to configure PBS datastore"
        return 1
    fi
    
    # Setup monitoring user
    if ! setup_pbs_monitoring_user "$ct_id" "$datastore_name"; then
        print_warning "Failed to setup monitoring user (PBS will still work)"
    fi
    
    # Configure schedules
    if ! configure_pbs_schedules "$ct_id" "$datastore_name" "$gc_schedule" "$prune_schedule"; then
        print_warning "Failed to configure schedules (can be done manually later)"
    fi
    
    local pbs_ip
    pbs_ip=$(get_lxc_ip "$ct_id")
    print_success "PBS configuration completed. Access web interface at: https://${pbs_ip}:8007"
    
    print_success "PBS configured"
}

# Configure Proxmox VE backup job
configure_pve_backup_job() {
    print_info "Configuring Proxmox VE backup job"
    
    local pbs_storage_name="datapool"
    local job_config_file="/etc/pve/jobs.cfg"
    local job_id="vzdump-automated-pbs"
    local pbs_ip
    pbs_ip=$(get_lxc_ip "$(yq -r '.stacks.backup.ct_id' "$WORK_DIR/stacks.yaml")")

    # Using existing datapool storage
    print_info "Using existing datapool storage for backup operations"
    
    # Verify datapool storage exists
    pvesm status --storage "$pbs_storage_name" >/dev/null 2>&1 || {
        print_info "Storage '$pbs_storage_name' not found. Configure PBS storage manually."
        return 0
    }
    
    # Check if backup job already exists
    if grep -q "^vzdump: $job_id" "$job_config_file" 2>/dev/null; then
        print_info "Backup job '$job_id' already exists"
        return 0
    fi
    
    # Create backup job configuration
    print_info "Creating automated backup job"
    cat >> "$job_config_file" << EOF

vzdump: $job_id
	storage $pbs_storage_name
	schedule daily 03:00
	compress zstd
	mode snapshot
	notes-template {{guestname}}
	protected 0
	mailnotification failure
EOF
    
    print_success "Backup job created (daily 03:00, zstd compression)"
}

# Show backup stack information
show_backup_info() {
    local ct_id="$1"
    local ct_ip="$2"
    
    local datastore_name
    datastore_name=$(yq -r ".stacks.backup.pbs_datastore_name" "$WORK_DIR/stacks.yaml")
    
    print_info ""
    print_info "=== Backup Stack ==="
    print_info "PBS Web:     https://$ct_ip:8007 (root/container-password)"
    print_info "Datastore:   $datastore_name (/datapool/backups)"
    print_info "Host Path:   /datapool/backups (owned by 101000:101000)"
    print_info "Monitoring:  prometheus@pbs (password in /root/.prometheus_password)"
    print_info ""
    print_info "Container:   pct exec $ct_id -- bash"
    print_info "Status:      pct exec $ct_id -- systemctl status proxmox-backup"
    print_info ""
}