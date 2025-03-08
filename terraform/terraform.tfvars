# Proxmox connection settings
proxmox_api_url = "https://192.168.1.10:8006/api2/json"
proxmox_user = "root@pam"
proxmox_password = "YOUR_PASSWORD"

# Node settings
target_node = "pve01"

# Storage settings
storage_pool = "datapool"  # Kullanıcı tarafından seçilen storage havuzu
storage_pool_type = "zfs"  # ZFS havuzu için uygun tip

# OS template - automatically detected latest version
ostemplate = "alpine-3.18-default_20230607_amd64.tar.xz"  # Otomatik tespit edilecek

# Network settings
network_bridge = "vmbr0" 
private_network = "192.168.1"

# LXC containers configuration
lxc_containers = {
  "media" = {
    id = 102
    hostname = "media"
    ip = "192.168.1.102"
    cores = 4
    memory = 16384
    storage = 32
  },
  "monitoring" = {
    id = 103
    hostname = "monitoring"
    ip = "192.168.1.103"
    cores = 2
    memory = 4096
    storage = 16
  },
  "logging" = {
    id = 104
    hostname = "logging"
    ip = "192.168.1.104"
    cores = 2
    memory = 4096
    storage = 16
  },
  "proxy" = {
    id = 125
    hostname = "proxy"
    ip = "192.168.1.125"
    cores = 2
    memory = 2048
    storage = 8
  }
}
