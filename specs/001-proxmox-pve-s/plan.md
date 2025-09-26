
# Implementation Plan: Proxmox PVE Zero-to-Production Automation

**Branch**: `001-proxmox-pve-s` | **Date**: 2025-09-26 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/workspaces/proxmox-homelab-automation/specs/001-proxmox-pve-s/spec.md`

## Execution Flow (/plan command scope)
```
1. Load feature spec from Input path
   → If not found: ERROR "No feature spec at {path}"
2. Fill Technical Context (scan for NEEDS CLARIFICATION)
   → Detect Project Type from file system structure or context (web=frontend+backend, mobile=app+api)
   → Set Structure Decision based on project type
3. Fill the Constitution Check section based on the content of the constitution document.
4. Evaluate Constitution Check section below
   → If violations exist: Document in Complexity Tracking
   → If no justification possible: ERROR "Simplify approach first"
   → Update Progress Tracking: Initial Constitution Check
5. Execute Phase 0 → research.md
   → If NEEDS CLARIFICATION remain: ERROR "Resolve unknowns"
6. Execute Phase 1 → contracts, data-model.md, quickstart.md, agent-specific template file (e.g., `CLAUDE.md` for Claude Code, `.github/copilot-instructions.md` for GitHub Copilot, `GEMINI.md` for Gemini CLI, `QWEN.md` for Qwen Code or `AGENTS.md` for opencode).
7. Re-evaluate Constitution Check section
   → If new violations: Refactor design, return to Phase 1
   → Update Progress Tracking: Post-Design Constitution Check
