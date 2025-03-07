output "lxc_containers" {
  description = "Oluşturulan LXC containerlar"
  value = {
    for name, container in proxmox_lxc.container : name => {
      id   = container.vmid
      ip   = container.network[0].ip
      name = container.hostname
    }
  }
}
