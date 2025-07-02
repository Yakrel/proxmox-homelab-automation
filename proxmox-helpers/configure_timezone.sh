#!/bin/bash

# Timezone Configuration Script for Proxmox
# Sets timezone to Europe/Istanbul and configures NTP servers for Turkey

set -e

# Simple utility functions
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "ERROR: This script must be run as root"
        exit 1
    fi
}

# Function to set timezone
configure_timezone() {
    echo "Configuring timezone to Europe/Istanbul..."
    
    # Set timezone
    timedatectl set-timezone Europe/Istanbul
    
    if [ $? -eq 0 ]; then
        echo "✓ Timezone set to Europe/Istanbul"
        
        # Show current time
        local current_time=$(date)
        echo "Current time: $current_time"
    else
        echo "ERROR: Failed to set timezone"
        return 1
    fi
}

# Function to configure NTP servers
configure_ntp() {
    echo "Configuring NTP servers for Turkey..."
    
    # Check if chronyd is available (Proxmox uses chrony)
    if systemctl is-enabled chronyd >/dev/null 2>&1 || systemctl is-active chronyd >/dev/null 2>&1; then
        echo "Using chronyd for NTP configuration"
        
        # Backup original chrony config
        if [ -f /etc/chrony/chrony.conf ]; then
            cp /etc/chrony/chrony.conf /etc/chrony/chrony.conf.backup
            echo "Backed up original chrony.conf"
        fi
        
        # Configure Turkish NTP servers in chrony
        cat > /etc/chrony/chrony.conf << EOF
# Turkish NTP servers
pool tr.pool.ntp.org iburst
server 0.tr.pool.ntp.org iburst
server 1.tr.pool.ntp.org iburst
server 2.tr.pool.ntp.org iburst

# Fallback servers
pool 0.pool.ntp.org iburst
pool 1.pool.ntp.org iburst

# Record the rate at which the system clock gains/losses time.
driftfile /var/lib/chrony/chrony.drift

# Allow the system clock to be stepped in the first three updates
# if its offset is larger than 1 second.
makestep 1.0 3

# Enable kernel synchronization of the real-time clock (RTC).
rtcsync

# Enable hardware timestamping on all interfaces that support it.
#hwtimestamp *

# Increase the minimum number of selectable sources required to adjust
# the system clock.
#minsources 2

# Allow NTP client access from local network.
#allow 192.168.0.0/16

# Serve time even if not synchronized to a time source.
#local stratum 10

# Specify file containing keys for NTP authentication.
keyfile /etc/chrony/chrony.keys

# Get TAI-UTC offset and leap seconds from the system tz database.
leapsectz right/UTC

# Specify directory for log files.
logdir /var/log/chrony
EOF
        
        # Restart chronyd
        systemctl restart chronyd
        
        if [ $? -eq 0 ]; then
            echo "✓ Chrony NTP servers configured and service restarted"
        else
            echo "ERROR: Failed to configure Chrony"
            return 1
        fi
        
    # Fallback to timesyncd if available
    elif systemctl list-unit-files | grep -q systemd-timesyncd; then
        echo "Using systemd-timesyncd for NTP configuration"
        
        # Backup original config
        if [ -f /etc/systemd/timesyncd.conf ]; then
            cp /etc/systemd/timesyncd.conf /etc/systemd/timesyncd.conf.backup
            echo "Backed up original timesyncd.conf"
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
            echo "✓ NTP servers configured and service restarted"
        else
            echo "ERROR: Failed to configure NTP"
            return 1
        fi
    else
        echo "WARNING: Neither chronyd nor systemd-timesyncd is available"
        echo "Installing chrony..."
        apt update && apt install -y chrony
        
        # Configure chrony after installation
        configure_ntp
    fi
}

# Function to show time sync status
show_time_status() {
    echo "Checking time synchronization status..."
    
    # Show timedatectl status
    echo ""
    echo "System Time Status:"
    timedatectl status
    
    echo ""
    echo "NTP Synchronization Status:"
    if systemctl is-active --quiet chronyd; then
        if chronyc tracking >/dev/null 2>&1; then
            chronyc tracking | head -5
        else
            echo "Chrony tracking information not available yet"
        fi
    else
        echo "Using system time synchronization"
    fi
    
    # Check if NTP is active (check both chronyd and timesyncd)
    if systemctl is-active --quiet chronyd; then
        echo "✓ Chrony time synchronization is active"
    elif systemctl is-active --quiet systemd-timesyncd; then
        echo "✓ Systemd-timesyncd synchronization is active"
    else
        echo "WARNING: Time synchronization service is not active"
    fi
}

# Function to test NTP connectivity (using chrony sources)
test_ntp_connectivity() {
    echo "Checking NTP server connectivity..."
    
    # Wait a moment for chrony to start connecting
    sleep 5
    
    if systemctl is-active --quiet chronyd; then
        echo "Checking chrony sources status..."
        
        # Check if chrony has sources
        if chronyc sources >/dev/null 2>&1; then
            local source_count=$(chronyc sources | wc -l)
            if [ "$source_count" -gt 3 ]; then
                echo "✓ NTP sources are available and working"
                
                # Show active sources
                local active_sources=$(chronyc sources | grep -E '^\^[\*\+]' | wc -l)
                if [ "$active_sources" -gt 0 ]; then
                    echo "✓ $active_sources NTP sources are actively synchronizing"
                else
                    echo "NTP sources are connecting (this may take a few minutes)"
                fi
            else
                echo "WARNING: NTP sources are still connecting..."
            fi
        else
            echo "WARNING: Chrony is starting up, sources not ready yet"
        fi
    else
        echo "WARNING: Chrony service is not running"
    fi
}

# Function to force time sync
force_time_sync() {
    echo "Forcing immediate time synchronization..."
    
    # Check which service is running and force sync accordingly
    if systemctl is-active --quiet chronyd; then
        echo "Using chrony for immediate sync"
        # Wait a bit more for chrony to initialize properly
        sleep 3
        # Try to force sync quietly without showing warnings
        chronyd -q 'pool tr.pool.ntp.org iburst' >/dev/null 2>&1 || chronyc makestep >/dev/null 2>&1
    elif systemctl is-active --quiet systemd-timesyncd; then
        # Stop timesyncd
        systemctl stop systemd-timesyncd
        
        # Force sync with ntpdate if available
        if command -v ntpdate >/dev/null 2>&1; then
            ntpdate -s tr.pool.ntp.org
            echo "Used ntpdate for immediate sync"
        else
            echo "WARNING: ntpdate not available, using timedatectl"
        fi
        
        # Start timesyncd again
        systemctl start systemd-timesyncd
    else
        echo "WARNING: No time sync service is running"
        return 1
    fi
    
    # Wait a moment and check
    sleep 3
    
    if timedatectl status | grep -q "synchronized: yes"; then
        echo "✓ Time synchronization successful"
    else
        echo "WARNING: Time sync may take a few minutes to complete"
    fi
}

# Check if running as root
check_root

# Main execution
echo "Configuring Timezone and NTP for Turkey"
echo ""

configure_timezone
configure_ntp
test_ntp_connectivity
force_time_sync
show_time_status

echo ""
echo "✓ Timezone and NTP configuration completed!"
echo "Your system is now configured for Turkey (Europe/Istanbul)"