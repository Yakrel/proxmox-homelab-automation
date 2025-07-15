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

    local jails=$(fail2ban-client status | grep "Jail list:" | sed -E 's/.*Jail list:\s*//' | sed 's/,//g')
    local banned_ips_array=()
    local ip_jail_map=()
    local counter=1

    if [ -z "$jails" ]; then
        echo "No active Fail2ban jails found."
        return 0
    fi

    echo "Currently Banned IPs:"
    echo "---------------------"
    for jail in $jails; do
        local banned_for_jail=$(fail2ban-client status "$jail" | grep "Currently banned:" | sed -E 's/.*Currently banned:\s*//')
        if [ -n "$banned_for_jail" ]; then
            for ip in $banned_for_jail; do
                echo "  $counter) $ip (Jail: $jail)"
                banned_ips_array+=("$ip")
                ip_jail_map+=("$jail")
                counter=$((counter + 1))
            done
        fi
    done

    if [ ${#banned_ips_array[@]} -eq 0 ]; then
        echo "No IPs currently banned across all jails."
        echo
        return 0
    fi

    echo
    read -p "Enter the number of the IP to unban (or 'q' to cancel): " choice

    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#banned_ips_array[@]}" ]; then
        local selected_ip="${banned_ips_array[$((choice - 1))]}"
        local selected_jail="${ip_jail_map[$((choice - 1))]}"
        echo "[INFO] Attempting to unban $selected_ip from $selected_jail..."
        fail2ban-client set "$selected_jail" unbanip "$selected_ip"
        if [ $? -eq 0 ]; then
            echo "[OK] Successfully unbanned $selected_ip from $selected_jail."
        else
            echo "[ERROR] Failed to unban $selected_ip from $selected_jail. Check logs."
        fi
    elif [[ "$choice" == "q" || "$choice" == "Q" ]]; then
        echo "[INFO] Unban operation cancelled."
    else
        echo "[ERROR] Invalid choice. Please enter a valid number or 'q'."
    fi
    echo
}

show_statistics() {
    echo "======================================="
    echo "      Fail2ban Statistics"
    echo "======================================="
    echo

    local jails=$(fail2ban-client status | grep "Jail list:" | sed -E 's/.*Jail list:\s*//' | sed 's/,//g')

    if [ -z "$jails" ]; then
        echo "No active Fail2ban jails found."
        return 0
    fi

    echo "Overall Fail2ban Statistics:"
    echo "----------------------------"
    fail2ban-client status
    echo

    echo "Jail-specific Statistics:"
    echo "-------------------------"
    for jail in $jails; do
        echo "Jail: $jail"
        fail2ban-client status "$jail"
        echo
    done
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
    echo "   3) Show Statistics"
    echo "---------------------------------------"
    echo "   b) Back to Main Menu"
    echo "   q) Quit"
    echo
    read -p "   Enter your choice: " choice

    case $choice in
        1) list_jails_and_bans; press_enter_to_continue ;;
        2) unban_ip; press_enter_to_continue ;;
        3) show_statistics; press_enter_to_continue ;;
        b|B) break ;;
        q|Q) echo "Exiting."; exit 0 ;;
        *) echo "[ERROR] Invalid choice. Please try again."; sleep 2 ;;
    esac
done
