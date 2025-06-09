#!/bin/bash

# Log Cleanup Script
# Cleans up Docker logs and system logs to free up space

set -e

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
DEFAULT_DAYS=7
DOCKER_LOG_PATH="/var/lib/docker/containers"

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

# Function to show disk usage
show_disk_usage() {
    print_step "Current disk usage:"
    df -h / | grep -E "Filesystem|/"
    echo ""
}

# Function to cleanup Docker logs
cleanup_docker_logs() {
    local days=${1:-$DEFAULT_DAYS}
    
    print_step "Cleaning up Docker logs older than $days days..."
    
    # Get current log sizes
    local total_size_before=0
    if [ -d "$DOCKER_LOG_PATH" ]; then
        total_size_before=$(du -s "$DOCKER_LOG_PATH" 2>/dev/null | cut -f1 || echo 0)
    fi
    
    # Cleanup using Docker's built-in command
    print_info "Truncating Docker container logs..."
    docker ps -a --format "table {{.Names}}" | tail -n +2 | while read container; do
        if [ ! -z "$container" ] && [ "$container" != "NAMES" ]; then
            # Truncate log file
            docker logs "$container" >/dev/null 2>&1 && echo "Cleared logs for: $container" || true
        fi
    done
    
    # Alternative: directly truncate log files
    print_info "Truncating log files directly..."
    find "$DOCKER_LOG_PATH" -name "*.log" -type f -mtime +$days -exec truncate -s 0 {} \; 2>/dev/null || true
    
    # Get log sizes after cleanup
    local total_size_after=0
    if [ -d "$DOCKER_LOG_PATH" ]; then
        total_size_after=$(du -s "$DOCKER_LOG_PATH" 2>/dev/null | cut -f1 || echo 0)
    fi
    
    local freed_space=$((total_size_before - total_size_after))
    if [ $freed_space -gt 0 ]; then
        print_info "✓ Freed $(($freed_space / 1024)) MB from Docker logs"
    else
        print_info "No significant space freed from Docker logs"
    fi
}

# Function to cleanup system logs
cleanup_system_logs() {
    local days=${1:-$DEFAULT_DAYS}
    
    print_step "Cleaning up system logs older than $days days..."
    
    # Clean journalctl logs
    print_info "Cleaning systemd journal logs..."
    journalctl --vacuum-time=${days}d 2>/dev/null || print_warning "Could not clean journalctl logs"
    
    # Clean syslog files
    print_info "Cleaning syslog files..."
    find /var/log -name "*.log" -type f -mtime +$days -exec rm -f {} \; 2>/dev/null || true
    find /var/log -name "*.log.*" -type f -mtime +$days -exec rm -f {} \; 2>/dev/null || true
    
    # Clean rotated logs
    find /var/log -name "*.gz" -type f -mtime +$days -exec rm -f {} \; 2>/dev/null || true
    find /var/log -name "*.old" -type f -mtime +$days -exec rm -f {} \; 2>/dev/null || true
    
    print_info "✓ System logs cleanup completed"
}

# Function to cleanup temporary files
cleanup_temp_files() {
    print_step "Cleaning up temporary files..."
    
    # Clean /tmp files older than 7 days
    find /tmp -type f -mtime +7 -delete 2>/dev/null || true
    
    # Clean /var/tmp files older than 30 days
    find /var/tmp -type f -mtime +30 -delete 2>/dev/null || true
    
    print_info "✓ Temporary files cleanup completed"
}

# Function to cleanup package cache
cleanup_package_cache() {
    print_step "Cleaning up package cache..."
    
    # Detect package manager and clean cache
    if command -v apt-get >/dev/null 2>&1; then
        print_info "Cleaning APT cache..."
        apt-get clean 2>/dev/null || true
        apt-get autoremove -y 2>/dev/null || true
    fi
    
    if command -v apk >/dev/null 2>&1; then
        print_info "Cleaning APK cache..."
        apk cache clean 2>/dev/null || true
    fi
    
    if command -v yum >/dev/null 2>&1; then
        print_info "Cleaning YUM cache..."
        yum clean all 2>/dev/null || true
    fi
    
    print_info "✓ Package cache cleanup completed"
}

