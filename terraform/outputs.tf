output "lxc_containers" {
  description = "Created LXC containers"
  value = {
    for name, container in proxmox_lxc.container : name => {
      id   = container.vmid
      ip   = container.network[0].ip
      name = container.hostname
    }
  }
}