8. Plan Phase 2 → Describe task generation approach (DO NOT create tasks.md)
9. STOP - Ready for /tasks command
```

**IMPORTANT**: The /plan command STOPS at step 7. Phases 2-4 are executed by other commands:
- Phase 2: /tasks command creates tasks.md
- Phase 3-4: Implementation execution (manual or via tools)

## Summary
Zero-to-production automation system for Proxmox VE homelab environments. Provides interactive menu-driven deployment of 8 containerized service stacks (proxy, media, files, webtools, monitoring, gameservers, backup, development) in isolated LXC containers. Features encrypted .env file management, idempotent operations, automatic Grafana dashboard imports, and fail-fast error handling. Built exclusively for Debian Trixie 13.1 PVE with hardcoded homelab-specific configurations.

## Technical Context
**Language/Version**: Bash 5.x (Debian Trixie default)  
**Primary Dependencies**: Proxmox VE pct commands, Docker Compose, OpenSSL (encryption), jq (JSON parsing)  
**Storage**: ZFS datapool, LXC container storage, Docker volumes  
**Testing**: N/A (Live PVE environment required, constitution principle)  
**Target Platform**: Proxmox VE (Debian Trixie 13.1) exclusively
**Project Type**: Single automation system - shell script orchestration  
**Performance Goals**: Interactive deployment (<5min per stack), menu responsiveness  
**Constraints**: Hardcoded homelab values, no configuration discovery, fail-fast only  
**Scale/Scope**: 8 predefined service stacks, single PVE host, homelab scale
**Configuration Flexibility**: Current stacks.yaml can be redesigned or replaced - not mandatory to use existing structure

## Constitution Check
*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

**I. Fail Fast & Simple**: ✅ Design includes fail-fast error handling, no retry mechanisms, individual service failures logged but don't stop deployment  
**II. Homelab-First Approach**: ✅ All values hardcoded (192.168.1.x network, datapool storage, Europe/Istanbul timezone)  
**III. Latest Everything**: ✅ Uses latest Docker images and system packages without version pinning  
**IV. Pure Bash Scripting**: ✅ Implementation uses only Bash scripting with minimal external dependencies (pct, docker-compose, openssl, jq)  
**V. PVE-Exclusive Design**: ✅ Leverages Proxmox VE specific features (pct commands, LXC containers) on Debian Trixie 13.1

*All constitution principles satisfied - no violations detected*

## Project Structure

### Documentation (this feature)
```
specs/[###-feature]/
├── plan.md              # This file (/plan command output)
├── research.md          # Phase 0 output (/plan command)
├── data-model.md        # Phase 1 output (/plan command)
├── quickstart.md        # Phase 1 output (/plan command)
├── contracts/           # Phase 1 output (/plan command)
└── tasks.md             # Phase 2 output (/tasks command - NOT created by /plan)
```

### Source Code (repository root)
```
scripts/
├── main-menu.sh           # Interactive menu system
├── deploy-stack.sh        # Core stack deployment orchestrator  
├── lxc-manager.sh         # LXC container creation & management
├── encrypt-env.sh         # Environment file encryption/decryption
├── monitoring-setup.sh    # Grafana dashboard & Prometheus config
├── helper-functions.sh    # Common utility functions
└── modules/
    ├── stack-proxy.sh     # Proxy stack deployment
    ├── stack-media.sh     # Media stack deployment
    ├── stack-monitoring.sh # Monitoring stack deployment
    └── ...                # Additional stack modules

config/
├── stacks.yaml           # LXC resource specifications
├── grafana-dashboards/   # Dashboard configurations
├── prometheus/          # Monitoring configurations
└── templates/           # Configuration templates

docker/
├── proxy/
├── media/
├── monitoring/
└── ...                  # Existing docker-compose files

.env.example             # Template environment files
│   ├── components/
│   ├── pages/
│   └── services/
└── tests/

# [REMOVE IF UNUSED] Option 3: Mobile + API (when "iOS/Android" detected)
api/
└── [same as backend above]

ios/ or android/
└── [platform-specific structure: feature modules, UI flows, platform tests]
```

**Structure Decision**: [Document the selected structure and reference the real
directories captured above]

## Phase 0: Outline & Research
1. **Extract unknowns from Technical Context** above:
   - For each NEEDS CLARIFICATION → research task
   - For each dependency → best practices task
   - For each integration → patterns task

2. **Generate and dispatch research agents**:
   ```
   For each unknown in Technical Context:
     Task: "Research {unknown} for {feature context}"
   For each technology choice:
     Task: "Find best practices for {tech} in {domain}"
   ```

3. **Consolidate findings** in `research.md` using format:
   - Decision: [what was chosen]
   - Rationale: [why chosen]
   - Alternatives considered: [what else evaluated]

**Output**: research.md with all NEEDS CLARIFICATION resolved

## Phase 1: Design & Contracts
*Prerequisites: research.md complete*

1. **Extract entities from feature spec** → `data-model.md`:
   - Entity name, fields, relationships
   - Validation rules from requirements
   - State transitions if applicable

2. **Generate API contracts** from functional requirements:
   - For each user action → endpoint
   - Use standard REST/GraphQL patterns
   - Output OpenAPI/GraphQL schema to `/contracts/`

3. **Generate contract tests** from contracts:
   - One test file per endpoint
   - Assert request/response schemas
   - Tests must fail (no implementation yet)

4. **Extract test scenarios** from user stories:
   - Each story → integration test scenario
   - Quickstart test = story validation steps

5. **Update agent file incrementally** (O(1) operation):
   - Run `.specify/scripts/bash/update-agent-context.sh copilot`
     **IMPORTANT**: Execute it exactly as specified above. Do not add or remove any arguments.
   - If exists: Add only NEW tech from current plan
   - Preserve manual additions between markers
   - Update recent changes (keep last 3)
   - Keep under 150 lines for token efficiency
   - Output to repository root

**Output**: data-model.md, /contracts/*, failing tests, quickstart.md, agent-specific file

## Phase 2: Task Planning Approach
*This section describes what the /tasks command will do - DO NOT execute during /plan*

**Task Generation Strategy**:
- Load `.specify/templates/tasks-template.md` as base
- Generate tasks from Phase 1 design docs (contracts, data model, quickstart)
- Each contract → contract test task [P]
- Each entity → model creation task [P] 
- Each user story → integration test task
- Implementation tasks to make tests pass

**Ordering Strategy**:
- TDD order: Tests before implementation 
- Dependency order: Models before services before UI
- Mark [P] for parallel execution (independent files)

**Estimated Output**: 25-30 numbered, ordered tasks in tasks.md

**IMPORTANT**: This phase is executed by the /tasks command, NOT by /plan

## Phase 3+: Future Implementation
*These phases are beyond the scope of the /plan command*

**Phase 3**: Task execution (/tasks command creates tasks.md)  
**Phase 4**: Implementation (execute tasks.md following constitutional principles)  
**Phase 5**: Validation (run tests, execute quickstart.md, performance validation)

## Complexity Tracking
*Fill ONLY if Constitution Check has violations that must be justified*

No constitutional violations detected - all principles satisfied in design.

## Phase 2: Task Planning Approach  
*Describes task generation strategy for /tasks command execution*

**Task Generation Strategy**:
- Core bash scripts from contracts (main-menu.sh, deploy-stack.sh, lxc-manager.sh, encrypt-env.sh, monitoring-setup.sh)
- LXC container creation and management tasks
- Docker compose deployment integration
- Configuration file updates (stacks.yaml, .env.example templates)  
- Interactive menu system implementation
- Grafana dashboard import automation

**Ordering Strategy**:
- Foundation: Helper functions, configuration parsing
- Core: LXC management, environment handling  
- Services: Docker deployment, monitoring setup
- Integration: Menu system, end-to-end workflow
- Mark [P] for parallel execution (independent components)

**Estimated Output**: 15-20 numbered implementation tasks

## Progress Tracking

- [x] **Step 1**: Feature spec loaded from `/workspaces/proxmox-homelab-automation/specs/001-proxmox-pve-s/spec.md`
- [x] **Step 2**: Technical Context filled - Bash 5.x, PVE-exclusive, homelab-first approach
- [x] **Step 3**: Constitution Check completed - All principles satisfied ✅
- [x] **Step 4**: Initial Constitution Check passed - No violations
- [x] **Step 5**: Phase 0 executed - research.md generated with technical decisions
- [x] **Step 6**: Phase 1 executed - data-model.md, contracts/, quickstart.md, AGENTS.md updated  
- [x] **Step 7**: Post-Design Constitution Check passed - No new violations
- [x] **Step 8**: Phase 2 planning described - Ready for /tasks command
- [x] **Step 9**: STOP - Implementation plan complete

**Status**: ✅ READY FOR /tasks COMMAND
| [e.g., 4th project] | [current need] | [why 3 projects insufficient] |
| [e.g., Repository pattern] | [specific problem] | [why direct DB access insufficient] |


## Progress Tracking
*This checklist is updated during execution flow*

**Phase Status**:
- [ ] Phase 0: Research complete (/plan command)
- [ ] Phase 1: Design complete (/plan command)
- [ ] Phase 2: Task planning complete (/plan command - describe approach only)
- [ ] Phase 3: Tasks generated (/tasks command)
- [ ] Phase 4: Implementation complete
- [ ] Phase 5: Validation passed

**Gate Status**:
- [ ] Initial Constitution Check: PASS
- [ ] Post-Design Constitution Check: PASS
- [ ] All NEEDS CLARIFICATION resolved
- [ ] Complexity deviations documented

---
*Based on Constitution v2.1.1 - See `/memory/constitution.md`*
