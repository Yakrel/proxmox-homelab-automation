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

- **Fail Fast & Simple**: Let commands fail naturally. No retry loops. Do not suppress stderr/stdout unless it mixes with command output parsing (e.g. `apt-get update` output mixing with `yq` variables).
- **Idempotency**: Do not manually check if something exists before running idempotent commands (e.g. run `mkdir -p` or `apt install` directly without `if` checks).
- **No residue-cleanup code**: Never add recurring script logic whose only purpose is deleting files, users, keys, or configuration left behind by an older deployment or previous commit. Such residue must be removed manually once (with explicit approval), never encoded permanently in the repository. Doing so turns a one-time cleanup into permanent bloat that lingers across versions.
- **Homelab focus**: Prefer hardcoded static configurations over dynamic runtime detection. Using `latest` image tags is an intentional project policy unless the user requests pinning.

## Deployment Lifecycle

- Treat LXC provisioning as a clean installation. If initial provisioning fails, delete the incomplete LXC and create it again; do not add repair or migration logic for partial installations.
- Treat an existing LXC as already provisioned. Apply Docker Compose and application configuration changes through **Fast Redeploy All** or by redeploying the selected stack. Keep both paths on the same stack-preparation code path.
- Do not repeat OS package, repository, or base-container provisioning during an application redeploy unless the task explicitly changes that lifecycle.
- Never add recurring script logic whose only purpose is deleting files, users, keys, or configuration left by an older deployment. With explicit approval, clean live residue directly once instead of permanently encoding the cleanup in the repository. Doing so turns a one-time cleanup into permanent bloat that lingers across versions.
- Current-run cleanup is still required: remove temporary decrypted secrets and temporary work directories with `trap`, and let declarative tools reconcile resources they own.

## Technical & Git Guidelines

- **Encryption & Secrets**: Use `openssl` with `-pbkdf2` and `-salt` for encrypting `.env` files. Decrypt/encrypt using `ENV_ENC_KEY` from CI/CD env variables. Commit only `.env.enc` files, never plain `.env`.
- **Documentation**: Keep project documentation in `README.md` or inline comments. Reserve `AGENTS.md` and `CLAUDE.md` for agent instructions. Do not create separate validation or health-check scripts.
- **Git Commit Info**: Always use these configurations before committing:
  `git config user.email "85676216+Yakrel@users.noreply.github.com"`
  `git config user.name "Berkay Yetgin"`
  *Never* write "Generated with AI" or similar in commit messages.

## Proxmox & LXC Context

- **Network & Storage**: Timezone is `Europe/Istanbul`, topology uses `192.168.1.x`, ZFS pool is `datapool`, bridge is `vmbr0`.
- **Environment**: Work normally happens inside the dev LXC, where host commands such as `pct` and `pvesh` are unavailable; mounted storage can still expose part of the live state. Use explicitly authorized SSH access when live host inspection or intervention is part of the task; never store credentials in the repository.
- **LXC Permissions (CRITICAL)**:
  - **Never run `chown` inside LXC containers.**
  - Always set host permissions with `chown 101000:101000` (which maps to `1000:1000` in container).
  - Target permissions directly to stack-specific subdirectories; do not run recursive `chown` on large, high-churn directories (like Immich media, torrents, or full `/fastpool/config`).
