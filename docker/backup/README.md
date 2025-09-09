# Backup Stack Configuration

This stack deploys Proxmox Backup Server (PBS) with:
- Native Debian installation (no Docker)
- Automated datastore configuration
- Monitoring user setup
- Scheduled garbage collection and verification
- Integration with Proxmox VE backup jobs

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