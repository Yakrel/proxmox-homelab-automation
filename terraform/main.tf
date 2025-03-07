# LXC Container oluşturma
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

  # Console erişimi
  tty          = 2
  cmode        = "console"
  console      = true
  
  # Root şifre
  password     = var.container_password  # Basit şifre, Ansible ile değiştirilecek

  # Resources
  cores  = each.value.cores
  memory = each.value.memory
  swap   = 512

  # Root Disk - datapool'daki images klasörüne oluşturulacak
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

  # Mount datapool - boyut belirtilmeden mount edilir
  mountpoint {
    key     = "mp0"
    slot    = 0
    storage = "datapool"
    mp      = "/datapool"
  }
}
