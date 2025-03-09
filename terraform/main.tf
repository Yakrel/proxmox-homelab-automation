terraform {
  required_providers {
    proxmox = {
      source = "telmate/proxmox"
      version = "2.9.14"
    }
  }
}

provider "proxmox" {
  pm_api_url      = var.proxmox_api_url
  pm_user         = var.proxmox_user
  pm_password     = var.proxmox_password
  pm_tls_insecure = true
}

resource "proxmox_lxc" "lxc_container" {
  for_each    = var.lxc_containers

  target_node = var.target_node
  vmid        = each.value.id
  hostname    = each.value.hostname
  ostemplate  = "${var.storage_pool}:vztmpl/${var.ostemplate}"
  password    = "changeme"  # Will be removed after SSH key is added
  unprivileged = true

  memory = each.value.memory
  swap   = 512
  cores  = each.value.cores

  rootfs {
    storage = var.storage_pool
    size    = "${each.value.storage}G"
  }

  network {
    name   = "eth0"
    bridge = var.network_bridge
    ip     = "${each.value.ip}/24"
    gw     = "${var.private_network}.1"
  }

  start  = true
  onboot = true

  features {
    nesting = true
  }

  # Only add datapool mountpoint if required
  mountpoint {
    key     = "0"
    slot    = 0
    storage = "datapool"
    mp      = "/datapool"
    size    = "0G"
  }

  ssh_public_keys = file("~/.ssh/id_rsa.pub")

  # FIXED: Use Proxmox host as a proxy to set up containers instead of direct SSH
  # This is more reliable as it doesn't depend on SSH being set up in the containers first
  provisioner "local-exec" {
    command = <<-EOT
      # Wait for container to fully initialize
      sleep 40
      
      # Connect to Proxmox host and run commands in the container
      ssh -o StrictHostKeyChecking=no ${var.proxmox_user%@*}@${split(":", replace(var.proxmox_api_url, "/api2/json", ""))[1]} \
        "pct exec ${each.value.id} -- ash -c 'apk update && \
        apk add --no-cache openssh bash curl docker docker-compose && \
        rc-update add sshd default && \
        rc-update add docker default && \
        mkdir -p /root/.ssh && \
        echo \"${file("~/.ssh/id_rsa.pub")}\" > /root/.ssh/authorized_keys && \
        chmod 700 /root/.ssh && \
        chmod 600 /root/.ssh/authorized_keys && \
        rc-service sshd start && \
        rc-service docker start'"
      
      # Wait for SSH to become available
      echo "Waiting for SSH on ${each.value.ip} to become available..."
      count=0
      while ! ssh -o StrictHostKeyChecking=no -o ConnectTimeout=3 -o BatchMode=yes root@${each.value.ip} exit 2>/dev/null; do
        count=$((count+1))
        if [ $count -gt 10 ]; then
          echo "WARNING: SSH connection could not be established after 10 attempts. Container may need manual SSH configuration."
          break
        fi
        echo "Attempt $count: SSH not ready yet. Waiting 5 seconds..."
        sleep 5
      done
    EOT
    on_failure = continue
  }
}

output "lxc_ips" {
  value = {
    for name, container in proxmox_lxc.lxc_container : name => container.network[0].ip
  }
}
