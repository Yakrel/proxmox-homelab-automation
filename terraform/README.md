# Terraform for Proxmox Infrastructure Automation

This directory contains Terraform code for creating LXC containers and related infrastructure on Proxmox.
Terraform is **only** responsible for creating infrastructure; container configurations are done with Ansible.

## Setup Steps

1. Copy `terraform.tfvars.example` as `terraform.tfvars`
2. Edit `terraform.tfvars` with your Proxmox password and other required information
3. Run the following commands:

```bash
terraform init
terraform plan
terraform apply
```

4. After Terraform finishes, create inventory with:

```bash
cd ..
./02_terraform_to_ansible.sh
```

5. Configure containers with Ansible:

```bash
cd ansible
ansible-playbook -i inventory/all playbook.yml
```

## Terraform Responsibilities:

- Creating LXC containers (Alpine Linux)
- Network configuration
- Storage mount points setup
- Setting permissions on required directories (/datapool/config, /datapool/media, /datapool/torrents)

## Ansible Responsibilities:

- Docker and Docker Compose installation
- SSH key distribution and security configurations
- Service configurations
- Deploying and starting Docker Compose files
