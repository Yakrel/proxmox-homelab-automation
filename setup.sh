#!/bin/bash

# Proxmox Homelab Automation Setup Script

set -e
trap 'echo "Error on line $LINENO" ; exit 1' ERR

DEFAULT_STORAGE_POOL="local"
DEFAULT_TIMEZONE="Europe/Istanbul"
DEFAULT_GRAFANA_PASSWORD=$(openssl rand -base64 12)
DEFAULT_PRIVATE_NETWORK="192.168.1"

DEFAULT_CONTAINERS=(
    "proxy:101:2:2048:8" 
    "media:102:4:16384:32"
    "monitoring:103:2:4096:16"
    "logging:104:2:4096:16"
)

ALPINE_TEMPLATE=""

setup_container() {
    local name="$1"
    local ctid="$2"
    local cores="$3"
    local memory="$4"
    local storage="$5"
    local ip="${private_network}.${ctid}"

    if pct list | grep -q " $ctid "; then
        echo "Container $ctid already exists. Skipping creation."
    else
        pct create $ctid $STORAGE_POOL:vztmpl/$ALPINE_TEMPLATE \
            --hostname $name \
            --cores $cores \
            --memory $memory \
            --swap 512 \
            --rootfs $STORAGE_POOL:$storage \
            --net0 name=eth0,bridge=vmbr0,ip=$ip/24,gw=${private_network}.1 \
            --unprivileged 1 \
            --features nesting=1 \
            --start 1
        sleep 10
    fi

    if [ "$datapool_exists" == "true" ]; then
        if ! pct config $ctid | grep -q 'mp0: datapool'; then
            pct set $ctid -mp0 /datapool,mp=/datapool
        fi
    fi

    pct exec $ctid -- ash -c "apk update && \
        apk add --no-cache docker docker-compose curl bash openssh && \
        rc-update add docker default && \
        rc-service docker start" || exit 1
    pct exec $ctid -- ash -c "passwd -d root" || exit 1
    prepare_container_for_service "$name" "$ctid" "$ip"
    echo "$name:$ctid:$ip"
}

prepare_container_for_service() {
    local service="$1"
    local ctid="$2"
    local ip="$3"

    pct exec $ctid -- mkdir -p /root/docker

    case "$service" in
        media)
            pct exec $ctid -- mkdir -p /datapool/config/{sonarr-config,radarr-config,bazarr-config,jellyfin-config,jellyseerr-config,qbittorrent-config,prowlarr-config,flaresolverr-config,watchtower-media-config,recyclarr-config,youtube-dl-config}
            pct exec $ctid -- mkdir -p /datapool/media/{tv,movies,youtube/{playlists,channels}}
            pct exec $ctid -- mkdir -p /datapool/torrents/{tv,movies}
            ;;
        monitoring)
            pct exec $ctid -- mkdir -p /datapool/config/{prometheus-config,grafana-config,alertmanager-config,watchtower-monitoring-config}
            create_env_file "$service" "$ctid" "$grafana_password"
            ;;
        logging)
            pct exec $ctid -- mkdir -p /datapool/config/{elasticsearch-config,logstash-config,kibana-config,filebeat-config,watchtower-logging-config}
            ;;
        proxy)
            pct exec $ctid -- mkdir -p /datapool/config/{cloudflared-config,watchtower-proxy-config,adguard-config/{work,conf}}
            create_env_file "$service" "$ctid" "$cloudflared_token"
            ;;
    esac

    local compose_url="https://raw.githubusercontent.com/Yakrel/proxmox-homelab-automation/main/docker/$service/docker-compose.yml"
    local compose_file="/tmp/docker-compose.yml"
    wget --retry-connrefused --waitretry=5 --quiet -O "$compose_file" "$compose_url"
    pct push $ctid $compose_file /root/docker/docker-compose.yml
    pct exec $ctid -- sed -i "s|Europe/Istanbul|$timezone|g" /root/docker/docker-compose.yml
    pct exec $ctid -- bash -c 'cd /root/docker && docker-compose up -d'
}

# Yeni - Konteyner içinde .env dosyası oluşturma fonksiyonu
create_env_file() {
    local service="$1"
    local ctid="$2"
    local value="$3"
    local env_example_url="https://raw.githubusercontent.com/Yakrel/proxmox-homelab-automation/main/docker/$service/.env.example"
    local env_example_file="/tmp/.env.example"
    local env_file="/tmp/.env"
    
    wget --retry-connrefused --waitretry=5 --quiet -O "$env_example_file" "$env_example_url"
    
    if [ "$service" == "monitoring" ]; then
        sed "s/your_grafana_password_here/$value/" "$env_example_file" > "$env_file"
    elif [ "$service" == "proxy" ]; then
        if [ -z "$value" ]; then
            echo "Error: Cloudflare Tunnel Token cannot be empty."
            exit 1
        fi
        sed "s/your_cloudflare_tunnel_token_here/$value/" "$env_example_file" > "$env_file"
    else
        cp "$env_example_file" "$env_file"
    fi

    if [ -f "/root/docker/.env" ]; then
        echo "Warning: .env file already exists. Skipping creation."
    else
        pct push $ctid "$env_file" /root/docker/.env
    fi
    rm -f "$env_example_file" "$env_file"
}

