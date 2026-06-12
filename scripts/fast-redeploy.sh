#!/bin/bash

# Fast Docker stack redeploy without LXC provisioning or package installation.
# Usage: fast-redeploy.sh [stack-name ...]
set -euo pipefail

WORK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)"

source "$WORK_DIR/scripts/helper-functions.sh"
source "$WORK_DIR/scripts/modules/docker-deployment.sh"
source "$WORK_DIR/scripts/modules/backrest-deployment.sh"

ENV_ENC_KEY=""
ENV_DECRYPTED_PATH=""

decrypt_stack_env() {
    local stack="$1"
    local enc_file="$WORK_DIR/docker/$stack/.env.enc"
    local output_file="/tmp/${stack}.fast-redeploy.env"

    [[ -f "$enc_file" ]] || {
        print_warning "No encrypted env found for $stack, skipping .env refresh"
        return 1
    }

    printf '%s' "$ENV_ENC_KEY" | openssl enc -d -aes-256-cbc -pbkdf2 -salt -pass stdin -in "$enc_file" -out "$output_file" || {
        rm -f "$output_file"
        print_error "Failed to decrypt docker/$stack/.env.enc"
        exit 1
    }

    ENV_DECRYPTED_PATH="$output_file"
    export ENV_DECRYPTED_PATH ENV_ENC_KEY
}

setup_fast_homepage_token() {
    local env_file="$1"

    grep -q "placeholder_will_be_set_on_deploy" "$env_file" || return 0

    print_info "Refreshing Homepage Proxmox API token"

    local pve_user="homepage@pve"
    local token_name="homepage-token"
    local token_output token_secret

    if ! pveum user list | grep -qw "$pve_user"; then
        pveum user add "$pve_user" --comment "Homepage dashboard monitoring"
    fi

    pveum acl modify / --user "$pve_user" --role PVEAuditor
    pveum user token remove "$pve_user" "$token_name" 2>/dev/null || true

    token_output=$(pveum user token add "$pve_user" "$token_name" --privsep 0 --output-format=json)
    token_secret=$(echo "$token_output" | grep -o '"value":"[^"]*"' | cut -d'"' -f4)

    [[ -n "$token_secret" ]] || {
        print_error "Failed to extract Homepage token secret"
        exit 1
    }

    sed -i "s/placeholder_will_be_set_on_deploy/$token_secret/g" "$env_file"
}

setup_fast_monitoring_user() {
    local env_file="$1"

    local pve_user pve_password
    pve_user=$(grep '^PVE_USER=' "$env_file" | cut -d'=' -f2- || true)
    pve_password=$(grep '^PVE_MONITORING_PASSWORD=' "$env_file" | cut -d'=' -f2- || true)

    pve_user=${pve_user:-pve-exporter@pve}

    [[ -n "$pve_password" ]] || {
        print_error "PVE_MONITORING_PASSWORD not found in monitoring env"
        exit 1
    }

    print_info "Refreshing PVE monitoring user"

    if pveum user list | grep -qw "$pve_user"; then
        pveum passwd "$pve_user" --password "$pve_password"
    else
        pveum user add "$pve_user" --password "$pve_password" --comment "Prometheus monitoring user"
    fi

    pveum acl modify / --user "$pve_user" --role PVEAuditor
}

copy_monitoring_configs() {
    local env_file="$1"

    print_info "Refreshing monitoring config files"

    mkdir -p /datapool/config/prometheus/data
    mkdir -p /datapool/config/prometheus/recording-rules
    mkdir -p /datapool/config/grafana/data
    mkdir -p /datapool/config/grafana/provisioning/datasources
    mkdir -p /datapool/config/grafana/provisioning/dashboards
    mkdir -p /datapool/config/grafana/dashboards
    mkdir -p /datapool/config/loki/data
    mkdir -p /datapool/config/prometheus-pve-exporter

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

    cp "$WORK_DIR/docker/monitor/prometheus.yml" /datapool/config/prometheus/prometheus.yml
    cp "$WORK_DIR/config/loki/loki.yml" /datapool/config/loki/loki.yml
    cp -r "$WORK_DIR/config/prometheus/rules" /datapool/config/prometheus/
    cp -r "$WORK_DIR/config/prometheus/recording-rules" /datapool/config/prometheus/
    cp "$WORK_DIR/config/grafana/dashboards/"*.json /datapool/config/grafana/dashboards/

    local pve_user pve_password pve_verify_ssl
    pve_user=$(grep '^PVE_USER=' "$env_file" | cut -d'=' -f2- || true)
    pve_password=$(grep '^PVE_MONITORING_PASSWORD=' "$env_file" | cut -d'=' -f2- || true)
    pve_verify_ssl=$(grep '^PVE_VERIFY_SSL=' "$env_file" | cut -d'=' -f2- || true)
    pve_verify_ssl="${pve_verify_ssl:-false}"
    pve_verify_ssl="${pve_verify_ssl,,}"

    [[ -n "$pve_password" ]] || {
        print_error "PVE_MONITORING_PASSWORD not found in monitoring env"
        exit 1
    }

    case "$pve_verify_ssl" in
        true|false)
            ;;
        *)
            print_error "PVE_VERIFY_SSL must be true or false"
            exit 1
            ;;
    esac

    cat > /datapool/config/prometheus-pve-exporter/pve.yml << EOF
