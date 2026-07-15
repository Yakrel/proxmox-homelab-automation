# Agent Instructions

1. Ask, don't assume. If something is unclear, ask before writing a single line. Never make silent assumptions about intent, architecture, or requirements. When running unattended, pick the most reasonable interpretation, proceed, and record the assumption rather than blocking.

2. Implement the simplest solution for simple problems, better solutions for harder problems. Do not over-engineer or add flexibility that isn't needed yet. 

3. Don't touch unrelated code but please do surface bad code or design smells you discover with me so we can address them as a separate issue.

4. Flag uncertainty explicitly. If you're unsure about something, see point 1 above. If it makes sense to do so, conduct a small, localised and low-risk experiment and bring the hypothesis and results to me to discuss. Confidence without certainty causes more damage than admitting a gap.

5. I'm always open to ideas on better ways to do things. Please don't hesitate to suggest a better way, or one that has long lasting impact over a tactical change. (as a few examples)

## Overview
Shell-based automation for deploying containerized services in LXC containers on Proxmox VE. Keep code clean and production-ready.

## Core Development Principles
- **Fail Fast & Simple**: Let commands fail naturally. No retry loops. Do not suppress stderr/stdout unless it mixes with command output parsing (e.g. `apt-get update` output mixing with `yq` variables).
- **Idempotency**: Do not manually check if something exists before running idempotent commands (e.g. run `mkdir -p` or `apt install` directly without `if` checks).
- **Homelab focus**: Prefer hardcoded static configurations over dynamic runtime detection. Always use the `latest` version tags.

## Technical & Git Guidelines
- **Encryption & Secrets**: Use `openssl` with `-pbkdf2` and `-salt` for encrypting `.env` files. Decrypt/encrypt using `ENV_ENC_KEY` from CI/CD env variables. Commit only `.env.enc` files, never plain `.env`.
- **Documentation**: Keep documentation minimal. Only write in `README.md` or inline comments. Do not create separate validation/health check scripts.
- **Git Commit Info**: Always use these configurations before committing:
  `git config user.email "85676216+Yakrel@users.noreply.github.com"`
  `git config user.name "Berkay Yetgin"`
  *Never* write "Generated with AI" or similar in commit messages.

## Proxmox & LXC Context
- **Network & Storage**: Timezone is `Europe/Istanbul`, topology uses `192.168.1.x`, ZFS pool is `datapool`, bridge is `vmbr0`.
- **Environment**: Working inside dev LXC with no access to host commands (`pct`/`pvesh`) and no SSH to other LXCs. View live state via `/datapool` mount.
- **LXC Permissions (CRITICAL)**:
  - **Never run `chown` inside LXC containers.**
  - Always set host permissions with `chown 101000:101000` (which maps to `1000:1000` in container).
  - Target permissions directly to stack-specific subdirectories; do not run recursive `chown` on large, high-churn directories (like Immich media, torrents, or full `/fastpool/config`).
