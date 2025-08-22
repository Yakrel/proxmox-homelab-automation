# Proxmox Homelab Automation

Automated deployment of containerized services on Proxmox VE using Ansible. Creates separate LXC containers for different service stacks, managed by Docker Compose.

## 🚀 Quick Start

Run the installer directly on your Proxmox host:

```bash
bash <(curl -s https://raw.githubusercontent.com/Yakrel/proxmox-homelab-automation/main/installer.sh)
```

**First run**: Creates Ansible Control LXC and configures API credentials  
**Subsequent runs**: Shows interactive menu to deploy stacks

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

## 📝 Managing Secrets

Edit encrypted secrets:
```bash
pct exec 151 -- ansible-vault edit /root/proxmox-homelab-automation/secrets.yml
```
