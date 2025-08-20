# Proxmox Homelab Automation (Ansible Edition)

This repository contains a collection of Ansible roles and playbooks to automate the setup of a personal homelab environment on Proxmox VE. The architecture is based on creating separate LXC containers for different service stacks, each managed by Docker Compose and deployed via Ansible.

## ⚠️ Project Philosophy & Disclaimer

This repository documents my personal homelab setup, tailored specifically to my own hardware and network configuration. It is shared publicly to showcase my approach to infrastructure-as-code, automation, and GitOps principles.

**Please be aware that this is not a universal, one-click deployment solution.**

By design, many values such as IP addresses, container IDs, and specific paths are hard-coded within the Ansible roles for my own convenience and rapid, repeatable deployments. If you wish to adapt this project for your own use, you should be prepared to:

*   Thoroughly review all Ansible roles and configuration files.
*   Replace hard-coded values with your own environment's settings.
*   Adjust resource allocations (CPU, RAM) in the `vars/main.yml` file of each role.

Feel free to fork this repository and use it as an inspiration or a template for your own homelab automation journey!

## Architecture: The "Host as Remote Control" Model

The new architecture is designed for true automation and idempotency, managed by a single script on the host that controls Ansible inside a dedicated container.

1.  **Unified Installer & Menu (`installer.sh`):** This is the single entry point for all operations, run on the Proxmox VE host. 
    -   **On its first run,** it bootstraps the entire system by creating the Ansible Control LXC (ID 151) and the necessary Proxmox API credentials.
    -   **On all subsequent runs,** it presents a menu to manage your homelab.

2.  **Ansible Control LXC:** A dedicated Debian container (ID 151) that holds this Git repository and Ansible. All configuration logic resides here, keeping the Proxmox host clean.

3.  **The Bridge (`pct exec`):** The menu on the host uses the `pct exec` command to trigger Ansible playbooks inside the Control LXC. This provides a clean, secure, and professional separation of concerns.

## Quick Start & Usage

All management is performed through the unified script on the Proxmox host.

```bash
# Navigate to the repository directory on your Proxmox host and run:
./installer.sh
```

- **First Time:** The script will perform the initial setup of the control node.
- **After Setup:** The script will automatically display a menu. From the menu, you can choose to set up the Proxmox host for the first time or deploy any of the available service stacks. The script will run the appropriate Ansible playbook for you, and you will see all output in your terminal.

## Secrets Management: Ansible Vault

All secrets (API keys, passwords, etc.) are now managed in a single encrypted file: `secrets.yml`.

- **Encryption:** This file is encrypted using `ansible-vault`. It is safe to commit to Git.
- **Editing:** To edit secrets, you must do so from the host by executing a command within the control LXC:
  ```bash
  pct exec 151 -- ansible-vault edit /root/proxmox-homelab-automation/secrets.yml
  ```

This replaces the old, cumbersome `.env.enc` workflow.

## Service Stacks

This project is divided into several service stacks, each defined by an Ansible role in the `roles/` directory. Configuration for each stack (like Docker images and versions) can be found in the `vars/main.yml` file within its role directory.

- **Host Configuration** (`roles/proxmox_host_setup`)
- **Proxy Stack** (`roles/proxy`)
- **Media Stack** (`roles/media`)
- **Files Stack** (`roles/files`)
- **Webtools Stack** (`roles/webtools`)
- **Monitoring Stack** (`roles/monitoring`)
- **Development Stack** (`roles/development`)
- **Backup Stack** (`roles/backup`)

## 🔒 Comprehensive Backup System

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
