terraform {
  required_providers {
    proxmox = {
      source = "telmate/proxmox"
      # En son sürüm kullanılacak - versiyon belirtilmedi
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
}
