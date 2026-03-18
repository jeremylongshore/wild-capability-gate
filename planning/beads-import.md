# Epic 1: Lay the Repo Foundation and Establish the Development Environment
- type: epic
- priority: 1
- labels: epic-1, foundation
- notes: Depends on nothing. Everything depends on this. One focused session. Governing references: 001-PP-PLAN-repo-blueprint.md, 005-PP-PLAN-epic-build-plan.md.

## Create Ruby gem directory structure and Gemfile with appropriate dependencies
- priority: 2

## Finalize repo-level CLAUDE.md with language, layout, build commands, and safety rules
- priority: 2

## Finalize README with mission, status, ecosystem context, and canonical doc pointers
- priority: 2

## Set up RSpec testing framework with initial configuration
- priority: 2

## Verify 000-docs/000-INDEX.md is current and accurately indexes all Phase 0 documents
- priority: 2

## Update planning/epics.md to reference the canonical 10-epic build plan document
- priority: 2

# Epic 2: Implement the Capability Registry — Define What Capabilities Exist
- type: epic
- priority: 1
- labels: epic-2, registry
- notes: The registry is deliberately simple — a hash of capability definitions loaded from YAML. Do not over-engineer it. YAML is the source of truth. Governing reference: 002-AT-STND-capability-model.md.

## Define the Capability data structure with name, description, risk_level, and prerequisites
- priority: 2

## Implement YAML config loader with schema validation and error reporting
- priority: 2

## Implement in-memory registry with lookup by name and list-all capability
- priority: 2

## Write registry tests: valid config loads, invalid config raises, duplicate names caught, unknown risk level rejected
- priority: 2

# Epic 3: Build the Rule Evaluator — The Core Access Decision Engine
- type: epic
- priority: 1
- labels: epic-3, evaluator
- notes: The evaluator at this stage is a pure function: input (caller, capability) → output (allowed/denied). No side effects. No state. This purity makes it easy to test and easy to reason about. Governing reference: 002-AT-STND-capability-model.md (evaluation semantics).

## Define the grant configuration YAML format and implement the loader with validation
- priority: 2

## Implement caller-to-capability matching logic including wildcard caller support
- priority: 2

## Implement denial results with reason codes: unknown_capability, not_granted
- priority: 2

## Write evaluator tests: granted caller passes, ungranted caller denied, unknown capability denied, wildcard grants work
- priority: 2

# Epic 4: Add Prerequisite Checking — Capabilities That Require Proof Before Granting
- type: epic
- priority: 1
- labels: epic-4, prerequisites
- notes: Only two prerequisite types in v1: file_exists and config_value. Resist the urge to build a general-purpose condition engine. Two types cover the real v1 use cases. Governing reference: 002-AT-STND-capability-model.md (prerequisite types).

## Define the prerequisite checker interface so new types can be added cleanly
- priority: 2

## Implement the file_exists prerequisite type that checks for a file path on the filesystem
- priority: 2

## Implement the config_value prerequisite type that checks a configuration key matches an expected value
- priority: 2

## Wire prerequisites into the evaluator decision pipeline: grant check → prerequisite check → result
- priority: 2

## Write prerequisite tests: prerequisite passes → allowed, file missing → denied, wrong config value → denied, multiple prerequisites all must pass
- priority: 2

# Epic 5: Add Session-Scoped State — Cache Evaluations Within a Session
- type: epic
- priority: 1
- labels: epic-5, session
- notes: Sessions are simple in v1 — an in-memory hash keyed by session ID. No database. No Redis. The gate runs in-process; session state lives in the process. Governing reference: 004-AT-ADEC-architecture-decisions.md (Decision 3).

## Define the Session data structure with id, created_at, and cached_evaluations
- priority: 2

## Implement session creation and lookup
- priority: 2

## Implement evaluation caching so first call evaluates and subsequent calls return cached result
- priority: 2

## Implement session cleanup for expired or completed sessions
- priority: 2

## Write session tests: first evaluation runs full pipeline, second returns cache, new session re-evaluates, expired session starts clean
- priority: 2

