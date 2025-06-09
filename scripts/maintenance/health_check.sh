#!/bin/bash

# Health Check Script
# Monitors the health of all stacks and services

set -e

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
TIMEOUT=10
CHECK_INTERVAL=5

# Function to print colored output
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_fail() {
    echo -e "${RED}[✗]${NC} $1"
}

# Function to check LXC status
check_lxc_status() {
    local lxc_id=$1
    local lxc_name=$2
    
    print_step "Checking LXC $lxc_id ($lxc_name)..."
    
    # Check if LXC exists
    if ! pct status "$lxc_id" >/dev/null 2>&1; then
        print_fail "LXC $lxc_id does not exist"
        return 1
    fi
    
    # Check if LXC is running
    local status=$(pct status "$lxc_id" 2>/dev/null | grep -o "running\|stopped" || echo "unknown")
    
    case $status in
        "running")
            print_success "LXC $lxc_id is running"
            
            # Check resource usage
            local cpu_usage=$(pct exec "$lxc_id" -- top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1 2>/dev/null || echo "unknown")
            local memory_usage=$(pct exec "$lxc_id" -- free | grep Mem | awk '{printf "%.1f", $3/$2 * 100.0}' 2>/dev/null || echo "unknown")
            
            print_info "  CPU Usage: ${cpu_usage}%"
            print_info "  Memory Usage: ${memory_usage}%"
            
            return 0
            ;;
        "stopped")
            print_fail "LXC $lxc_id is stopped"
            return 1
            ;;
        *)
            print_fail "LXC $lxc_id status unknown"
            return 1
            ;;
    esac
}

# Function to check Docker service health
check_docker_health() {
    local lxc_id=$1
    
    print_step "Checking Docker health in LXC $lxc_id..."
    
    # Check if Docker is running
    if pct exec "$lxc_id" -- systemctl is-active docker >/dev/null 2>&1; then
        print_success "Docker service is running"
    else
        print_fail "Docker service is not running"
        return 1
    fi
    
    # Check Docker daemon responsiveness
    if pct exec "$lxc_id" -- timeout $TIMEOUT docker ps >/dev/null 2>&1; then
        print_success "Docker daemon is responsive"
    else
        print_fail "Docker daemon is not responsive"
        return 1
    fi
    
    return 0
}

# Function to check container health
check_container_health() {
    local lxc_id=$1
    local stack_name=$2
    
    print_step "Checking containers in $stack_name stack (LXC $lxc_id)..."
    
    # Get running containers
    local containers=$(pct exec "$lxc_id" -- docker ps --format "{{.Names}}" 2>/dev/null || echo "")
    
    if [ -z "$containers" ]; then
        print_warning "No running containers found in LXC $lxc_id"
        return 1
    fi
    
    local total_containers=0
    local healthy_containers=0
    
    echo "$containers" | while read container; do
        if [ ! -z "$container" ]; then
            total_containers=$((total_containers + 1))
            
            # Check container status
            local status=$(pct exec "$lxc_id" -- docker inspect --format='{{.State.Status}}' "$container" 2>/dev/null || echo "unknown")
            local health=$(pct exec "$lxc_id" -- docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null || echo "none")
            
            case $status in
                "running")
                    if [ "$health" = "healthy" ] || [ "$health" = "none" ]; then
                        print_success "  $container: running (${health})"
                        healthy_containers=$((healthy_containers + 1))
                    else
                        print_warning "  $container: running but ${health}"
                    fi
                    ;;
                "exited")
                    local exit_code=$(pct exec "$lxc_id" -- docker inspect --format='{{.State.ExitCode}}' "$container" 2>/dev/null || echo "unknown")
                    print_fail "  $container: exited (code: $exit_code)"
                    ;;
                *)
                    print_fail "  $container: $status"
                    ;;
            esac
        fi
    done
    
    if [ $healthy_containers -eq $total_containers ] && [ $total_containers -gt 0 ]; then
        print_success "$stack_name stack: $healthy_containers/$total_containers containers healthy"
        return 0
    else
        print_warning "$stack_name stack: $healthy_containers/$total_containers containers healthy"
        return 1
    fi
}

# Function to check service connectivity
check_service_connectivity() {
    local service_name=$1
    local host=$2
    local port=$3
    
    # Test connection with timeout
    if timeout $TIMEOUT bash -c "</dev/tcp/$host/$port" 2>/dev/null; then
        print_success "  $service_name ($host:$port): accessible"
        return 0
    else
        print_fail "  $service_name ($host:$port): not accessible"
        return 1
    fi
}

