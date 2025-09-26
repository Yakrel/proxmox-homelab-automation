# Tasks: Proxmox PVE Zero-to-Production Automation

**Input**: Design documents from `/workspaces/proxmox-homelab-automation/specs/001-proxmox-pve-s/`
**Prerequisites**: plan.md, research.md, data-model.md, contracts/, quickstart.md

## Execution Flow Summary
Based on available design documents:
- **Technology Stack**: Bash 5.x scripting with PVE-specific tools
- **Core Scripts**: main-menu.sh, deploy-stack.sh, lxc-manager.sh, encrypt-env.sh, monitoring-setup.sh
- **Configuration**: Flexible config structure (current stacks.yaml optional)
- **Key Entities**: ServiceStack, LXCContainer, EnvironmentConfig, DockerService, GrafanaDashboard
- **Integration Points**: Proxmox pct commands, Docker Compose, OpenSSL encryption, Grafana API

## Format: `[ID] [P?] Description`
- **[P]**: Can run in parallel (independent files, no dependencies)
- All paths are absolute from repository root

## Phase 3.1: Project Foundation
- [x] **T001** [P] Create helper functions library in `scripts/helper-functions.sh`
- [x] **T002** [P] Create configuration parser for stack specifications in `scripts/config-parser.sh`
- [x] **T003** [P] Create logging utilities with fail-fast patterns in `scripts/logger.sh`
- [x] **T004** Validate Proxmox environment prerequisites (pct, datapool, vmbr0) in `scripts/validate-environment.sh`

## Phase 3.2: Core Components (Independent Scripts)
- [x] **T005** [P] Implement LXC container management in `scripts/lxc-manager.sh`
  - Actions: create, start, stop, destroy, exec, status
  - Idempotency: skip existing containers, continue deployment
  - Resource specs from configuration file
- [x] **T006** [P] Implement environment encryption/decryption in `scripts/encrypt-env.sh`
  - OpenSSL AES-256-CBC encryption
  - Fallback to .env.example on decryption failure
  - Automatic cleanup of temporary .env files
- [x] **T007** [P] Implement Grafana dashboard import in `scripts/monitoring-setup.sh`
  - HTTP API integration for dashboard imports
  - Community dashboard ID-based downloads
  - Prometheus datasource configuration
- [x] **T008** [P] Create service stack deployment orchestrator in `scripts/deploy-stack.sh`
  - Stack selection and validation
  - LXC container creation integration  
  - Environment decryption integration
  - Docker Compose deployment within containers

## Phase 3.3: Service Integration & Menu System
- [x] **T009** Implement interactive menu system in `scripts/main-menu.sh`
  - Bash select-based stack selection
  - Integration with deploy-stack.sh
  - Error handling and user experience
  - Graceful exit and cleanup
- [x] **T010** Create configuration management system
  - Design configuration file structure (using existing stacks.yaml)
  - LXC resource allocation definitions (in stacks.yaml)
  - Service stack specifications (in stacks.yaml)
  - Grafana dashboard ID mappings (in monitoring-setup.sh)

## Phase 3.4: Docker Integration & Service Deployment
- [x] **T011** [P] Verify existing Docker Compose configurations in `docker/` directories
  - Ensure compatibility with .env variable substitution
  - Validate latest tag usage (constitution compliance)
  - Test environment variable integration
- [x] **T012** [P] Create .env.example templates for each service stack
  - Placeholder values with clear naming conventions
  - Security-safe fallback configurations
  - Documentation comments for each variable
- [x] **T013** Implement Docker service deployment integration
  - Container-to-container Docker Compose execution
  - Service failure logging (continue deployment principle)
  - Health checking and status reporting

## Phase 3.5: System Integration & Validation
- [x] **T014** Integrate all components into complete automation workflow
  - End-to-end deployment testing
  - Idempotency validation (safe re-deployment)
  - Error propagation and logging
- [x] **T015** [P] Create deployment validation scripts
  - Container status verification
  - Service health checking
  - Network connectivity validation
- [x] **T016** [P] Implement cleanup and maintenance utilities
  - Container cleanup procedures
  - Environment file cleanup
  - Log rotation and maintenance

## Phase 3.6: Documentation & Finalization  
- [x] **T017** [P] Update repository documentation in `README.md`
  - Installation and quickstart guide (already comprehensive)
  - Service stack descriptions and access URLs (already documented)
  - Troubleshooting common issues (covered in DEPLOYMENT-CHECKLIST.md)
