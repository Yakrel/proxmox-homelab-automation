#!/bin/bash

# Dev LXC terminal experience shared by full deploys and fast redeploys.
# Keeps the Proxmox/root login shell on Bash while making code-server's
# integrated terminal use Zsh with Oh My Zsh and the workstation's Tokyo Night palette.

deploy_dev_terminal() {
    local ct_id="$1"
    local guest_script remote_script
    local hindsight_api_key=""
    local ai_env_enc="$WORK_DIR/docker/ai/.env.enc"

    if [[ -f "$ai_env_enc" ]]; then
        local ai_tmp
        ai_tmp=$(mktemp)
        register_runtime_temp_file "$ai_tmp"
        if ! decrypt_openssl_file "$ai_env_enc" "$ai_tmp" "${ENV_ENC_KEY:-${KEY:-}}"; then
            rm -f "$ai_tmp"
            print_error "Failed to decrypt docker/ai/.env.enc for dev terminal configuration"
            return 1
        fi
        hindsight_api_key=$(get_env_value "HINDSIGHT_API_KEY" "$ai_tmp")
        rm -f "$ai_tmp"
    fi

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

# code-server renders the terminal in the browser, so fonts installed only in
# the LXC are invisible to it. Serve the Nerd Font with the workbench instead.
workbench_dir=/usr/lib/code-server/lib/vscode/out/vs/code/browser/workbench
font_tmp=$(mktemp /tmp/JetBrainsMonoNerdFontMono.XXXXXX.ttf)
trap 'rm -f "$font_tmp"' EXIT
curl -fsSL \
    https://raw.githubusercontent.com/ryanoasis/nerd-fonts/master/patched-fonts/JetBrainsMono/Ligatures/JetBrainsMonoNerdFontMono-Regular.ttf \
    -o "$font_tmp"
install -m 0644 "$font_tmp" "$workbench_dir/JetBrainsMonoNerdFontMono-Regular.ttf"
rm -f "$font_tmp"
trap - EXIT

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

# Reconcile Oh My Pi Hindsight memory configuration
install -d -m 0700 /root/.omp/agent
python3 - "${HINDSIGHT_API_KEY:-}" <<'OMP_CONFIG'
import re
import sys
from pathlib import Path

api_key = sys.argv[1] if sys.argv[1] else ""
config_path = Path("/root/.omp/agent/config.yml")
content = config_path.read_text(encoding="utf-8") if config_path.exists() else ""

api_key_line = f"  apiToken: {api_key}\n" if api_key else ""
hindsight_block = f"""memory:
  backend: hindsight
hindsight:
  apiUrl: http://192.168.1.104:8888
{api_key_line}  bankId: main
  scoping: per-project-tagged
  retainMode: last-turn
  retainEveryNTurns: 2
  retainOverlapTurns: 1
"""

if "backend: hindsight" not in content:
    content = (content.rstrip() + "\n\n" + hindsight_block).lstrip()
else:
    # Clean up deprecated apiKey if present.
    content = re.sub(r"(?m)^  apiKey:[^\n]*\n?", "", content)
    if api_key:
        if re.search(r"(?m)^  apiToken:", content):
            content = re.sub(
                r"(?m)^  apiToken:[^\n]*$",
                f"  apiToken: {api_key}",
                content,
                count=1,
            )
        else:
            content = re.sub(
                r"(?m)^(hindsight:\s*)$",
                rf"\1\n{api_key_line.rstrip()}",
                content,
                count=1,
            )

    # Retain every 2 user turns with one preceding turn of conversational context.
    # Remove prior tuning first so repeated deployments remain idempotent.
    for key in (
        "autoRecall",
        "autoRetain",
        "retainMode",
        "retainUpdateMode",
        "retainEveryNTurns",
        "retainOverlapTurns",
    ):
        content = re.sub(
            rf"(?m)^  {re.escape(key)}:[^\n]*\n?",
            "",
            content,
        )

    retention_lines = "\n".join(
        (
            "  retainMode: last-turn",
            "  retainEveryNTurns: 2",
            "  retainOverlapTurns: 1",
        )
    )
    content, updated = re.subn(
        r"(?m)^(  scoping:[^\n]*)$",
        rf"\1\n{retention_lines}",
        content,
        count=1,
    )
    if updated != 1:
        raise RuntimeError("Unable to reconcile OMP retention settings")

config_path.write_text(content, encoding="utf-8")
config_path.chmod(0o600)
OMP_CONFIG
GUEST_SCRIPT

    pct push "$ct_id" "$guest_script" "$remote_script"
    pct exec "$ct_id" -- chmod 0700 "$remote_script"

    if ! pct exec "$ct_id" -- env HINDSIGHT_API_KEY="$hindsight_api_key" "$remote_script"; then
        pct exec "$ct_id" -- rm -f "$remote_script" || true
        print_error "Failed to configure dev terminal"
        return 1
    fi

    pct exec "$ct_id" -- rm -f "$remote_script"
    print_success "Dev code-server terminal reconciled"
}