# Function to check stack services
check_stack_services() {
    local stack_type=$1
    local lxc_id=$2
    
    print_step "Checking $stack_type stack services..."
    
    local host_ip=$(pct exec "$lxc_id" -- hostname -I | awk '{print $1}' 2>/dev/null || echo "127.0.0.1")
    
    case $stack_type in
        "media")
            check_service_connectivity "Sonarr" "$host_ip" "8989"
            check_service_connectivity "Radarr" "$host_ip" "7878"
            check_service_connectivity "Jellyfin" "$host_ip" "8096"
            check_service_connectivity "qBittorrent" "$host_ip" "8080"
            check_service_connectivity "Prowlarr" "$host_ip" "9696"
            check_service_connectivity "Bazarr" "$host_ip" "6767"
            check_service_connectivity "Jellyseerr" "$host_ip" "5055"
            ;;
        "proxy")
            print_info "  Cloudflared: Check Cloudflare dashboard for tunnel status"
            ;;
        "downloads")
            check_service_connectivity "JDownloader2" "$host_ip" "5801"
            check_service_connectivity "MeTube" "$host_ip" "8081"
            ;;
        "utility")
            check_service_connectivity "Firefox" "$host_ip" "5800"
            ;;
        "monitoring")
            check_service_connectivity "Grafana" "$host_ip" "3000"
            check_service_connectivity "Prometheus" "$host_ip" "9090"
            check_service_connectivity "Alertmanager" "$host_ip" "9093"
            check_service_connectivity "cAdvisor" "$host_ip" "8080"
            ;;
    esac
}

# Function to check disk usage
check_disk_usage() {
    print_step "Checking disk usage..."
    
    # Check root filesystem
    local root_usage=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')
    if [ "$root_usage" -lt 80 ]; then
        print_success "Root filesystem: ${root_usage}% used"
    elif [ "$root_usage" -lt 90 ]; then
        print_warning "Root filesystem: ${root_usage}% used (getting full)"
    else
        print_fail "Root filesystem: ${root_usage}% used (critically full)"
    fi
    
    # Check datapool if exists
    if mountpoint -q /datapool 2>/dev/null; then
        local datapool_usage=$(df /datapool | tail -1 | awk '{print $5}' | sed 's/%//')
        if [ "$datapool_usage" -lt 80 ]; then
            print_success "Datapool: ${datapool_usage}% used"
        elif [ "$datapool_usage" -lt 90 ]; then
            print_warning "Datapool: ${datapool_usage}% used (getting full)"
        else
            print_fail "Datapool: ${datapool_usage}% used (critically full)"
        fi
    fi
}

# Function to check memory usage
check_memory_usage() {
    print_step "Checking memory usage..."
    
    local memory_usage=$(free | grep Mem | awk '{printf "%.1f", $3/$2 * 100.0}')
    local memory_available=$(free -h | grep Mem | awk '{print $7}')
    
    if (( $(echo "$memory_usage < 80" | bc -l) )); then
        print_success "Memory usage: ${memory_usage}% (${memory_available} available)"
    elif (( $(echo "$memory_usage < 90" | bc -l) )); then
        print_warning "Memory usage: ${memory_usage}% (${memory_available} available)"
    else
        print_fail "Memory usage: ${memory_usage}% (${memory_available} available)"
    fi
}

# Function to generate health report
generate_health_report() {
    local report_file="/tmp/health_report_$(date +%Y%m%d_%H%M%S).txt"
    
    print_step "Generating health report..."
    
    {
        echo "Proxmox Homelab Health Report"
        echo "Generated: $(date)"
        echo "=============================="
        echo ""
        
        echo "System Resources:"
        echo "-----------------"
        df -h
        echo ""
        free -h
        echo ""
        
        echo "LXC Status:"
        echo "-----------"
        for lxc_id in 100 101 102 103 104; do
            if pct status "$lxc_id" >/dev/null 2>&1; then
                echo "LXC $lxc_id: $(pct status $lxc_id)"
            fi
        done
        echo ""
        
        echo "Docker Containers:"
        echo "------------------"
        for lxc_id in 100 101 102 103 104; do
            if pct status "$lxc_id" | grep -q "running"; then
                echo "LXC $lxc_id containers:"
                pct exec "$lxc_id" -- docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || echo "  Docker not available"
                echo ""
            fi
        done
        
    } > "$report_file"
    
    print_success "Health report saved to: $report_file"
    
    # Show summary
    print_info "Report summary:"
    wc -l "$report_file" | awk '{print "  Lines: " $1}'
    ls -lh "$report_file" | awk '{print "  Size: " $5}'
}

