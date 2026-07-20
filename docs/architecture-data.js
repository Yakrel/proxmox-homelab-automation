// Architecture Data - Single Source of Truth for the Dashboard
const ARCHITECTURE_DATA = {
    meta: {
        lastUpdated: "2026-07-20",
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
            categories: { Infrastructure: "Infrastructure", Media: "Media", Utilities: "Utilities", Productivity: "Productivity", "AI & Automation": "AI & Automation", Development: "Development" }
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
            categories: { Infrastructure: "Altyapı", Media: "Medya", Utilities: "Araçlar", Productivity: "Üretkenlik", "AI & Automation": "Yapay Zeka ve Otomasyon", Development: "Geliştirme" }
        }
    },
    networks: [
        { id: "wan", name: "Internet", type: "external" },
        { id: "cloudflare", name: { en: "Cloudflare Edge", tr: "Cloudflare Edge" }, type: "edge", services: ["Zero Trust", "WAF", "DDoS Protection"] },
        { id: "lan", name: { en: "Home LAN", tr: "Ev Ağı (LAN)" }, type: "internal", subnet: "192.168.1.0/24" },
        { id: "proxy-net", name: "homelab-proxy", type: "docker", subnet: "172.18.0.0/16" }
    ],
    timeline: [
        { date: "2026-06-11", title: { en: "Helper Scripts & CI/CD Refactor", tr: "Yardımcı Scriptler ve CI/CD Yenilemesi" }, desc: { en: "Improved fail2ban logging and created automated GitHub Actions Pages deployment.", tr: "Fail2ban loglama iyileştirildi ve otomatik GitHub Actions Pages dağıtımı kuruldu." } },
        { date: "2026-06-11", title: { en: "Infrastructure Consolidation", tr: "Altyapı Konsolidasyonu" }, desc: { en: "Reorganized stacks, merged backup services into utility (LXC 102), and updated all docker configuration structures.", tr: "Yığınlar yeniden düzenlendi, yedekleme hizmetleri utility (LXC 102) ile birleştirildi ve tüm docker yapılandırma mimarisi güncellendi." } },
        { date: "2025-12-24", title: { en: "VPN Architecture Upgrade", tr: "VPN Mimari Güncellemesi" }, desc: { en: "Deployed Tailscale as primary VPN; repurposed Cloudflare for Web Tunnel only.", tr: "Tailscale ana VPN olarak yapılandırıldı; Cloudflare sadece Web Tunnel için ayrıldı." } }
    ],
    stacks: [
        {
            id: 100,
            name: { en: "Proxy & Ingress (Gateway)", tr: "Proxy ve Giriş (Gateway)" },
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
            name: { en: "Media Automation (Media)", tr: "Medya Otomasyonu (Media)" },
            ip: "192.168.1.101",
            category: "Media",
            specs: { cpu: 6, ram: "10GB", gpu: "NVIDIA GTX 970" },
            services: [
                { name: "Jellyfin", icon: "fa-solid fa-film", port: "8096", url: "https://media.byetgin.com", desc: { en: "Media Server (Hardware Transcoding)", tr: "Medya Sunucusu (Donanım Transcoding)" }, status: "active", gpu: true },
                { name: "Immich", icon: "fa-solid fa-images", port: "2283", url: "https://photos.byetgin.com", desc: { en: "Self-hosted Photos alternative", tr: "Self-hosted Fotoğraf alternatifi" }, status: "active", gpu: true },
                { name: "Sonarr", icon: "fa-solid fa-tv", port: "8989", desc: { en: "TV Show Automation", tr: "Dizi Otomasyonu" }, status: "active" },
                { name: "Radarr", icon: "fa-solid fa-film", port: "7878", desc: { en: "Movie Automation", tr: "Film Otomasyonu" }, status: "active" },
                { name: "Bazarr", icon: "fa-solid fa-closed-captioning", port: "6767", desc: { en: "Subtitle Management", tr: "Altyazı Yönetimi" }, status: "active" },
                { name: "Jellyseerr", icon: "fa-solid fa-magnifying-glass", port: "5055", desc: { en: "Request Management", tr: "Talep Yönetimi" }, status: "active" },
                { name: "Prowlarr", icon: "fa-solid fa-search", port: "9696", desc: { en: "Indexer Manager", tr: "İndeksleyici Yöneticisi" }, status: "active" },
                { name: "qBittorrent", icon: "fa-solid fa-download", port: "8080", desc: { en: "Torrent Client", tr: "Torrent İstemcisi" }, status: "active" },
                { name: "FlareSolverr", icon: "fa-solid fa-wand-magic-sparkles", port: "8191", desc: { en: "Bypass Cloudflare protection", tr: "Cloudflare korumasını atlatıcı" }, status: "active" },
                { name: "Tor Proxy", icon: "fa-solid fa-mask", port: "9050", desc: { en: "Tor SOCKS Proxy for anonymized access", tr: "Anonim erişim için Tor SOCKS Proxy" }, status: "active" },
                { name: "Recyclarr", icon: "fa-solid fa-arrows-spin", port: "Auto", desc: { en: "Sync TRaSH guides profiles", tr: "TRaSH rehberleri profil senkronizesi" }, status: "active" },
                { name: "Cleanuperr", icon: "fa-solid fa-trash-can", port: "11011", desc: { en: "Disk space cleanup utility", tr: "Disk alanı temizlik aracı" }, status: "active" },
                { name: "Tdarr", icon: "fa-solid fa-compact-disc", port: "8265", desc: { en: "Distributed Transcoding", tr: "Dağıtık Transcoding Platformu" }, status: "active", gpu: true }
            ]
        },
        {
            id: 102,
            name: { en: "Utility & Backup (Utility)", tr: "Araçlar ve Yedekleme (Utility)" },
            ip: "192.168.1.102",
            category: "Utilities",
            specs: { cpu: 4, ram: "4GB" },
            services: [
                { name: "JDownloader 2", icon: "fa-solid fa-download", port: "3129", desc: { en: "Download Manager", tr: "İndirme Yöneticisi" }, status: "active" },
                { name: "Samba Share", icon: "fa-solid fa-share-nodes", port: "445", desc: { en: "Local File Sharing Service", tr: "Yerel Dosya Paylaşım Servisi" }, status: "active" },
                { name: "Repackarr", icon: "fa-solid fa-box", port: "Auto", desc: { en: "Release Repackaging Automator", tr: "Sürüm Paketleme Otomasyonu" }, status: "active" },
                { name: "Backrest", icon: "fa-solid fa-box-archive", port: "9898", desc: { en: "Local Backup Orchestrator", tr: "Yerel Yedekleme Orkestratörü" }, status: "active" },
                { name: "MeTube", icon: "fa-brands fa-youtube", port: "8081", desc: { en: "YouTube Downloader", tr: "YouTube İndirici" }, status: "active" },
                { name: "Changedetection.io", icon: "fa-solid fa-eye", port: "5000", desc: { en: "Website Change Monitor", tr: "Web Sitesi Değişim İzleyici" }, status: "active" },
                { name: "Karakeep", icon: "fa-solid fa-bookmark", port: "3000", desc: { en: "Bookmark & Hoarder App", tr: "Yer İmleri ve Toplama Uygulaması" }, status: "active" }
            ]
        },
        {
            id: 103,
            name: { en: "Desktop Workspace (Desktop)", tr: "Masaüstü Çalışma Alanı (Desktop)" },
            ip: "192.168.1.103",
            category: "Productivity",
            specs: { cpu: 4, ram: "6GB", gpu: "Shared" },
            services: [
                { name: "Homepage", icon: "fa-solid fa-table-columns", port: "3000", url: "https://home.byetgin.com", desc: { en: "Main Dashboard", tr: "Ana Panel" }, status: "active" },
                { name: "Desktop Workspace", icon: "fa-solid fa-desktop", port: "5800", desc: { en: "Web-based Linux Desktop (GPU Accel)", tr: "Web tabanlı Linux Masaüstü (GPU Hızlandırmalı)" }, status: "active", gpu: true },
                { name: "Apache Guacamole", icon: "fa-solid fa-network-wired", port: "8080", desc: { en: "Clientless Remote Desktop Gateway", tr: "Kurulumsuz Uzak Masaüstü Geçidi" }, status: "active" },
                { name: "Sshwifty", icon: "fa-solid fa-terminal", port: "8182", desc: { en: "Web-based SSH/Telnet Connector", tr: "Web tabanlı SSH/Telnet Konnektörü" }, status: "active" },
                { name: "Vaultwarden", icon: "fa-solid fa-lock", port: "8201", desc: { en: "Password Manager", tr: "Şifre Yöneticisi" }, status: "active" },
                { name: "CouchDB", icon: "fa-solid fa-database", port: "5984", desc: { en: "Obsidian Sync Database", tr: "Obsidian Senkronizasyon Veritabanı" }, status: "active" },
                { name: "Desktop OTP Gate", icon: "fa-solid fa-key", port: "Auto", desc: { en: "TOTP Authentication Gateway", tr: "TOTP Kimlik Doğrulama Geçidi" }, status: "active" },
                { name: "Radicale CalDAV", icon: "fa-solid fa-calendar-check", port: "5232", desc: { en: "CalDAV/CardDAV Calendar Sync", tr: "CalDAV/CardDAV Takvim Senkronizasyonu" }, status: "active" }
            ]
        },

        {
            id: 105,
            name: { en: "AI & Automation", tr: "Yapay Zeka ve Otomasyon" },
            ip: "192.168.1.105",
            category: "AI & Automation",
            specs: { cpu: 4, ram: "4GB" },
            services: [
                { name: "Hermes Agent", icon: "fa-solid fa-robot", port: "8088", desc: { en: "AI Agent Gateway", tr: "Yapay Zeka Ajanı Geçidi" }, status: "active" },
                { name: "OmniRoute", icon: "fa-solid fa-route", port: "5001", desc: { en: "API Routing & Mesh", tr: "API Yönlendirme ve Mesh" }, status: "active" },
                { name: "Agentmemory", icon: "fa-solid fa-brain", port: "3030", desc: { en: "Long-term Memory for Agents", tr: "Ajanlar için Uzun Süreli Hafıza" }, status: "active" }
            ]
        },
        {
            id: 106,
            name: { en: "Development (Dev)", tr: "Geliştirme Ortamı (Dev)" },
            ip: "192.168.1.106",
            category: "Development",
            specs: { cpu: 4, ram: "6GB" },
            services: [
                { name: "Code-Server", icon: "fa-solid fa-code", port: "8680", desc: { en: "Web-based VS Code IDE", tr: "Web tabanlı VS Code Geliştirme Ortamı" }, status: "active" },
                { name: "Node.js", icon: "fa-brands fa-node-js", port: "Local", desc: { en: "JavaScript Runtime Environment", tr: "JavaScript Çalışma Ortamı" }, status: "active" },
                { name: "Python", icon: "fa-brands fa-python", port: "Local", desc: { en: "Python Runtime & Pip", tr: "Python Çalışma Ortamı ve Pip" }, status: "active" },
                { name: "OpenCode", icon: "fa-solid fa-terminal", port: "Local", desc: { en: "AI Coding Agent CLI", tr: "Yapay Zeka Kodlama Ajanı CLI" }, status: "active" },
                { name: "Antigravity CLI", icon: "fa-solid fa-rocket", port: "Local", desc: { en: "AI Coding Assistant Tool", tr: "Yapay Zeka Kodlama Yardımcısı" }, status: "active" }
            ]
        }
    ]
};
