#!/bin/bash

# Proxmox Homelab Automation Setup Script

set -e
trap 'echo "Error on line $LINENO" ; exit 1' ERR

DEFAULT_PROXMOX_IP="192.168.1.10"
DEFAULT_PROXMOX_USER="root@pam"
DEFAULT_PROXMOX_NODE="pve01"
DEFAULT_STORAGE_POOL="datapool"
DEFAULT_TIMEZONE="Europe/Istanbul"
DEFAULT_GRAFANA_PASSWORD=$(openssl rand -base64 12)
DEFAULT_PRIVATE_NETWORK="192.168.1"

DEFAULT_CONTAINERS=(
    "media:102:4:16384:32"
    "monitoring:103:2:4096:16"
    "logging:104:2:4096:16"
    "proxy:125:2:2048:8"
)

PROXMOX_PASSWORD=""
ALPINE_TEMPLATE=""

run_proxmox_command() {
    local command="$1"
    ssh -o StrictHostKeyChecking=no ${proxmox_user%@*}@${proxmox_ip} "$command"
}

copy_to_proxmox() {
    local src="$1"
    local dest="$2"
    scp -o StrictHostKeyChecking=no "$src" ${proxmox_user%@*}@${proxmox_ip}:"$dest"
}

setup_container() {
    local name="$1"
    local ctid="$2"
    local cores="$3"
    local memory="$4"
    local storage="$5"
    local ip="${private_network}.${ctid}"

    if run_proxmox_command "pct list | grep -q ' $ctid '"; then
        echo "Container $ctid already exists. Skipping creation."
    else
        run_proxmox_command "pct create $ctid $STORAGE_POOL:vztmpl/$ALPINE_TEMPLATE \
            --hostname $name \
            --cores $cores \
            --memory $memory \
            --swap 512 \
            --rootfs $STORAGE_POOL:$storage \
            --net0 name=eth0,bridge=vmbr0,ip=$ip/24,gw=${private_network}.1 \
            --unprivileged 1 \
            --features nesting=1 \
            --start 1"
        sleep 10
    fi

    if [ "$datapool_exists" == "true" ]; then
        if ! run_proxmox_command "pct config $ctid | grep -q 'mp0: datapool'"; then
            run_proxmox_command "pct set $ctid -mp0 /datapool,mp=/datapool"
        fi
    fi

    run_proxmox_command "pct exec $ctid -- ash -c \"apk update && 
        apk add --no-cache docker docker-compose curl bash openssh && 
        rc-update add docker default && 
        rc-service docker start\""
    run_proxmox_command "pct exec $ctid -- ash -c \"passwd -d root\""
    prepare_container_for_service "$name" "$ctid" "$ip"
    echo "$name:$ctid:$ip"
}

prepare_container_for_service() {
    local service="$1"
    local ctid="$2"
    local ip="$3"

    run_proxmox_command "pct exec $ctid -- mkdir -p /root/docker"

    case "$service" in
        media)
            run_proxmox_command "pct exec $ctid -- mkdir -p /datapool/config/{sonarr-config,radarr-config,bazarr-config,jellyfin-config,jellyseerr-config,qbittorrent-config,prowlarr-config,flaresolverr-config,watchtower-media-config,recyclarr-config,youtube-dl-config}"
            run_proxmox_command "pct exec $ctid -- mkdir -p /datapool/media/{tv,movies,youtube/{playlists,channels}}"
            run_proxmox_command "pct exec $ctid -- mkdir -p /datapool/torrents/{tv,movies}"
            ;;
        monitoring)
            run_proxmox_command "pct exec $ctid -- mkdir -p /datapool/config/{prometheus-config,grafana-config,alertmanager-config,watchtower-monitoring-config}"
            cat > /tmp/monitoring.env << EOF
GRAFANA_PASSWORD=$grafana_password
EOF
            run_proxmox_command "pct push $ctid /tmp/monitoring.env /root/docker/.env"
            ;;
        logging)
            run_proxmox_command "pct exec $ctid -- mkdir -p /datapool/config/{elasticsearch-config,logstash-config,kibana-config,filebeat-config,watchtower-logging-config}"
            ;;
        proxy)
            run_proxmox_command "pct exec $ctid -- mkdir -p /datapool/config/{cloudflared-config,watchtower-proxy-config,adguard-config/{work,conf}}"
            cat > /tmp/proxy.env << EOF