# Function to run full health check
run_full_health_check() {
    print_info "🔍 Starting comprehensive health check..."
    echo ""
    
    local overall_status=0
    
    # System health
    check_disk_usage || overall_status=1
    check_memory_usage || overall_status=1
    echo ""
    
    # Check each stack
    local stacks=("proxy:100" "media:101" "downloads:102" "utility:103" "monitoring:104")
    
    for stack_info in "${stacks[@]}"; do
        local stack_type=$(echo "$stack_info" | cut -d: -f1)
        local lxc_id=$(echo "$stack_info" | cut -d: -f2)
        
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        print_info "Checking $stack_type stack (LXC $lxc_id)"
        echo ""
        
        if check_lxc_status "$lxc_id" "$stack_type"; then
            check_docker_health "$lxc_id" || overall_status=1
            check_container_health "$lxc_id" "$stack_type" || overall_status=1
            check_stack_services "$stack_type" "$lxc_id" || overall_status=1
        else
            overall_status=1
        fi
        echo ""
    done
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    if [ $overall_status -eq 0 ]; then
        print_success "✅ All health checks passed!"
    else
        print_warning "⚠️  Some health checks failed - review the output above"
    fi
    
    return $overall_status
}

# Function to monitor continuously
monitor_continuously() {
    local interval=${1:-60}
    
    print_info "🔄 Starting continuous monitoring (interval: ${interval}s)"
    print_info "Press Ctrl+C to stop"
    echo ""
    
    while true; do
        clear
        echo "Continuous Health Monitor - $(date)"
        echo "Next check in ${interval} seconds"
        echo "========================================"
        echo ""
        
        run_full_health_check
        
        sleep "$interval"
    done
}

# Main function
main() {
    case "${1:-check}" in
        "check"|"full")
            run_full_health_check
            ;;
        "lxc")
            if [ -z "$2" ]; then
                print_error "Please specify LXC ID"
                exit 1
            fi
            check_lxc_status "$2" "manual"
            ;;
        "docker")
            if [ -z "$2" ]; then
                print_error "Please specify LXC ID"
                exit 1
            fi
            check_docker_health "$2"
            ;;
        "containers")
            if [ -z "$2" ] || [ -z "$3" ]; then
                print_error "Please specify LXC ID and stack name"
                exit 1
            fi
            check_container_health "$2" "$3"
            ;;
        "services")
            if [ -z "$2" ] || [ -z "$3" ]; then
                print_error "Please specify stack type and LXC ID"
                exit 1
            fi
            check_stack_services "$2" "$3"
            ;;
        "disk")
            check_disk_usage
            ;;
        "memory")
            check_memory_usage
            ;;
        "report")
            generate_health_report
            ;;
        "monitor")
            monitor_continuously "${2:-60}"
            ;;
        *)
            echo "Usage: $0 {check|lxc|docker|containers|services|disk|memory|report|monitor} [options]"
            echo ""
            echo "Commands:"
            echo "  check                    Run full health check (default)"
            echo "  lxc <id>                Check specific LXC"
            echo "  docker <id>             Check Docker in specific LXC"
            echo "  containers <id> <stack> Check containers in stack"
            echo "  services <stack> <id>   Check service connectivity"
            echo "  disk                    Check disk usage only"
            echo "  memory                  Check memory usage only"
            echo "  report                  Generate detailed health report"
            echo "  monitor [seconds]       Continuous monitoring (default: 60s)"
            echo ""
            echo "Examples:"
            echo "  $0 check                # Full health check"
            echo "  $0 lxc 101             # Check media LXC only"
            echo "  $0 services media 101  # Check media stack services"
            echo "  $0 monitor 30          # Monitor every 30 seconds"
            exit 1
            ;;
    esac
}

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    print_error "This script must be run as root"
    exit 1
fi

# Install bc if not present (for floating point calculations)
if ! command -v bc >/dev/null 2>&1; then
    print_warning "Installing bc for calculations..."
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update && apt-get install -y bc >/dev/null 2>&1
    elif command -v apk >/dev/null 2>&1; then
        apk add bc >/dev/null 2>&1
    fi
fi

# Execute main function
main "$@"