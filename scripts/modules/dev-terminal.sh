#!/bin/bash

# Dev LXC terminal and Oh My Pi configuration shared by full deploys and fast
# redeploys. Keeps the Proxmox/root login shell on Bash while configuring Zsh
# with Oh My Zsh and reconciling Oh My Pi's Hindsight memory and ompweb workspace.

deploy_dev_terminal() {
    local ct_id="$1"
    local guest_script remote_script
    local hindsight_api_key="" hindsight_retain_mission="" ai_tmp="" # gitleaks:allow
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
    # Keep the server-wide retain mission in docker/ai/docker-compose.yml as the
    # single source of truth for the Hindsight bank profile.
    hindsight_retain_mission=$(yq -r '.services.hindsight.environment[] | select(startswith("HINDSIGHT_API_RETAIN_MISSION=")) | ltrimstr("HINDSIGHT_API_RETAIN_MISSION=")' "$WORK_DIR/docker/ai/docker-compose.yml")
    [[ -n "$hindsight_retain_mission" ]] || {
        print_error "HINDSIGHT_API_RETAIN_MISSION is missing in docker/ai/docker-compose.yml"
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
for command_name in zsh git eza batcat zoxide btop omp ompweb; do
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

# Reconcile Oh My Pi Hindsight memory configuration, the mental model refresh
# policy on the Hindsight bank, and register the default workspace in ompweb.
# Oh My Pi and ompweb also write these files, so parse and re-emit YAML/JSON
# instead of replacing them.
install -d -m 0700 /root/.omp/agent
# The key stays in the environment, never in a process argument list.
python3 - <<'OMP_CONFIG'
import json
import os
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

import yaml

agent_dir = Path("/root/.omp/agent")
config_path = agent_dir / "config.yml"
config = (yaml.safe_load(config_path.read_text(encoding="utf-8")) if config_path.exists() else None) or {}

config.setdefault("memory", {})["backend"] = "hindsight"
hindsight = config.setdefault("hindsight", {})
hindsight.update({
    "apiUrl": "http://192.168.1.104:8888",
    "apiToken": os.environ["HINDSIGHT_API_KEY"],
    "bankId": "main",
    "scoping": "per-project-tagged",
    "retainMission": os.environ["HINDSIGHT_RETAIN_MISSION"],
    # Retain every 2 user turns with one preceding turn of conversational context.
    "retainMode": "last-turn",
    "retainEveryNTurns": 2,
    "retainOverlapTurns": 1,
})

config_path.write_text(yaml.safe_dump(config, sort_keys=False), encoding="utf-8")
config_path.chmod(0o600)

# Oh My Pi seeds mental models with incremental (delta) refreshes after every
# consolidation, so their content only grows until the injected snapshot is
# truncated. Regenerate each model from scratch once a day instead; a cron
# refresh runs only when the model has new memories. Keep single-project build,
# CI and stack rules out of the cross-project User Preferences model.
hindsight_bank_url = f"{hindsight['apiUrl']}/v1/default/banks/{urllib.parse.quote(hindsight['bankId'], safe='')}"

def hindsight_request(method, path, body=None):
    request = urllib.request.Request(
        f"{hindsight_bank_url}{path}",
        data=None if body is None else json.dumps(body).encode("utf-8"),
        headers={
            "Authorization": f"Bearer {os.environ['HINDSIGHT_API_KEY']}",
            "Content-Type": "application/json",
        },
        method=method,
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.loads(response.read() or b"null")

user_preferences_query = (
    "What does the user prefer in coding style, tooling, communication, and review? "
    "Capture only durable, cross-project preferences expressed across sessions, not one-off requests. "
    "Exclude rules that belong to a single project (its build, test or CI matrix, deployment, "
    "stack or container settings, paths, hostnames, versions); those belong in that project's conventions."
)
for model in hindsight_request("GET", "/mental-models?limit=1000")["items"]:
    update = {"trigger": {"mode": "full", "refresh_after_consolidation": False, "refresh_cron": "0 3 * * *"}}
    if model["id"] == "user-preferences":
        update["source_query"] = user_preferences_query
    hindsight_request("PATCH", f"/mental-models/{urllib.parse.quote(model['id'], safe='')}", update)

projects_path = agent_dir / "projects.json"
registry = (json.loads(projects_path.read_text(encoding="utf-8")) if projects_path.exists() else None) or {}
projects = registry.get("projects") if isinstance(registry.get("projects"), list) else []
workspace_path = str(Path("/root/workspace").resolve())
if not any(isinstance(item, dict) and item.get("path") == workspace_path for item in projects):
    projects.append({
        "path": workspace_path,
        "addedAt": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "hidden": False,
        "alias": "workspace",
    })
    projects_path.write_text(
        json.dumps({"version": 1, "projects": projects}, indent=2) + "\n",
        encoding="utf-8",
    )
    projects_path.chmod(0o600)
OMP_CONFIG
GUEST_SCRIPT

    pct push "$ct_id" "$guest_script" "$remote_script"
    pct exec "$ct_id" -- chmod 0700 "$remote_script"

    if ! pct exec "$ct_id" -- env \
        HINDSIGHT_API_KEY="$hindsight_api_key" \
        HINDSIGHT_RETAIN_MISSION="$hindsight_retain_mission" \
        "$remote_script"; then
        pct exec "$ct_id" -- rm -f "$remote_script" || true
        print_error "Failed to configure dev terminal"
        return 1
    fi

    pct exec "$ct_id" -- rm -f "$remote_script"

    if ! deploy_lxc_beszel_agent \
        "$ct_id" "lxc-dev" "$ai_tmp" "ompweb*,beszel*"; then
        print_error "Failed to configure the Dev Beszel agent"
        return 1
    fi
    rm -f "$ai_tmp"
    print_success "Dev terminal and Beszel agent reconciled"
}
