#!/bin/bash

# Timezone Configuration Script for Proxmox
# Sets timezone to Europe/Istanbul and configures NTP servers for Turkey

set -e

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

print_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

# Function to set timezone
configure_timezone() {
    print_step "Configuring timezone to Europe/Istanbul..."
    
    # Set timezone
    timedatectl set-timezone Europe/Istanbul
    
    if [ $? -eq 0 ]; then
        print_success "Timezone set to Europe/Istanbul"
        
        # Show current time
        local current_time=$(date)
        print_info "Current time: $current_time"
    else
        print_error "Failed to set timezone"
        return 1
    fi
}

# Function to configure NTP servers
configure_ntp() {
    print_step "Configuring NTP servers for Turkey..."
    
    # Backup original config
    if [ -f /etc/systemd/timesyncd.conf ]; then
        cp /etc/systemd/timesyncd.conf /etc/systemd/timesyncd.conf.backup
        print_info "Backed up original timesyncd.conf"
    fi
    
    # Configure Turkish NTP servers
    cat > /etc/systemd/timesyncd.conf << EOF
[Time]
NTP=tr.pool.ntp.org 0.tr.pool.ntp.org 1.tr.pool.ntp.org 2.tr.pool.ntp.org
FallbackNTP=pool.ntp.org 0.pool.ntp.org 1.pool.ntp.org
#RootDistanceMaxSec=5
#PollIntervalMinSec=32
#PollIntervalMaxSec=2048
EOF
    
    # Enable and restart timesyncd
    systemctl enable systemd-timesyncd
    systemctl restart systemd-timesyncd
    
    if [ $? -eq 0 ]; then
        print_success "NTP servers configured and service restarted"
    else
        print_error "Failed to configure NTP"
        return 1
    fi
}

# Function to show time sync status
show_time_status() {
    print_step "Checking time synchronization status..."
    
    # Show timedatectl status
    echo ""
    print_info "System Time Status:"
    timedatectl status
    
    echo ""
    print_info "Time Sync Status:"
    timedatectl show-timesync --all
    
    # Check if NTP is active
    if systemctl is-active --quiet systemd-timesyncd; then
        print_success "Time synchronization is active"
    else
        print_warning "Time synchronization service is not active"
    fi
}

# Function to test NTP connectivity
test_ntp_connectivity() {
    print_step "Testing connectivity to Turkish NTP servers..."
    
    local ntp_servers=("tr.pool.ntp.org" "0.tr.pool.ntp.org" "1.tr.pool.ntp.org")
    
    for server in "${ntp_servers[@]}"; do
        if timeout 5 ping -c 1 "$server" >/dev/null 2>&1; then
            print_success "✓ $server is reachable"
        else
            print_warning "✗ $server is not reachable"
        fi
    done
}

# Function to force time sync
force_time_sync() {
    print_step "Forcing immediate time synchronization..."
    
    # Stop timesyncd
    systemctl stop systemd-timesyncd
    
    # Force sync with ntpdate if available
    if command -v ntpdate >/dev/null 2>&1; then
        ntpdate -s tr.pool.ntp.org
        print_info "Used ntpdate for immediate sync"
    else
        print_warning "ntpdate not available, using timedatectl"
    fi
    
    # Start timesyncd again
    systemctl start systemd-timesyncd
    
    # Wait a moment and check
    sleep 3
    
    if timedatectl status | grep -q "synchronized: yes"; then
        print_success "Time synchronization successful"
    else
        print_warning "Time sync may take a few minutes to complete"
    fi
}

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    print_error "This script must be run as root"
    exit 1
fi

# Main execution
print_info "🕐 Configuring Timezone and NTP for Turkey"
echo ""

configure_timezone
configure_ntp
test_ntp_connectivity
force_time_sync
show_time_status

echo ""
print_success "✅ Timezone and NTP configuration completed!"
print_info "Your system is now configured for Turkey (Europe/Istanbul)"