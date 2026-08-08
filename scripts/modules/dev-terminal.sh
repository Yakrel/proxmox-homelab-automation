#!/bin/bash

# Dev LXC terminal experience shared by full deploys and fast redeploys.
# Keeps the Proxmox/root login shell on Bash while making code-server's
# integrated terminal use Zsh with Oh My Zsh and the desktop's Tokyo Night palette.

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
apt-get install -y -qq zsh git zsh-autosuggestions zsh-syntax-highlighting eza bat zoxide btop

# Debian exposes the bat package as /usr/bin/batcat. Keep the familiar `bat`
# command name available without adding runtime validation logic.
ln -sfn /usr/bin/batcat /usr/local/bin/bat

# Reconcile Oh My Zsh without its interactive installer so both fresh deploys
# and fast redeploys follow the same idempotent path.
install -d -m 0755 /root/.oh-my-zsh
git -C /root/.oh-my-zsh init -q
git -C /root/.oh-my-zsh config remote.origin.url https://github.com/ohmyzsh/ohmyzsh.git
git -C /root/.oh-my-zsh config remote.origin.fetch '+refs/heads/master:refs/remotes/origin/master'
git -C /root/.oh-my-zsh fetch -q --depth=1 origin master
git -C /root/.oh-my-zsh reset -q --hard FETCH_HEAD

cat > /root/.zshrc <<'ZSH_CONFIG'
export PATH="$HOME/.local/bin:/usr/local/bin:$PATH"
export ZSH="$HOME/.oh-my-zsh"

ZSH_THEME="robbyrussell"
plugins=(git zoxide)
zstyle ':omz:update' mode disabled

source "$ZSH/oh-my-zsh.sh"

alias ls='eza --icons'
alias ll='eza -lh --icons'
alias la='eza -la --icons'
alias tree='eza --tree --icons'
alias cat='batcat'

source /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh
source /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
ZSH_CONFIG

# code-server stores machine-scoped settings under its data directory. That
# directory is already symlinked to /fastpool/config/code-server/data, so these
# settings persist without overwriting the user's editor preferences.
install -d -m 0755 /root/.local/share/code-server/Machine
cat > /root/.local/share/code-server/Machine/settings.json <<'CODE_SERVER_SETTINGS'
{
  "terminal.integrated.defaultProfile.linux": "zsh",
  "terminal.integrated.profiles.linux": {
    "zsh": {
      "path": "/usr/bin/zsh"
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
