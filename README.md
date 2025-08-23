# Proxmox Homelab Automation (Ansible Edition)

This repository contains a collection of Ansible roles and playbooks to automate the setup of a personal homelab environment on Proxmox VE. The architecture is based on creating separate LXC containers for different service stacks, each managed by Docker Compose and deployed via Ansible.

## Project Philosophy & Disclaimer

This repository documents my personal homelab setup, tailored specifically to my own hardware and network configuration. It is shared publicly to showcase my approach to infrastructure-as-code, automation, and GitOps principles.

**Please be aware that this is not a universal, one-click deployment solution.**

By design, many values are configurable through `stacks.yaml`, but some values such as IP addresses, container IDs, and specific paths may require customization for your environment. If you wish to adapt this project for your own use, you should be prepared to:

- Thoroughly review all Ansible roles and configuration files
- Replace default values with your own environment's settings in `stacks.yaml`
- Adjust resource allocations (CPU, RAM) as needed

Feel free to fork this repository and use it as inspiration or a template for your own homelab automation journey!

## Architecture: The "Host as Remote Control" Model

The architecture is designed for true automation and idempotency, managed by a single script on the host that controls Ansible inside a dedicated container.

1. **Unified Installer & Menu (`installer.sh`):** This is the single entry point for all operations, run on the Proxmox VE host.
   - **On its first run,** it bootstraps the entire system by creating the Ansible Control LXC (ID 151) and the necessary Proxmox API credentials.
   - **On all subsequent runs,** it presents a menu to manage your homelab.

2. **Ansible Control LXC:** A dedicated Debian container (ID 151) that holds this Git repository and Ansible. All configuration logic resides here, keeping the Proxmox host clean.

3. **The Bridge (`pct exec`):** The menu on the host uses the `pct exec` command to trigger Ansible playbooks inside the Control LXC. This provides a clean, secure, and professional separation of concerns.

4. **Service Stacks:** Individual LXC containers for each service group, managed via Docker Compose and deployed through Ansible.

## One-Line Installation

All management is performed through the unified installer script. You can run it directly from GitHub without cloning the repository first.

```bash
bash <(curl -s https://raw.githubusercontent.com/Yakrel/proxmox-homelab-automation/main/installer.sh)
```

### How It Works

- **First Time:** The script will perform the initial setup by creating the Ansible Control LXC (ID 151) and configuring all necessary credentials
- **After Setup:** The script will automatically display an interactive menu. From this menu, you can:
  - Configure the Proxmox host (timezone, security, etc.)
  - Deploy any of the available service stacks (proxy, media, monitoring, etc.)
  - All operations are performed automatically - just select the option and the script will run the appropriate Ansible playbook
  - After each operation completes, you'll be returned to the main menu to perform additional tasks
- **Everything is menu-driven** - no manual playbook execution required!

## Service Stacks

This project is divided into several service stacks, each defined by an Ansible role in the `roles/` directory. Each stack runs in its own LXC container for isolation and resource management.

## Available Stacks

| Stack | Description | Container ID | Role Directory |
|-------|-------------|--------------|----------------|
| Host Configuration | Proxmox host setup | - | `roles/proxmox_host_setup` |
| Proxy | Cloudflared, monitoring agents | 100 | `roles/proxy` |
| Media | Jellyfin, Sonarr, Radarr, etc. | 101 | `roles/media` |
| Files | File management services | 102 | `roles/files` |
| Webtools | Web-based utilities | 103 | `roles/webtools` |
| Monitoring | Prometheus, Grafana | 104 | `roles/monitoring` |
| Development | Development tools | 105 | `roles/development` |
| Backup | Proxmox Backup Server | 150 | `roles/backup` |

## 🔐 Configuration

- **Central Config**: All settings in `stacks.yaml`
- **Secrets**: Encrypted with Ansible Vault in `secrets.yml`
- **Customization**: Modify `stacks.yaml` for your environment

## Important Notes

This is a **personal homelab configuration**. Before using:

1. Review `stacks.yaml` and adjust IP addresses, storage pools, etc.
2. Update secrets in `secrets.yml` during first setup
3. Modify resource allocations as needed

## Secrets Management: Ansible Vault

All secrets (API keys, passwords, etc.) are managed in a single encrypted file: `secrets.yml`.

- **Encryption**: File is encrypted using `ansible-vault` with a password you set during setup. It is safe to commit to Git
- **Password Management**: You'll be prompted for the vault password when deploying stacks or running playbooks through the installer menu
- **Editing**: Use the ansible-vault edit command from within the control LXC:

```bash
pct exec 151 -- ansible-vault edit /root/proxmox-homelab-automation/secrets.yml
```

**Important**: Remember your vault password - you'll need it for all homelab operations! The installer will prompt you to set this password during first-time setup and will request it each time you deploy stacks.

## Comprehensive Backup System

The backup stack provides a complete, automated backup solution using Proxmox Backup Server (PBS). This implementation fulfills the "set and forget" philosophy with intelligent scheduling and retention policies optimized for homelab environments.

### Key Features:
- **Fully Automated Setup**: Creates PBS LXC, configures datastore, sets up schedules
- **Intelligent Retention**: 7d/4w/6m/1y retention policy with automatic pruning
- **Complete Integration**: Automatically configures Proxmox VE storage and backup jobs
- **Security-First**: Dedicated users, secure authentication, minimal permissions
- **Zero Maintenance**: Handles garbage collection, verification, and pruning automatically

### Quick Deployment:
```bash
# Deploy the comprehensive backup system
ansible-playbook deploy.yml --extra-vars "stack_name=backup"

# Validate deployment
./validate-pbs-system.sh
```