- [x] **T018** [P] Update AI agent guidelines in `AGENTS.md`
  - Implementation-specific patterns and conventions
  - Error handling examples
  - Configuration management approach
- [x] **T019** Create deployment verification checklist
  - Pre-deployment environment checks
  - Post-deployment validation steps
  - Performance benchmarks and expectations

## Dependencies & Execution Order

### Foundation Dependencies
- T001-T003 (helpers, config, logging) → Required by all other tasks
- T004 (environment validation) → Required before T005-T008

### Core Component Dependencies  
- T005-T008 can run in parallel (different files)
- T010 (config management) → Required by T009, T011, T012

### Integration Dependencies
- T009 (menu) depends on T008 (deploy-stack)
- T011-T012 can run in parallel (independent validation tasks)
- T013 depends on T011, T012 (Docker integration needs validated configs)

### Final Integration Dependencies
- T014 depends on T005-T013 (complete workflow integration)
- T015-T016 can run in parallel with T014 complete
- T017-T019 can run in parallel (documentation tasks)

## Parallel Execution Examples

### Phase 3.1 Foundation (Parallel)
```bash
# All foundation scripts can be developed simultaneously
Task T001: "Create helper functions library"
Task T002: "Create configuration parser"  
Task T003: "Create logging utilities"
```

### Phase 3.2 Core Components (Parallel)
```bash
# Independent core scripts can be developed simultaneously
Task T005: "Implement LXC container management"
Task T006: "Implement environment encryption/decryption" 
Task T007: "Implement Grafana dashboard import"
Task T008: "Create service stack deployment orchestrator"
```

### Phase 3.4 Docker Integration (Parallel)
```bash
# Docker configuration tasks can run simultaneously
Task T011: "Verify existing Docker Compose configurations"
Task T012: "Create .env.example templates for each service stack"
```

### Phase 3.6 Documentation (Parallel)
```bash
# Documentation updates can be done simultaneously
Task T017: "Update repository documentation in README.md"
Task T018: "Update AI agent guidelines in AGENTS.md"
Task T019: "Create deployment verification checklist"
```

## Validation Checklist

### Script Interface Contracts
- [x] main-menu.sh interface contract defined
- [x] deploy-stack.sh interface contract defined  
- [x] lxc-manager.sh interface contract defined
- [x] encrypt-env.sh interface contract defined
- [x] monitoring-setup.sh interface contract defined

### Configuration Contracts
- [x] Configuration file structure contract defined
- [x] .env.example template contract defined
- [x] Docker Compose integration contract defined

### Entity Implementation
- [ ] ServiceStack entity management (T010, T008)
- [ ] LXCContainer lifecycle management (T005)
- [ ] EnvironmentConfig encryption handling (T006)
- [ ] DockerService deployment handling (T008, T013)
- [ ] GrafanaDashboard import automation (T007)

### Integration Points
- [ ] Proxmox pct command integration (T005)
- [ ] Docker Compose deployment (T013)
- [ ] OpenSSL encryption integration (T006)
- [ ] Grafana HTTP API integration (T007)
- [ ] Interactive bash menu system (T009)

## Implementation Notes

### Constitutional Compliance
All tasks must adhere to project constitution principles:
- **Fail Fast & Simple**: No retry mechanisms, clear error messages
- **Homelab-First**: Hardcoded values (192.168.1.x, datapool, Europe/Istanbul)
- **Latest Everything**: Use latest Docker images and packages
- **Pure Bash**: Only bash scripting with minimal dependencies
- **PVE-Exclusive**: Leverage Proxmox-specific features

### Error Handling Pattern
```bash
# Standard error handling for all scripts
if ! command_that_might_fail; then
    echo "ERROR: Component: Specific failure: Additional context" >&2
    exit 3  # Infrastructure error code
fi
```

### File Structure Expectations
```
scripts/
├── main-menu.sh          # T009 - Interactive menu system
├── deploy-stack.sh       # T008 - Stack deployment orchestrator
├── lxc-manager.sh        # T005 - LXC container management
├── encrypt-env.sh        # T006 - Environment encryption
├── monitoring-setup.sh   # T007 - Grafana dashboard import
├── helper-functions.sh   # T001 - Utility functions
├── config-parser.sh      # T002 - Configuration parsing
├── logger.sh            # T003 - Logging utilities
└── validate-environment.sh # T004 - Environment validation
```

This task list provides a complete implementation roadmap for the Proxmox PVE automation system, with clear dependencies and parallel execution opportunities.