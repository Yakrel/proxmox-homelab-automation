terraform {
  required_providers {
    proxmox = {
      source = "telmate/proxmox"
      version = "2.9.14"
    }
  }
}

provider "proxmox" {
  pm_api_url = var.proxmox_api_url
  pm_api_token_id = var.proxmox_api_token_id
  pm_api_token_secret = var.proxmox_api_token_secret
  pm_tls_insecure = true
}

resource "proxmox_lxc" "lxc_container" {
  for_each = var.lxc_containers

  target_node = var.target_node
  vmid = each.value.id
  hostname = each.value.hostname
  ostemplate = "local:vztmpl/alpine-3.18-default_20230607_amd64.tar.xz"
  password = "changeme"  # Will be removed after SSH key is added
  unprivileged = true

  memory = each.value.memory
  swap = 512
  cores = each.value.cores

  rootfs {
    storage = var.storage_pool
    size = "${each.value.storage}G"
  }

  network {
    name = "eth0"
    bridge = var.network_bridge
    ip = "${each.value.ip}/24"
    gw = "${var.private_network}.1"
  }

  start = true
  onboot = true

  features {
    nesting = true
    fuse = true
  }

  mountpoint {
    key = "0"
    slot = 0
    storage = "/datapool"
    mp = "/datapool"
    size = "0G"
  }

  ssh_public_keys = file("~/.ssh/id_rsa.pub")

  # Install required packages and setup SSH
  provisioner "local-exec" {
    command = <<-EOT
      sleep 30
      ssh -o StrictHostKeyChecking=no root@${each.value.ip} "apk update && \
      apk add --no-cache openssh bash curl docker docker-compose && \
      rc-update add sshd && \
      rc-update add docker && \
      rc-service sshd start && \
      rc-service docker start"
    EOT
  }
}

output "lxc_ips" {
  value = {
    for name, container in proxmox_lxc.lxc_container : name => container.network[0].ip
  }
}