default:
  user: ${pve_user:-pve-exporter@pve}
  password: ${pve_password}
  verify_ssl: ${pve_verify_ssl}
EOF

    cat > /datapool/config/grafana/provisioning/datasources/datasources.yml << 'EOF'
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

    cat > /datapool/config/grafana/provisioning/dashboards/provider.yml << 'EOF'
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

    fix_path_owner /datapool/config/prometheus/prometheus.yml
    fix_path_owner_recursive /datapool/config/prometheus/rules
    fix_path_owner_recursive /datapool/config/prometheus/recording-rules
    fix_path_owner /datapool/config/loki/loki.yml
    fix_path_owner /datapool/config/grafana/provisioning/datasources/datasources.yml
    fix_path_owner /datapool/config/grafana/provisioning/dashboards/provider.yml
    fix_path_owner_recursive /datapool/config/grafana/dashboards
    fix_path_owner_recursive /datapool/config/prometheus-pve-exporter
}

copy_promtail_config() {
    local ct_id="$1"
    local hostname="$2"
    local temp_promtail="/tmp/promtail_${hostname}.fast-redeploy.yml"

    pct exec "$ct_id" -- mkdir -p /etc/promtail /var/lib/promtail/positions
    sed "s/REPLACE_HOST_LABEL/$hostname/g" "$WORK_DIR/config/promtail/promtail.yml" > "$temp_promtail"
    pct push "$ct_id" "$temp_promtail" /etc/promtail/promtail.yml
    rm -f "$temp_promtail"
}

fast_redeploy_stack() {
    local stack="$1"

    [[ "$stack" != "dev" ]] || {
        print_info "Skipping dev stack (no Docker compose)"
        return 0
    }

    local compose_file="$WORK_DIR/docker/$stack/docker-compose.yml"
    [[ -f "$compose_file" ]] || {
        print_info "Skipping $stack (no docker-compose.yml)"
        return 0
    }

    get_stack_config "$stack"

    if ! check_container_running "$CT_ID"; then
        print_warning "Skipping $stack: LXC $CT_ID is not running"
        return 0
    fi

    verify_docker "$CT_ID"

    echo
    print_info "Fast redeploying [$stack] on LXC $CT_ID ($CT_HOSTNAME)"

    decrypt_stack_env "$stack"

    if [[ "$stack" == "desktop" ]]; then
        setup_desktop_permissions
        setup_homepage_config "$CT_ID"
        setup_couchdb_config "$CT_ID"
        setup_fast_homepage_token "$ENV_DECRYPTED_PATH"
        setup_guacamole_config "$CT_ID"
        setup_sshwifty_config "$CT_ID"
    elif [[ "$stack" == "utility" ]]; then
        setup_utility_permissions
        deploy_backrest "$CT_ID"
    elif [[ "$stack" == "monitor" ]]; then
        setup_fast_monitoring_user "$ENV_DECRYPTED_PATH"
        copy_monitoring_configs "$ENV_DECRYPTED_PATH"
    elif [[ "$stack" == "gateway" ]]; then
        setup_gateway_permissions
    elif [[ "$stack" == "gaming" ]]; then
        setup_gaming_permissions
    fi

    pct push "$CT_ID" "$ENV_DECRYPTED_PATH" /root/.env
    pct push "$CT_ID" "$compose_file" /root/docker-compose.yml
    pct push "$CT_ID" "$WORK_DIR/docker/_infra/docker-compose.yml" /root/infra-compose.yml
    copy_promtail_config "$CT_ID" "$CT_HOSTNAME"
    setup_stack_aliases "$CT_ID"

    pct exec "$CT_ID" -- sh -c "cd /root && docker compose -p app -f docker-compose.yml up -d --remove-orphans"
    pct exec "$CT_ID" -- sh -c "cd /root && docker compose -p infra -f infra-compose.yml up -d --remove-orphans"

    rm -f "$ENV_DECRYPTED_PATH"
    ENV_DECRYPTED_PATH=""

    print_success "Fast redeployed: $stack"
}

main() {
    require_root

    local -a stacks=()

    if [[ $# -gt 0 ]]; then
        stacks=("$@")
    else
        while IFS= read -r stack; do
            stacks+=("$stack")
        done < <(get_available_stacks "$WORK_DIR/stacks.yaml")
    fi

    ENV_ENC_KEY=$(prompt_env_passphrase)
    export ENV_ENC_KEY

    for stack in "${stacks[@]}"; do
        fast_redeploy_stack "$stack"
    done

    rm -f /tmp/*.fast-redeploy.env /tmp/promtail_*.fast-redeploy.yml

    print_success "Fast redeploy completed"
}

main "$@"
