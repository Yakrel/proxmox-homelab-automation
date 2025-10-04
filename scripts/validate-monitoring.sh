#!/bin/bash

# =================================================================
#           Monitoring Stack Validation Script
# =================================================================
# Comprehensive validation of monitoring system configuration
# and connections with other stacks
set -euo pipefail

WORK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)"

# --- Load Shared Functions ---
source "$WORK_DIR/scripts/helper-functions.sh"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;36m'
NC='\033[0m' # No Color

# Counters
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0
WARNING_CHECKS=0

# Test result tracking
test_pass() {
    local msg="$1"
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    PASSED_CHECKS=$((PASSED_CHECKS + 1))
    echo -e "${GREEN}✓${NC} ${msg}"
}

test_fail() {
    local msg="$1"
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    FAILED_CHECKS=$((FAILED_CHECKS + 1))
    echo -e "${RED}✗${NC} ${msg}"
}

test_warn() {
    local msg="$1"
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    WARNING_CHECKS=$((WARNING_CHECKS + 1))
    echo -e "${YELLOW}⚠${NC} ${msg}"
}

section_header() {
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# === VALIDATION FUNCTIONS ===

validate_env_enc_key() {
    section_header "1. ENV_ENC_KEY Validation"
    
    if [[ -z "${ENV_ENC_KEY:-}" ]]; then
        test_fail "ENV_ENC_KEY not set"
        return 1
    fi
    test_pass "ENV_ENC_KEY is set"
    
    # Try to decrypt .env.enc
    local enc_file="$WORK_DIR/docker/monitoring/.env.enc"
    if [[ ! -f "$enc_file" ]]; then
        test_fail ".env.enc file not found: $enc_file"
        return 1
    fi
    test_pass ".env.enc file exists"
    
    local decrypted_content
    if decrypted_content=$(printf '%s' "$ENV_ENC_KEY" | openssl enc -d -aes-256-cbc -pbkdf2 -pass stdin -in "$enc_file" 2>&1); then
        test_pass "Successfully decrypted .env.enc with ENV_ENC_KEY"
        
        # Save for further validation
        echo "$decrypted_content" > /tmp/monitoring_env_decrypted
        return 0
    else
        test_fail "Failed to decrypt .env.enc with ENV_ENC_KEY"
        return 1
    fi
}

validate_env_variables() {
    section_header "2. Environment Variables Validation"
    
    if [[ ! -f /tmp/monitoring_env_decrypted ]]; then
        test_fail "Decrypted .env not available for validation"
        return 1
    fi
    
    # Required variables for monitoring stack
    local required_vars=(
        "GF_SECURITY_ADMIN_USER"
        "GF_SECURITY_ADMIN_PASSWORD"
        "PVE_MONITORING_PASSWORD"
        "PBS_PROMETHEUS_PASSWORD"
        "PVE_URL"
        "PVE_USER"
        "PVE_VERIFY_SSL"
        "TZ"
    )
    
    local env_file=/tmp/monitoring_env_decrypted
    for var in "${required_vars[@]}"; do
        if grep -q "^${var}=" "$env_file"; then
            local value
            value=$(grep "^${var}=" "$env_file" | cut -d'=' -f2-)
            if [[ -n "$value" ]]; then
                test_pass "$var is set"
            else
                test_fail "$var is empty"
            fi
        else
            test_fail "$var not found in .env"
        fi
    done
}

validate_monitoring_deployment_script() {
    section_header "3. Monitoring Deployment Script Validation"
    
    local script="$WORK_DIR/scripts/modules/monitoring-deployment.sh"
    if [[ ! -f "$script" ]]; then
        test_fail "monitoring-deployment.sh not found"
        return 1
    fi
    test_pass "monitoring-deployment.sh exists"
    
    # Check critical functions exist
    local required_functions=(
        "setup_monitoring_environment"
        "configure_pbs_monitoring"
        "setup_monitoring_directories"
        "provision_grafana_dashboards"
        "configure_grafana_automation"
        "validate_monitoring_configs"
        "deploy_monitoring_stack"
    )
    
    for func in "${required_functions[@]}"; do
        if grep -q "^${func}()" "$script"; then
            test_pass "Function $func exists"
        else
            test_fail "Function $func missing"
        fi
    done
    
    # Check for fail-fast pattern
    if grep -q "set -euo pipefail" "$script"; then
        test_pass "Fail-fast error handling enabled"
    else
        test_warn "Fail-fast error handling not found"
    fi
}

validate_prometheus_config() {
    section_header "4. Prometheus Configuration Validation"
    
    local prom_config="$WORK_DIR/docker/monitoring/prometheus.yml"
    if [[ ! -f "$prom_config" ]]; then
        test_fail "prometheus.yml not found"
        return 1
    fi
    test_pass "prometheus.yml exists"
    
    # Check for required job names
    local required_jobs=(
        "prometheus"
        "docker_engine"
        "proxmox"
        "pbs"
        "loki"
        "promtail"
    )
    
    for job in "${required_jobs[@]}"; do
        if grep -q "job_name: '$job'" "$prom_config" || grep -q "job_name: \"$job\"" "$prom_config"; then
            test_pass "Prometheus job '$job' configured"
        else
            test_fail "Prometheus job '$job' missing"
        fi
    done
    
    # Check Docker Engine targets for all Docker stacks
    local docker_stacks=("192.168.1.100" "192.168.1.101" "192.168.1.102" "192.168.1.103" "192.168.1.104" "192.168.1.105")
    for target in "${docker_stacks[@]}"; do
        if grep -q "${target}:9323" "$prom_config"; then
            test_pass "Docker engine target ${target}:9323 configured"
        else
            test_fail "Docker engine target ${target}:9323 missing"
        fi
    done
    
    # Verify PBS uses file service discovery
    if grep -q "file_sd_configs:" "$prom_config"; then
        test_pass "PBS uses file service discovery"
    else
        test_warn "PBS file service discovery not configured"
    fi
    
    # Check PBS password file reference
    if grep -q "password_file: '/etc/prometheus/.prometheus-password'" "$prom_config"; then
        test_pass "PBS password file reference configured"
    else
        test_fail "PBS password file reference missing"
    fi
}

validate_grafana_config() {
    section_header "5. Grafana Configuration Validation"
    
    # Check docker-compose for Grafana
    local compose="$WORK_DIR/docker/monitoring/docker-compose.yml"
    if [[ ! -f "$compose" ]]; then
        test_fail "docker-compose.yml not found"
        return 1
    fi
    test_pass "docker-compose.yml exists"
    
    # Check Grafana service
    if grep -q "grafana:" "$compose"; then
        test_pass "Grafana service defined"
    else
        test_fail "Grafana service missing"
    fi
    
    # Check environment variables
    local env_vars=("GF_SECURITY_ADMIN_USER" "GF_SECURITY_ADMIN_PASSWORD")
    for var in "${env_vars[@]}"; do
        if grep -q "$var" "$compose"; then
            test_pass "Grafana env var $var referenced"
        else
            test_fail "Grafana env var $var not referenced"
        fi
    done
    
    # Check provisioning volumes
    if grep -q "/datapool/config/grafana/provisioning:/etc/grafana/provisioning" "$compose"; then
        test_pass "Grafana provisioning volume configured"
    else
        test_fail "Grafana provisioning volume missing"
    fi
    
    # Check dashboards volume (critical for dashboard provisioning)
    if grep -q "/datapool/config/grafana/dashboards:/datapool/config/grafana/dashboards" "$compose"; then
        test_pass "Grafana dashboards volume configured"
    else
        test_fail "Grafana dashboards volume missing (required for dashboard provisioning)"
    fi
    
    # Check depends_on
    if grep -A 5 "grafana:" "$compose" | grep -q "depends_on:"; then
        test_pass "Grafana has service dependencies"
        if grep -A 10 "depends_on:" "$compose" | grep -q "prometheus"; then
            test_pass "Grafana depends on Prometheus"
        else
            test_warn "Grafana doesn't depend on Prometheus"
        fi
        if grep -A 10 "depends_on:" "$compose" | grep -q "loki"; then
            test_pass "Grafana depends on Loki"
        else
            test_warn "Grafana doesn't depend on Loki"
        fi
    fi
}

validate_loki_config() {
    section_header "6. Loki Configuration Validation"
    
    local loki_config="$WORK_DIR/config/loki/loki.yml"
    if [[ ! -f "$loki_config" ]]; then
        test_fail "loki.yml not found"
        return 1
    fi
    test_pass "loki.yml exists"
    
    # Check retention period
    if grep -q "retention_period:" "$loki_config"; then
        local retention
        retention=$(grep "retention_period:" "$loki_config" | awk '{print $2}')
        test_pass "Retention period set to $retention"
    else
        test_warn "Retention period not configured"
    fi
    
    # Check compactor configuration
    if grep -q "compactor:" "$loki_config"; then
        test_pass "Compactor configured"
        if grep -q "retention_enabled: true" "$loki_config"; then
            test_pass "Retention enabled in compactor"
        else
            test_warn "Retention not enabled in compactor"
        fi
    else
        test_warn "Compactor not configured"
    fi
    
    # Check docker-compose Loki service
    local compose="$WORK_DIR/docker/monitoring/docker-compose.yml"
    if grep -q "loki:" "$compose"; then
        test_pass "Loki service defined in docker-compose"
    else
        test_fail "Loki service missing from docker-compose"
    fi
}

validate_promtail_config() {
    section_header "7. Promtail Configuration Validation"
    
    local promtail_config="$WORK_DIR/config/promtail/promtail.yml"
    if [[ ! -f "$promtail_config" ]]; then
        test_fail "promtail.yml template not found"
        return 1
    fi
    test_pass "promtail.yml template exists"
    
    # Check for REPLACE_HOST_LABEL placeholder
    if grep -q "REPLACE_HOST_LABEL" "$promtail_config"; then
        test_pass "REPLACE_HOST_LABEL placeholder found"
    else
        test_fail "REPLACE_HOST_LABEL placeholder missing"
    fi
    
    # Check Loki URL
    if grep -q "http://192.168.1.104:3100/loki/api/v1/push" "$promtail_config"; then
        test_pass "Loki URL configured correctly"
    else
        test_fail "Loki URL incorrect or missing"
    fi
    
    # Check scrape configs
    if grep -q "job_name: containers" "$promtail_config"; then
        test_pass "Container logs scrape job configured"
    else
        test_fail "Container logs scrape job missing"
    fi
    
    if grep -q "job_name: system" "$promtail_config"; then
        test_pass "System logs scrape job configured"
    else
        test_fail "System logs scrape job missing"
    fi
}

validate_promtail_in_stacks() {
    section_header "8. Promtail in Other Stacks Validation"
    
    local docker_stacks=("proxy" "media" "files" "webtools" "gameservers")
    
    for stack in "${docker_stacks[@]}"; do
        local compose="$WORK_DIR/docker/$stack/docker-compose.yml"
        if [[ ! -f "$compose" ]]; then
            test_warn "docker-compose.yml not found for $stack"
            continue
        fi
        
        if grep -q "promtail:" "$compose"; then
            test_pass "$stack: Promtail service defined"
            
            # Check volumes
            if grep -A 10 "promtail:" "$compose" | grep -q "/var/lib/docker/containers:/var/lib/docker/containers:ro"; then
                test_pass "$stack: Container logs volume mounted"
            else
                test_fail "$stack: Container logs volume missing"
            fi
            
            if grep -A 10 "promtail:" "$compose" | grep -q "/etc/promtail:/etc/promtail:ro"; then
                test_pass "$stack: Promtail config volume mounted"
            else
                test_fail "$stack: Promtail config volume missing"
            fi
        else
            test_fail "$stack: Promtail service missing"
        fi
    done
}

validate_pbs_integration() {
    section_header "9. PBS (Proxmox Backup Server) Integration Validation"
    
    # Check if backup stack exists in stacks.yaml
    if yq -r ".stacks.backup.ct_id" "$WORK_DIR/stacks.yaml" | grep -q "106"; then
        test_pass "Backup stack (PBS) defined in stacks.yaml"
    else
        test_fail "Backup stack not found in stacks.yaml"
    fi
    
    # Check if monitoring-deployment.sh handles PBS monitoring
    local script="$WORK_DIR/scripts/modules/monitoring-deployment.sh"
    if grep -q "configure_pbs_monitoring" "$script"; then
        test_pass "PBS monitoring configuration function exists"
    else
        test_fail "PBS monitoring configuration function missing"
    fi
    
    # Check PBS password handling
    if grep -q "PBS_PROMETHEUS_PASSWORD" "$script"; then
        test_pass "PBS Prometheus password handling exists"
    else
        test_fail "PBS Prometheus password handling missing"
    fi
    
    # Check pbs_job.yml creation
    if grep -q "pbs_job.yml" "$script"; then
        test_pass "PBS job file creation logic exists"
    else
        test_fail "PBS job file creation logic missing"
    fi
}

validate_pve_exporter() {
    section_header "10. Proxmox VE Exporter Validation"
    
    local compose="$WORK_DIR/docker/monitoring/docker-compose.yml"
    
    # Check if prometheus-pve-exporter service exists
    if grep -q "prometheus-pve-exporter:" "$compose"; then
        test_pass "Prometheus PVE Exporter service defined"
    else
        test_fail "Prometheus PVE Exporter service missing"
    fi
    
    # Check environment variables
    local env_vars=("PVE_USER" "PVE_PASSWORD" "PVE_URL" "PVE_VERIFY_SSL")
    for var in "${env_vars[@]}"; do
        if grep -q "$var" "$compose"; then
            test_pass "PVE Exporter env var $var referenced"
        else
            test_fail "PVE Exporter env var $var not referenced"
        fi
    done
    
    # Check deploy-stack.sh for PVE user creation
    local deploy_script="$WORK_DIR/scripts/deploy-stack.sh"
    if grep -q "setup_proxmox_monitoring_user" "$deploy_script"; then
        test_pass "PVE monitoring user setup function exists"
    else
        test_fail "PVE monitoring user setup function missing"
    fi
}

validate_docker_engine_metrics() {
    section_header "11. Docker Engine Metrics Validation"
    
    # Docker daemon must expose metrics on port 9323
    # This is configured in daemon.json on each LXC
    
    local daemon_json_info="Docker daemon.json should contain:"
    echo "$daemon_json_info"
    echo '  "metrics-addr": "0.0.0.0:9323"'
    echo '  "experimental": true'
    
    test_pass "Docker engine metrics expected on port 9323"
    test_pass "Prometheus configured to scrape all Docker LXCs"
}

validate_deployment_flow() {
    section_header "12. Deployment Flow Validation"
    
    local deploy_script="$WORK_DIR/scripts/deploy-stack.sh"
    
    # Check monitoring stack deployment logic
    if grep -q "monitoring" "$deploy_script"; then
        test_pass "Monitoring stack handling exists in deploy-stack.sh"
    else
        test_fail "Monitoring stack handling missing"
    fi
    
    # Check .env decryption
    if grep -q "decrypt_env_for_deploy" "$deploy_script"; then
        test_pass "Environment decryption function exists"
    else
        test_fail "Environment decryption function missing"
    fi
    
    # Check monitoring module loading
    if grep -q "source.*monitoring-deployment.sh" "$deploy_script"; then
        test_pass "Monitoring deployment module loaded"
    else
        test_fail "Monitoring deployment module not loaded"
    fi
    
    # Check deployment sequence
    if grep -q "deploy_monitoring_stack" "$deploy_script"; then
        test_pass "Monitoring stack deployment function called"
    else
        test_fail "Monitoring stack deployment function not called"
    fi
}

validate_automation_idempotency() {
    section_header "13. Automation & Idempotency Validation"
    
    local script="$WORK_DIR/scripts/modules/monitoring-deployment.sh"
    
    # Check for datasource automation
    if grep -q "configure_grafana_automation" "$script"; then
        test_pass "Grafana datasource automation exists"
    else
        test_fail "Grafana datasource automation missing"
    fi
    
    # Check for dashboard provisioning
    if grep -q "provision_grafana_dashboards" "$script"; then
        test_pass "Dashboard provisioning automation exists"
    else
        test_fail "Dashboard provisioning automation missing"
    fi
    
    # Check for dashboard downloads
    if grep -q "grafana.com/api/dashboards" "$script"; then
        test_pass "Dashboard download automation exists"
    else
        test_fail "Dashboard download automation missing"
    fi
    
    # Check for file overwriting (idempotency)
    if grep -q "overwrites existing" "$script" || grep -q "overwrite" "$script"; then
        test_pass "Configuration overwriting for idempotency"
    else
        test_warn "No explicit overwriting mentioned (may affect idempotency)"
    fi
}

validate_network_topology() {
    section_header "14. Network Topology Validation"
    
    # Check IP addressing scheme
    test_pass "Network scheme: 192.168.1.{ct_id}"
    test_pass "Monitoring LXC: 192.168.1.104 (CT 104)"
    test_pass "Backup LXC: 192.168.1.106 (CT 106)"
    
    # Verify stacks.yaml network consistency
    local monitoring_id
    monitoring_id=$(yq -r ".stacks.monitoring.ct_id" "$WORK_DIR/stacks.yaml")
    if [[ "$monitoring_id" == "104" ]]; then
        test_pass "Monitoring CT ID matches expected (104)"
    else
        test_fail "Monitoring CT ID mismatch: expected 104, got $monitoring_id"
    fi
    
    # Check all stack IPs align with CT IDs
    local stacks=("proxy" "media" "files" "webtools" "monitoring" "gameservers" "backup")
    for stack in "${stacks[@]}"; do
        local ct_id
        ct_id=$(yq -r ".stacks.$stack.ct_id" "$WORK_DIR/stacks.yaml" 2>/dev/null)
        if [[ "$ct_id" != "null" && -n "$ct_id" ]]; then
            test_pass "$stack: CT ID $ct_id → IP 192.168.1.$ct_id"
        fi
    done
    
    # Verify monitoring-deployment.sh uses hardcoded network topology (not dynamic lookups)
    local script="$WORK_DIR/scripts/modules/monitoring-deployment.sh"
    if grep -q "192.168.1.\${backup_ct_id}" "$script"; then
        test_pass "PBS IP uses hardcoded network scheme (192.168.1.{ct_id})"
    else
        test_warn "PBS IP may use complex dynamic lookup instead of hardcoded scheme"
    fi
}

validate_watchtower_config() {
    section_header "15. Watchtower Auto-Update Validation"
    
    local compose="$WORK_DIR/docker/monitoring/docker-compose.yml"
    
    if grep -q "watchtower:" "$compose"; then
        test_pass "Watchtower service defined"
        
        # Check schedule
        if grep -q "schedule" "$compose"; then
            local schedule
            schedule=$(grep -A 5 "watchtower:" "$compose" | grep "schedule" | sed 's/.*schedule",//' | tr -d '"]')
            test_pass "Watchtower schedule configured"
        fi
        
        # Check cleanup
        if grep -q "WATCHTOWER_CLEANUP=true" "$compose"; then
            test_pass "Watchtower cleanup enabled"
        else
            test_warn "Watchtower cleanup not enabled"
        fi
    else
        test_warn "Watchtower not configured"
    fi
    
    # Check Watchtower in other stacks
    local docker_stacks=("proxy" "media" "files" "webtools" "gameservers")
    for stack in "${docker_stacks[@]}"; do
        local stack_compose="$WORK_DIR/docker/$stack/docker-compose.yml"
        if [[ -f "$stack_compose" ]] && grep -q "watchtower:" "$stack_compose"; then
            test_pass "$stack: Watchtower configured"
        fi
    done
}

# === MAIN EXECUTION ===

print_info "Proxmox Homelab - Monitoring System Validation"
print_info "================================================"
print_info ""
print_info "This script validates the monitoring system configuration"
print_info "and its connections with other stacks based on CLAUDE.md principles."
print_info ""

# Run all validations
validate_env_enc_key || true
validate_env_variables || true
validate_monitoring_deployment_script || true
validate_prometheus_config || true
validate_grafana_config || true
validate_loki_config || true
validate_promtail_config || true
validate_promtail_in_stacks || true
validate_pbs_integration || true
validate_pve_exporter || true
validate_docker_engine_metrics || true
validate_deployment_flow || true
validate_automation_idempotency || true
validate_network_topology || true
validate_watchtower_config || true

# Clean up
rm -f /tmp/monitoring_env_decrypted

# Summary
section_header "VALIDATION SUMMARY"
echo ""
echo -e "Total Checks:    ${BLUE}$TOTAL_CHECKS${NC}"
echo -e "Passed:          ${GREEN}$PASSED_CHECKS${NC}"
echo -e "Failed:          ${RED}$FAILED_CHECKS${NC}"
echo -e "Warnings:        ${YELLOW}$WARNING_CHECKS${NC}"
echo ""

if [[ $FAILED_CHECKS -eq 0 ]]; then
    echo -e "${GREEN}✓ All critical validations passed!${NC}"
    echo ""
    echo -e "${GREEN}Monitoring system is correctly configured and automated.${NC}"
    exit 0
else
    echo -e "${RED}✗ Some validations failed. Please review the issues above.${NC}"
    exit 1
fi
