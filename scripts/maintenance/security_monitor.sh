#!/bin/bash

# Security Monitoring Script - Optimized Version
# Shows basic fail2ban status and blocked IPs

set -e

# Source common functions
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
source "$SCRIPT_DIR/../common/functions.sh"

# Check root privileges
check_root

# Main security check function
show_security_status() {
    echo "🛡️  Security Status Report"
    echo "=========================="
    echo ""
    
    # Check if fail2ban is installed and running
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
    
    # Get active jails
    local jails=$(fail2ban-client status 2>/dev/null | grep "Jail list:" | cut -d: -f2 | tr ',' ' ')
    
    if [ -z "$jails" ]; then
        print_warning "No active jails found"
        return 1
    fi
    
    # Show jail status
    echo "📊 Jail Status:"
    local total_blocked=0
    
    for jail in $jails; do
        jail=$(echo $jail | xargs)
        [ -z "$jail" ] && continue
        
        local status=$(fail2ban-client status $jail 2>/dev/null)
        local currently_banned=$(echo "$status" | grep "Currently banned:" | awk '{print $NF}')
        local total_banned=$(echo "$status" | grep "Total banned:" | awk '{print $NF}')
        
        if [ "$currently_banned" -gt 0 ]; then
            echo "  🔒 $jail: $currently_banned blocked (total: $total_banned)"
            total_blocked=$((total_blocked + currently_banned))
        else
            echo "  ✅ $jail: $currently_banned blocked (total: $total_banned)"
        fi
    done
    
    echo ""
    
    # Show blocked IPs if any
    if [ $total_blocked -gt 0 ]; then
        echo "🚫 Currently Blocked IPs:"
        for jail in $jails; do
            jail=$(echo $jail | xargs)
            [ -z "$jail" ] && continue
            
            local banned_ips=$(fail2ban-client status $jail 2>/dev/null | grep "Banned IP list:" | cut -d: -f2)
            
            for ip in $banned_ips; do
                [ ! -z "$ip" ] && echo "  📍 $ip ($jail)"
            done
        done
    else
        print_info "✅ No IPs currently blocked"
    fi
    
    echo ""
    
    # Show recent activity summary
    echo "🔍 Recent Activity (24h):"
    local ssh_failures=$(journalctl --since "24 hours ago" --grep "Failed password" 2>/dev/null | wc -l)
    local ban_actions=$(journalctl --since "24 hours ago" --grep "fail2ban.*Ban" 2>/dev/null | wc -l)
    
    echo "  📈 SSH failed attempts: $ssh_failures"
    echo "  🔨 IPs banned: $ban_actions"
    
    # Show top attacker
    local top_attacker=$(journalctl --since "24 hours ago" --grep "Failed password" 2>/dev/null | \
        grep -oE 'from [0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | \
        awk '{print $2}' | sort | uniq -c | sort -nr | head -1)
    
    [ ! -z "$top_attacker" ] && echo "  🎯 Top attacker: $top_attacker"
}

# Run the security check
show_security_status