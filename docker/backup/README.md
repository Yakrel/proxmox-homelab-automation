# Backup Stack Configuration

This stack deploys Proxmox Backup Server (PBS) with:
- Native Debian installation (no Docker)
- Automated datastore configuration using best practices
- Monitoring user setup
- Scheduled garbage collection and verification
- Integration with Proxmox VE backup jobs

## PBS Datastore Best Practices

This deployment follows PBS best practices for datastore configuration:

### Directory Structure
- **Host Path**: `/datapool/backups` - Direct use of the backup storage area
- **Container Path**: `/datapool/backups` - Mounted directly from host
- **PBS Datastore**: Points to `/datapool/backups` within container

### Why This Structure?
1. **Direct Storage Access**: PBS accesses the backup storage directly without nested subdirectories
2. **Efficiency**: Avoids unnecessary directory layers that can impact performance
3. **Simplicity**: Clear, straightforward path structure for maintenance
4. **Standard Practice**: Follows Proxmox documentation recommendations

### Permissions
- **Host Ownership**: `101000:101000` (mapped from container backup user)
- **Container User**: `backup` user (PBS service account)
- **Access Mode**: Read/write for PBS operations

## Configuration

All configuration is managed through `stacks.yaml`:
- `pbs_datastore_name`: Name of the backup datastore
- `pbs_prune_schedule`: Schedule for backup pruning
- `pbs_gc_schedule`: Schedule for garbage collection  
- `pbs_verify_schedule`: Schedule for backup verification

## Authentication

PBS uses the default root authentication inherited from the LXC container.
Access the web interface at: `https://<container-ip>:8007`

## No Environment Files

Unlike other stacks, the backup stack does not use `.env` files.
All configuration is handled through `stacks.yaml` and automatic setup.

## Troubleshooting

### Permission Issues
If you encounter permission denied errors:
```bash
# Fix host directory ownership
chown 101000:101000 /datapool/backups

# Check container access
pct exec 106 -- ls -la /datapool/backups
```

### Service Issues
```bash
# Check PBS service status
pct exec 106 -- systemctl status proxmox-backup

# View PBS logs
pct exec 106 -- journalctl -u proxmox-backup -f
```