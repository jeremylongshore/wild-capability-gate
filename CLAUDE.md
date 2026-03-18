# CLAUDE.md

This file provides guidance to Claude Code when working in this repository.

## Identity

- **Repo:** `wild-capability-gate`
- **Ecosystem:** wild (see `../CLAUDE.md` for ecosystem-level rules)
- **Archetype:** D — Coordination / Registry
- **Mission:** Governed access control for sensitive AI tool capabilities across the Wild ecosystem
- **Language:** Ruby (gem)
- **Status:** Epic 6 complete — structured audit trail for every capability evaluation

## What This Repo Does

Provides a reusable capability gate that consuming repos call before executing privileged tools. The gate evaluates whether a caller has a specific capability based on grant configuration and prerequisite satisfaction. Every evaluation is audited. The gate fails closed.

## What This Repo Does NOT Do

- Not a full IAM platform. No users, groups, roles, or org hierarchies.
- Not a policy engine for data access, hook execution, or permission correctness.
- Not an MCP server. The gate is a library consumed by MCP servers.
- Not a UI or dashboard. Operator visibility comes from audit logs and config inspection.

## Directory Layout

```
lib/                    # Source code
  wild/
    capability_gate/
      registry/         # Capability definitions and YAML loading
      evaluator/        # Grant matching and rule evaluation
      prerequisites/    # Prerequisite type implementations
      session/          # Session-scoped state management
      audit/            # Audit event emission
spec/                   # Tests (RSpec)
config/                 # Default configuration files
000-docs/               # Canonical docs per /doc-filing
planning/               # Active planning artifacts
```

## Build Commands

```bash
bundle install          # Install dependencies
bundle exec rspec       # Run test suite
bundle exec rubocop     # Lint
```

## Safety Rules for Claude Code

1. **Fail closed.** If evaluation errors, the result is denial. Never permission. Never raise an exception from the public interface.
2. **No implicit grants.** Unknown capabilities are denied. Unconfigured callers are denied.
3. **Prerequisites are enforced.** No skip mode. No override flag. No escape hatch.
4. **Audit is mandatory.** Every evaluation produces a log entry. No silent evaluation path.
5. **Configuration is startup-only.** No runtime modification of capability definitions or grants through the public interface.
6. **Keep the interface minimal.** `evaluate` and `capabilities` — that is the public API. Resist adding methods.

## Key Canonical Docs

| Doc | Purpose |
|-----|---------|
| `000-docs/001-PP-PLAN-repo-blueprint.md` | Mission, boundaries, architecture direction |
| `000-docs/002-AT-STND-capability-model.md` | Capability data structures, evaluation semantics, audit format |
| `000-docs/003-TQ-STND-governance-model.md` | Safety constraints and defect definitions |
| `000-docs/004-AT-ADEC-architecture-decisions.md` | Key decisions: gem not service, YAML not DB, session-scoped state |
| `000-docs/005-PP-PLAN-epic-build-plan.md` | 10-epic build plan |

## Task Tracking

Uses **Beads** (`bd`). All execution tracked repo-locally.

```bash
bd ready                # Find unblocked work
bd update <id> --claim  # Claim a task
bd close <id> --reason "evidence"  # Close with evidence
```

## Before Working Here

1. Read this file completely
2. Read the ecosystem CLAUDE.md at `../CLAUDE.md`
3. Check `bd ready` for current work state
4. Read the relevant canonical doc for the active epic
5. Do not skip ahead to later epics
