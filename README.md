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

All management is performed through the unified installer script. You can run it directly from GitHub without cloning the repository first.

### Standard Usage (Production)

```bash
# Run the installer directly from GitHub (recommended):
bash <(curl -s https://raw.githubusercontent.com/Yakrel/proxmox-homelab-automation/main/installer.sh)
```

### Development & Testing Usage

The installer now supports testing from different branches without merging to main first, perfect for GitOps workflows:

```bash
# Test from a specific branch:
bash <(curl -s https://raw.githubusercontent.com/Yakrel/proxmox-homelab-automation/main/installer.sh) --branch your-feature-branch

# Test from a forked repository:
bash <(curl -s https://raw.githubusercontent.com/Yakrel/proxmox-homelab-automation/main/installer.sh) --repo-url https://github.com/yourusername/proxmox-homelab-automation.git --branch your-branch

# Auto-detect and use current branch (when running from local repository):
./installer.sh --auto-detect

# Show all available options:
./installer.sh --help
```

Alternatively, if you have already cloned the repository:

```bash
# Navigate to the repository directory on your Proxmox host and run:
./installer.sh
```

### How It Works:

- **First Time:** The script will perform the initial setup by creating the Ansible Control LXC (ID 151) and configuring all necessary credentials.
- **After Setup:** The script will automatically display an interactive menu. From this menu, you can:
  - Configure the Proxmox host (timezone, security, etc.)
  - Deploy any of the available service stacks (proxy, media, monitoring, etc.)
  - All operations are performed automatically - just select the option and the script will run the appropriate Ansible playbook
  - After each operation completes, you'll be returned to the main menu to perform additional tasks

**Everything is menu-driven - no manual playbook execution required!**

## Development & Testing Workflow

The installer now supports testing from development branches without merging to main first, ideal for GitOps practices:

### Branch-Based Testing Options

| Command | Description |
|---------|-------------|
| `./installer.sh` | Uses main branch (default, production) |
| `./installer.sh --branch feature-xyz` | Test specific branch |
| `./installer.sh --auto-detect` | Auto-detect current branch from local repo |
| `./installer.sh --repo-url https://github.com/user/fork.git --branch dev` | Test from forked repository |

### Example Development Workflow

```bash
# 1. Create and switch to feature branch
git checkout -b feature-new-service

# 2. Make your changes to roles, playbooks, etc.
# ... edit files ...

# 3. Test your changes without merging to main
./installer.sh --auto-detect

# 4. The installer will use your current branch automatically
# 5. Deploy and test your changes in the Proxmox environment
```

### Branch Safety Features

- **Branch validation**: Verifies branch exists on remote before proceeding
- **Automatic switching**: Handles branch changes in existing Control LXC
- **Repository validation**: Supports switching between different repository URLs
- **Fallback protection**: Re-clones repository if branch operations fail

## Secrets Management: Ansible Vault

All secrets (API keys, passwords, etc.) are now managed in a single encrypted file: `secrets.yml`.

- **Encryption:** This file is encrypted using `ansible-vault` with an interactive password that you set during first-time setup. It is safe to commit to Git.
- **Password Management:** You will be prompted for the vault password whenever deploying stacks or running playbooks through the installer menu.
- **Editing:** To edit secrets, you can use the ansible-vault edit command from within the control LXC:
  ```bash
  pct exec 151 -- ansible-vault edit /root/proxmox-homelab-automation/secrets.yml
  ```

**Important:** Remember your vault password! You'll need it for all homelab operations. The installer will prompt you to set this password during first-time setup and will request it each time you deploy stacks.

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
