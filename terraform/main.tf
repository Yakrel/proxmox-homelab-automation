# LXC Container creation
resource "proxmox_lxc" "container" {
  for_each = { for container in var.lxc_containers : container.name => container }
  
  target_node  = var.proxmox_node
  hostname     = each.value.name
  vmid         = each.value.id
  description  = each.value.description
  ostemplate   = var.alpine_template
  unprivileged = true
  start        = true
  onboot       = true

  # Console access
  tty          = 2
  cmode        = "console"
  console      = true
  
  # Root password
  password     = var.container_password  # Simple password, will be changed by Ansible

  # Resources
  cores  = each.value.cores
  memory = each.value.memory
  swap   = 512

  # Root Disk - created in the images folder on datapool
  rootfs {
    storage = "datapool"
    size    = each.value.disk_size
  }

  # Network
  network {
    name   = "eth0"
    bridge = "vmbr0"
    ip     = "${each.value.ip}/24"
    gw     = var.gateway
  }

  # DNS
  nameserver = var.nameserver

  # Container features
  features {
    nesting = true
    keyctl  = true
    fuse    = true
  }

  # Mount datapool - 4TB size with ACL enabled
  mountpoint {
    key     = "mp0"
    slot    = 0
    storage = "datapool"
    mp      = "/datapool"
    size    = "4T"  # 4TB disk size defined
    acl     = true  # Extended access control enabled
  }
  
  # Wait for container to be fully created before proceeding
  provisioner "local-exec" {
    command = "sleep 30"
  }
}

# SSH setup for Alpine LXCs
resource "null_resource" "ssh_setup" {
  depends_on = [proxmox_lxc.container]

  # Separate resource for each container
  for_each = { for container in var.lxc_containers : container.name => container }

  provisioner "local-exec" {
    command = "sleep 30"
  }

  # Copy script to a predictable location and run it
  provisioner "local-exec" {
    command = "${path.module}/scripts/setup_ssh.sh ${each.value.id}"
    
    on_failure = continue
  }

  # Check SSH connectivity after service starts
  provisioner "local-exec" {
    command = <<-EOT
      echo "Checking SSH connectivity for ${each.value.ip}..." >> ssh_setup_${each.value.id}.log
      ATTEMPTS=0
      MAX_ATTEMPTS=30
      while [ $ATTEMPTS -lt $MAX_ATTEMPTS ]; do
        if nc -z -w5 ${each.value.ip} 22; then
          echo "SUCCESS: SSH is up on ${each.value.ip} (container ${each.value.id})" >> ssh_setup_${each.value.id}.log
          exit 0
        fi
        echo "Waiting for SSH on ${each.value.ip}... (attempt $((ATTEMPTS+1))/$MAX_ATTEMPTS)" >> ssh_setup_${each.value.id}.log
        ATTEMPTS=$((ATTEMPTS+1))
        sleep 5
      done
      echo "WARNING: Could not verify SSH on ${each.value.ip} after $MAX_ATTEMPTS attempts" >> ssh_setup_${each.value.id}.log
      exit 0  # Always exit with success to not fail the Terraform apply
    EOT
    on_failure = continue
  }
}

# Automatically generate Ansible inventory file
resource "local_file" "ansible_inventory" {
  depends_on = [proxmox_lxc.container]  # Changed to only depend on container creation, not SSH setup
  
  filename = "../ansible/inventory/all"
  content = templatefile("${path.module}/templates/inventory.tftpl", {
    proxy_ip = proxmox_lxc.container["lxc-proxy-01"].network[0].ip,
    media_ip = proxmox_lxc.container["lxc-media-01"].network[0].ip,
    monitoring_ip = proxmox_lxc.container["lxc-monitoring-01"].network[0].ip,
    logging_ip = proxmox_lxc.container["lxc-logging-01"].network[0].ip,
    proxy_id = proxmox_lxc.container["lxc-proxy-01"].vmid,
    media_id = proxmox_lxc.container["lxc-media-01"].vmid,
    monitoring_id = proxmox_lxc.container["lxc-monitoring-01"].vmid,
    logging_id = proxmox_lxc.container["lxc-logging-01"].vmid
  })
}