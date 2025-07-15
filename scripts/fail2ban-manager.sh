#!/bin/bash

set -e

# --- Generic Helper Functions ---
press_enter_to_continue() {
    echo
    read -p "Press Enter to continue..."
}

# --- Fail2ban Functions ---

list_jails_and_bans() {
    echo "======================================="
    echo "      Fail2ban Status"
    echo "======================================="
    echo

    local jails=$(fail2ban-client status | grep "Jail list:" | sed -E 's/.*Jail list:\s*//' | sed 's/,//g')

    if [ -z "$jails" ]; then
        echo "No active Fail2ban jails found."
        return 0
    fi

    echo "Active Jails:"
    for jail in $jails; do
        echo "  - $jail"
        local banned_ips=$(fail2ban-client status "$jail" | grep "Currently banned:" | sed -E 's/.*Currently banned:\s*//')
        if [ -n "$banned_ips" ]; then
            echo "    Banned IPs: $banned_ips"
        else
            echo "    No IPs currently banned in this jail."
        fi
    done
    echo
}

unban_ip() {
    echo "======================================="
    echo "      Fail2ban Unban IP"
    echo "======================================="
    echo

    read -p "Enter Jail name (e.g., sshd, proxmox): " jail_name
    read -p "Enter IP address to unban: " ip_address

    if [ -z "$jail_name" ] || [ -z "$ip_address" ]; then
        echo "[ERROR] Jail name and IP address cannot be empty."
        return 1
    fi

    echo "[INFO] Attempting to unban $ip_address from $jail_name..."
    fail2ban-client set "$jail_name" unbanip "$ip_address"
    if [ $? -eq 0 ]; then
        echo "[OK] Successfully unbanned $ip_address from $jail_name."
    else
        echo "[ERROR] Failed to unban $ip_address from $jail_name. Check jail name and IP."
    fi
    echo
}

# --- Main Menu ---

while true; do
    clear
    echo "======================================="
    echo "      Fail2ban Manager"
    echo "======================================="
    echo
    echo "   1) List Jails and Banned IPs"
    echo "   2) Unban an IP Address"
    echo "---------------------------------------"
    echo "   b) Back to Main Menu"
    echo "   q) Quit"
    echo
    read -p "   Enter your choice: " choice

    case $choice in
        1) list_jails_and_bans; press_enter_to_continue ;;
        2) unban_ip; press_enter_to_continue ;;
        b|B) break ;;
        q|Q) echo "Exiting."; exit 0 ;;
        *) echo "[ERROR] Invalid choice. Please try again."; sleep 2 ;;
    esac
done
