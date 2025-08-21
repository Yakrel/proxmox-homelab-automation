# Proxmox Homelab Automation (Ansible Edition)

Always reference these instructions first and fallback to search or bash commands only when you encounter unexpected information that does not match the info here.

Proxmox Homelab Automation is an infrastructure-as-code project that uses Ansible to manage LXC containers on Proxmox VE hosts. It implements a "Host as Remote Control" architecture where a single installer script manages everything through an Ansible Control LXC container.

## Working Effectively

### Bootstrap and Validation Commands
- **Install required Python packages**: `pip install ansible-lint` - takes ~30 seconds
- **Install Ansible collections**: `ansible-galaxy collection install community.general community.proxmox community.docker` - takes ~12 seconds, NEVER CANCEL
- **Run ansible-lint**: `ansible-lint --skip-list=internal-error` - takes ~7 seconds (or ~2 seconds after collections installed)
- **Validate playbook syntax**: `ansible-playbook deploy.yml --syntax-check` - fails without secrets.yml (expected)
- **Test playbook in dry-run**: `ansible-playbook setup-host.yml --check --diff` - takes ~4 seconds

### Production Environment Commands (Proxmox Host Only)
- **Run installer**: `./installer.sh` - First run: Creates Ansible Control LXC, configures API credentials
- **Run installer (subsequent)**: `./installer.sh` - Shows interactive menu for stack management  
- **Direct deployment**: `pct exec 151 -- bash -c "cd /root/proxmox-homelab-automation && ansible-playbook deploy.yml --extra-vars 'stack_name=proxy'"` - deployment time varies by stack complexity
- **Host setup**: `pct exec 151 -- bash -c "cd /root/proxmox-homelab-automation && ansible-playbook setup-host.yml"` - takes ~5-10 minutes

### Critical Timeout and Timing Information
- **NEVER CANCEL ansible-galaxy collection installs** - Can take up to 2 minutes for all collections
- **NEVER CANCEL first installer run** - Creates LXC container, installs packages, can take 15-30 minutes
- **NEVER CANCEL stack deployments** - Docker compose deployments can take 10-20 minutes per stack
- **Set ansible-playbook timeouts to 30+ minutes** for production deployments
- **Set installer.sh timeouts to 60+ minutes** for first-time setup

## Validation

### Always Test These Scenarios After Changes
1. **Syntax validation**: Run `ansible-lint` and `ansible-playbook --syntax-check` on all playbooks
2. **Dry-run testing**: Execute `ansible-playbook setup-host.yml --check --diff` to validate host configuration changes
3. **Role syntax**: Test individual roles with `ansible-playbook deploy.yml --check --extra-vars "stack_name=<role_name>"` - Note: Will fail with missing lxc_template variable (expected)
4. **Configuration syntax**: Validate YAML files with `yamllint stacks.yaml group_vars/all.yml`

### Manual Validation Requirements
- **Always run ansible-lint** before committing changes - the project has specific skip rules in .ansible-lint
- **Always create test secrets file** when testing deploy.yml: Create temporary `test-secrets.yml` with mock credentials
- **Cannot fully test installer.sh** outside Proxmox environment (requires pveum, pct commands)
- **Validate stacks.yaml changes** by checking that all referenced variables are properly defined

## Common Tasks

### Repository Structure Quick Reference
```
├── installer.sh              # Main entry point - unified installer & menu
├── stacks.yaml              # Central configuration - all hardcoded values
├── deploy.yml               # Main deployment playbook
├── setup-host.yml           # Proxmox host configuration  
├── ansible.cfg              # Ansible configuration
├── group_vars/all.yml       # Dynamic variables from stacks.yaml
├── roles/                   # Ansible roles for each service stack
│   ├── proxy/               # Cloudflared, Promtail, Watchtower
│   ├── media/               # Media server stack
│   ├── files/               # File management services
│   ├── webtools/            # Web-based utilities
│   ├── monitoring/          # Prometheus, Grafana stack
│   ├── backup/              # Proxmox Backup Server
│   ├── ansible-control/     # Control node setup
│   ├── proxmox_host_setup/  # Host configuration
│   └── common/              # Shared tasks
└── docker/                  # Docker Compose files for each stack
    ├── proxy/
    ├── media/
    ├── monitoring/
    ├── files/
    └── webtools/
```