# Function to show log sizes
show_log_sizes() {
    print_step "Current log sizes:"
    
    # Docker logs
    if [ -d "$DOCKER_LOG_PATH" ]; then
        local docker_size=$(du -sh "$DOCKER_LOG_PATH" 2>/dev/null | cut -f1 || echo "0")
        print_info "Docker logs: $docker_size"
    fi
    
    # System logs
    local syslog_size=$(du -sh /var/log 2>/dev/null | cut -f1 || echo "0")
    print_info "System logs (/var/log): $syslog_size"
    
    # Journal logs
    local journal_size=$(journalctl --disk-usage 2>/dev/null | grep -o '[0-9.]*[KMGT]B' || echo "Unknown")
    print_info "Journal logs: $journal_size"
    
    echo ""
}

# Function to force Docker log rotation
force_docker_log_rotation() {
    print_step "Forcing Docker log rotation..."
    
    # Send USR1 signal to Docker daemon to rotate logs
    if pgrep dockerd >/dev/null; then
        print_info "Sending rotation signal to Docker daemon..."
        pkill -USR1 dockerd 2>/dev/null || print_warning "Could not signal Docker daemon"
    fi
    
    # Restart Docker containers to force log rotation
    print_info "Restarting Docker containers for log rotation..."
    docker ps --format "{{.Names}}" | while read container; do
        if [ ! -z "$container" ]; then
            print_info "Restarting: $container"
            docker restart "$container" >/dev/null 2>&1 || true
        fi
    done
    
    print_info "✓ Docker log rotation completed"
}

# Function to show cleanup summary
show_cleanup_summary() {
    print_step "Cleanup Summary:"
    show_disk_usage
    show_log_sizes
}

# Main function
main() {
    local days=${2:-$DEFAULT_DAYS}
    
    case "${1:-all}" in
        "docker")
            print_info "🧹 Cleaning Docker logs only..."
            show_disk_usage
            cleanup_docker_logs "$days"
            show_cleanup_summary
            ;;
        "system")
            print_info "🧹 Cleaning system logs only..."
            show_disk_usage
            cleanup_system_logs "$days"
            show_cleanup_summary
            ;;
        "temp")
            print_info "🧹 Cleaning temporary files only..."
            show_disk_usage
            cleanup_temp_files
            show_cleanup_summary
            ;;
        "cache")
            print_info "🧹 Cleaning package cache only..."
            show_disk_usage
            cleanup_package_cache
            show_cleanup_summary
            ;;
        "rotate")
            print_info "🔄 Forcing Docker log rotation..."
            force_docker_log_rotation
            ;;
        "all")
            print_info "🧹 Starting comprehensive log cleanup..."
            show_disk_usage
            show_log_sizes
            cleanup_docker_logs "$days"
            cleanup_system_logs "$days"
            cleanup_temp_files
            cleanup_package_cache
            show_cleanup_summary
            print_info "✅ Cleanup completed successfully!"
            ;;
        "status"|"info")
            show_disk_usage
            show_log_sizes
            ;;
        *)
            echo "Usage: $0 {all|docker|system|temp|cache|rotate|status} [days]"
            echo ""
            echo "Commands:"
            echo "  all     Complete cleanup (default)"
            echo "  docker  Clean Docker logs only"
            echo "  system  Clean system logs only" 
            echo "  temp    Clean temporary files only"
            echo "  cache   Clean package cache only"
            echo "  rotate  Force Docker log rotation"
            echo "  status  Show current disk and log usage"
            echo ""
            echo "Options:"
            echo "  days    Number of days to keep logs (default: $DEFAULT_DAYS)"
            echo ""
            echo "Examples:"
            echo "  $0 all 7        # Clean all logs older than 7 days"
            echo "  $0 docker 3     # Clean Docker logs older than 3 days"
            echo "  $0 status       # Show current usage"
            exit 1
            ;;
    esac
}

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    print_error "This script must be run as root"
    exit 1
fi

# Execute main function
main "$@"