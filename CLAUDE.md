# Agent Instructions

<!--
    CRITICAL: This file must be kept identical to AGENTS.md
    Both files need the same context and guidelines for all AI assistants.
    Any changes made to one file must be mirrored in the other exactly.
-->

## Overview

Shell-based automation for deploying containerized services in LXC containers on Proxmox VE.

**Always follow best practices and keep code clean.**

## Core Development Principles

### Fail Fast & Simple
- Ensure idempotency in all operations
- Let commands fail naturally with their original error messages
- **NEVER** use `>/dev/null 2>&1` - all output must be visible for debugging
- **EXCEPTION:** Suppress output when it interferes with command parsing (e.g., `apt-get update` output mixing with `yq`/`jq` parsing)
- **EXCEPTION:** Basic health checks are allowed when immediately needed (e.g., waiting for service to be ready before API call)
- **EXCEPTION:** Variable capture and parsing - when suppression prevents script failures from command output mixing with variable assignments (e.g., `ct_id=$(yq ... 2>/dev/null)`)
- No retry logic or waiting loops in deployment scripts
- Focus on main scenario - edge cases should fail fast

### Idempotency Without Manual Checks
- **NEVER** manually check if something exists before running idempotent commands
- Commands like `apt install`, `systemctl enable`, `mkdir -p` are already idempotent
- Always run the actual command - let it handle "already exists" cases
- Example: Use `apt install docker` directly, NOT `if ! command -v docker; then apt install docker; fi`
- This keeps scripts simple and ensures packages stay up-to-date

### Homelab-First Approach
- Static/hardcoded values must be used always if possible
- Accept that manual intervention is normal for edge cases
- Prefer simple solutions over complex error recovery

### Latest Everything
- Always use `latest` for everything in homelab context
- Version pinning only if absolutely required for compatibility

## Documentation Standards

### Minimal Documentation Philosophy
- **NO test scripts**: Do not create validation or health check scripts
- **NO extra .md files**: Keep documentation minimal - only in README.md or inline comments
- **EXCEPTION**: Critical technical notes (like GPU configuration) can have a dedicated README.md in the specific stack directory (e.g., `docker/media/README.md`)
- **Inline comments**: For important notes, use comments in the actual scripts where relevant
- **README.md**: General project documentation goes in the main README.md only

## Technical Guidelines

### Security and Encryption
Always use `-pbkdf2` and `-salt` with openssl for env file encryption/decryption. Do not use `-iter` unless explicitly required by the environment.

### Environment Secrets
The repository uses encrypted `.env.enc` files for sensitive configuration. Use `ENV_ENC_KEY` from GitHub secrets (available as environment variable in CI/CD) for decryption/encryption with openssl. The same `ENV_ENC_KEY` can be used to decrypt any `.env.enc` file in the repository for inspection or modification. Always commit only `.env.enc` files, never decrypted `.env` files.

### Version Control
- **NEVER** use "Generated with [AI Tool]" in commits
- Commit as the actual developer (Yakrel), not as AI
- Always check code to ensure no secrets or passwords are committed
- **Git Configuration**: Use `git config user.email "85676216+Yakrel@users.noreply.github.com"` and `git config user.name "Berkay Yetgin"` before committing

## Project Context

This is a personal homelab automation with:
- Fixed network topology: `192.168.1.x` range
- ZFS storage pool: `datapool`
- Network bridge: `vmbr0`
- Timezone: `Europe/Istanbul`
- Unprivileged LXC containers with UID/GID mapping (101000:101000 on host → 1000:1000 in container)

### Development Environment & Workflow
- **Working in dev LXC** - no access to Proxmox host commands (`pct`, `pvesh`, etc.)
- **No SSH** to other LXC containers
- **View live state** via `/datapool` mount
- **Workflow**: Make changes in repository first, test in `/datapool` if live config exists
- **Proxmox/LXC commands**: Provide grouped commands with inline comments for user execution

### LXC File Permissions
**CRITICAL: Never do chown inside LXC containers**
- Always set permissions on Proxmox host with `chown 101000:101000`
- For shared config files: `chown -R 101000:101000 /datapool/config` (this is sufficient for all LXC containers)
- **Never** chown to `/datapool` itself (parent directory) - only to `/datapool/config` or subdirectories
- Files in `/datapool/config` with host UID 101000 automatically map to UID 1000 inside unprivileged LXC containers
- Docker containers using `user: "1000:1000"` can access these files correctly without additional chown operations