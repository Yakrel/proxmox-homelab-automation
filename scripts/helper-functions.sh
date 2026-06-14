#!/bin/bash

# =================================================================
#             Shared Helper Functions for Homelab Automation
# =================================================================
# This file contains all common utility functions to follow DRY principle.
# All scripts should source this file instead of duplicating functions.
#
# Usage: source "$WORK_DIR/scripts/helper-functions.sh"
#

# Strict error handling
set -euo pipefail

# === LOGGING FUNCTIONS ===
# Colored output functions used throughout all scripts

print_info() { 
    echo -e "\033[36m▸\033[0m $1" 
}

print_success() { 
    echo -e "\033[32m✓\033[0m $1" 
}

print_error() { 
    echo -e "\033[31m[ERROR]\033[0m $1" >&2
}

print_warning() { 
    echo -e "\033[33m[WARNING]\033[0m $1" 
}

# === USER INTERACTION FUNCTIONS ===
# Common user input and interaction patterns

press_enter_to_continue() {
    echo
    read -r -p "Press Enter to continue..."
}

prompt_env_passphrase() {
    local pass=""

    echo -n "Enter encryption passphrase: " >&2
    read -r -s pass
    echo >&2

    # Return the clean passphrase
    printf '%s' "$pass"
}

# === SYSTEM UTILITIES ===
# Common system-level utility functions

require_root() {
    if [[ "$(id -u)" -ne 0 ]]; then
        print_error "This script must be run as root!"
        exit 1
    fi
}

