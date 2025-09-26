<!--
Sync Impact Report:
Version change: Initial → 1.0.0
Modified principles: All principles created from scratch
Added sections: Core Principles, Platform Requirements, Development Standards, Governance
Removed sections: None (initial creation)
Templates requiring updates: ✅ updated
Follow-up TODOs: None
-->

# Proxmox Homelab Automation Constitution

## Core Principles

### I. Fail Fast & Simple (NON-NEGOTIABLE)
All operations must be idempotent and allow natural command failures. No retry logic, waiting loops, health checks, or error recovery mechanisms. Commands must fail fast with their original error messages intact. Focus exclusively on main scenarios - edge cases should fail immediately without graceful handling.

*Rationale: Simplicity and reliability over complex error handling in a homelab environment.*

### II. Homelab-First Approach
Static and hardcoded values must be used whenever possible instead of dynamic discovery or configuration. All deployment scripts are designed exclusively for the specific Proxmox VE environment (Debian Trixie 13.1) with predefined network ranges (192.168.1.x), storage pools (datapool), and timezone (Europe/Istanbul).

*Rationale: Eliminates configuration complexity and ensures predictable behavior in controlled homelab environment.*

### III. Latest Everything
Always use `latest` versions for all components: Docker images, system packages, and base distributions. No version pinning or compatibility matrices. Update systems regularly with `apt update && apt upgrade`.

*Rationale: Homelab environments benefit from latest features and security updates without production stability concerns.*

### IV. Pure Bash Scripting
Use only Bash scripting for automation. No Ansible, Terraform, or other configuration management tools. Minimal external dependencies - prefer Bash built-ins and basic system tools. Critical or best-practice exceptions allowed only when absolutely necessary.

*Rationale: Reduces complexity, dependencies, and learning curve while maintaining full control over automation logic.*

### V. PVE-Exclusive Design
All code runs exclusively on Proxmox VE (Debian Trixie 13.1). No cross-platform compatibility requirements. Leverage PVE-specific features and assume PVE environment availability.

*Rationale: Optimizes for the target platform without generic abstraction overhead.*

## Platform Requirements

### Target Environment
- **Operating System**: Proxmox VE based on Debian Trixie 13.1
- **Network**: 192.168.1.x range with vmbr0 bridge and 192.168.1.1 gateway  
- **Storage**: ZFS pool named `datapool`
- **Timezone**: Europe/Istanbul for all containers
- **User Mapping**: UID/GID 101000:101000, PUID=1000

### Technology Stack
- **Scripting**: Bash 5.x (Debian Trixie default)
- **Containerization**: LXC containers managed by Proxmox
- **Services**: Docker Compose for application stacks
- **Monitoring**: Prometheus, Grafana, Loki stack
- **Versioning**: Latest versions for all components

## Development Standards

### Code Quality
- Clean, readable Bash code with proper error handling
- Meaningful variable names and function documentation  
- Consistent indentation and formatting
- No testing requirements (live PVE environment unavailable for testing)

### Security Practices
- Encrypted .env files for sensitive data
- No hardcoded passwords in version control
- Proper file permissions and ownership
- Network isolation through LXC containers

### Git Workflow  
- Never use "Generated with [AI Tool]" in commit messages
- Commit as actual developer (Yakrel), not as AI assistant
- Review code for secrets before committing
- Clear, descriptive commit messages

## Governance

This constitution supersedes all other development practices and guidelines. All code changes, scripts, and automation must comply with these principles. The constitution takes precedence over convenience or common practices that conflict with these requirements.

Amendments require:
1. Documentation of rationale for change
2. Version increment following semantic versioning
3. Update of all dependent templates and documentation

Use `AGENTS.md` for runtime development guidance and AI assistant instructions.

**Version**: 1.0.0 | **Ratified**: 2025-09-26 | **Last Amended**: 2025-09-26