### Key Configuration Files
- **stacks.yaml**: Single source of truth - contains all LXC configurations, IP addresses, resource allocations
- **group_vars/all.yml**: Dynamically loads values from stacks.yaml for Ansible consumption
- **secrets.yml**: Encrypted file (Ansible Vault) containing API credentials and sensitive data
- **docker/*/docker-compose.yml**: Service definitions for each stack

### Architecture Overview  
1. **installer.sh**: Runs on Proxmox host, creates/manages Ansible Control LXC (ID 151)
2. **Ansible Control LXC**: Contains this Git repo, executes all playbooks
3. **Service LXCs**: Created by Ansible, run Docker Compose stacks
4. **All values hardcoded**: IP addresses, container IDs, paths optimized for specific homelab

### Working with Roles
- **Each role creates one LXC**: Uses `community.proxmox.proxmox` module
- **Standard structure**: All service roles follow same pattern in tasks/main.yml
- **Variables loaded**: From `roles/<name>/vars/main.yml` and `stacks.yaml`
- **Docker integration**: Roles deploy Docker Compose files to LXCs
- **Template handling**: Installer script manages LXC template downloads

### Debugging Tips
- **Check LXC status**: Use `pct status <id>` and `pct exec <id> -- <command>`
- **Ansible logs**: Run with `-vv` flag for detailed output
- **Template issues**: Installer handles Alpine/Debian template selection automatically
- **API credentials**: Generated by installer, stored in `/etc/ansible_secrets/`

### Important Notes
- **Requires Proxmox VE**: This is not a generic deployment - designed for specific homelab setup
- **Hardcoded values**: IP ranges (192.168.1.x), storage pool (datapool), node name (pve01)
- **Security model**: API user `ansible-bot@pve` with minimal required permissions
- **Idempotent design**: All operations can be run multiple times safely
- **Menu-driven**: After setup, installer.sh provides interactive menu for all operations

### Common Variable Patterns
- **LXC identifiers**: `ct_id`, `hostname`, `ip_octet` defined in stacks.yaml
- **Resource allocation**: `cpu_cores`, `memory_mb`, `disk_gb` per stack
- **Network configuration**: Static IPs using `network_ip_base` + `ip_octet`
- **Storage**: All containers use `storage_pool` with datapool mount

### Collection Dependencies
The project requires these Ansible collections (installed by installer.sh):
- `community.general`: System management modules
- `community.proxmox`: Proxmox VE integration  
- `community.docker`: Docker Compose management

## Build and Deployment Process

### First-Time Setup (Proxmox Host)
1. Download: `bash <(curl -s https://raw.githubusercontent.com/Yakrel/proxmox-homelab-automation/main/installer.sh)`
2. Creates Ansible Control LXC (ID 151)
3. Installs Ansible, clones repo, configures API credentials
4. Takes 15-30 minutes - NEVER CANCEL

### Subsequent Operations (Menu-Driven)
1. Run `./installer.sh` on Proxmox host
2. Select from interactive menu:
   - Configure Proxmox host
   - Deploy service stacks (proxy, media, monitoring, etc.)
   - All operations automated through Ansible

### Manual Playbook Execution (Advanced)
- **Host setup**: `pct exec 151 -- ansible-playbook setup-host.yml`
- **Stack deployment**: `pct exec 151 -- ansible-playbook deploy.yml --extra-vars "stack_name=media"`
- **All operations from within Control LXC**: Repository located at `/root/proxmox-homelab-automation`