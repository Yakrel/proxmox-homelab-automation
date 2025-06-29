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
    local ssh_failures=0
    local proxmox_failures=0
    local ban_actions=0
    
    if [ -f /var/log/fail2ban.log ]; then
        ssh_failures=$(grep "\[sshd\] Found" /var/log/fail2ban.log | grep "$(date '+%Y-%m-%d')" | wc -l)
        proxmox_failures=$(grep "\[proxmox\] Found" /var/log/fail2ban.log | grep "$(date '+%Y-%m-%d')" | wc -l)
        ban_actions=$(grep -E "\] Ban " /var/log/fail2ban.log | grep "$(date '+%Y-%m-%d')" | wc -l)
    fi
    
    echo "  📈 SSH failed attempts: $ssh_failures"
    echo "  🌐 Proxmox web failed attempts: $proxmox_failures"
    echo "  🔨 IPs banned: $ban_actions"
    
    # Show top attacking IPs
    echo ""
    echo "🎯 Top Attacking IPs (24h):"
    local top_attackers=""
    
    if [ -f /var/log/fail2ban.log ]; then
        top_attackers=$(grep -E "\[(sshd|proxmox)\] Found" /var/log/fail2ban.log | grep "$(date '+%Y-%m-%d')" | \
            grep -oE '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | \
            sort | uniq -c | sort -nr | head -5)
    fi
    
    if [ ! -z "$top_attackers" ]; then
        echo "$top_attackers" | while read count ip; do
            echo "  📍 $ip ($count attempts)"
        done
    else
        echo "  ✅ No failed attempts found"
    fi
    
    # Show last 10 SSH failed attempts
    echo ""
    echo "🚪 Last 10 SSH Failed Attempts:"
    if [ -f /var/log/fail2ban.log ]; then
        grep "\[sshd\] Found" /var/log/fail2ban.log | tail -10 | tac | while IFS= read -r line; do
            local timestamp=$(echo "$line" | awk '{print $1, $2}' | cut -d',' -f1)
            local ip=$(echo "$line" | grep -oE '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | head -1)
            if [ ! -z "$ip" ]; then
                echo "  ⏰ $timestamp - $ip (SSH)"
            fi
        done
    fi
    
    # Also check for Proxmox web interface failed attempts
    echo ""
    echo "🌐 Last 10 Proxmox Web Failed Attempts:"
    if [ -f /var/log/fail2ban.log ]; then
        grep "\[proxmox\] Found" /var/log/fail2ban.log | tail -10 | tac | while IFS= read -r line; do
            local timestamp=$(echo "$line" | awk '{print $1, $2}' | cut -d',' -f1)
            local ip=$(echo "$line" | grep -oE '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | head -1)
            if [ ! -z "$ip" ]; then
                echo "  ⏰ $timestamp - $ip (Proxmox Web)"
            fi
        done
    fi
    
    # Show last 10 banned IPs
    echo ""
    echo "🔨 Last 10 Banned IPs:"
    if [ -f /var/log/fail2ban.log ]; then
        grep "\] Ban " /var/log/fail2ban.log | tail -10 | tac | while IFS= read -r line; do
            local timestamp=$(echo "$line" | awk '{print $1, $2}' | cut -d',' -f1)
            local ip=$(echo "$line" | grep -oE '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | head -1)
            local jail=$(echo "$line" | sed -n 's/.*\[\([^]]*\)\].*/\1/p')
            if [ ! -z "$ip" ]; then
                echo "  🚫 $timestamp - $ip [$jail]"
            fi
        done
    fi
}

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    print_error "This script must be run as root"
    exit 1
fi

# Run the check
show_security_status