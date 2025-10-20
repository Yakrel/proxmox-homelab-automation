#!/bin/bash

# Strict error handling
set -euo pipefail

# --- Load Shared Functions ---
WORK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)"
source "$WORK_DIR/scripts/helper-functions.sh"

# --- Fail2ban Functions ---

list_jails_and_bans() {
    echo "======================================="
    echo "      Fail2ban Banned IPs (Detailed)"
    echo "======================================="
    echo

    local jails
    jails=$(fail2ban-client status | grep "Jail list:" | sed -E 's/.*Jail list:\s*//' | sed 's/,//g')

    if [ -z "$jails" ]; then
        echo "No active Fail2ban jails found."
        return 0
    fi

    local total_banned=0
    echo "Currently Banned IPs:"
    echo "---------------------"
    
    for jail in $jails; do
        local jail_status
        jail_status=$(fail2ban-client status "$jail")
        local banned_ips
        banned_ips=$(echo "$jail_status" | grep "Banned IP list:" | sed -E 's/.*Banned IP list:\s*//')
        local currently_banned
        currently_banned=$(echo "$jail_status" | grep "Currently banned:" | sed -E 's/.*Currently banned:\s*//')
        
        if [ -n "$banned_ips" ] && [ "$currently_banned" -gt 0 ] 2>/dev/null; then
            for ip in $banned_ips; do
                total_banned=$((total_banned + 1))
                
                # Try to get ban start time from logs
                local ban_time
                ban_time=$(journalctl -u fail2ban.service --since "7 days ago" -q | grep -E "Ban.*$ip.*$jail" | tail -1 | awk '{print $1, $2}')
                if [ -z "$ban_time" ]; then
                    ban_time="unknown time"
                else
                    ban_time="$(date -d "$ban_time" '+%H:%M %d/%m' || echo "$ban_time")"
                fi
                
                # Get attempt count
                local attempts
                attempts=$(journalctl -u fail2ban.service --since "7 days ago" -q | grep -c "$ip" || echo "?")
                
                printf "  %-15s (%-8s jail) - Banned: %-12s [%s attempts]\n" "$ip" "$jail" "$ban_time" "$attempts"
            done
        fi
    done
    
    if [ $total_banned -eq 0 ]; then
        echo "  No IPs currently banned across all jails."
    else
        echo
        echo "Total banned IPs: $total_banned"
    fi
    echo
}

