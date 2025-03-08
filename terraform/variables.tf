# Proxmox connection variables
variable "proxmox_api_url" {
  description = "The URL of the Proxmox API"
  type        = string
}

variable "proxmox_api_token_id" {
  description = "The token ID for Proxmox API authentication"
  type        = string
}

variable "proxmox_api_token_secret" {
  description = "The token secret for Proxmox API authentication"
  type        = string
  sensitive   = true
}

# Node settings
variable "target_node" {
  description = "The target Proxmox node name"
  type        = string
}

# Storage settings
variable "storage_pool" {
  description = "The storage pool to use for LXC containers"
  type        = string
  default     = "local-lvm"
}

variable "storage_pool_type" {
  description = "The type of storage pool"
  type        = string
  default     = "lvm-thin"
}

# Network settings
variable "network_bridge" {
  description = "The network bridge to use for LXC containers"
  type        = string
  default     = "vmbr0"
}

variable "private_network" {
  description = "The private network prefix (e.g., 192.168.1)"
  type        = string
  default     = "192.168.1"
}

# LXC container configuration
variable "lxc_containers" {
  description = "Configuration for LXC containers"
  type = map(object({
    id       = number
    hostname = string
    ip       = string
    cores    = number
    memory   = number
    storage  = number
  }))
}
