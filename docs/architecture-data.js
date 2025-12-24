// Architecture Data - Single Source of Truth for the Dashboard
const ARCHITECTURE_DATA = {
    meta: {
        lastUpdated: "2025-12-15",
        host: "Proxmox VE (192.168.1.10)",
        specs: "Intel Xeon E3-1276 v3 @ 3.60GHz | 32GB DDR3 ECC | ZFS Storage"
    },
    networks: [
        { id: "wan", name: "Internet", type: "external" },
        { id: "cloudflare", name: "Cloudflare Edge", type: "edge", services: ["Zero Trust", "WAF", "DDoS Protection"] },
        { id: "lan", name: "Home LAN", type: "internal", subnet: "192.168.1.0/24" },
        { id: "proxy-net", name: "homelab-proxy", type: "docker", subnet: "172.18.0.0/16" }
    ],
    // High-Level Timeline of changes
    timeline: [
        { date: "2025-12-24", title: "VPN Architecture Upgrade", desc: "Deployed Tailscale as primary VPN; repurposed Cloudflare for Web Tunnel only." },
        { date: "2025-12-15", title: "Game Server Expansion", desc: "Added Palworld & Satisfactory with automated switching." },
        { date: "2025-11-20", title: "GPU Passthrough", desc: "Implemented Unprivileged LXC Nvidia passthrough for Jellyfin." },
        { date: "2025-10-01", title: "Zero Trust Migration", desc: "Moved all ingress to Cloudflare Tunnels, closed port 443." }
    ],
    // The Core Inventory
    stacks: [
        {
            id: 100,
            name: "Proxy & Ingress",
            ip: "192.168.1.100",
            category: "Infrastructure",
            specs: { cpu: 2, ram: "2GB" },
            services: [
                { name: "Nginx Proxy Manager", icon: "fa-solid fa-arrow-right-to-bracket", port: "80/443", url: "https://npm.byetgin.com", desc: "Reverse Proxy & SSL Management", status: "active" },
                { name: "AdGuard Home", icon: "fa-solid fa-shield-dog", port: "53", url: "http://192.168.1.100:3000", desc: "Network-wide Ad Blocking & DNS", status: "active" },
                { name: "Tailscale", icon: "fa-solid fa-network-wired", port: "VPN", desc: "Mesh VPN & Subnet Router", status: "active" },
                { name: "Cloudflared", icon: "fa-brands fa-cloudflare", port: "Tunnel", desc: "Web Services Tunnel (Ingress)", status: "active" }
            ]
        },
        {
            id: 101,
            name: "Media Stack",
            ip: "192.168.1.101",
            category: "Media",
            specs: { cpu: 6, ram: "10GB", gpu: "NVIDIA GTX 970" },
            services: [
                { name: "Jellyfin", icon: "fa-solid fa-film", port: "8096", url: "https://media.byetgin.com", desc: "Media Server (Hardware Transcoding)", status: "active", gpu: true },
                { name: "Immich", icon: "fa-solid fa-images", port: "2283", url: "https://photos.byetgin.com", desc: "Self-hosted Google Photos alternative", status: "active", gpu: true },
                { name: "Sonarr", icon: "fa-solid fa-tv", port: "8989", desc: "TV Show Automation", status: "active" },
                { name: "Radarr", icon: "fa-solid fa-film", port: "7878", desc: "Movie Automation", status: "active" },
                { name: "qBittorrent", icon: "fa-solid fa-download", port: "8080", desc: "Download Client", status: "active" },
                { name: "Jellyseerr", icon: "fa-solid fa-magnifying-glass", port: "5055", desc: "Request Management", status: "active" }
            ]
        },
        {
            id: 102,
            name: "File Manager",
            ip: "192.168.1.102",
            category: "Utilities",
            specs: { cpu: 2, ram: "3GB" },
            services: [
                { name: "JDownloader 2", icon: "fa-solid fa-download", port: "3129", desc: "Download Manager", status: "active" },
                { name: "MeTube", icon: "fa-brands fa-youtube", port: "8081", desc: "YouTube Downloader", status: "active" },
                { name: "Palmr", icon: "fa-solid fa-folder-open", port: "5487", desc: "File Manager", status: "active" }
            ]
        },
        {
            id: 103,
            name: "Web Tools",
            ip: "192.168.1.103",
            category: "Productivity",
            specs: { cpu: 4, ram: "6GB", gpu: "Shared" },
            services: [
                { name: "Homepage", icon: "fa-solid fa-table-columns", port: "3000", url: "https://home.byetgin.com", desc: "Main Dashboard", status: "active" },
                { name: "Desktop Workspace", icon: "fa-solid fa-desktop", port: "5800", desc: "Web-based Linux Desktop (GPU Accel)", status: "active", gpu: true },
                { name: "Vaultwarden", icon: "fa-solid fa-lock", port: "8201", desc: "Password Manager", status: "active" },
                { name: "CouchDB", icon: "fa-solid fa-database", port: "5984", desc: "Obsidian Sync Database", status: "active" }
            ]
        },
        {
            id: 104,
            name: "Monitoring",
            ip: "192.168.1.104",
            category: "Observability",
            specs: { cpu: 4, ram: "6GB" },
            services: [
                { name: "Grafana", icon: "fa-solid fa-chart-line", port: "3000", url: "https://grafana.byetgin.com", desc: "Metrics Visualization", status: "active" },
                { name: "Prometheus", icon: "fa-solid fa-eye", port: "9090", desc: "Time-series Database", status: "active" },
                { name: "Loki", icon: "fa-solid fa-list", port: "3100", desc: "Log Aggregation", status: "active" }
            ]
        },
        {
            id: 105,
            name: "Game Servers",
            ip: "192.168.1.105",
            category: "Gaming",
            specs: { cpu: 8, ram: "16GB" },
            services: [
                { name: "Palworld", icon: "fa-solid fa-gamepad", port: "8211 UDP", desc: "Dedicated Server", status: "standby" },
                { name: "Satisfactory", icon: "fa-solid fa-industry", port: "7777 UDP", desc: "Dedicated Server", status: "active" }
            ]
        },
        {
            id: 106,
            name: "Backup",
            ip: "192.168.1.106",
            category: "Infrastructure",
            specs: { cpu: 4, ram: "8GB" },
            services: [
                { name: "Backrest", icon: "fa-solid fa-box-archive", port: "9898", desc: "Local Backup Orchestrator", status: "active" },
                { name: "Rclone", icon: "fa-brands fa-google-drive", port: "Sync", desc: "Offsite Encrypted Sync", status: "active" }
            ]
        },
        {
            id: 107,
            name: "Development",
            ip: "192.168.1.107",
            category: "Development",
            specs: { cpu: 4, ram: "6GB" },
            services: [
                { name: "Docker Env", icon: "fa-brands fa-docker", port: "N/A", desc: "Test Environment", status: "active" },
                { name: "Scripts", icon: "fa-solid fa-terminal", port: "Auto", desc: "Automation Scripts", status: "active" }
            ]
        }
    ]
};