CLOUDFLARED_TOKEN=$cloudflared_token
EOF
            run_proxmox_command "pct push $ctid /tmp/proxy.env /root/docker/.env"
            ;;
    esac

    local compose_url="https://raw.githubusercontent.com/Yakrel/proxmox-homelab-automation/main/docker/$service/docker-compose.yml"
    local compose_file="/tmp/docker-compose.yml"
    wget --retry-connrefused --waitretry=5 --quiet -O "$compose_file" "$compose_url"
    run_proxmox_command "pct push $ctid $compose_file /root/docker/docker-compose.yml"
    run_proxmox_command "pct exec $ctid -- sed -i 's|Europe/Istanbul|$timezone|g' /root/docker/docker-compose.yml"
    run_proxmox_command "pct exec $ctid -- bash -c 'cd /root/docker && docker-compose up -d'"
}

echo "===== Proxmox Homelab Automation Setup ====="

echo "[1/8] Checking prerequisites"

if ! command -v curl &> /dev/null; then
    apt-get update && apt-get install -y curl
fi

if ! command -v sshpass &> /dev/null; then
    apt-get update && apt-get install -y sshpass
fi

if ! command -v expect &> /dev/null; then
    apt-get update && apt-get install -y expect
fi

echo "[2/8] Setting up SSH keys"

if [ ! -f ~/.ssh/id_rsa ]; then
    ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N ""
fi

echo "[3/8] Proxmox connection information"
read -p "Enter Proxmox server IP [$DEFAULT_PROXMOX_IP]: " proxmox_ip
proxmox_ip=${proxmox_ip:-$DEFAULT_PROXMOX_IP}

read -p "Enter Proxmox username [$DEFAULT_PROXMOX_USER]: " proxmox_user
proxmox_user=${proxmox_user:-$DEFAULT_PROXMOX_USER}

read -p "Enter Proxmox node name [$DEFAULT_PROXMOX_NODE]: " proxmox_node
proxmox_node=${proxmox_node:-$DEFAULT_PROXMOX_NODE}

read -s PROXMOX_PASSWORD
echo ""

read -p "Enter your timezone [$DEFAULT_TIMEZONE]: " timezone
timezone=${timezone:-$DEFAULT_TIMEZONE}

read -p "Enter your private network prefix [$DEFAULT_PRIVATE_NETWORK]: " private_network
private_network=${private_network:-$DEFAULT_PRIVATE_NETWORK}

echo "[4/8] Setting up SSH key authentication to Proxmox"
read -p "Would you like to set up SSH key authentication to Proxmox? (y/n): " setup_ssh

if [ "$setup_ssh" == "y" ]; then
    if command -v expect &> /dev/null; then
        cat > /tmp/ssh_copy_id.exp << EOF
#!/usr/bin/expect -f
spawn ssh-copy-id -o StrictHostKeyChecking=no ${proxmox_user%@*}@${proxmox_ip}
expect "password:"
send "${PROXMOX_PASSWORD}\r"
expect eof
EOF
        chmod +x /tmp/ssh_copy_id.exp
        /tmp/ssh_copy_id.exp
        rm -f /tmp/ssh_copy_id.exp
    else
        ssh-copy-id -o StrictHostKeyChecking=no ${proxmox_user%@*}@${proxmox_ip}
    fi
fi

echo "[5/8] Running Proxmox configuration scripts"
read -p "Do you want to run storage.sh and security.sh scripts on your Proxmox server? (y/n): " run_scripts

if [ "$run_scripts" == "y" ]; then
    copy_to_proxmox "scripts/storage.sh" "/tmp/storage.sh"
    copy_to_proxmox "scripts/security.sh" "/tmp/security.sh"
    if [ "$setup_ssh" != "y" ] && command -v expect &> /dev/null; then
        cat > /tmp/run_storage.exp << EOF
