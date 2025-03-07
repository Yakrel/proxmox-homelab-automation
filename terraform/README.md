# Terraform ile Proxmox Altyapı Otomasyonu

Bu klasör, Proxmox üzerinde LXC container'ları ve ilgili altyapıyı oluşturmak için Terraform kodlarını içerir.
Terraform **sadece** altyapı oluşturmaktan sorumludur, container içi yapılandırmalar Ansible ile yapılır.

## Kurulum Adımları

1. `terraform.tfvars.example` dosyasını `terraform.tfvars` olarak kopyalayın
2. `terraform.tfvars` dosyasını düzenleyerek Proxmox şifrenizi ve diğer gerekli bilgileri girin
3. Aşağıdaki komutları çalıştırın:

```bash
terraform init
terraform plan
terraform apply
```

4. Terraform işlemini bitirdikten sonra, inventory oluşturmak için:

```bash
cd ..
./generate_inventory.sh
```

5. Ansible ile container içi yapılandırmaları yapın:

```bash
cd ansible
ansible-playbook -i inventory/all playbook.yml
```

## Terraform'un Sorumlu Olduğu İşlemler:

- LXC container oluşturma (Alpine Linux)
- Network yapılandırması
- Storage mount noktalarının ayarlanması
- Gerekli dizinlerde izinlerin ayarlanması (/datapool/config, /datapool/media, /datapool/torrents)

## Ansible'ın Sorumlu Olduğu İşlemler:

- Docker ve Docker Compose kurulumu
- SSH anahtarı dağıtımı ve güvenlik yapılandırmaları
- Servis yapılandırmaları
- Docker Compose dosyalarının yerleştirilmesi ve başlatılması
