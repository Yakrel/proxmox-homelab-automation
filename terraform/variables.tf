# Proxmox Provider Variables
variable "proxmox_api_url" {
  description = "Proxmox API URL"
  type        = string
  # No default - differs per environment
}

variable "proxmox_user" {
  description = "Proxmox username"
  type        = string
  default     = "root@pam"  # Typically unchanged, safe default
}

variable "proxmox_password" {
  description = "Proxmox password"
  type        = string
  sensitive   = true  # Mark as sensitive data
}

variable "proxmox_tls_insecure" {
  description = "Disable Proxmox TLS verification"
  type        = bool
  default     = true  # Usually true in home environments
}

variable "proxmox_debug" {
  description = "Enable debug mode for Proxmox provider"
  type        = bool
  default     = false  # Debug disabled by default
}

# Proxmox Node Variable
variable "proxmox_node" {
  description = "Proxmox node name"
  type        = string
  default     = "pve01"  # Can be changed
}

# Network Variables
variable "gateway" {
  description = "Network gateway IP address"
  type        = string
  # No default - differs per network
}

variable "nameserver" {
  description = "DNS server IP address"
  type        = string
  default     = "1.1.1.1"  # Common DNS, safe default
}

# LXC Container Definitions
variable "lxc_containers" {
  description = "List of LXC containers"
  type = list(object({
    name        = string
    id          = number
    ip          = string
    memory      = number
    cores       = number
    disk_size   = string
    description = string
  }))
  # No default - custom environment configuration
}

# Alpine Template Variable
variable "alpine_template" {
  description = "Alpine template path and filename"
  type        = string
  default     = "datapool:template/cache/alpine-3.21-default_20241217_amd64.tar.xz"
}

# Container Password Variable
variable "container_password" {
  description = "LXC container root password"
  type        = string
  default     = "alpine"  # Should use a secure password
  sensitive   = true
}

variable "grafana_password" {
  description = "Grafana admin password"
  type        = string
  default     = "grafana"
}
