# Comprehensive PBS Backup System Documentation

## Overview

This document describes the fully automated Proxmox Backup Server (PBS) implementation that provides a complete "set and forget" backup solution for the entire Proxmox homelab environment.

## Features Implemented

### 🚀 Automatic PBS Installation
- **Dedicated LXC Container**: Creates PBS in LXC container 150 (lxc-backup-01) with 4 cores, 8GB RAM, 50GB disk
- **Latest Debian Template**: Automatically uses the latest available Debian template for optimal compatibility
- **Mount Point Configuration**: Automatically mounts `/datapool/backups` from host into the PBS container
- **Service Management**: Ensures PBS services are properly started and enabled

### 🎯 Intelligent Backup Policies
- **Datastore Configuration**: Creates `backup-datastore` pointing to `/datapool/backups`
- **Garbage Collection**: Daily at 2:00 AM to optimize storage usage
- **Pruning Schedule**: Daily at 3:00 AM with intelligent retention:
  - Daily backups: 7 days
  - Weekly backups: 4 weeks  
  - Monthly backups: 6 months
  - Yearly backups: 1 year
- **Verification**: Weekly on Mondays at 4:00 AM to ensure backup integrity

### 🔐 Security & Authentication
- **Dedicated PBS User**: Creates `proxmox-backup@pbs` user for Proxmox VE integration
- **Secure Password Generation**: Generates cryptographically secure random passwords
- **Minimal Permissions**: Assigns only required DatastoreBackup and DatastoreReader roles
- **ACL Configuration**: Proper access control lists for secure operation

### 🔄 Full Proxmox VE Integration  
- **Storage Backend**: Automatically adds PBS as storage in `/etc/pve/storage.cfg`
- **Authentication Setup**: Configures username/password authentication for PBS storage
- **Comprehensive Backup Job**: Creates job that backs up ALL VMs and LXCs
- **Automated Scheduling**: Nightly backups at 2:30 AM
- **Optimal Settings**: Uses snapshot mode and zstd compression for efficiency

### 📊 Homelab-Optimized Configuration
- **Resource Efficiency**: Conservative scheduling to avoid conflicts
- **Appropriate Retention**: Balanced between data protection and storage usage
- **No Manual Intervention**: Completely automated setup and ongoing operation
- **Idempotent Operations**: Can be run multiple times safely

## Deployment

### Prerequisites
1. Proxmox VE host with datapool storage
2. Ansible Control LXC (CT 151) set up via installer.sh
3. API credentials configured in secrets.yml

### Deploy the Backup System
```bash
# From Proxmox host, run:
bash <(curl -s https://raw.githubusercontent.com/Yakrel/proxmox-homelab-automation/main/installer.sh)

# Then select option 8 from the menu to deploy backup stack
```

### Alternative Direct Deployment
```bash
# From inside the Ansible Control LXC:
ansible-playbook deploy.yml --extra-vars "stack_name=backup"
```

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ Proxmox VE Host (pve01)                                     │
│ ┌─────────────────────┐    ┌─────────────────────────────┐   │
│ │ /datapool/backups   │────│ LXC 150 (lxc-backup-01)    │   │
│ │ (ZFS Dataset)       │    │ ┌─────────────────────────┐ │   │
│ └─────────────────────┘    │ │ Proxmox Backup Server   │ │   │
│                            │ │ - Web UI: :8007         │ │   │
│ ┌─────────────────────┐    │ │ - Datastore: backup-... │ │   │
│ │ Backup Job Config   │────│ │ - User: proxmox-backup@ │ │   │
│ │ /etc/pve/jobs.cfg   │    │ │ - Schedules & Policies  │ │   │
│ └─────────────────────┘    │ └─────────────────────────┘ │   │
│                            └─────────────────────────────┘   │
│ ┌─────────────────────┐                                      │
│ │ PBS Storage Config  │                                      │
│ │ /etc/pve/storage.cfg│                                      │
│ └─────────────────────┘                                      │
└─────────────────────────────────────────────────────────────┘
```

## Scheduling Overview

| Time  | Task                    | Frequency | Purpose                |
|-------|-------------------------|-----------|------------------------|
| 02:00 | Garbage Collection      | Daily     | Optimize storage usage |
| 02:30 | Backup Job Execution    | Daily     | Backup all VMs/LXCs   |
| 03:00 | Backup Pruning          | Daily     | Apply retention policy |
| 04:00 | Backup Verification     | Weekly    | Ensure backup integrity|

## Retention Policy

| Backup Type | Retention Period | Purpose                           |
|-------------|------------------|-----------------------------------|
| Daily       | 7 days          | Recent changes and quick recovery |
| Weekly      | 4 weeks         | Monthly restore points            |
| Monthly     | 6 months        | Quarterly restore points          |
| Yearly      | 1 year          | Annual restore points             |

## Post-Deployment Verification

### 1. Check PBS Web Interface
```bash
# Access PBS web interface at:
https://<proxmox-ip>.150:8007
# Login: root@pam (set password during PBS setup)
```

### 2. Verify Datastore
```bash
# Check datastore creation and configuration
pct exec 150 -- proxmox-backup-manager datastore list
```

### 3. Check Backup Jobs
```bash
# Verify Proxmox VE backup job
cat /etc/pve/jobs.cfg | grep -A10 "pbs-homelab-backup"
```

### 4. Test Backup Execution
```bash
# Manually trigger a backup to test
vzdump <vm-id> --storage pbs-backup --mode snapshot
```

## Troubleshooting

### Common Issues

#### PBS Service Not Starting
```bash
# Check service status
pct exec 150 -- systemctl status proxmox-backup

# Check logs
pct exec 150 -- journalctl -u proxmox-backup
```

#### Mount Point Issues
```bash
# Verify mount point
pct exec 150 -- df -h | grep datapool

# Check container configuration  
pct config 150 | grep mp0
```

#### Authentication Problems
```bash
# Reset PBS user password
pct exec 150 -- proxmox-backup-manager user passwd proxmox-backup@pbs
```

## Maintenance

### Regular Tasks (Automated)
- ✅ Daily garbage collection
- ✅ Daily backup pruning  
- ✅ Weekly verification
- ✅ Nightly backups

### Periodic Manual Tasks (Optional)
- Monitor backup storage usage
- Review backup logs monthly
- Test restore procedures quarterly
- Update retention policies as needed

## Advanced Configuration

### Customizing Schedules
Edit `/roles/backup/vars/main.yml` to modify:
- Backup timing
- Retention policies
- Compression settings
- Verification frequency

### Adding Email Notifications
Configure PBS to send backup status emails:
```bash
pct exec 150 -- proxmox-backup-manager user update root@pam --email your@email.com
```

## Security Considerations

✅ **Implemented Security Features:**
- Unprivileged LXC container
- Dedicated service account with minimal permissions
- Encrypted backup storage option available
- Secure password generation
- Proper file permissions and ACLs

## Performance Optimization

✅ **Implemented Optimizations:**
- Snapshot-based backups for minimal downtime
- zstd compression for optimal size/speed ratio
- Scheduled operations outside business hours
- Incremental backup support via PBS
- Resource-efficient LXC container deployment

This comprehensive backup solution provides enterprise-grade backup capabilities specifically tuned for homelab environments, ensuring your critical data is protected with minimal ongoing maintenance requirements.