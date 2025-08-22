# Proxmox Homelab Automation

Automated deployment of containerized services on Proxmox VE using Ansible. Creates separate LXC containers for different service stacks, each managed by Docker Compose and deployed via Ansible.

## ⚠️ Project Philosophy & Disclaimer

This repository documents my personal homelab setup, tailored specifically to my own hardware and network configuration. It is shared publicly to showcase my approach to infrastructure-as-code, automation, and GitOps principles.

**Please be aware that this is not a universal, one-click deployment solution.**

By design, many values are configurable through `stacks.yaml`, but you should be prepared to:
- Thoroughly review all configuration files
- Replace default values with your own environment's settings  
- Adjust resource allocations as needed

Feel free to fork this repository and use it as inspiration for your own homelab automation journey!

## 🚀 Quick Start

### Recommended: Direct from GitHub

Run the installer directly on your Proxmox host:

```bash
bash <(curl -s https://raw.githubusercontent.com/Yakrel/proxmox-homelab-automation/main/installer.sh)
```

### Alternative: Local Execution

If you have already cloned the repository:

```bash
# Navigate to the repository directory on your Proxmox host and run:
./installer.sh
```

### How It Works

- **First Time**: Creates Ansible Control LXC (ID 151) and configures API credentials
- **After Setup**: Interactive menu to deploy stacks and manage your homelab
- **Everything is menu-driven** - no manual playbook execution required!

## 🏗️ Architecture

- **installer.sh**: Single entry point, runs on Proxmox host
- **Ansible Control LXC**: Dedicated container (ID 151) with Ansible and this repository  
- **Service Stacks**: Individual LXC containers for each service group

## 📦 Available Stacks

| Stack | Description | Container ID |
|-------|-------------|--------------|
| Host Configuration | Proxmox host setup | - |
| Proxy | Cloudflared, monitoring agents | 100 |
| Media | Jellyfin, Sonarr, Radarr, etc. | 101 |
| Files | File management services | 102 |
| Webtools | Web-based utilities | 103 |
| Monitoring | Prometheus, Grafana | 104 |
| Backup | Proxmox Backup Server | 150 |

## 🔐 Configuration

- **Central Config**: All settings in `stacks.yaml`
- **Secrets**: Encrypted with Ansible Vault in `secrets.yml`
- **Customization**: Modify `stacks.yaml` for your environment

## ⚠️ Important Notes

This is a **personal homelab configuration**. Before using:

1. Review `stacks.yaml` and adjust IP addresses, storage pools, etc.
2. Update secrets in `secrets.yml` during first setup
3. Modify resource allocations as needed

## 📝 Secrets Management

All secrets (API keys, passwords, etc.) are managed in a single encrypted file: `secrets.yml`.

- **Encryption**: File is encrypted using `ansible-vault` with a password you set during setup
- **Password Management**: You'll be prompted for the vault password when deploying stacks
- **Editing**: Use the ansible-vault edit command from within the control LXC:

```bash
pct exec 151 -- ansible-vault edit /root/proxmox-homelab-automation/secrets.yml
```

**Important**: Remember your vault password - you'll need it for all homelab operations!
