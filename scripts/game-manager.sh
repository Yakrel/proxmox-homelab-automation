#!/bin/bash

# Game Server Manager - Ensures only one game server runs at a time

# Dynamic paths - will be in gameservers container
DOCKER_DIR="/root"

# Available game profiles
GAMES=("palworld" "satisfactory")

# Map profiles to container names for status checking
declare -A CONTAINER_NAMES=(
    ["palworld"]="palworld-server"
    ["satisfactory"]="satisfactory-server"
)

show_current_game() {
    echo "=== Current Game Status ==="
    local running_found=false
    
    for game in "${GAMES[@]}"; do
        local container="${CONTAINER_NAMES[$game]}"
        # Check if container exists and is running
        if docker ps --format '{{.Names}}' | grep -q "^${container}$"; then
            echo "✓ $game is RUNNING"
            running_found=true
        fi
    done
    
    if [ "$running_found" = false ]; then
        echo "No game servers are currently running"
        return 1
    fi
    return 0
}

stop_all_games() {
    echo "Stopping all game servers..."
    
    cd "$DOCKER_DIR" || { echo "Error: Cannot find docker directory $DOCKER_DIR"; return 1; }

    for game in "${GAMES[@]}"; do
        echo "  Stopping $game..."
        # Stop specific profile services only
        docker compose --profile "$game" stop
    done
    
    echo "All games stopped."
}

start_game() {
    local game="$1"
    local valid_game=false

    # Validate game name
    for g in "${GAMES[@]}"; do
        if [[ "$g" == "$game" ]]; then
            valid_game=true
            break
        fi
    done

    if [ "$valid_game" = false ]; then
        echo "Error: Unknown game '$game'"
        echo "Available games: ${GAMES[*]}"
        return 1
    fi

    # Check if base gaming stack is running (gameserver-net network must exist)
    if ! docker network inspect gameserver-net &>/dev/null; then
        echo "✗ Error: Base gaming stack is not running!"
        echo "  Please run 'docker compose up -d' in $DOCKER_DIR first to start:"
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
        if pct exec "$CONTAINER_ID" -- bash -c "cd $DOCKER_DIR && docker compose --profile $game up -d"; then
            echo "✓ $game server started successfully"
        else
            echo "✗ Failed to start $game server"
            return 1
        fi
    else
        # We're inside container
        cd "$DOCKER_DIR" || return 1
        if docker compose --profile "$game" up -d; then
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
    for game in "${GAMES[@]}"; do
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
                if [[ "$choice" =~ ^[0-9]+$ ]] && [[ $choice -gt 0 ]] && [[ $choice -le ${#GAMES[@]} ]]; then
                    local selected_game="${GAMES[$((choice-1))]}"
                    start_game "$selected_game"
                else
                    # Check if typed name matches
                    local match=false
                    for g in "${GAMES[@]}"; do
                        if [[ "$g" == "$choice" ]]; then
                            start_game "$choice"
                            match=true
                            break
                        fi
                    done
                    if [ "$match" = false ]; then
                        echo "Invalid selection: $choice"
                    fi
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
            echo "Available games: ${GAMES[*]}"
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
        echo "Available games: ${GAMES[*]}"
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
        echo "Available games: ${GAMES[*]}"
        exit 1
        ;;
esac