ensure_packages() {
    local missing_pkgs=()
    for pkg in "$@"; do
        if ! dpkg -s "$pkg" >/dev/null 2>&1; then
            missing_pkgs+=("$pkg")
        fi
    done

    if [[ ${#missing_pkgs[@]} -gt 0 ]]; then
        print_info "Installing missing host packages: ${missing_pkgs[*]}"
        apt-get update -qq
        apt-get install -y -qq "${missing_pkgs[@]}"
        print_success "Packages installed"
    fi
}

# === HOMELAB INFRASTRUCTURE CONSTANTS ===
# Fixed topology for homelab - no discovery needed

readonly LXC_IP_BASE="192.168.1"
readonly DATAPOOL="/datapool"
readonly NETWORK_BRIDGE="vmbr0"
readonly NETWORK_GATEWAY="192.168.1.1"

# Compute LXC IP from container ID
get_lxc_ip() {
    local ct_id="$1"
    echo "${LXC_IP_BASE}.${ct_id}"
}

# === CONFIGURATION MANAGEMENT ===
# Unified configuration parsing and validation

# Get list of available stacks from stacks.yaml, sorted by CT ID
get_available_stacks() {
    local stacks_file="${1:-$WORK_DIR/stacks.yaml}"

    [[ ! -f "$stacks_file" ]] && { print_error "Stacks file not found: $stacks_file"; exit 1; }

    # Get stacks with their CT IDs, sort by CT ID, then return stack names only
    yq -r '.stacks | to_entries | map(select(.value.ct_id != null)) | sort_by(.value.ct_id) | .[].key' "$stacks_file"
}

# Generate dynamic stack menu options
generate_stack_menu_options() {
    local stacks_file="${1:-$WORK_DIR/stacks.yaml}"
    local -a options=()
    
    [[ ! -f "$stacks_file" ]] && { print_error "Stacks file not found: $stacks_file"; exit 1; }
    
    while IFS= read -r stack; do
        local ct_id
        local hostname
        ct_id=$(yq -r ".stacks.$stack.ct_id" "$stacks_file")
        hostname=$(yq -r ".stacks.$stack.hostname" "$stacks_file")
        
        if [[ "$ct_id" != "null" && -n "$ct_id" ]]; then
            options+=("Deploy [$stack] Stack -> LXC $ct_id ($hostname)")
        fi
    done < <(get_available_stacks "$stacks_file")
    
    printf '%s\n' "${options[@]}"
}

# Get stack name from menu selection index  
get_stack_from_menu_index() {
    local index="$1"
    local stacks_file="${2:-$WORK_DIR/stacks.yaml}"
    local -a stacks=()
    
    while IFS= read -r stack; do
        stacks+=("$stack")
    done < <(get_available_stacks "$stacks_file")
    
    if [[ $index -ge 0 && $index -lt ${#stacks[@]} ]]; then
        echo "${stacks[$index]}"
    else
        return 1
    fi
}

get_stack_config() {
    local stack="$1"
    local stacks_file="${2:-$WORK_DIR/stacks.yaml}"

    # Validate stacks file exists
    [[ ! -f "$stacks_file" ]] && { print_error "Stacks file not found: $stacks_file"; exit 1; }

    # Read all common fields in a single yq call (5x faster)
    read -r CT_ID CT_HOSTNAME CT_CPU_CORES CT_MEMORY_MB CT_DISK_GB STORAGE_POOL TEMPLATE_POOL <<< \
        $(yq -r "[.stacks.$stack.ct_id, .stacks.$stack.hostname, .stacks.$stack.cpu_cores, .stacks.$stack.memory_mb, .stacks.$stack.disk_gb, .storage.pool, .storage.template_pool] | @tsv" "$stacks_file")

    # Validate required fields
    [[ -z "$CT_ID" || "$CT_ID" == "null" ]] && { print_error "Stack '$stack' not found in $stacks_file"; exit 1; }

    # Use fixed homelab infrastructure values
    CT_IP=$(get_lxc_ip "$CT_ID")

    # Export all variables for use in calling scripts
    export CT_ID CT_HOSTNAME CT_CPU_CORES CT_MEMORY_MB CT_DISK_GB
    export NETWORK_GATEWAY NETWORK_BRIDGE STORAGE_POOL TEMPLATE_POOL CT_IP
}

# === CONTAINER MANAGEMENT ===
# Common LXC container operations

check_container_exists() {
    local ct_id="$1"
    pct status "$ct_id" &>/dev/null
}

check_container_running() {
    local ct_id="$1"
    local status
    status=$(pct status "$ct_id" 2>&1 | awk '{print $2}')
    [[ "$status" == "running" ]]
}



# === MENU UTILITIES ===
# Common menu display patterns

show_menu_header() {
    local title="$1"
    echo
    echo "======================================="
    echo "      $title"
    echo "======================================="
    echo
}

show_menu_footer() {
    echo "---------------------------------------"
    echo "   b) Back to Main Menu"
    echo "   q) Quit"
    echo
}

# Interactive menu system with options and handlers
show_interactive_menu() {
    local title="$1"
    local -n options_ref="$2"
    local -n handlers_ref="$3"
    local back_handler="${4:-}"
    local quit_handler="${5:-}"
    
    while true; do
        show_menu_header "$title"
        
        # Show numbered options
        for i in "${!options_ref[@]}"; do
            echo "   $((i+1))) ${options_ref[$i]}"
        done
        
        show_menu_footer
        read -r -p "   Enter your choice: " choice
        
        case $choice in
            [1-9]|[1-9][0-9])
                local index=$((choice - 1))
                if [[ $index -ge 0 && $index -lt ${#options_ref[@]} ]]; then
                    ${handlers_ref[$index]} $index
                else
                    print_error "Invalid choice. Please try again."
                fi
                ;;
            b|B)
                if [[ -n "$back_handler" ]]; then
                    $back_handler
                    return 0
                else
                    return 0
                fi
                ;;
            q|Q)
                if [[ -n "$quit_handler" ]]; then
                    $quit_handler
                else
                    print_info "Exiting..."
                    exit 0
                fi
                ;;
            *)
                print_error "Invalid choice. Please try again."
                ;;
        esac
    done
}

# Fix LXC container permissions globally
fix_all_permissions() {
    print_info "Ensuring shared permissions on /datapool (config, backup, media, torrents)"
    
    # Create base directories if they don't exist
    mkdir -p /datapool/config /datapool/backup /datapool/media /datapool/torrents

    # Performance Optimization: Shallow fix only (Top-level folder permissions)
    # Recursive scanning 60k+ files (especially in config/media) caused massive delays.
    # Containers usually inherit correct permissions or manage their own files.
    local dirs=("/datapool/config" "/datapool/backup" "/datapool/media" "/datapool/torrents")
    
    for dir in "${dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            # Only fix the root folder permissions, skip recursive scan
            chown 101000:101000 "$dir"
        fi
    done
    
    print_success "Permissions updated for /datapool"
}

fix_path_owner() {
    local path="$1"

    [[ -e "$path" ]] || return 0
    
    # Optimize ZFS I/O: Only change if it does not match
    local current_uid current_gid
    current_uid=$(stat -c "%u" "$path" 2>/dev/null || echo "")
    current_gid=$(stat -c "%g" "$path" 2>/dev/null || echo "")
    if [[ "$current_uid" != "101000" ]] || [[ "$current_gid" != "101000" ]]; then
        chown 101000:101000 "$path"
    fi
}

fix_path_owner_recursive() {
    local path="$1"

    [[ -e "$path" ]] || return 0
    
    # Optimize ZFS I/O: Only chown files/dirs that don't match the target UID/GID
    # This prevents rewriting metadata for unchanged files (read-only scan via ZFS ARC)
    find "$path" \
        \( ! -user 101000 -o ! -group 101000 \) \
        -exec chown 101000:101000 {} +
}

# === SHARED PROVISIONING UTILITIES ===

setup_homepage_proxmox_token() {
    local env_file="${1:-$ENV_DECRYPTED_PATH}"

    grep -q "placeholder_will_be_set_on_deploy" "$env_file" || return 0

    print_info "Setting up Homepage API token"

    local pve_user="homepage@pve"
    local token_name="homepage-token"

    if ! pveum user list | grep -qw "$pve_user"; then
        pveum user add "$pve_user" --comment "Homepage dashboard monitoring"
    fi

    pveum acl modify / --user "$pve_user" --role PVEAuditor
    pveum user token remove "$pve_user" "$token_name" 2>/dev/null || true

    local token_output token_secret
    token_output=$(pveum user token add "$pve_user" "$token_name" --privsep 0 --output-format=json)
    token_secret=$(echo "$token_output" | grep -o '"value":"[^"]*"' | cut -d'"' -f4)

    if [[ -z "$token_secret" ]]; then
        print_error "Failed to extract token secret"
        return 1
    fi

    sed -i "s/placeholder_will_be_set_on_deploy/$token_secret/g" "$env_file"
    print_success "API token configured"
}

setup_proxmox_monitoring_user() {
    local env_file="${1:-$ENV_DECRYPTED_PATH}"

    local pve_user pve_password
    pve_user=$(grep '^PVE_USER=' "$env_file" | cut -d'=' -f2- || true)
    pve_password=$(grep '^PVE_MONITORING_PASSWORD=' "$env_file" | cut -d'=' -f2- || true)

    pve_user=${pve_user:-pve-exporter@pve}
    if [[ -z "$pve_password" ]]; then
        pve_password="${PVE_MONITORING_PASSWORD:-}"
    fi

    [[ -n "$pve_password" ]] || {
        print_error "PVE_MONITORING_PASSWORD not found in environment/env file"
        exit 1
    }

    print_info "Setting up PVE monitoring user ($pve_user)"

    if pveum user list | grep -qw "$pve_user"; then
        pveum passwd "$pve_user" --password "$pve_password"
    else
        pveum user add "$pve_user" --password "$pve_password" --comment "Prometheus monitoring user"
    fi

    pveum acl modify / --user "$pve_user" --role PVEAuditor
    print_success "PVE monitoring user configured"
}

setup_promtail_config() {
    local ct_id="$1"
    local hostname="$2"

    print_info "Configuring Promtail for $hostname"

    # Ensure target directories exist inside container
    pct exec "$ct_id" -- mkdir -p /etc/promtail /var/lib/promtail/positions || {
        print_error "Failed to create Promtail directories in container"
        return 1
    }

    # Generate customized config from template
    local temp_promtail="/tmp/promtail_${hostname}.yml"
    sed "s/REPLACE_HOST_LABEL/$hostname/g" "$WORK_DIR/config/promtail/promtail.yml" > "$temp_promtail"

    # Push to container
    pct push "$ct_id" "$temp_promtail" "/etc/promtail/promtail.yml" || {
        print_error "Failed to push Promtail config to container"
        rm -f "$temp_promtail"
        return 1
    }
    rm -f "$temp_promtail"

    print_success "Promtail configured"
}

setup_monitoring_configs() {
    local env_file="${1:-$ENV_DECRYPTED_PATH}"

    print_info "Setting up monitoring configuration files"

    # Create all required directories
    mkdir -p /datapool/config/prometheus/data
    mkdir -p /datapool/config/prometheus/recording-rules
    mkdir -p /datapool/config/grafana/data
    mkdir -p /datapool/config/loki/data
    mkdir -p /datapool/config/grafana/provisioning/datasources
    mkdir -p /datapool/config/grafana/provisioning/dashboards
    mkdir -p /datapool/config/grafana/dashboards
    mkdir -p /datapool/config/prometheus-pve-exporter

    # Fix base directory ownerships
    fix_path_owner /datapool/config/prometheus
    fix_path_owner /datapool/config/prometheus/data
    fix_path_owner /datapool/config/prometheus/recording-rules
    fix_path_owner /datapool/config/grafana
    fix_path_owner /datapool/config/grafana/data
    fix_path_owner /datapool/config/grafana/provisioning
    fix_path_owner /datapool/config/grafana/provisioning/datasources
    fix_path_owner /datapool/config/grafana/provisioning/dashboards
    fix_path_owner /datapool/config/grafana/dashboards
    fix_path_owner /datapool/config/loki
    fix_path_owner /datapool/config/loki/data
    fix_path_owner_recursive /datapool/config/prometheus-pve-exporter

    # Copy config files from workspace
    local prom_source="$WORK_DIR/config/prometheus/prometheus.yml"
    if [[ -f "$prom_source" ]]; then
        cp "$prom_source" "/datapool/config/prometheus/prometheus.yml" || {
            print_error "Failed to copy prometheus.yml"
            exit 1
        }
    else
        print_error "prometheus.yml not found at $prom_source"
        exit 1
    fi

    local loki_source="$WORK_DIR/config/loki/loki.yml"
    if [[ -f "$loki_source" ]]; then
        cp "$loki_source" "/datapool/config/loki/loki.yml" || {
            print_error "Failed to copy loki.yml"
            exit 1
        }
    else
        print_error "loki.yml not found at $loki_source"
        exit 1
    fi

    if [[ -d "$WORK_DIR/config/prometheus/rules" ]]; then
        cp -r "$WORK_DIR/config/prometheus/rules" /datapool/config/prometheus/ || {
            print_error "Failed to copy prometheus rules"
            exit 1
        }
    else
        print_error "Prometheus rules directory not found"
        exit 1
    fi

    if [[ -d "$WORK_DIR/config/prometheus/recording-rules" ]]; then
        cp -r "$WORK_DIR/config/prometheus/recording-rules" /datapool/config/prometheus/ || {
            print_error "Failed to copy prometheus recording rules"
            exit 1
        }
    else
        print_error "Prometheus recording-rules directory not found"
        exit 1
    fi

    if [[ -d "$WORK_DIR/config/grafana/dashboards" ]]; then
        cp "$WORK_DIR/config/grafana/dashboards/"*.json /datapool/config/grafana/dashboards/ || {
            print_error "Failed to copy Grafana dashboards"
            exit 1
        }
    fi

    # Read credentials from env file for PVE exporter config
    local pve_user pve_password pve_verify_ssl
    pve_user=$(grep '^PVE_USER=' "$env_file" | cut -d'=' -f2- || true)
    pve_password=$(grep '^PVE_MONITORING_PASSWORD=' "$env_file" | cut -d'=' -f2- || true)
    pve_verify_ssl=$(grep '^PVE_VERIFY_SSL=' "$env_file" | cut -d'=' -f2- || true)

    # Fallback to exported variables if running in full installer
    pve_user=${pve_user:-${MONITORING_PVE_USER:-pve-exporter@pve}}
    pve_password=${pve_password:-$PVE_MONITORING_PASSWORD}
    pve_verify_ssl=${pve_verify_ssl:-${MONITORING_PVE_VERIFY_SSL:-false}}

    pve_verify_ssl="${pve_verify_ssl,,}"

    [[ -n "$pve_password" ]] || {
        print_error "PVE_MONITORING_PASSWORD not found in environment/env file"
        exit 1
    }

    cat > /datapool/config/prometheus-pve-exporter/pve.yml << EOF
default:
  user: ${pve_user}
  password: ${pve_password}
  verify_ssl: ${pve_verify_ssl}
EOF

    # Fix final config ownerships
    fix_path_owner /datapool/config/prometheus/prometheus.yml
    fix_path_owner_recursive /datapool/config/prometheus/rules
    fix_path_owner_recursive /datapool/config/prometheus/recording-rules
    fix_path_owner /datapool/config/loki/loki.yml
    fix_path_owner_recursive /datapool/config/prometheus-pve-exporter

    print_success "Monitoring configuration files set up and ownership fixed"
}

setup_grafana_provisioning() {
    print_info "Configuring Grafana datasource and dashboard provisioning"

    # Create datasource provisioning file
    local datasource_config="/tmp/datasources.yml"
    cat > "$datasource_config" << 'EOF'
apiVersion: 1

deleteDatasources:
  - name: Prometheus
    orgId: 1
  - name: Loki
    orgId: 1

datasources:
  - name: Prometheus
    type: prometheus
    uid: prometheus
    access: proxy
    orgId: 1
    url: http://prometheus:9090
    isDefault: true
    jsonData:
      httpMethod: POST
      timeInterval: 30s
    editable: false

  - name: Loki
    type: loki
    uid: loki
    access: proxy
    orgId: 1
    url: http://loki:3100
    isDefault: false
    jsonData:
      maxLines: 1000
    editable: false
EOF

    cp "$datasource_config" "/datapool/config/grafana/provisioning/datasources/datasources.yml" || {
        print_error "Failed to configure datasources"
        rm -f "$datasource_config"
        return 1
    }
    rm -f "$datasource_config"

    # Create dashboard provisioning config
    local dashboard_provider_config="/tmp/dashboard_provider.yml"
    cat > "$dashboard_provider_config" << 'EOF'
apiVersion: 1

providers:
  - name: 'default'
    orgId: 1
    folder: ''
    type: file
    disableDeletion: false
    updateIntervalSeconds: 10
    allowUiUpdates: true
    options:
      path: /datapool/config/grafana/dashboards
EOF

    cp "$dashboard_provider_config" "/datapool/config/grafana/provisioning/dashboards/provider.yml" || {
        print_error "Failed to configure dashboard provider"
        rm -f "$dashboard_provider_config"
        return 1
    }
    rm -f "$dashboard_provider_config"

    # Fix ownership of Grafana files
    fix_path_owner /datapool/config/grafana/provisioning/datasources/datasources.yml
    fix_path_owner /datapool/config/grafana/provisioning/dashboards/provider.yml
    fix_path_owner_recursive /datapool/config/grafana/dashboards

    print_success "Grafana provisioning configured"
}