#!/usr/bin/expect -f
spawn ssh -o StrictHostKeyChecking=no ${proxmox_user%@*}@${proxmox_ip} "bash /tmp/storage.sh"
expect "password:"
send "${PROXMOX_PASSWORD}\r"
expect "New SMB password:"
send "${PROXMOX_PASSWORD}\r"
expect "Retype new SMB password:"
send "${PROXMOX_PASSWORD}\r"
expect eof
EOF
        chmod +x /tmp/run_storage.exp
        /tmp/run_storage.exp
        rm -f /tmp/run_storage.exp

        cat > /tmp/run_security.exp << EOF
#!/usr/bin/expect -f
spawn ssh -o StrictHostKeyChecking=no ${proxmox_user%@*}@${proxmox_ip} "bash /tmp/security.sh"
expect "password:"
send "${PROXMOX_PASSWORD}\r"
expect eof
EOF
        chmod +x /tmp/run_security.exp
        /tmp/run_security.exp
        rm -f /tmp/run_security.exp
    else
        run_proxmox_command "bash /tmp/storage.sh"
        run_proxmox_command "bash /tmp/security.sh"
    fi
fi

echo "[6/8] Selecting storage pool and template"

STORAGE_INFO=$(run_proxmox_command "pvesm status")

STORAGE_OPTIONS=()
while IFS= read -r line; do
    [ -z "$line" ] && continue
    storage_name=$(echo "$line" | awk '{print $1}')
    [[ "$storage_name" == "Name" ]] && continue
    STORAGE_OPTIONS+=("$storage_name")
done <<< "$STORAGE_INFO"

if [ ${#STORAGE_OPTIONS[@]} -eq 0 ]; then
    exit 1
fi

select STORAGE_POOL in "${STORAGE_OPTIONS[@]}"; do
    if [ -n "$STORAGE_POOL" ]; then
        break
    fi
done

datapool_exists=$(run_proxmox_command "[ -d /datapool ] && echo 'true' || echo 'false'")

if [ "$datapool_exists" != "true" ]; then
    read -p "Would you like to continue without datapool? (y/n): " continue_without_datapool
    if [ "$continue_without_datapool" != "y" ]; then
        exit 1
    fi
fi

run_proxmox_command "pveam update"

ALPINE_TEMPLATES=$(run_proxmox_command "pveam available | grep alpine | grep -v edge | sort -V")

if [ -z "$ALPINE_TEMPLATES" ]; then
    exit 1
fi

ALPINE_TEMPLATE=$(echo "$ALPINE_TEMPLATES" | grep -i default | grep -v edge | grep -v rc | tail -n 1 | awk '{print $2}')

if [ -z "$ALPINE_TEMPLATE" ]; then
    ALPINE_TEMPLATE=$(echo "$ALPINE_TEMPLATES" | tail -n 1 | awk '{print $2}')
fi

read -p "Do you want to use this template or select a different one? (use/select): " template_choice

if [ "$template_choice" == "select" ]; then
    read -p "Template name: " user_template
    if [ -n "$user_template" ]; then
        ALPINE_TEMPLATE=$user_template
    fi
fi

TEMPLATE_DOWNLOADED=$(run_proxmox_command "pveam list $STORAGE_POOL | grep $ALPINE_TEMPLATE" || echo "")

if [ -z "$TEMPLATE_DOWNLOADED" ]; then
    run_proxmox_command "pveam download $STORAGE_POOL $ALPINE_TEMPLATE"
    TEMPLATE_VERIFY=$(run_proxmox_command "pveam list $STORAGE_POOL | grep $ALPINE_TEMPLATE" || echo "")
    if [ -z "$TEMPLATE_VERIFY" ]; then
        exit 1
    fi
fi

echo "[7/8] Setting up environment variables"

read -p "Enter Grafana password [$DEFAULT_GRAFANA_PASSWORD]: " grafana_password
grafana_password=${grafana_password:-$DEFAULT_GRAFANA_PASSWORD}

read -p "Enter Cloudflare Tunnel Token (can be blank): " cloudflared_token
cloudflared_token=${cloudflared_token:-"your_token_here"}

echo "[8/8] Setting up containers"

options=("All" "Media" "Monitoring" "Logging" "Proxy" "Exit")

select opt in "${options[@]}"; do
    case $opt in
        "All")
            services_to_install=("media" "monitoring" "logging" "proxy")
            break
            ;;
        "Media")
            services_to_install=("media")
            break
            ;;
        "Monitoring")
            services_to_install=("monitoring")
            break
            ;;
        "Logging")
            services_to_install=("logging")
            break
            ;;
        "Proxy")
            services_to_install=("proxy")
            break
            ;;
        "Exit")
            exit 0
            ;;
    esac
