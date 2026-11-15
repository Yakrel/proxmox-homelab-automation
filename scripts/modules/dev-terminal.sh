#!/bin/bash

# Dev LXC terminal and Claude Code memory configuration shared by full deploys
# and fast redeploys. Keeps the Proxmox/root login shell on Bash while
# configuring Zsh with Oh My Zsh and the Hindsight plugin settings.

deploy_dev_terminal() {
    local ct_id="$1"
    local guest_script remote_script
    local hindsight_api_key="" ai_tmp="" # gitleaks:allow
    local ai_env_enc="$WORK_DIR/docker/ai/.env.enc"

    if [[ ! -f "$ai_env_enc" ]]; then
        print_error "docker/ai/.env.enc is required for Dev configuration"
        return 1
    fi

    ai_tmp=$(mktemp)
    register_runtime_temp_file "$ai_tmp"
    if ! decrypt_env_file "$ai_env_enc" "$ai_tmp"; then
        rm -f "$ai_tmp"
        print_error "Failed to decrypt docker/ai/.env.enc for Dev configuration"
        return 1
    fi
    hindsight_api_key=$(get_env_value "HINDSIGHT_API_KEY" "$ai_tmp")
    [[ -n "$hindsight_api_key" ]] || {
        print_error "HINDSIGHT_API_KEY is empty in docker/ai/.env.enc"
        return 1
    }

    guest_script=$(mktemp /tmp/dev-terminal-setup.XXXXXX)
    register_runtime_temp_file "$guest_script"
    remote_script="/tmp/dev-terminal-setup.sh"

    cat > "$guest_script" <<'GUEST_SCRIPT'
#!/bin/bash
set -euo pipefail

# Provisioning lives in lxc-manager.sh. Both redeploy paths validate the
# installed tools before changing configuration.
export PATH="/root/.local/bin:/usr/local/bin:$PATH"
for command_name in zsh git eza batcat zoxide btop claude paseo; do
    command -v "$command_name" >/dev/null 2>&1 || {
        echo "Missing required Dev terminal command: $command_name" >&2
        exit 1
    }
done

required_files=(
    /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh
    /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
    /root/.oh-my-zsh/oh-my-zsh.sh
    /root/.oh-my-zsh/themes/robbyrussell.zsh-theme
    /root/.oh-my-zsh/plugins/git/git.plugin.zsh
    /usr/lib/systemd/systemd-socket-proxyd
)
for required_file in "${required_files[@]}"; do
    [[ -f "$required_file" ]] || {
        echo "Missing required Dev terminal file: $required_file" >&2
        exit 1
    }
done

# Debian exposes the bat package as /usr/bin/batcat. Keep the familiar `bat`
# command name used by the NixOS shell configuration.
ln -sfn /usr/bin/batcat /usr/local/bin/bat

cat > /root/.zshrc <<'ZSH_CONFIG'
export PATH="$HOME/.local/bin:/usr/local/bin:$PATH"
export ZSH="$HOME/.oh-my-zsh"

ZSH_THEME="robbyrussell"
plugins=(git)
zstyle ':omz:update' mode disabled

source "$ZSH/oh-my-zsh.sh"

eval "$(zoxide init zsh)"

# Match Home Manager's eza Zsh integration plus the explicit workstation aliases.
alias eza='eza --icons=auto'
alias ls='eza'
alias ll='eza -lh'
alias la='eza -la'
alias lt='eza --tree'
alias lla='eza -la'
alias tree='eza --tree'
alias cat='bat'

source /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh
source /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

# Keep encryption key assignments out of the history even without a leading
# space. The command still runs; only the history line is dropped.
zshaddhistory() { [[ $1 != *KEY=* ]]; }
ZSH_CONFIG

# Claude Code reaches Hindsight through the hindsight-coding-agents hooks that
# lxc-manager.sh installs. Each project gets its own bank named after its
# directory, and the same name is used by every machine and agent, so they
# share one memory per project. Everything except the server, the bank name,
# secret redaction and autoInject stays on the plugin's defaults. autoInject
# is "pages" because the default "reflect" runs an LLM synthesis on the first
# prompt of every session (18-20 s, often a timeout), while "pages" injects
# page search hits in milliseconds. Memory Defense is a per-bank setting with
# no server-wide switch, so the plugin writes it into every bank it creates.
# The key stays in the environment, never in a process argument list.
install -d -m 0700 /root/.hindsight
python3 - <<'PLUGIN_CONFIG'
import json
import os
from pathlib import Path

plugin_config_path = Path("/root/.hindsight/coding-agent.json")
plugin_config_path.touch(mode=0o600)
plugin_config_path.write_text(json.dumps({
    "serverMode": "self-hosted",
    "apiUrl": "http://192.168.1.104:8888",
    "apiToken": os.environ["HINDSIGHT_API_KEY"],
    "bankIdTemplate": "{gitProject}",
    "autoInject": "pages",
    "defaultBankConfig": {
        "memory_defense": {"enabled": True, "rules": [{"on": "sensitive_data", "action": "redact"}]},
    },
}, indent=2) + "\n", encoding="utf-8")
plugin_config_path.chmod(0o600)
PLUGIN_CONFIG
GUEST_SCRIPT

    pct push "$ct_id" "$guest_script" "$remote_script"
    pct exec "$ct_id" -- chmod 0700 "$remote_script"

    if ! pct exec "$ct_id" -- env \
        HINDSIGHT_API_KEY="$hindsight_api_key" \
        "$remote_script"; then
        pct exec "$ct_id" -- rm -f "$remote_script" || true
        print_error "Failed to configure dev terminal"
        return 1
    fi

    pct exec "$ct_id" -- rm -f "$remote_script"

    if ! deploy_lxc_beszel_agent \
        "$ct_id" "lxc-dev" "$ai_tmp" "paseo*,beszel*"; then
        print_error "Failed to configure the Dev Beszel agent"
        return 1
    fi
    rm -f "$ai_tmp"
    print_success "Dev terminal and Beszel agent reconciled"
}
