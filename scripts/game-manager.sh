#!/bin/bash

# Game Server Manager - Ensures only one game server runs at a time

# Dynamic paths - will be in gameservers container
DOCKER_DIR="/root/docker"

# Available games - add new games here
declare -A GAMES=(
    ["palworld"]="palworld.yml"
    ["satisfactory"]="satisfactory.yml"
)

show_current_game() {
    echo "=== Current Game Status ==="
    
    for game in "${!GAMES[@]}"; do
        compose_file="${GAMES[$game]}"
        if docker compose -f "$DOCKER_DIR/$compose_file" ps -q | grep -q .; then
            echo "✓ $game is RUNNING"
            return 0
        fi
    done
    
    echo "No game servers are currently running"
    return 1
}

stop_all_games() {
    echo "Stopping all game servers..."
    
    for game in "${!GAMES[@]}"; do
        compose_file="${GAMES[$game]}"
        if docker compose -f "$DOCKER_DIR/$compose_file" ps -q | grep -q .; then
            echo "  Stopping $game..."
            docker compose -f "$DOCKER_DIR/$compose_file" down --remove-orphans
        fi
    done
    
    echo "All games stopped."
}

start_game() {
    local game="$1"

    if [[ -z "${GAMES[$game]}" ]]; then
        echo "Error: Unknown game '$game'"
        echo "Available games: ${!GAMES[*]}"
        return 1
    fi

    compose_file="${GAMES[$game]}"

    # Check if base gaming stack is running (gameserver-net network must exist)
    if ! docker network inspect gameserver-net &>/dev/null; then
        echo "✗ Error: Base gaming stack is not running!"
        echo "  Please run 'docker-compose up -d' in $DOCKER_DIR first to start:"
        echo "  - Watchtower (auto-updates)"
        echo "  - Promtail (logging)"
        echo "  - gameserver-net network"
        return 1
    fi

    # Stop all games first
    stop_all_games
    
    # Start the selected game
    echo "Starting $game server..."
    
    # Simple detection: if 'pct' command exists, we're on PVE host
    if command -v pct &>/dev/null; then
        # We're on PVE host, execute in container
        if pct exec "$CONTAINER_ID" -- bash -c "cd $DOCKER_DIR && docker compose -f $compose_file up -d"; then
            echo "✓ $game server started successfully"
        else
            echo "✗ Failed to start $game server"
            return 1
        fi
    else
        # We're inside container
        cd "$DOCKER_DIR" || return 1
        if docker compose -f "$compose_file" up -d; then
            echo "✓ $game server started successfully"
        else
            echo "✗ Failed to start $game server"
            return 1
        fi
    fi
}

show_menu() {
    echo
    echo "=== Game Server Manager ==="
    show_current_game
    echo
    echo "Available Games:"
    local i=1
    for game in "${!GAMES[@]}"; do
        echo "  $i) $game"
        i=$((i + 1))
    done
    echo "  s) Stop all games"
    echo "  q) Quit"
    echo
}

interactive_mode() {
    while true; do
        show_menu
        read -r -p "Select game to run (or 's' to stop all, 'q' to quit): " choice
        
        case "$choice" in
            "s"|"S")
                stop_all_games
                ;;
            "q"|"Q")
                echo "Exiting..."
                break
                ;;
            *)
                # Convert number to game name
                local games_array
                mapfile -t games_array < <(printf '%s\n' "${!GAMES[@]}")
                if [[ "$choice" =~ ^[0-9]+$ ]] && [[ $choice -gt 0 ]] && [[ $choice -le ${#games_array[@]} ]]; then
                    local selected_game="${games_array[$((choice-1))]}"
                    start_game "$selected_game"
                elif [[ -n "${GAMES[$choice]}" ]]; then
                    start_game "$choice"
                else
                    echo "Invalid selection: $choice"
                fi
                ;;
        esac
        
        echo
        read -p "Press Enter to continue..." -r
    done
}

# Main logic
case "$1" in
    "start")
        if [[ -z "$2" ]]; then
            echo "Usage: $0 start <game_name>"
            echo "Available games: ${!GAMES[*]}"
            exit 1
        fi
        start_game "$2"
        ;;
    "stop")
        stop_all_games
        ;;
    "status")
        show_current_game
        ;;
    "list")
        echo "Available games: ${!GAMES[*]}"
        ;;
    "")
        interactive_mode
        ;;
    *)
        echo "Usage: $0 [start|stop|status|list] [game_name]"
        echo "  start <game>  - Start a specific game (stops others)"
        echo "  stop          - Stop all games"
        echo "  status        - Show current running games"
        echo "  list          - List available games"
        echo "  (no args)     - Interactive mode"
        echo
        echo "Available games: ${!GAMES[*]}"
        exit 1
        ;;
esac