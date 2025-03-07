# Storage Yapılandırması

## Samba Paylaşımı
Proxmox host üzerinde Samba paylaşımı yapılandırması:

```bash
# Samba kurulumu
apt update
apt install samba

# Samba konfigürasyonu
cat >> /etc/samba/smb.conf << 'EOF'

[datapool]
   path = /datapool
   browseable = yes
   read only = no
   force create mode = 0660
   force directory mode = 0770
   valid users = root
   # Performans optimizasyonları
   socket options = TCP_NODELAY IPTOS_LOWDELAY
   read raw = yes
   write raw = yes
   strict locking = no
EOF

# Root kullanıcısı için Samba şifresi belirleme
# Not: Proxmox root şifresi ile aynı şifreyi girin
smbpasswd -a root

# Servisi yeniden başlat
systemctl restart smbd
```

### Samba Erişim Bilgileri
- Kullanıcı adı: root
- Windows'ta bağlantı: `\\192.168.1.10\datapool`

## Sanoid Snapshot Yönetimi
Sanoid, ZFS snapshot'larını otomatik olarak yönetmek için kullanılır. Proxmox host üzerinde çalışır.

### Mevcut Snapshot'ları Temizleme
```bash
# Tüm snapshot'ları listele
zfs list -t snapshot

# rpool sistem snapshot'larını temizle
for snap in $(zfs list -H -t snapshot -o name | grep "rpool/ROOT/pve-1@"); do
    zfs destroy $snap
done

# datapool snapshot'larını temizle
for snap in $(zfs list -H -t snapshot -o name | grep "datapool@"); do
    zfs destroy $snap
done
```

### Kurulum ve Yapılandırma
```bash
# Sanoid kurulumu
apt update
apt install sanoid

# Sanoid config klasörünü oluştur
mkdir -p /etc/sanoid

# Yapılandırma dosyasını oluştur
cat > /etc/sanoid/sanoid.conf << EOF
[rpool/ROOT/pve-1]
        use_template = system
        recursive = yes

[datapool]
        use_template = data
        recursive = yes

[template_system]
        frequently = 0
        hourly = 0
        daily = 7
        monthly = 1
        yearly = 0
        autosnap = yes
        autoprune = yes

[template_data]
        frequently = 0
        hourly = 0
        daily = 15
        monthly = 2
        yearly = 0
        autosnap = yes
        autoprune = yes
EOF

# Servisi etkinleştir ve başlat
systemctl enable sanoid.timer
systemctl start sanoid.timer

# İlk snapshot'ları oluştur
sanoid --take-snapshots --verbose

# Servis durumunu kontrol et
systemctl status sanoid.timer

# Snapshot'ları listele
zfs list -t snapshot
```



### Sıkıştırılmış Backup Alma ve Geri Yükleme
```bash
# Backup alma
zfs send rpool/ROOT/pve-1@snapshot_adi | gzip > /datapool/backups/system_backup.gz
zfs send datapool@snapshot_adi | gzip > /datapool/backups/data_backup.gz

# Geri yükleme
gunzip -c /datapool/backups/system_backup.gz | zfs receive rpool/ROOT/pve-1
gunzip -c /datapool/backups/data_backup.gz | zfs receive datapool
```
