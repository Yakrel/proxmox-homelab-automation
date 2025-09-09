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
    
    # Create datastore directory
    pct exec "$ct_id" -- mkdir -p "/datapool/pbs-datastore"
    pct exec "$ct_id" -- chown backup:backup "/datapool/pbs-datastore"
    
    # Configure datastore in PBS
    pct exec "$ct_id" -- proxmox-backup-manager datastore create "$datastore_name" "/datapool/pbs-datastore" 2>/dev/null || {
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
    
    # Check if monitoring user already exists
    if ! pct exec "$ct_id" -- test -f "$prom_pass_path"; then
        print_info "Creating Prometheus monitoring user"
        
        pct exec "$ct_id" -- proxmox-backup-manager user create "$prom_user" --comment "Read-only user for Prometheus monitoring" 2>/dev/null || true
        pct exec "$ct_id" -- proxmox-backup-manager acl update /datastore/"$datastore_name" --user "$prom_user" --role DatastoreAudit 2>/dev/null || true

        local prom_pass
        prom_pass=$(openssl rand -base64 16)
        pct exec "$ct_id" -- proxmox-backup-manager user update "$prom_user" --password "$prom_pass"
        printf '%s' "$prom_pass" | pct exec "$ct_id" -- sh -c "cat > $prom_pass_path && chmod 600 $prom_pass_path"
        printf '%s' "$prom_pass" | pct exec "$ct_id" -- sh -c "cat > /root/.prometheus-password && chmod 600 /root/.prometheus-password"
        print_success "Prometheus user created"
    else
        print_info "Prometheus user exists, skipping creation"
    fi
}

# Configure PBS schedules
configure_pbs_schedules() {
    local ct_id="$1"
    local datastore_name="$2"
    local gc_schedule="$3"
    local prune_schedule="$4"
    local verify_schedule="$5"
    
    print_info "Configuring PBS schedules"
    
    # Configure schedules
    pct exec "$ct_id" -- proxmox-backup-manager datastore update "$datastore_name" \
        --gc-schedule "$gc_schedule" 2>/dev/null || true
    pct exec "$ct_id" -- proxmox-backup-manager datastore update "$datastore_name" \
        --prune-schedule "$prune_schedule" 2>/dev/null || true
    pct exec "$ct_id" -- proxmox-backup-manager datastore update "$datastore_name" \
        --verify-schedule "$verify_schedule" 2>/dev/null || true
    
    print_success "PBS schedules configured"
}

# Complete PBS configuration
configure_pbs() {
    local ct_id="$1"
    
    print_info "Configuring Proxmox Backup Server"
    
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
    pct exec "$ct_id" -- systemctl is-active --quiet proxmox-backup || {
        print_info "Starting PBS service"
        pct exec "$ct_id" -- systemctl start proxmox-backup
        pct exec "$ct_id" -- systemctl enable proxmox-backup
        sleep 5
    }
    
    # Configure datastore
    configure_pbs_datastore "$ct_id" "$datastore_name"
    
    # Setup monitoring user
    setup_pbs_monitoring_user "$ct_id" "$datastore_name"
    
    # Configure schedules
    configure_pbs_schedules "$ct_id" "$datastore_name" "$gc_schedule" "$prune_schedule" "$verify_schedule"
    
    local pbs_ip
    pbs_ip=$(yq -r ".network.ip_base" "$WORK_DIR/stacks.yaml").$(yq -r ".stacks.backup.ip_octet" "$WORK_DIR/stacks.yaml")
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
    pbs_ip=$(yq -r ".network.ip_base" "$WORK_DIR/stacks.yaml").$(yq -r ".stacks.backup.ip_octet" "$WORK_DIR/stacks.yaml")

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
    print_info "Datastore:   $datastore_name (/datapool/pbs-datastore)"
    print_info "Monitoring:  prometheus@pbs (password in /root/.prometheus_password)"
    print_info ""
    print_info "Container:   pct exec $ct_id -- bash"
    print_info "Status:      pct exec $ct_id -- systemctl status proxmox-backup"
    print_info ""
}