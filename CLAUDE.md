# CLAUDE.md

<!--
    CRITICAL: This file must be kept identical to AGENTS.md
    Both files need the same context and guidelines for all AI assistants.
    Any changes made to one file must be mirrored in the other exactly.
-->

AI coding agents guidance for this Proxmox homelab automation project.

**Always follow best practices and keep code clean.**

## Project Overview

Shell-based automation for deploying containerized services in LXC containers on Proxmox VE.

## Core Principles (CRITICAL - Follow Exactly)

### **Fail Fast & Simple**
- Ensure idempotency
- Let commands fail naturally with their original error messages
- **NEVER** use `>/dev/null 2>&1` - all output must be visible for debugging
- No retry logic or waiting loops in deployment scripts
- **EXCEPTION:** Basic health checks are allowed when immediately needed (e.g., waiting for service to be ready before API call)
- Focus on main scenario - edge cases should fail fast

### **Homelab-First Approach**
- Static/hardcoded values must be used always if possible
- Accept that manual intervention is normal for edge cases
- Prefer simple solutions over complex error recovery

### **Latest Everything**
- Always use `latest` for everything in homelab context
- Version pinning only if absolutely required for compatibility

## Git Guidelines

- **NEVER** use "Generated with [AI Tool]" in commits
- Commit as the actual developer (Yakrel), not as AI
- Check code to not commit secrets or passwords when committing