echo "===== Proxmox Homelab Automation Setup ====="

echo "[1/6] Setting up environment"

read -p "Enter your timezone [$DEFAULT_TIMEZONE]: " timezone
timezone=${timezone:-$DEFAULT_TIMEZONE}

read -p "Enter your private network prefix [$DEFAULT_PRIVATE_NETWORK]: " private_network
private_network=${private_network:-$DEFAULT_PRIVATE_NETWORK}

echo "[2/6] Running Proxmox configuration scripts"
read -p "Do you want to run storage.sh and security.sh scripts on this Proxmox server? (y/n): " run_scripts

if [ "$run_scripts" == "y" ]; then
    echo "Running storage.sh script..."
    if [ -f "scripts/storage.sh" ]; then
        bash scripts/storage.sh
    else
        echo "Warning: scripts/storage.sh not found"
    fi
    
    echo "Running security.sh script..."
    if [ -f "scripts/security.sh" ]; then
        bash scripts/security.sh
    else
        echo "Warning: scripts/security.sh not found"
    fi
fi

echo "[3/6] Selecting storage pool and template"

STORAGE_INFO=$(pvesm status)

STORAGE_OPTIONS=()
while IFS= read -r line; do
    [ -z "$line" ] && continue
    storage_name=$(echo "$line" | awk '{print $1}')
    [[ "$storage_name" == "Name" ]] && continue
    STORAGE_OPTIONS+=("$storage_name")
done <<< "$STORAGE_INFO"

if [ ${#STORAGE_OPTIONS[@]} -eq 0 ]; then
    echo "Error: No storage pools found!"
    exit 1
fi

select STORAGE_POOL in "${STORAGE_OPTIONS[@]}"; do
    if [ -n "$STORAGE_POOL" ]; then
        break
    fi
done

datapool_exists=$(test -d /datapool && echo 'true' || echo 'false')

if [ "$datapool_exists" != "true" ]; then
    read -p "Would you like to continue without datapool? (y/n): " continue_without_datapool
    if [ "$continue_without_datapool" != "y" ]; then
        echo "Exiting as datapool is missing."
        exit 1
    fi
fi

pveam update

ALPINE_TEMPLATES=$(pveam available | grep alpine | grep -v edge | sort -V)

if [ -z "$ALPINE_TEMPLATES" ]; then
    echo "Error: No Alpine templates found!"
    exit 1
fi

ALPINE_TEMPLATE=$(echo "$ALPINE_TEMPLATES" | grep -i default | grep -v edge | grep -v rc | tail -n 1 | awk '{print $2}')

if [ -z "$ALPINE_TEMPLATE" ]; then
    ALPINE_TEMPLATE=$(echo "$ALPINE_TEMPLATES" | tail -n 1 | awk '{print $2}')
fi

echo "Selected template: $ALPINE_TEMPLATE"

TEMPLATE_DOWNLOADED=$(pveam list $STORAGE_POOL | grep $ALPINE_TEMPLATE || echo "")

if [ -z "$TEMPLATE_DOWNLOADED" ]; then
    echo "Downloading Alpine template..."
    pveam download $STORAGE_POOL $ALPINE_TEMPLATE
    TEMPLATE_VERIFY=$(pveam list $STORAGE_POOL | grep $ALPINE_TEMPLATE || echo "")
    if [ -z "$TEMPLATE_VERIFY" ]; then
        echo "Error: Failed to download template!"
        exit 1
    fi
fi

echo "[4/6] Setting up environment variables"

read -p "Enter Grafana password [$DEFAULT_GRAFANA_PASSWORD]: " grafana_password
grafana_password=${grafana_password:-$DEFAULT_GRAFANA_PASSWORD}

read -p "Enter Cloudflare Tunnel Token (can be blank): " cloudflared_token
cloudflared_token=${cloudflared_token:-"your_token_here"}

# .env dosyalarını oluştur
echo "Creating .env files..."
if [ -d "docker/monitoring" ]; then
    echo "GRAFANA_PASSWORD=$grafana_password" > docker/monitoring/.env
fi
if [ -d "docker/proxy" ]; then
    echo "CLOUDFLARED_TOKEN=$cloudflared_token" > docker/proxy/.env
fi

echo "[5/6] Setting up containers"

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

    echo "Creating container $service (CTID: $ctid)..."
    container_info=$(setup_container "$service" "$ctid" "$cores" "$memory" "$storage")
    installed_containers+=("$container_info")
done

echo "===== Homelab setup completed successfully! ====="

rm -f /tmp/docker-compose.yml

echo "Script completed!"
exit 0
