#!/bin/bash

# Dev LXC terminal experience shared by full deploys and fast redeploys.
# Keeps the Proxmox/root login shell on Bash while making code-server's
# integrated terminal use Zsh with Oh My Zsh and the workstation's Tokyo Night palette.

deploy_dev_terminal() {
    local ct_id="$1"
    local guest_script remote_script
    local hindsight_api_key="" ai_tmp=""
    local ai_env_enc="$WORK_DIR/docker/ai/.env.enc"

    if [[ ! -f "$ai_env_enc" ]]; then
        print_error "docker/ai/.env.enc is required for Dev configuration"
        return 1
    fi

    ai_tmp=$(mktemp)
    register_runtime_temp_file "$ai_tmp"
    if ! decrypt_openssl_file "$ai_env_enc" "$ai_tmp" "${ENV_ENC_KEY:-${KEY:-}}"; then
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
# installed tools before changing terminal configuration.
for command_name in zsh git eza batcat zoxide btop; do
    command -v "$command_name" >/dev/null 2>&1 || {
        echo "Missing required Dev terminal command: $command_name" >&2
        exit 1
    }
done

workbench_dir=/usr/lib/code-server/lib/vscode/out/vs/code/browser/workbench
required_files=(
    /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh
    /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
    /root/.oh-my-zsh/oh-my-zsh.sh
    /root/.oh-my-zsh/themes/robbyrussell.zsh-theme
    /root/.oh-my-zsh/plugins/git/git.plugin.zsh
    "$workbench_dir/workbench.html"
    "$workbench_dir/JetBrainsMonoNerdFontMono-Regular.ttf"
)
for required_file in "${required_files[@]}"; do
    [[ -f "$required_file" ]] || {
        echo "Missing required Dev terminal file: $required_file" >&2
        exit 1
    }
done

cat > "$workbench_dir/dev-terminal-font.css" <<'FONT_CSS'
@font-face {
  font-family: "Dev JetBrainsMono Nerd Font Mono";
  src: url("./JetBrainsMonoNerdFontMono-Regular.ttf") format("truetype");
  font-style: normal;
  font-weight: 100 900;
  font-display: swap;
}
FONT_CSS

python3 - "$workbench_dir/workbench.html" <<'PYTHON'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
start = "<!-- dev-terminal-font:start -->"
end = "<!-- dev-terminal-font:end -->"
stylesheet = (
    f"\t\t{start}\n"
    '\t\t<link rel="stylesheet" href="{{WORKBENCH_WEB_BASE_URL}}'
    '/out/vs/code/browser/workbench/dev-terminal-font.css">\n'
    f"\t\t{end}"
)
workbench_stylesheet = (
    '\t\t<link rel="stylesheet" href="{{WORKBENCH_WEB_BASE_URL}}'
    '/out/vs/code/browser/workbench/workbench.css">'
)

html = path.read_text()
html = re.sub(
    rf"\n?\s*{re.escape(start)}.*?{re.escape(end)}",
    "",
    html,
    flags=re.DOTALL,
)
if html.count(workbench_stylesheet) != 1:
    raise SystemExit("Could not locate the code-server workbench stylesheet")
path.write_text(html.replace(workbench_stylesheet, f"{workbench_stylesheet}\n{stylesheet}"))
PYTHON

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
eval "$(omp completions zsh)"

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
  "terminal.integrated.fontFamily": "'Dev JetBrainsMono Nerd Font Mono', monospace",
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

# Reconcile Oh My Pi Hindsight memory configuration. Oh My Pi also writes this
# file, so parse and re-emit YAML instead of patching text.
install -d -m 0700 /root/.omp/agent
# The key stays in the environment, never in a process argument list.
python3 - <<'OMP_CONFIG'
import os
from pathlib import Path

import yaml

api_key = os.environ["HINDSIGHT_API_KEY"]
config_path = Path("/root/.omp/agent/config.yml")
config = (yaml.safe_load(config_path.read_text(encoding="utf-8")) if config_path.exists() else None) or {}

config.setdefault("memory", {})["backend"] = "hindsight"
hindsight = config.setdefault("hindsight", {})
hindsight.update({
    "apiUrl": "http://192.168.1.104:8888",
    "bankId": "main",
    "scoping": "per-project-tagged",
    # Retain every 2 user turns with one preceding turn of conversational context.
    "retainMode": "last-turn",
    "retainEveryNTurns": 2,
    "retainOverlapTurns": 1,
})
hindsight["apiToken"] = api_key
for key in ("autoRecall", "autoRetain", "retainUpdateMode"):
    hindsight.pop(key, None)

config_path.write_text(yaml.safe_dump(config, sort_keys=False), encoding="utf-8")
config_path.chmod(0o600)
OMP_CONFIG

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
        "$ct_id" "lxc-dev" "$ai_tmp" "code-server*,beszel*"; then
        print_error "Failed to configure the Dev Beszel agent"
        return 1
    fi
    rm -f "$ai_tmp"
    print_success "Dev terminal and Beszel agent reconciled"
}
