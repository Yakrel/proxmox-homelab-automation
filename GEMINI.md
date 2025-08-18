# Gemini Code Assistant Context

## Project Overview

This repository contains a comprehensive automation suite for setting up and managing a personal homelab on Proxmox VE. The core philosophy is to use a GitOps-centric and idempotent approach to infrastructure-as-code. The architecture is modular, isolating different service categories into dedicated, lightweight Proxmox LXC containers. Each container runs a specific stack of services managed by Docker and Docker Compose.

The project is highly personalized, with many hard-coded values (IP addresses, container IDs, etc.) tailored for the author's specific environment. It serves as a public showcase of automation techniques rather than a universal, one-click deployment solution.

**Key Technologies:**

*   **Orchestration:** Proxmox VE
*   **Containerization:** LXC and Docker (with Docker Compose)
*   **Automation:** Bash scripts
*   **Configuration:** YAML
*   **Monitoring:** Prometheus, Grafana, Loki, Promtail
*   **Secrets Management:** OpenSSL for encrypting/decrypting `.env` files.

## Architecture

1.  **Bootstrapping:** A single `installer.sh` script, designed to be run via `curl | bash`, kicks off the entire process. It downloads the necessary scripts from the main branch of the GitHub repository into a temporary directory.
2.  **Main Menu:** The `scripts/main-menu.sh` script acts as the central user interface, providing an interactive menu to deploy different service stacks or run helper scripts.
3.  **Stack Deployment:** The `scripts/deploy-stack.sh` script is the workhorse for deploying a single stack. It reads configuration from `stacks.yaml`, creates the LXC container using `scripts/lxc-manager.sh`, configures the environment (including decrypting secrets), and finally deploys the services using `docker-compose`.
4.  **Configuration as Code:** The `stacks.yaml` file is the single source of truth for defining LXC container properties like IDs, hostnames, IP octets, and resource allocations. Docker Compose files are located in the `docker/` directory, organized by stack.
5.  **Secrets Management:** The project uses a manual encryption workflow. Plaintext `.env` files are encrypted into `.env.enc` files using `scripts/encrypt-env.ps1` (a PowerShell script for local management). These encrypted files are safe to commit to the repository. During deployment, the `deploy-stack.sh` script prompts the user for a passphrase to decrypt the secrets into the target LXC container.

## Building and Running

The primary workflow is initiated from the Proxmox host's shell.

**Initial Setup:**

To start the entire process, run the following command on the Proxmox host:

```bash
bash <(curl -s https://raw.githubusercontent.com/Yakrel/proxmox-homelab-automation/main/installer.sh)
```

This will download the latest scripts and present the main menu.

**Deployment Workflow:**

1.  Run the installer command above.
2.  From the main menu, select the stack you wish to deploy (e.g., `proxy`, `media`, `monitoring`).
3.  The script will prompt for any necessary information, such as the decryption passphrase for the stack's `.env.enc` file.
4.  The script will then automate the creation of the LXC, configuration, and Docker Compose deployment.

## Development Conventions

*   **Idempotency:** All scripts are designed to be idempotent, meaning they can be run multiple times without causing unintended side effects. They will always converge the system to the desired state.
*   **Modularity:** The project is broken down into logical components:
    *   `installer.sh`: The main entry point.
    *   `scripts/`: Contains all the automation logic.
    *   `docker/`: Contains the Docker Compose files and environment variable examples for each stack.
    *   `config/`: Contains configuration files for services like Homepage, Loki, and Promtail.
    *   `stacks.yaml`: The central configuration file for all stacks.
*   **Shell Scripting Style:** The shell scripts are well-structured, using helper functions for common tasks like printing colored output. They use `set -e` to exit on error.
*   **Secrets:** Never commit plaintext `.env` files. Always use the provided `scripts/encrypt-env.ps1` script to create an encrypted `.env.enc` file.
*   **Customization:** To adapt this project for your own use, you will need to:
    *   Fork the repository.
    *   Modify `stacks.yaml` to match your network and resource requirements.
    *   Update the hard-coded values in the scripts and configuration files.
    *   Create your own `.env.enc` files with your secrets.