unban_ip() {
    echo "======================================="
    echo "      Unban IP Address"
    echo "======================================="
    echo

    local jails
    jails=$(fail2ban-client status | grep "Jail list:" | sed -E 's/.*Jail list:\s*//' | sed 's/,//g')
    local banned_ips_array=()
    local ip_jail_map=()
    local counter=1

    if [ -z "$jails" ]; then
        echo "No active Fail2ban jails found."
        return 0
    fi

    echo "Select IP to unban:"
    echo "-------------------"
    for jail in $jails; do
        local jail_status
        jail_status=$(fail2ban-client status "$jail")
        local banned_ips
        banned_ips=$(echo "$jail_status" | grep "Banned IP list:" | sed -E 's/.*Banned IP list:\s*//')
        local currently_banned
        currently_banned=$(echo "$jail_status" | grep "Currently banned:" | sed -E 's/.*Currently banned:\s*//')
        
        if [ -n "$banned_ips" ] && [ "$currently_banned" -gt 0 ]; then
            for ip in $banned_ips; do
                # Get attempt count from logs
                local attempts
                attempts=$(journalctl -u fail2ban.service --since "7 days ago" -q | grep -c "$ip" || echo "?")
                
                # Get ban time
                local ban_time
                ban_time=$(journalctl -u fail2ban.service --since "7 days ago" -q | grep -E "Ban.*$ip.*$jail" | tail -1 | awk '{print $1, $2}')
                if [ -z "$ban_time" ]; then
                    ban_time="unknown"
                else
                    ban_time="$(date -d "$ban_time" '+%H:%M %d/%m' || echo "$ban_time")"
                fi
                
                printf "  %d) %-15s (%-8s jail) - %s attempts - Banned %s\n" "$counter" "$ip" "$jail" "$attempts" "$ban_time"
                banned_ips_array+=("$ip")
                ip_jail_map+=("$jail")
                counter=$((counter + 1))
            done
        fi
    done

    if [ ${#banned_ips_array[@]} -eq 0 ]; then
        echo "  No IPs currently banned across all jails."
        echo
        return 0
    fi

    echo
    read -r -p "Enter number to unban (or 'q' to cancel): " choice

    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#banned_ips_array[@]}" ]; then
        local selected_ip="${banned_ips_array[$((choice - 1))]}"
        local selected_jail="${ip_jail_map[$((choice - 1))]}"
        echo "[INFO] Unbanning $selected_ip from $selected_jail..."
        if fail2ban-client set "$selected_jail" unbanip "$selected_ip"; then
            echo "[SUCCESS] $selected_ip successfully unbanned from $selected_jail."
        else
            echo "[ERROR] Failed to unban $selected_ip. Check fail2ban logs."
        fi
    elif [[ "$choice" == "q" || "$choice" == "Q" ]]; then
        echo "[INFO] Unban cancelled."
    else
        echo "[ERROR] Invalid choice. Enter a number or 'q'."
    fi
    echo
}

show_recent_attempts() {
    echo "======================================="
    echo "      Recent Failed Attempts (24h)"
    echo "======================================="
    echo

    echo "Analyzing recent failed login attempts..."
    echo
    
    # Get recent fail2ban activity from journal
    local log_output
    log_output=$(journalctl -u fail2ban.service --since "24 hours ago" -q | grep -E "(Ban|Found)" | tail -20)
    
    if [ -z "$log_output" ]; then
        echo "No recent fail2ban activity found in the last 24 hours."
        echo
        return 0
    fi
    
    echo "Recent Activity Summary:"
    echo "------------------------"
    
    # Extract unique IPs and their attempt counts
    local temp_file
    temp_file=$(mktemp)
    echo "$log_output" | grep -oE "[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}" | sort | uniq -c | sort -nr > "$temp_file"
    
    local counter=1
    while read -r count ip; do
        if [ $counter -le 10 ]; then  # Show top 10
            # Check if IP is currently banned
            local status="active"
            local jails
            jails=$(fail2ban-client status | grep "Jail list:" | sed -E 's/.*Jail list:\s*//' | sed 's/,//g')
            for jail in $jails; do
                if fail2ban-client status "$jail" | grep -q "$ip"; then
                    status="BANNED"
                    break
                fi
            done
            
            printf "  %-15s  %2d attempts  [%s]\n" "$ip" "$count" "$status"
            counter=$((counter + 1))
        fi
    done < "$temp_file"
    
    rm -f "$temp_file"
    echo
}

show_statistics() {
    echo "======================================="
    echo "      Fail2ban Statistics"
    echo "======================================="
    echo

    local jails
    jails=$(fail2ban-client status | grep "Jail list:" | sed -E 's/.*Jail list:\s*//' | sed 's/,//g')

    if [ -z "$jails" ]; then
        echo "No active Fail2ban jails found."
        return 0
    fi

    echo "Jail Status Summary:"
    echo "-------------------"
    for jail in $jails; do
        local jail_status
        jail_status=$(fail2ban-client status "$jail")
        local currently_failed
        currently_failed=$(echo "$jail_status" | grep "Currently failed:" | sed -E 's/.*Currently failed:\s*//')
        local total_failed
        total_failed=$(echo "$jail_status" | grep "Total failed:" | sed -E 's/.*Total failed:\s*//')
        local currently_banned
        currently_banned=$(echo "$jail_status" | grep "Currently banned:" | sed -E 's/.*Currently banned:\s*//' | wc -w)
        local total_banned
        total_banned=$(echo "$jail_status" | grep "Total banned:" | sed -E 's/.*Total banned:\s*//')
        
        printf "  %-12s | Failed: %-3s (total: %-4s) | Banned: %-2s (total: %-4s)\n" "[$jail]" "${currently_failed:-0}" "${total_failed:-0}" "$currently_banned" "${total_banned:-0}"
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
    echo "   1) Show Banned IPs (Detailed)"
    echo "   2) Unban IP Address"
    echo "   3) Show Recent Attempts (24h)"
    echo "   4) Show Jail Statistics"
    echo "---------------------------------------"
    echo "   b) Back to Main Menu"
    echo "   q) Quit"
    echo
    read -r -p "   Enter your choice: " choice

    case $choice in
        1) list_jails_and_bans; press_enter_to_continue ;;
        2) unban_ip; press_enter_to_continue ;;
        3) show_recent_attempts; press_enter_to_continue ;;
        4) show_statistics; press_enter_to_continue ;;
        b|B) break ;;
        q|Q) echo "Exiting."; exit 0 ;;
        *) print_error "Invalid choice. Please try again." ;;
    esac
done
