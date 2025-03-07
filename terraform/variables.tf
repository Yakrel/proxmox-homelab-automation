# Proxmox Provider Değişkenleri
variable "proxmox_api_url" {
  description = "Proxmox API URL'si"
  type        = string
  # Varsayılan değer YOK - Her ortam için farklı olabilir
}

variable "proxmox_user" {
  description = "Proxmox kullanıcı adı"
  type        = string
  default     = "root@pam"  # Genellikle değişmez, güvenli değer
}

variable "proxmox_password" {
  description = "Proxmox şifresi"
  type        = string
  sensitive   = true  # Hassas veri olarak işaretle
}

variable "proxmox_tls_insecure" {
  description = "Proxmox TLS doğrulamasını devre dışı bırak"
  type        = bool
  default     = true  # Ev ortamlarında genellikle true
}

variable "proxmox_debug" {
  description = "Proxmox provider debug modunu etkinleştir"
  type        = bool
  default     = false  # Normalde debug kapalı
}

# Proxmox Node Değişkeni
variable "proxmox_node" {
  description = "Proxmox node adı"
  type        = string
  default     = "pve01"  # Değiştirilebilir
}

# Network Değişkenleri
variable "gateway" {
  description = "Ağ geçidi IP adresi"
  type        = string
  # Varsayılan değer YOK - her ağ için farklı olabilir
}

variable "nameserver" {
  description = "DNS sunucu IP adresi"
  type        = string
  default     = "1.1.1.1"  # Ortak DNS, güvenli değer
}

# LXC Container Tanımları
variable "lxc_containers" {
  description = "LXC container listesi"
  type = list(object({
    name        = string
    id          = number
    ip          = string
    memory      = number
    cores       = number
    disk_size   = string
    description = string
  }))
  # Varsayılan değer YOK - özel ortam yapılandırması
}

# Alpine Template Değişkeni
variable "alpine_template" {
  description = "Alpine template yolu ve dosya adı"
  type        = string
  default     = "datapool:template/cache/alpine-3.21-default_20241217_amd64.tar.xz"
}

# Container Şifre Değişkeni
variable "container_password" {
  description = "LXC container root şifresi"
  type        = string
  default     = "alpine"  # Güvenli bir şifre kullanılmalı
  sensitive   = true
}

variable "grafana_password" {
  description = "Grafana admin şifresi"
  type        = string
  default     = "grafana"
}
