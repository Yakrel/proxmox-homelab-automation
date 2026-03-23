// Architecture Data - Single Source of Truth for the Dashboard
const ARCHITECTURE_DATA = {
    meta: {
        lastUpdated: "2025-12-15",
        host: "Proxmox VE (192.168.1.10)",
        specs: "Intel Xeon E3-1276 v3 @ 3.60GHz | 32GB DDR3 ECC | ZFS Storage"
    },
    translations: {
        en: {
            title: "Proxmox Homelab Architecture",
            subtitle: "Hybrid Infrastructure & Network Topology",
            lastUpdated: "Last Updated",
            specs: "System Specifications",
            networkTopology: "Network Topology",
            serviceInventory: "Service Inventory",
            timeline: "Infrastructure Timeline",
            status: { active: "Active", standby: "Standby", maintenance: "Maintenance" },
            categories: { Infrastructure: "Infrastructure", Media: "Media", Utilities: "Utilities", Productivity: "Productivity", Observability: "Observability", Gaming: "Gaming", Development: "Development" }
        },
        tr: {
            title: "Proxmox Homelab Mimarisi",
            subtitle: "Hibrit Altyapı ve Ağ Topolojisi",
            lastUpdated: "Son Güncelleme",
            specs: "Sistem Özellikleri",
            networkTopology: "Ağ Topolojisi",
            serviceInventory: "Servis Envanteri",
            timeline: "Altyapı Geçmişi",
            status: { active: "Aktif", standby: "Beklemede", maintenance: "Bakım" },
            categories: { Infrastructure: "Altyapı", Media: "Medya", Utilities: "Araçlar", Productivity: "Üretkenlik", Observability: "Gözlemlenebilirlik", Gaming: "Oyun", Development: "Geliştirme" }
        }
    },
    networks: [
        { id: "wan", name: "Internet", type: "external" },
        { id: "cloudflare", name: { en: "Cloudflare Edge", tr: "Cloudflare Edge" }, type: "edge", services: ["Zero Trust", "WAF", "DDoS Protection"] },
        { id: "lan", name: { en: "Home LAN", tr: "Ev Ağı (LAN)" }, type: "internal", subnet: "192.168.1.0/24" },
        { id: "proxy-net", name: "homelab-proxy", type: "docker", subnet: "172.18.0.0/16" }
    ],
    timeline: [
        { date: "2025-12-24", title: { en: "VPN Architecture Upgrade", tr: "VPN Mimari Güncellemesi" }, desc: { en: "Deployed Tailscale as primary VPN; repurposed Cloudflare for Web Tunnel only.", tr: "Tailscale ana VPN olarak yapılandırıldı; Cloudflare sadece Web Tunnel için ayrıldı." } },
        { date: "2025-12-15", title: { en: "Game Server Expansion", tr: "Oyun Sunucusu Genişletmesi" }, desc: { en: "Added Palworld & Satisfactory with automated switching.", tr: "Otomatik geçişli Palworld ve Satisfactory sunucuları eklendi." } },
        { date: "2025-11-20", title: { en: "GPU Passthrough", tr: "GPU Passthrough" }, desc: { en: "Implemented Unprivileged LXC Nvidia passthrough for Jellyfin.", tr: "Jellyfin için ayrıcalıksız LXC Nvidia passthrough uygulandı." } },
        { date: "2025-10-01", title: { en: "Zero Trust Migration", tr: "Zero Trust Geçişi" }, desc: { en: "Moved all ingress to Cloudflare Tunnels, closed port 443.", tr: "Tüm giriş trafiği Cloudflare Tunnels'a taşındı, 443 portu kapatıldı." } }
    ],
    stacks: [
        {
            id: 100,
            name: { en: "Proxy & Ingress", tr: "Proxy ve Giriş" },
            ip: "192.168.1.100",
            category: "Infrastructure",
            specs: { cpu: 2, ram: "2GB" },
            services: [
                { name: "Nginx Proxy Manager", icon: "fa-solid fa-arrow-right-to-bracket", port: "80/443", url: "https://npm.byetgin.com", desc: { en: "Reverse Proxy & SSL Management", tr: "Ters Proxy ve SSL Yönetimi" }, status: "active" },
                { name: "AdGuard Home", icon: "fa-solid fa-shield-dog", port: "53", url: "http://192.168.1.100:3000", desc: { en: "Network-wide Ad Blocking & DNS", tr: "Ağ Genelinde Reklam Engelleme ve DNS" }, status: "active" },
                { name: "Tailscale", icon: "fa-solid fa-network-wired", port: "VPN", desc: { en: "Mesh VPN & Subnet Router", tr: "Mesh VPN ve Alt Ağ Yönlendirici" }, status: "active" },
                { name: "Cloudflared", icon: "fa-brands fa-cloudflare", port: "Tunnel", desc: { en: "Web Services Tunnel (Ingress)", tr: "Web Servisleri Tüneli (Giriş)" }, status: "active" }
            ]
        },
        {
            id: 101,
            name: { en: "Media Stack", tr: "Medya Yığını" },
            ip: "192.168.1.101",
            category: "Media",
            specs: { cpu: 6, ram: "10GB", gpu: "NVIDIA GTX 970" },
            services: [
                { name: "Jellyfin", icon: "fa-solid fa-film", port: "8096", url: "https://media.byetgin.com", desc: { en: "Media Server (Hardware Transcoding)", tr: "Medya Sunucusu (Donanım Transcoding)" }, status: "active", gpu: true },
                { name: "Immich", icon: "fa-solid fa-images", port: "2283", url: "https://photos.byetgin.com", desc: { en: "Self-hosted Google Photos alternative", tr: "Self-hosted Google Photos alternatifi" }, status: "active", gpu: true },
                { name: "Sonarr", icon: "fa-solid fa-tv", port: "8989", desc: { en: "TV Show Automation", tr: "Dizi Otomasyonu" }, status: "active" },
                { name: "Radarr", icon: "fa-solid fa-film", port: "7878", desc: { en: "Movie Automation", tr: "Film Otomasyonu" }, status: "active" },
                { name: "qBittorrent", icon: "fa-solid fa-download", port: "8080", desc: { en: "Download Client", tr: "İndirme İstemcisi" }, status: "active" },
                { name: "Jellyseerr", icon: "fa-solid fa-magnifying-glass", port: "5055", desc: { en: "Request Management", tr: "Talep Yönetimi" }, status: "active" }
            ]
        },
        {
            id: 102,
            name: { en: "File Manager", tr: "Dosya Yöneticisi" },
            ip: "192.168.1.102",
            category: "Utilities",
            specs: { cpu: 2, ram: "3GB" },
            services: [
                { name: "JDownloader 2", icon: "fa-solid fa-download", port: "3129", desc: { en: "Download Manager", tr: "İndirme Yöneticisi" }, status: "active" },
                { name: "MeTube", icon: "fa-brands fa-youtube", port: "8081", desc: { en: "YouTube Downloader", tr: "YouTube İndirici" }, status: "active" },
                { name: "Palmr", icon: "fa-solid fa-folder-open", port: "5487", desc: { en: "File Manager", tr: "Dosya Yöneticisi" }, status: "active" }
            ]
        },
        {
            id: 103,
            name: { en: "Web Tools", tr: "Web Araçları" },
            ip: "192.168.1.103",
            category: "Productivity",
            specs: { cpu: 4, ram: "6GB", gpu: "Shared" },
            services: [
                { name: "Homepage", icon: "fa-solid fa-table-columns", port: "3000", url: "https://home.byetgin.com", desc: { en: "Main Dashboard", tr: "Ana Panel" }, status: "active" },
                { name: "Desktop Workspace", icon: "fa-solid fa-desktop", port: "5800", desc: { en: "Web-based Linux Desktop (GPU Accel)", tr: "Web tabanlı Linux Masaüstü (GPU Hızlandırmalı)" }, status: "active", gpu: true },
                { name: "Vaultwarden", icon: "fa-solid fa-lock", port: "8201", desc: { en: "Password Manager", tr: "Şifre Yöneticisi" }, status: "active" },
                { name: "CouchDB", icon: "fa-solid fa-database", port: "5984", desc: { en: "Obsidian Sync Database", tr: "Obsidian Senkronizasyon Veritabanı" }, status: "active" }
            ]
        },
        {
            id: 104,
            name: { en: "Monitoring", tr: "İzleme" },
            ip: "192.168.1.104",
            category: "Observability",
            specs: { cpu: 4, ram: "6GB" },
            services: [
                { name: "Grafana", icon: "fa-solid fa-chart-line", port: "3000", url: "https://grafana.byetgin.com", desc: { en: "Metrics Visualization", tr: "Metrik Görselleştirme" }, status: "active" },
                { name: "Prometheus", icon: "fa-solid fa-eye", port: "9090", desc: { en: "Time-series Database", tr: "Zaman Serisi Veritabanı" }, status: "active" },
                { name: "Loki", icon: "fa-solid fa-list", port: "3100", desc: { en: "Log Aggregation", tr: "Log Toplama" }, status: "active" }
            ]
        },
        {
            id: 105,
            name: { en: "Game Servers", tr: "Oyun Sunucuları" },
            ip: "192.168.1.105",
            category: "Gaming",
            specs: { cpu: 8, ram: "16GB" },
            services: [
                { name: "Palworld", icon: "fa-solid fa-gamepad", port: "8211 UDP", desc: { en: "Dedicated Server", tr: "Dedicated Sunucu" }, status: "standby" },
                { name: "Satisfactory", icon: "fa-solid fa-industry", port: "7777 UDP", desc: { en: "Dedicated Server", tr: "Dedicated Sunucu" }, status: "active" }
            ]
        },
        {
            id: 106,
            name: { en: "Backup", tr: "Yedekleme" },
            ip: "192.168.1.106",
            category: "Infrastructure",
            specs: { cpu: 4, ram: "8GB" },
            services: [
                { name: "Backrest", icon: "fa-solid fa-box-archive", port: "9898", desc: { en: "Local Backup Orchestrator", tr: "Yerel Yedekleme Orkestratörü" }, status: "active" },
                { name: "Rclone", icon: "fa-brands fa-google-drive", port: "Sync", desc: { en: "Offsite Encrypted Sync", tr: "Uzak Şifreli Senkronizasyon" }, status: "active" }
            ]
        },
        {
            id: 107,
            name: { en: "Development", tr: "Geliştirme" },
            ip: "192.168.1.107",
            category: "Development",
            specs: { cpu: 4, ram: "6GB" },
            services: [
                { name: "Docker Env", icon: "fa-brands fa-docker", port: "N/A", desc: { en: "Test Environment", tr: "Test Ortamı" }, status: "active" },
                { name: "Scripts", icon: "fa-solid fa-terminal", port: "Auto", desc: { en: "Automation Scripts", tr: "Otomasyon Scriptleri" }, status: "active" }
            ]
        }
    ]
};
