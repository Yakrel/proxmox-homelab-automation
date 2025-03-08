terraform {
  required_providers {
    proxmox = {
      source = "telmate/proxmox"
      # Latest version will be used - version not specified
    }
  }
  required_version = ">= 1.0.0"
}

provider "proxmox" {
  pm_api_url      = var.proxmox_api_url
  pm_user         = var.proxmox_user
  pm_password     = var.proxmox_password
  pm_tls_insecure = var.proxmox_tls_insecure
  pm_debug        = var.proxmox_debug
  pm_log_levels = {
    _default    = "debug"
    _capturelog = ""
  }
}
