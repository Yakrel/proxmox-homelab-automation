# Ansible Migration Plan

This document outlines the step-by-step plan to migrate the current shell script-based automation to a robust, idempotent Ansible project.

## Phase 0: Core Architecture & Principles

The fundamental architecture will be as follows:

1.  **Minimal Host Installer (`installer.sh`):** A single `curl | bash` script run on the Proxmox host. Its sole responsibility is to bootstrap and maintain the Ansible Control LXC.
2.  **Ansible Control LXC (CT 151):** A dedicated, persistent Debian-based LXC that will contain the Git repository, Ansible, and all related tooling. This will be the central control node for all automation.
3.  **Execution Flow:** The user initiates any action by running the `installer.sh` script. This script ensures the Control LXC is running and the local repository is up-to-date via `git pull`. It then delegates all further actions to a menu script running *inside* the Control LXC.
4.  **Connection Method:** Ansible will manage the Proxmox host via the Proxmox API, using a secure API token. SSH will not be used for management.
5.  **Configuration:** All hardcoded values (LXC names, IPs, resources) will be moved from the scripts into a central Ansible variables file (`group_vars/all.yml`), maintaining the current project's tailored nature but in a structured way.

## Phase 1: New Project Structure

The repository will be reorganized to follow standard Ansible best practices.

```
/
├── installer.sh            # NEW: The minimal host installer
└── ansible/                # NEW: Top-level directory for all Ansible content
    ├── ansible.cfg         # Configures Ansible (e.g., inventory path, roles path)
    ├── inventory.ini       # Defines `localhost` as the target for the Proxmox API
    ├── main-menu.sh        # NEW: The main menu, runs inside the Control LXC
    ├── secrets.yml         # NEW: Ansible Vault file for all encrypted secrets
    │
    ├── group_vars/
    │   └── all.yml         # Central variable definitions (replaces stacks.yaml)
    │
    ├── playbooks/
    │   ├── pb_deploy_stack.yml   # Deploys a generic Docker-based stack
    │   ├── pb_setup_pbs.yml      # Deploys the Proxmox Backup Server stack
    │   └── ... (playbooks for helper scripts)
    │
    └── roles/
        ├── lxc_provision/    # Creates and configures a base LXC
        ├── pbs_setup/        # Configures PBS and the PVE backup job
        ├── docker_stack/     # Deploys a generic Docker Compose application
        └── ... (other roles as needed)
```

## Phase 2: Secrets Migration (`.env.enc` to Ansible Vault)

We will transition from the custom OpenSSL encryption to Ansible's native, more robust secret management system.

1.  **Manual Decryption:** Use the existing `encrypt-env.ps1` script one last time to decrypt all `.env.enc` files into plaintext.
2.  **Create Vault:** Create a new, encrypted Ansible Vault file named `ansible/secrets.yml`.
3.  **Populate Vault:** Copy all secrets from the plaintext `.env` files into the `ansible/secrets.yml` Vault. This is done using the `ansible-vault edit` command, which opens a secure editor.
4.  **Cleanup:** Delete the old `.env.enc`, `.env.example`, and the `encrypt-env.ps1` script.
5.  **Integration:** All playbooks and roles will be configured to pull secrets directly from the Vault file. Ansible handles the decryption in memory at runtime when provided with the vault password.

## Phase 3: Implementation Steps

### Step 3.1: The New `installer.sh`

This script will be rewritten to be a minimal, intelligent bootstrapper.

*   **Logic:**
    1.  Check if the Control LXC (e.g., 151) exists.
    2.  **If not (First Time Setup):**
        *   It will contain the logic from the existing `lxc-manager.sh` to find and download the latest **Debian** template.
        *   Create the LXC using `pct create`.
        *   Install all necessary dependencies inside the LXC: `git`, `ansible`, `python3-pip`, `npm`, etc., using `pct exec`.
        *   Clone the Git repository into `/root/` inside the LXC.
    3.  **If it exists (Day-to-Day Use):**
        *   Run `git pull` inside the LXC's repository to ensure the automation code is up-to-date.
    4.  **Delegate:** In both cases, the script's final action is to execute `pct exec 151 -- /path/to/ansible/main-menu.sh`.

### Step 3.2: Ansible Roles & Playbooks

The logic from the current `.sh` files will be broken down and migrated into the corresponding Ansible roles and playbooks.

*   **Password & Prompt Handling:** Ansible has a built-in mechanism called `vars_prompt` that will be used in playbooks for interactive, one-time password entry (like setting the initial PBS `root@pam` password). This replaces the `read -s` commands in the shell scripts.
*   **`lxc_provision` Role:** This role will use the `community.general.proxmox_lxc` module to create containers. It will be fully idempotent.
*   **`pbs_setup` Role:** This will contain all the logic for creating the `prometheus@pbs` user, storing its random password in the Vault, creating the datastore, and adding the backup job to the Proxmox VE host's `jobs.cfg` file.
*   **`docker_stack` Role:** This generic role will read a stack's configuration from `group_vars/all.yml`, pull the necessary secrets from the Vault, and run `docker compose up`.

### Step 3.3: The New `main-menu.sh`

This menu will be simplified. Its only job is to present options and trigger the corresponding `ansible-playbook` command with the correct parameters (e.g., `--extra-vars "stack_name=media"`).

---

This plan provides a clear roadmap for the migration. It addresses all requirements for idempotency, security, and ease of use, while retaining the tailored, hardcoded nature of the project in a more structured format.