# Epic 6: Build the Audit Trail — Every Evaluation Leaves a Record
- type: epic
- priority: 1
- labels: epic-6, audit
- notes: Audit is not optional. The governance model defines missing audit events as a safety defect. Wire audit emission into the pipeline at the same level as the result return. Governing references: 002-AT-STND-capability-model.md (audit event format), 003-TQ-STND-governance-model.md (audit completeness rule).

## Define the audit event schema matching the capability model specification
- priority: 2

## Implement JSON Lines log writer with append-only semantics
- priority: 2

## Wire audit emission into the evaluation pipeline so every evaluation is logged before the result returns
- priority: 2

## Write audit tests: every evaluation type (allowed, denied, error) produces a correct and complete audit event
- priority: 2

# Epic 7: Define and Stabilize the Public Interface for Consuming Repos
- type: epic
- priority: 1
- labels: epic-7, interface
- notes: This is the most important epic for the ecosystem. The interface defined here is what wild-rails-safe-introspection-mcp will call. If it changes, that repo must change. Stabilize early. Governing reference: 004-AT-ADEC-architecture-decisions.md (Decision 5: minimal interface).

## Implement Wild::CapabilityGate.new(config_path:) initialization with config loading
- priority: 2

## Implement gate.evaluate(caller:, capability:, context:) returning an EvaluationResult object
- priority: 2

## Implement gate.capabilities for listing known capabilities (read-only)
- priority: 2

## Implement fail-closed error handling so evaluation errors return denial, never raise
- priority: 2

## Write and file the interface contract document (006-AT-STND-interface-contract.md)
- priority: 2

## Write integration tests: full evaluation pipeline from public interface through to audit log
- priority: 2

# Epic 8: Prove the Gate Works — Safety Testing and Adversarial Validation
- type: epic
- priority: 1
- labels: epic-8, safety-testing
- notes: Every safety defect in the governance model (Section 6, 7 conditions) must have a test that tries to trigger it and confirms it does not happen. Governing reference: 003-TQ-STND-governance-model.md.

## Write tests for every governance rule in the governance model document
- priority: 2

## Test fail-closed behavior: broken config → denial, missing prerequisite file → denial, evaluator error → denial
- priority: 2

## Test no implicit grants: unknown capability → denial, unconfigured caller → denial, empty grants → denial
- priority: 2

## Test prerequisite enforcement: cannot bypass prerequisites, cannot skip checks, cannot override
- priority: 2

## Test audit completeness: every evaluation type produces correct audit event, no evaluation bypasses audit
- priority: 2

## Write and file the evaluation strategy document (007-TQ-SECU-evaluation-strategy.md)
- priority: 2

# Epic 9: Package the MVP — Operator Docs, Configuration Guide, and Consumer Integration Guide
- type: epic
- priority: 1
- labels: epic-9, packaging
- notes: The consumer integration guide is particularly important. wild-rails-safe-introspection-mcp Epic 10 will use this guide to integrate the real gate. Make it clear, concrete, and tested.

## Write the configuration reference documenting capabilities.yml and grants.yml format, fields, defaults, and validation
- priority: 2

## Write the operator workflow guide: add capability, modify grants, emergency lockdown, audit inspection
- priority: 2

## Write the consumer integration guide: gem dependency, initialization, evaluate call, result handling
- priority: 2

## Update README to reflect v1 status with getting-started instructions
- priority: 2

## Produce end-to-end validation: follow the integration guide with a test consumer and verify correct behavior
- priority: 2

# Epic 10: Document Extension Points and Close the v1 Story
- type: epic
- priority: 1
- labels: epic-10, expansion
- notes: This epic is about preserving clarity. When a future session opens this repo, they should instantly know: what is built, what is proven, what comes next, and what is not in scope.

## Document planned v2 extension points: attestation prerequisites, time-window prerequisites, caller attributes
- priority: 2

## Document the integration status with wild-rails-safe-introspection-mcp and wild-admin-tools-mcp
- priority: 2

## Write the confirmed out-of-scope list so future sessions do not relitigate these decisions
- priority: 2

## Update the repo blueprint if v1 experience revealed corrections
- priority: 2
