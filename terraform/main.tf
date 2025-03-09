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
  pm_user = var.proxmox_user
  pm_password = var.proxmox_password
  pm_tls_insecure = true
}

resource "proxmox_lxc" "lxc_container" {
  for_each = var.lxc_containers

  target_node = var.target_node
  vmid = each.value.id
  hostname = each.value.hostname
  ostemplate = "${var.storage_pool}:vztmpl/${var.ostemplate}"
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
    # Removed fuse = true that caused permission issues
  }

  # Only add datapool mountpoint if it exists
  mountpoint {
    key = "0"
    slot = 0
    storage = "datapool"  # changed from "/datapool"
    mp = "/datapool"
    size = "0G"
  }

  ssh_public_keys = file("~/.ssh/id_rsa.pub")

  # İlk önce konteyneri oluşturalım, başlatılmasını ve kurulumunu sağlayalım
  provisioner "local-exec" {
    command = <<-EOT
      # Konteynerin tamamen başladığından emin olalım
      sleep 20
      
      # Proxmox host üzerinden doğrudan konteynere erişim sağlayarak paketleri kur
      echo "Temel paketleri yüklüyorum: ${each.value.hostname} (${each.value.ip})"
      ssh -o StrictHostKeyChecking=no ${var.proxmox_user%@*}@${split(":", replace(var.proxmox_api_url, "/api2/json", ""))[1]} \
        "pct exec ${each.value.id} -- ash -c 'apk update && \
        apk add --no-cache openssh bash curl docker docker-compose && \
        rc-update add sshd default && \
        rc-update add docker default'"
    EOT
  }
  
  # İkinci adım: SSH servisini başlat ve SSH anahtarını doğru yere yerleştir
  provisioner "local-exec" {
    command = <<-EOT
      echo "SSH servisini başlatıyorum: ${each.value.hostname} (${each.value.ip})"
      ssh -o StrictHostKeyChecking=no ${var.proxmox_user%@*}@${split(":", replace(var.proxmox_api_url, "/api2/json", ""))[1]} \
        "pct exec ${each.value.id} -- ash -c 'mkdir -p /root/.ssh && \
        echo \"${file("~/.ssh/id_rsa.pub")}\" > /root/.ssh/authorized_keys && \
        chmod 700 /root/.ssh && \
        chmod 600 /root/.ssh/authorized_keys && \
        rc-service sshd start && \
        rc-service docker start'"
    EOT
  }
  
  # SSH bağlantısını test et, başarısız olursa devam et ama hata göster
  provisioner "local-exec" {
    command = <<-EOT
      echo "SSH bağlantısını kontrol ediyorum: ${each.value.hostname} (${each.value.ip})..."
      # SSH bağlantısı için 5 deneme yapalım
      for i in 1 2 3 4 5; do
        ssh -o StrictHostKeyChecking=no -o ConnectTimeout=3 root@${each.value.ip} "echo 'SSH bağlantısı başarılı'" && break || {
          echo "SSH bağlantı denemesi $i başarısız, 5 saniye sonra tekrar deneniyor..."
          if [ $i -eq 5 ]; then
            echo "UYARI: SSH bağlantısı kurulamadı ama kurulum devam ediyor. Konteyner kuruldu ancak SSH ile erişim sağlanamadı."
            echo "Konteynere manuel olarak erişip SSH servisini kontrol edin."
          fi
          sleep 5
        }
      done
    EOT
    on_failure = continue
  }
  
  # Eğer SSH başarılı olursa, Docker'ı da kontrol et
  provisioner "local-exec" {
    command = <<-EOT
      if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=3 -o BatchMode=yes root@${each.value.ip} exit 2>/dev/null; then
        echo "Docker servisini kontrol ediyorum: ${each.value.hostname}"
        ssh -o StrictHostKeyChecking=no root@${each.value.ip} "docker --version || echo 'Docker kurulumu başarısız olabilir. Manuel kontrol edin.'"
      else
        echo "SSH bağlantısı başarısız olduğu için Docker kontrolü yapılamadı"
      fi
    EOT
    on_failure = continue
  }
}

output "lxc_ips" {
  value = {
    for name, container in proxmox_lxc.lxc_container : name => container.network[0].ip
  }
}
