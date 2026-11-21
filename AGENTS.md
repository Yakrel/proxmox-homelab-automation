# Agent Instructions

## Collaboration

- Ask when missing information would materially change the architecture, result, or risk. For low-risk ambiguity, use the simplest reasonable interpretation and state the assumption.
- Keep changes focused on the requested work. Surface unrelated bugs and design smells separately instead of silently expanding the scope.
- Prefer simple, durable solutions over speculative flexibility or tactical workarounds.
- State uncertainty explicitly. Use small, local, low-risk experiments when they can resolve it.
- Suggest improvements with long-term value when they are relevant.

## Overview
Shell-based automation for deploying containerized services in LXC containers on Proxmox VE. Keep code clean and production-ready.

## Core Development Principles

- **Fail Fast & Simple**: Let commands fail naturally. No custom retry loops. Bounded retries provided by remote transfer clients are allowed for offsite backup operations, but must still return non-zero after exhaustion. Do not suppress stderr/stdout unless it mixes with command output parsing (e.g. `apt-get update` output mixing with `yq` variables).
- **Idempotency**: Do not manually check if something exists before running idempotent commands (e.g. run `mkdir -p` or `apt install` directly without `if` checks).
- **No residue-cleanup code**: Never add recurring script logic whose only purpose is deleting files, users, keys, or configuration left behind by an older deployment or previous commit. Such residue must be removed manually once (with explicit approval), never encoded permanently in the repository. Doing so turns a one-time cleanup into permanent bloat that lingers across versions.
- **Homelab focus**: Prefer hardcoded static configurations over dynamic runtime detection. Using `latest` image tags is an intentional project policy unless the user requests pinning.

## Deployment Lifecycle

- Treat LXC provisioning as a clean installation. If initial provisioning fails, delete the incomplete LXC and create it again; do not add repair or migration logic for partial installations.
- Treat an existing LXC as already provisioned. Apply Docker Compose and application configuration changes through **Fast Redeploy All** or by redeploying the selected stack. Keep both paths on the same stack-preparation code path.
- Do not repeat OS package, repository, or base-container provisioning during an application redeploy unless the task explicitly changes that lifecycle.
- Never add recurring script logic whose only purpose is deleting files, users, keys, or configuration left by an older deployment. With explicit approval, clean live residue directly once instead of permanently encoding the cleanup in the repository. Doing so turns a one-time cleanup into permanent bloat that lingers across versions.
- Current-run cleanup is still required: remove temporary decrypted secrets and temporary work directories with `trap`, and let declarative tools reconcile resources they own.

## Live Config vs Repository

Decide where a change belongs by what Backrest covers. Backrest backs up only `/fastpool/config` (plus Immich photos) into the restic repository in `/datapool/backup`, mirrored offsite. Nothing else is backed up: PVE host files, LXC configs and root filesystems, and Docker images are lost on a PVE reinstall or LXC recreation.

- **Under `/fastpool/config`** (application settings, NPM, Homepage, Backrest, Sshwifty, rclone): live-only. Edit the live files, do not copy them into the repository, and never let a redeploy overwrite them.
- **Outside `/fastpool/config`** (PVE host files such as `/etc/pve`, `/etc/ssh`, `/etc/fail2ban`, `/etc/sanoid`, systemd units and Tailscale flags; LXC settings; OS config inside LXCs): not backed up, so the repository scripts must recreate it from scratch. Encode it in the scripts (`lxc-manager.sh`, `helper-menu.sh`, `setup-tailscale-host.sh`) with hardcoded static values and describe it in `README.md`.
- **Cloud-managed settings** (Cloudflare, Tailscale policy, tags and node keys): in neither place and not reachable by agents. Record in `README.md` what the repository depends on, and hand the change to the user as a manual console step.

## Technical & Git Guidelines

- **Commit Approval**: Always obtain explicit user approval immediately before creating a Git commit. Never commit changes unless the user has approved that specific commit after reviewing the completed work.
- **Encryption & Secrets**: Repository-managed `docker/*/.env.enc` files are SOPS dotenv files: variable names stay readable, values are encrypted to the age recipient in `.sops.yaml`. The age identity is committed only as `.sops-key.age`, encrypted with the user's master passphrase (age scrypt). **Agents must never ask for, read, echo, print, log, or inspect the master passphrase, the decrypted age identity, `SOPS_AGE_KEY`, `/tmp/.sops-key`, or existing decrypted secret values.** Do not store, copy, or reproduce secrets in prompts, tool output, temporary files, shell history, or agent memory. Variable names can be read from `.env.enc` without decrypting. When a `.env.enc` key needs to be added or updated, have the user unwrap `.sops-key.age` into a temporary `0600` file (`install -m 0600 /dev/null /tmp/.sops-key && age -d .sops-key.age > /tmp/.sops-key`), then update only the requested key blindly via `SOPS_AGE_KEY_FILE=/tmp/.sops-key sops set --input-type dotenv --output-type dotenv --value-stdin` and delete `/tmp/.sops-key` immediately with `trap`. Otherwise, changing a value is a user action with `sops edit --input-type dotenv --output-type dotenv docker/<stack>/.env.enc`. Commit only `.env.enc` files, never plain `.env`. Never commit a plaintext age identity.
- **Documentation**: Keep project documentation in `README.md` or inline comments. Reserve `AGENTS.md` and `CLAUDE.md` for agent instructions. Do not create separate validation or health-check scripts.
- **Git Commit Info**: Always use these configurations before committing:
  `git config user.email "85676216+Yakrel@users.noreply.github.com"`
  `git config user.name "Berkay Yetgin"`
  *Never* write "Generated with AI" or similar in commit messages.

## Proxmox & LXC Context

- **Network & Storage**: Timezone is `Europe/Istanbul`, topology uses `192.168.1.x`, ZFS pools are `fastpool` (SSD) and `datapool` (HDD), bridge is `vmbr0`.
- **Environment**: Work happens exclusively inside the dev LXC. SSH is completely disabled across all LXCs and host access is unavailable; commands like `pct`, `pvesh`, or remote container execution cannot be run directly. Live state inspection is limited to mounted storage (e.g., `/fastpool/config`) and local/network endpoints. Any host-level or LXC-level operations requiring PVE console access must be delegated to the user.
- **LXC Permissions (CRITICAL)**:
  - **Never run `chown` inside LXC containers.**
  - Always set host permissions with `chown 101000:101000` (which maps to `1000:1000` in container).
  - Target permissions directly to stack-specific subdirectories; do not run recursive `chown` on large, high-churn directories (like Immich media, torrents, or full `/fastpool/config`).