done

installed_containers=()

for service in "${services_to_install[@]}"; do
    default_ctid=""
    default_cores=""
    default_memory=""
    default_storage=""

    for container in "${DEFAULT_CONTAINERS[@]}"; do
        name=$(echo $container | cut -d: -f1)
        if [ "$name" == "$service" ]; then
            default_ctid=$(echo $container | cut -d: -f2)
            default_cores=$(echo $container | cut -d: -f3)
            default_memory=$(echo $container | cut -d: -f4)
            default_storage=$(echo $container | cut -d: -f5)
            break
        fi
    done

    read -p "Enter container ID (CTID) for $service [$default_ctid]: " ctid
    ctid=${ctid:-$default_ctid}

    read -p "Enter CPU cores for $service [$default_cores]: " cores
    cores=${cores:-$default_cores}

    read -p "Enter memory in MB for $service [$default_memory]: " memory
    memory=${memory:-$default_memory}

    read -p "Enter storage in GB for $service [$default_storage]: " storage
    storage=${storage:-$default_storage}

    container_info=$(setup_container "$service" "$ctid" "$cores" "$memory" "$storage")
    installed_containers+=("$container_info")
done

if [ ${#installed_containers[@]} -gt 0 ]; then
    for container_info in "${installed_containers[@]}"; do
        name=$(echo $container_info | cut -d: -f1)
        ctid=$(echo $container_info | cut -d: -f2)
        ip=$(echo $container_info | cut -d: -f3)
        run_proxmox_command "pct exec $ctid -- docker ps"
    done

    echo "===== Homelab setup completed successfully! ====="
    echo "You can access your services at the following addresses:"

    echo ""
    echo "┌────────────────────────────────────────────────────────────────┐"
    echo "│                       SERVICE SUMMARY                           │"
    echo "├────────────┬─────────┬────────────────┬────────────────────────┤"
    echo "│ Service    │ CTID    │ IP Address     │ Available Ports        │"
    echo "├────────────┼─────────┼────────────────┼────────────────────────┤"

    for container_info in "${installed_containers[@]}"; do
        name=$(echo $container_info | cut -d: -f1)
        ctid=$(echo $container_info | cut -d: -f2)
        ip=$(echo $container_info | cut -d: -f3)

        case $name in
            "media")
                ports="8989,7878,6767,8096,5055,8080..."
                printf "│ %-10s │ %-7s │ %-14s │ %-22s │\n" "Media" "$ctid" "$ip" "$ports"
                ;;
            "monitoring")
                ports="9090,3000,9093,9100"
                printf "│ %-10s │ %-7s │ %-14s │ %-22s │\n" "Monitoring" "$ctid" "$ip" "$ports"
                ;;
            "logging")
                ports="9200,5601,5044"
                printf "│ %-10s │ %-7s │ %-14s │ %-22s │\n" "Logging" "$ctid" "$ip" "$ports"
                ;;
            "proxy")
                ports="3000,80,53"
                printf "│ %-10s │ %-7s │ %-14s │ %-22s │\n" "Proxy" "$ctid" "$ip" "$ports"
                ;;
        esac
    done

    echo "└────────────┴─────────┴────────────────┴────────────────────────┘"
    echo ""

    echo "Detailed service URLs:"
    for container_info in "${installed_containers[@]}"; do
        name=$(echo $container_info | cut -d: -f1)
        ip=$(echo $container_info | cut -d: -f3)

        case $name in
            "media")
                echo "- Media Stack (${ip}):"
                echo "  ├─ Sonarr: http://${ip}:8989"
                echo "  ├─ Radarr: http://${ip}:7878"
                echo "  ├─ Bazarr: http://${ip}:6767"
                echo "  ├─ Jellyfin: http://${ip}:8096"
                echo "  ├─ Jellyseerr: http://${ip}:5055"
                echo "  ├─ qBittorrent: http://${ip}:8080"
                echo "  ├─ Prowlarr: http://${ip}:9696"
                echo "  ├─ FlareSolverr: http://${ip}:8191"
                echo "  └─ Youtube-DL: http://${ip}:8998"
                ;;
            "monitoring")
                echo "- Monitoring Stack (${ip}):"
                echo "  ├─ Prometheus: http://${ip}:9090"
                echo "  ├─ Grafana: http://${ip}:3000"
                echo "  ├─ Alertmanager: http://${ip}:9093"
                echo "  └─ Node Exporter: http://${ip}:9100"
                ;;
            "logging")
                echo "- Logging Stack (${ip}):"
                echo "  ├─ Elasticsearch: http://${ip}:9200"
                echo "  └─ Kibana: http://${ip}:5601"
                ;;
            "proxy")
                echo "- Proxy Stack (${ip}):"
                echo "  └─ AdGuard Home: http://${ip}:3000"
                ;;
        esac
    done

    SUMMARY_FILE="homelab_summary.txt"
    {
        echo "Proxmox Homelab - Installation Summary"
        echo "====================================="
        echo "Date: $(date)"
        echo "Proxmox Server: ${proxmox_ip} (${proxmox_node})"
        echo ""
        echo "Installed Services:"

        for container_info in "${installed_containers[@]}"; do
            name=$(echo $container_info | cut -d: -f1)
            ctid=$(echo $container_info | cut -d: -f2)
            ip=$(echo $container_info | cut -d: -f3)
            echo "- ${name} (CTID: ${ctid}, IP: ${ip})"
        done

        echo ""
        echo "Access Information:"

        for container_info in "${installed_containers[@]}"; do
            name=$(echo $container_info | cut -d: -f1)
            ip=$(echo $container_info | cut -d: -f3)

            case $name in
                "media")
                    echo "- Media Stack (${ip}):"
                    echo "  * Sonarr: http://${ip}:8989"
                    echo "  * Radarr: http://${ip}:7878"
                    echo "  * Bazarr: http://${ip}:6767"
                    echo "  * Jellyfin: http://${ip}:8096"
                    echo "  * Jellyseerr: http://${ip}:5055"
                    echo "  * qBittorrent: http://${ip}:8080"
                    echo "  * Prowlarr: http://${ip}:9696"
                    echo "  * FlareSolverr: http://${ip}:8191"
                    echo "  * Youtube-DL: http://${ip}:8998"
                    ;;
                "monitoring")
                    echo "- Monitoring Stack (${ip}):"
                    echo "  * Prometheus: http://${ip}:9090"
                    echo "  * Grafana: http://${ip}:3000 (admin / ${grafana_password})"
                    echo "  * Alertmanager: http://${ip}:9093"
                    echo "  * Node Exporter: http://${ip}:9100"
                    ;;
                "logging")
                    echo "- Logging Stack (${ip}):"
                    echo "  * Elasticsearch: http://${ip}:9200"
                    echo "  * Kibana: http://${ip}:5601"
                    ;;
                "proxy")
                    echo "- Proxy Stack (${ip}):"
                    echo "  * AdGuard Home: http://${ip}:3000"
                    if [ "$cloudflared_token" != "your_token_here" ]; then
                        echo "  * Cloudflared Tunnel: Configured with your token"
                    else
                        echo "  * Cloudflared Tunnel: Not configured (token missing)"
                    fi
                    ;;
            esac
        done

        echo ""
        echo "Notes:"
        echo "- All containers are using Alpine Linux"
        echo "- All data is stored in /datapool for persistence"
        echo "- Container console access is passwordless (root)"
        echo ""
        echo "Maintenance Commands:"
        echo "- Docker Compose commands: pct exec CTID -- cd /root/docker && docker-compose <command>"
        echo "- Container shell access: pct enter CTID"
        echo "- Container restart: pct restart CTID"
        echo ""
    } > "$SUMMARY_FILE"

    echo "A detailed summary has been saved to: $SUMMARY_FILE"
    echo ""
    echo "Enjoy your homelab!"
else
    echo "No containers were installed."
fi

rm -f /tmp/monitoring.env /tmp/proxy.env /tmp/docker-compose.yml
rm -- "$0"

exit 0
