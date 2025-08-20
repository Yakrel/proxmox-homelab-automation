# Ansible Migration Plan (v2)

This document outlines the step-by-step plan to migrate the current shell script-based automation to a robust, idempotent Ansible project. This version incorporates a more advanced, automated setup process.

## Phase 0: Core Architecture & Principles

1.  **Minimal Host Installer (`installer.sh`):** A single `curl | bash` script run on the Proxmox host. Its primary responsibility is to create and provision the Ansible Control LXC and the necessary API credentials.
2.  **Ansible Control LXC (CT 151):** A dedicated, persistent **Debian-based** LXC that will contain the Git repository and all Ansible tooling. This is the central control node.
3.  **Execution Flow:** The user runs `installer.sh`. The script ensures the Control LXC and API credentials exist, updates the repo via `git pull`, and then delegates all further actions to Ansible playbooks run *inside* the Control LXC.
4.  **Connection Method:** Ansible will manage the Proxmox host via the Proxmox API using an automatically generated API token.
5.  **Configuration:** All hardcoded values will be moved into a central Ansible variables file (`group_vars/all.yml`), maintaining the project's tailored nature in a structured way.

### 0.1: OS Template Strategy

-   **Default Template:** The latest version of **Alpine Linux** will be used for all standard LXC stacks (proxy, media, etc.).
-   **Exception-based Templates:** The latest version of **Debian** will be used for the `development` (Ansible Control) and `backup` (Proxmox Backup Server) stacks, which have specific OS requirements.
-   **Storage:** All templates will be downloaded to and used from the `datapool` storage pool.

### 0.2: Automated API Credential Setup

To achieve true "zero-manual-step" automation, the `installer.sh` script will be responsible for creating the Ansible API user and its token on the Proxmox host.

1.  **User Creation:** The script will idempotently create a dedicated user, e.g., `ansible-bot@pve`.
2.  **Token Generation:** It will then idempotently generate a new API token for this user with the required permissions.
3.  **Secret Injection:** The script will capture the generated **Token ID** and **Token Secret** and securely inject them into the `secrets.yml` Ansible Vault file *inside* the newly created Control LXC.

## Phase 1: New Project Structure

The repository will be reorganized to follow standard Ansible best practices.

```
/
├── installer.sh            # The minimal, intelligent host installer
├── ansible.cfg             # Configures Ansible (e.g., inventory path, roles path)
├── inventory               # Defines `localhost` as the target for the Proxmox API
├── secrets.yml             # Ansible Vault file for all encrypted secrets
│
├── group_vars/
│   └── all.yml             # Central variable definitions (replaces stacks.yaml)
│
├── playbooks/
│   └── deploy_stack.yml    # A master playbook to deploy a specific stack
│
└── roles/
    ├── lxc_base/           # Creates/provisions a base LXC based on template type
    ├── pbs_setup/          # Configures PBS and the PVE backup job
    ├── docker_stack/       # Deploys a generic Docker Compose application
    └── ... (other roles as needed)
```

## Phase 2: Secrets Migration (`.env.enc` to Ansible Vault)

This process is now largely automated.

1.  **Automated Decryption:** The existing `.env.enc` files will be decrypted once to read their values.
2.  **Automated Vault Population:** The `installer.sh` script (or a one-time setup playbook) will populate the `secrets.yml` vault with both the old secrets from the `.env` files and the newly generated Proxmox API token secret.
3.  **Encryption:** The `secrets.yml` file will be encrypted using `ansible-vault`.
4.  **Cleanup:** The old `.env.enc`, `.env`, and related scripts will be removed.

## Phase 3: Implementation Steps

### Step 3.1: The New `installer.sh`

This script will be rewritten to be a minimal, intelligent bootstrapper.

*   **Logic:**
    1.  **Idempotently create `ansible-bot@pve` user and API token** on the Proxmox host. Capture the credentials.
    2.  Check if the Control LXC (e.g., 151) exists.
    3.  **If not (First Time Setup):**
        *   Find and download the latest **Debian** template to `datapool`.
        *   Create the LXC using `pct create`.
        *   Install dependencies inside the LXC: `git`, `ansible`, etc., using `pct exec`.
        *   Clone the Git repository into `/root/` inside the LXC.
        *   **Inject all secrets** (old .env values + new API token) into a plaintext `secrets.yml` inside the LXC.
        *   **Encrypt the vault** by running `ansible-vault encrypt` inside the LXC.
    4.  **If it exists (Day-to-Day Use):**
        *   Run `git pull` inside the LXC's repository.
    5.  **Delegate:** The user will then be instructed to `pct enter 151` and run `ansible-playbook` commands from there.

### Step 3.2: Ansible Roles & Playbooks

*   **`lxc_base` Role:** This role will contain the logic to create a container. It will have a variable (`lxc_template_type: alpine|debian`) to determine which OS template to find and use. It will handle all `pct create` and basic provisioning steps.
*   **Playbooks:** Instead of a menu script, we will use master playbooks. For example, `ansible-playbook playbooks/deploy_stack.yml --extra-vars "stack_name=media"` will trigger the deployment of the media stack.

---

This updated plan provides a clearer, more automated, and more robust path for the migration.
