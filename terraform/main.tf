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

  # Mount datapool - 4TB boyut ve ACL etkin
  mountpoint {
    key     = "mp0"
    slot    = 0
    storage = "datapool"
    mp      = "/datapool"
    size    = "4T"  # 4TB disk boyutu tanımlandı
    acl     = true  # Genişletilmiş erişim kontrolü etkinleştirildi
  }
}

# Alpine LXC'lere SSH kurulumu (Ansible bağlantısı için gerekli)
resource "null_resource" "ssh_setup" {
  depends_on = [proxmox_lxc.container]

  # Her container için ayrı bir provisioner
  for_each = { for container in var.lxc_containers : container.name => container }

  # Container başlamadan provisionerlar çalışmasın diye 
  # bekletiyoruz
  provisioner "local-exec" {
    command = "sleep 10"
  }

  # Bir log dosyası oluştur (opsiyonel ama yararlı)
  provisioner "local-exec" {
    command = "echo 'SSH Setup for ${each.value.name} (ID: ${each.value.id}) - $(date)' > ssh_setup_${each.value.id}.log"
  }

  # SSH ve diğer gereksinimleri kur
  provisioner "local-exec" {
    command = <<-EOT
      echo "Installing SSH for container ${each.value.id}..." >> ssh_setup_${each.value.id}.log
      pct exec ${each.value.id} -- ash -c "apk update" >> ssh_setup_${each.value.id}.log 2>&1 || true
      pct exec ${each.value.id} -- ash -c "apk add openssh-server bash shadow" >> ssh_setup_${each.value.id}.log 2>&1 || true
      pct exec ${each.value.id} -- ash -c "rc-update add sshd" >> ssh_setup_${each.value.id}.log 2>&1 || true
      pct exec ${each.value.id} -- ash -c "mkdir -p /etc/ssh/" >> ssh_setup_${each.value.id}.log 2>&1 || true
      pct exec ${each.value.id} -- ash -c 'echo "PermitRootLogin yes" >> /etc/ssh/sshd_config' >> ssh_setup_${each.value.id}.log 2>&1 || true
      pct exec ${each.value.id} -- ash -c 'echo "PasswordAuthentication yes" >> /etc/ssh/sshd_config' >> ssh_setup_${each.value.id}.log 2>&1 || true
      pct exec ${each.value.id} -- ash -c "/etc/init.d/sshd start" >> ssh_setup_${each.value.id}.log 2>&1 || true
      echo "SSH setup completed for container ${each.value.id}" >> ssh_setup_${each.value.id}.log
    EOT
  }

  # SSH servisi başladıktan sonra bağlantı kontrolü yap
  provisioner "local-exec" {
    command = <<-EOT
      echo "Checking SSH connectivity for ${each.value.ip}..." >> ssh_setup_${each.value.id}.log
      ATTEMPTS=0
      MAX_ATTEMPTS=30
      while [ $ATTEMPTS -lt $MAX_ATTEMPTS ]; do
        if nc -z -w5 ${each.value.ip} 22; then
          echo "SUCCESS: SSH is up on ${each.value.ip} (container ${each.value.id})" >> ssh_setup_${each.value.id}.log
          exit 0
        fi
        echo "Waiting for SSH on ${each.value.ip}... (attempt $((ATTEMPTS+1))/$MAX_ATTEMPTS)" >> ssh_setup_${each.value.id}.log
        ATTEMPTS=$((ATTEMPTS+1))
        sleep 5
      done
      echo "WARNING: Could not verify SSH on ${each.value.ip} after $MAX_ATTEMPTS attempts" >> ssh_setup_${each.value.id}.log
      # Exit with 0 to not fail the Terraform apply
      exit 0
    EOT
  }
}

# Ansible inventory dosyasını otomatik oluştur
resource "local_file" "ansible_inventory" {
  depends_on = [null_resource.ssh_setup]
  
  filename = "../ansible/inventory/all"
  content = templatefile("${path.module}/templates/inventory.tftpl", {
    proxy_ip = proxmox_lxc.container["lxc-proxy-01"].network[0].ip,
    media_ip = proxmox_lxc.container["lxc-media-01"].network[0].ip,
    monitoring_ip = proxmox_lxc.container["lxc-monitoring-01"].network[0].ip,
    logging_ip = proxmox_lxc.container["lxc-logging-01"].network[0].ip
  })
}