#!/bin/bash

# Security Monitoring Script - Simple Version
# Shows basic fail2ban status and blocked IPs

set -e

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Main security check function
show_security_status() {
    echo "🛡️  Security Status Report"
    echo "=========================="
    echo ""
    
    # Check if fail2ban is running
    if ! command -v fail2ban-client >/dev/null 2>&1; then
        print_error "Fail2ban is not installed"
        return 1
    fi
    
    if ! systemctl is-active --quiet fail2ban; then
        print_error "Fail2ban service is not running"
        return 1
    fi
    
    print_info "✓ Fail2ban is running"
    echo ""
    
    # Show jail status
    echo "📊 Jail Status:"
    local jails=$(fail2ban-client status 2>/dev/null | grep "Jail list:" | cut -d: -f2 | tr ',' ' ')
    
    if [ -z "$jails" ]; then
        print_warning "No active jails found"
        return 1
    fi
    
    local total_blocked=0
    
    for jail in $jails; do
        jail=$(echo $jail | xargs)
        if [ ! -z "$jail" ]; then
            local status=$(fail2ban-client status $jail 2>/dev/null)
            local currently_banned=$(echo "$status" | grep "Currently banned:" | awk '{print $NF}')
            local total_banned=$(echo "$status" | grep "Total banned:" | awk '{print $NF}')
            
            if [ "$currently_banned" -gt 0 ]; then
                echo "  🔒 $jail: $currently_banned blocked (total: $total_banned)"
                total_blocked=$((total_blocked + currently_banned))
            else
                echo "  ✅ $jail: $currently_banned blocked (total: $total_banned)"
            fi
        fi
    done
    
    echo ""
    
    # Show blocked IPs if any
    if [ $total_blocked -gt 0 ]; then
        echo "🚫 Currently Blocked IPs:"
        for jail in $jails; do
            jail=$(echo $jail | xargs)
            if [ ! -z "$jail" ]; then
                local banned_ips=$(fail2ban-client status $jail 2>/dev/null | grep "Banned IP list:" | cut -d: -f2)
                
                if [ ! -z "$banned_ips" ] && [ "$banned_ips" != " " ]; then
                    for ip in $banned_ips; do
                        if [ ! -z "$ip" ]; then
                            echo "  📍 $ip ($jail)"
                        fi
                    done
                fi
            fi
        done
    else
        print_info "✅ No IPs currently blocked"
    fi
    
    echo ""
    
    # Show recent attack summary
    echo "🔍 Recent Activity (24h):"
    local ssh_failures=$(journalctl --since "24 hours ago" --grep "Failed password" | wc -l)
    local ban_actions=$(journalctl --since "24 hours ago" --grep "fail2ban.*Ban" | wc -l)
    
    echo "  📈 SSH failed attempts: $ssh_failures"
    echo "  🔨 IPs banned: $ban_actions"
    
    # Show top attacking IP
    local top_attacker=$(journalctl --since "24 hours ago" --grep "Failed password" | \
        grep -oE 'from [0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | \
        awk '{print $2}' | sort | uniq -c | sort -nr | head -1)
    
    if [ ! -z "$top_attacker" ]; then
        echo "  🎯 Top attacker: $top_attacker"
    fi
}

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    print_error "This script must be run as root"
    exit 1
fi

# Run the check
show_security_status