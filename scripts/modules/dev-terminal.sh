#!/bin/bash

# Dev LXC terminal experience shared by full deploys and fast redeploys.
# Keeps the Proxmox/root login shell on Bash while making code-server's
# integrated terminal use Fish with the desktop's Tokyo Night palette.

deploy_dev_terminal() {
    local ct_id="$1"
    local guest_script remote_script

    guest_script=$(mktemp /tmp/dev-terminal-setup.XXXXXX)
    register_runtime_temp_file "$guest_script"
    remote_script="/tmp/dev-terminal-setup.sh"

    cat > "$guest_script" <<'GUEST_SCRIPT'
#!/bin/bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

# Keep the server lean: code-server is the terminal emulator, so only install
# shell/CLI tooling. Kitty and desktop packages intentionally stay on NixOS.
apt-get update -qq
apt-get install -y -qq fish eza bat zoxide btop

# Debian ships bat as /usr/bin/batcat. Match the NixOS command name so the same
# Fish alias can be used on both systems.
ln -sfn /usr/bin/batcat /usr/local/bin/bat

install -d -m 0755 /root/.config/fish
cat > /root/.config/fish/config.fish <<'FISH_CONFIG'
if status is-interactive
    set -g fish_greeting
    set -gx PATH /root/.local/bin /usr/local/bin $PATH

    alias ls 'eza --icons'
    alias ll 'eza -lh --icons'
    alias la 'eza -la --icons'
    alias tree 'eza --tree --icons'
    alias cat 'bat'

    zoxide init fish | source
end
FISH_CONFIG

# code-server stores machine-scoped settings under its data directory. That
# directory is already symlinked to /fastpool/config/code-server/data, so these
# settings persist without overwriting the user's editor preferences.
install -d -m 0755 /root/.local/share/code-server/Machine
cat > /root/.local/share/code-server/Machine/settings.json <<'CODE_SERVER_SETTINGS'
{
  "terminal.integrated.defaultProfile.linux": "fish",
  "terminal.integrated.profiles.linux": {
    "fish": {
      "path": "/usr/bin/fish"
    }
  },
  "terminal.integrated.fontFamily": "'JetBrainsMono Nerd Font', monospace",
  "terminal.integrated.fontSize": 11,
  "workbench.colorCustomizations": {
    "terminal.background": "#1a1b26",
    "terminal.foreground": "#a9b1d6",
    "terminal.selectionBackground": "#28344a",
    "terminalCursor.foreground": "#c0caf5",
    "terminal.ansiBlack": "#15161e",
    "terminal.ansiBrightBlack": "#414868",
    "terminal.ansiRed": "#f7768e",
    "terminal.ansiBrightRed": "#f7768e",
    "terminal.ansiGreen": "#9ece6a",
    "terminal.ansiBrightGreen": "#9ece6a",
    "terminal.ansiYellow": "#e0af68",
    "terminal.ansiBrightYellow": "#e0af68",
    "terminal.ansiBlue": "#7aa2f7",
    "terminal.ansiBrightBlue": "#7aa2f7",
    "terminal.ansiMagenta": "#bb9af7",
    "terminal.ansiBrightMagenta": "#bb9af7",
    "terminal.ansiCyan": "#7dcfff",
    "terminal.ansiBrightCyan": "#7dcfff",
    "terminal.ansiWhite": "#a9b1d6",
    "terminal.ansiBrightWhite": "#c0caf5"
  }
}
CODE_SERVER_SETTINGS

for command_name in fish eza bat zoxide btop; do
    command -v "$command_name" >/dev/null 2>&1 || {
        echo "Missing required dev terminal command: $command_name" >&2
        exit 1
    }
done

python3 -m json.tool /root/.local/share/code-server/Machine/settings.json >/dev/null

# The integrated terminal uses Fish explicitly; administrative/root login paths
# must remain on Bash (or another non-Fish shell).
root_shell=$(getent passwd root | cut -d: -f7)
case "$root_shell" in
    */fish)
        echo "Root login shell must not be Fish: $root_shell" >&2
        exit 1
        ;;
esac

systemctl is-active code-server@root >/dev/null 2>&1
GUEST_SCRIPT

    pct push "$ct_id" "$guest_script" "$remote_script"
    pct exec "$ct_id" -- chmod 0700 "$remote_script"

    if ! pct exec "$ct_id" -- "$remote_script"; then
        pct exec "$ct_id" -- rm -f "$remote_script" || true
        print_error "Failed to configure dev terminal"
        return 1
    fi

    pct exec "$ct_id" -- rm -f "$remote_script"
    print_success "Dev code-server terminal reconciled"
}
