# wild-capability-gate — 10-Epic Build Plan

**Document type:** Canonical repo build plan
**Filed as:** `005-PP-PLAN-epic-build-plan.md`
**Repo:** `wild-capability-gate`
**Archetype:** D — Coordination
**Status:** Active — planning phase
**Last updated:** 2026-03-17
**Blueprint reference:** `001-PP-PLAN-repo-blueprint.md`

---

## 1. Purpose

This is the canonical 10-epic build plan for `wild-capability-gate`. It translates the blueprint into a sequenced, story-driven execution plan.

---

## 2. Sequencing Logic

The gate is infrastructure that other repos consume. The build sequence follows a principle: **stabilize the interface before consumers integrate**.

1. Foundation and docs first — the repo must be a clean home
2. Capability model before evaluation logic — define what capabilities are before writing the engine that evaluates them
3. Evaluation engine before session state — the core logic must work before caching is layered on
4. Audit before the public interface — evaluations must be logged before consumers can call the gate
5. Public interface after the full stack — the first time a consumer calls `evaluate`, the entire pipeline works
6. Integration testing before MVP — prove the gate works with a real consumer
7. Operator docs before anyone deploys it

---

## 3. The 10 Epics

---

### Epic 1 — Lay the Repo Foundation and Establish the Development Environment

**Mission:** Set up the repo for development: directory structure, Gemfile, CLAUDE.md, README, and verification that all planning docs are correctly filed and indexed.

**Why now:** Nothing else works without a clean home. Same rationale as every Wild repo.

**Scope:** Directory structure (lib/, spec/, config/), Gemfile with Ruby version, RSpec setup, CLAUDE.md finalized, README finalized, 000-INDEX.md current.

**Out of scope:** Application code. CI/CD. Publishing the gem.

**Child-task themes:**
- Create Ruby gem directory structure and Gemfile
- Finalize CLAUDE.md with repo-specific conventions
- Finalize README with mission and status
- Set up RSpec
- Verify 000-INDEX.md is current
- Update planning/epics.md to reference this plan

**Dependencies:** None. Everything depends on this.

**Supporting docs:** Blueprint (001), this plan (005)

**Annotation:** One focused session. After this, the repo is development-ready.

---

### Epic 2 — Implement the Capability Registry: Define What Capabilities Exist

**Mission:** Build the capability registry — the component that loads capability definitions from YAML configuration, validates them, and makes them queryable by name. When this epic closes, the system knows what capabilities exist, what risk level each carries, and what prerequisites each requires.

**Why now:** The evaluation engine (Epic 3) needs capabilities to evaluate. The registry is the data source.

**Scope:** YAML configuration loading, validation (schema checks, duplicate detection), in-memory registry with lookup by name, risk level enum, prerequisite definition structure.

**Out of scope:** Evaluating grants. Checking prerequisites. Session state. Audit logging.

**Child-task themes:**
- Define the Capability data structure (name, description, risk_level, prerequisites)
- Implement YAML config loader with validation
- Implement in-memory registry with lookup by name
- Write tests: valid config loads, invalid config raises, duplicate names caught, unknown risk level rejected

**Dependencies:** Epic 1 (repo structure).

**Supporting docs:** `002-AT-STND-capability-model.md` governs the data structures.

**Annotation:** The registry is deliberately simple — a hash of capability definitions loaded from YAML. Do not over-engineer it with database backends or dynamic registration. YAML is the source of truth.

---

### Epic 3 — Build the Rule Evaluator: The Core Access Decision Engine

**Mission:** Implement the rule evaluator — the component that, given a caller identity and a capability name, determines whether the caller is granted that capability based on the grant configuration. This is the core logic of the gate. When this epic closes, the system can answer "is this caller allowed to do this?" — without prerequisites, without session state, without audit.

**Why now:** The evaluator is the central logic. Everything else wraps, decorates, or consumes it.

**Scope:** Grant configuration loading from YAML, caller-to-capability matching, wildcard caller support, denial with reason codes, unknown capability denial, no-grant denial.

**Out of scope:** Prerequisite checks (Epic 4). Session caching (Epic 5). Audit (Epic 6). Public interface (Epic 7).

**Child-task themes:**
- Define grant configuration YAML format
- Implement grant config loader with validation
- Implement caller-capability matching logic
- Implement wildcard caller matching
- Implement denial result with reason codes (unknown_capability, not_granted)
- Write tests: granted caller passes, ungranted caller denied, unknown capability denied, wildcard grants work

**Dependencies:** Epic 2 (capability registry must exist so the evaluator can look up capabilities).

**Supporting docs:** `002-AT-STND-capability-model.md` (evaluation semantics).

**Annotation:** The evaluator at this stage is a pure function: input (caller, capability) → output (allowed/denied). No side effects. No state. This purity makes it easy to test and easy to reason about.

---

### Epic 4 — Add Prerequisite Checking: Capabilities That Require Proof Before Granting

**Mission:** Implement the prerequisite checker — the component that evaluates prerequisite conditions before a capability can be granted. Even if a caller is listed in the grant config, the capability is denied if its prerequisites are not satisfied. When this epic closes, capabilities can require proof (a file exists, a config value is set) before they unlock.

**Why now:** The evaluator (Epic 3) can check grants but cannot enforce prerequisites. This epic adds that layer so the full evaluation semantics from the capability model are implemented.

**Scope:** Prerequisite evaluation framework, `file_exists` prerequisite type, `config_value` prerequisite type, integration with the evaluator's decision pipeline, clear denial reasons when prerequisites fail.

**Out of scope:** Complex prerequisite types (attestation, time windows). Session state. Audit.

**Child-task themes:**
- Define the prerequisite checker interface
- Implement `file_exists` prerequisite type
- Implement `config_value` prerequisite type
- Wire prerequisites into the evaluator's decision pipeline (grant check → prerequisite check → result)
- Write tests: prerequisite passes → allowed, prerequisite fails → denied with reason, missing file → denied, wrong config value → denied

**Dependencies:** Epics 2 (capabilities with prerequisites defined) and 3 (evaluator to wire into).

**Supporting docs:** `002-AT-STND-capability-model.md` (prerequisite types).

**Annotation:** Only two prerequisite types in v1: file_exists and config_value. Resist the urge to build a general-purpose condition engine. Two types cover the real v1 use cases. Add more types when real demand appears.

---

### Epic 5 — Add Session-Scoped State: Cache Evaluations Within a Session

**Mission:** Implement session-scoped state management — caching capability evaluation results so that repeated checks within the same session do not re-evaluate from scratch. Each new session starts clean.

**Why now:** Without session state, every capability check re-runs the full evaluation pipeline. This is functionally correct but wasteful. More importantly, session state establishes the boundary: capabilities are scoped to sessions, not persisted.

**Scope:** Session object creation, evaluation result caching per session, session expiry/cleanup, no cross-session persistence.

**Out of scope:** Persistent capability grants. Session management UI. Session analytics.

**Child-task themes:**
- Define the Session data structure (id, created_at, cached_evaluations)
- Implement session creation and lookup
- Implement evaluation caching (first call evaluates, subsequent calls return cached result)
- Implement session cleanup
- Write tests: first evaluation runs full pipeline, second evaluation returns cache, new session re-evaluates, expired session starts clean

**Dependencies:** Epics 3 and 4 (the full evaluation pipeline to cache results from).

**Supporting docs:** `004-AT-ADEC-architecture-decisions.md` (Decision 3: session-scoped state).

**Annotation:** Sessions are simple in v1 — an in-memory hash keyed by session ID. No database. No Redis. The gate runs in-process; session state lives in the process.

---

### Epic 6 — Build the Audit Trail: Every Evaluation Leaves a Record

**Mission:** Implement audit logging for every capability evaluation. Grants, denials, errors — all produce structured audit events. The audit trail is how operators verify the gate is working correctly.

**Why now:** The public interface (Epic 7) should not be exposed until audit logging is in place. An unaudited gate is an unaccountable gate.

**Scope:** Audit event schema, JSON Lines log writer, integration with the evaluation pipeline, parameter capture, prerequisite evaluation recording.

**Out of scope:** Audit log analysis. External log shipping. Dashboard.

**Child-task themes:**
- Define the audit event schema (see capability model doc)
- Implement JSON Lines log writer (append-only)
- Wire audit emission into the evaluation pipeline (after every evaluation, before returning result)
- Write tests: every evaluation type (allowed, denied, error) produces a correct audit event, no evaluation bypasses audit

**Dependencies:** Epics 3–5 (the full evaluation pipeline including session state).

**Supporting docs:** `002-AT-STND-capability-model.md` (audit event format), `003-TQ-STND-governance-model.md` (audit completeness rule).

**Annotation:** Audit is not optional. The governance model defines missing audit events as a safety defect. Wire audit emission into the pipeline at the same level as the result return — not as an afterthought callback.

---

### Epic 7 — Define and Stabilize the Public Interface for Consuming Repos

**Mission:** Define, implement, and document the public interface that consuming repos will call. This is the contract other repos design against. It must be minimal, stable, and well-documented. When this epic closes, consuming repos can integrate.

**Why now:** Everything under the interface is now built: registry, evaluator, prerequisites, sessions, audit. The interface is the stable surface that wraps it all.

**Scope:** The `Wild::CapabilityGate` class with `evaluate` and `capabilities` methods, the `EvaluationResult` result object, configuration initialization, error handling that returns denial (never raises), documentation of the interface contract.

**Out of scope:** Consumer-side integration code (that lives in consuming repos). HTTP/API surface. CLI tools.

**Child-task themes:**
- Implement `Wild::CapabilityGate.new(config_path:)` initialization
- Implement `gate.evaluate(caller:, capability:, context:)` → `EvaluationResult`
- Implement `gate.capabilities` → list of known capabilities (read-only)
- Implement fail-closed error handling (evaluation errors return denial, never raise)
- Write and file the interface contract document
- Write integration tests: full evaluation pipeline from public interface through to audit log

**Dependencies:** All of Epics 1–6.

**Supporting docs:** Create `006-AT-STND-interface-contract.md` documenting the public API, method signatures, return types, and stability guarantees.

**Annotation:** This is the most important epic for the ecosystem. The interface defined here is what `wild-rails-safe-introspection-mcp` will call. If it changes, that repo must change. Stabilize it early and resist modifications after consumers integrate.

---

### Epic 8 — Prove the Gate Works: Safety Testing and Adversarial Validation

**Mission:** Before any consuming repo integrates, prove the gate's governance claims are real. Test that fail-closed works. Test that prerequisites cannot be bypassed. Test that unknown capabilities are denied. Test that audit is never skipped. Every governance rule in the governance model doc should have a test that proves it.

**Why now:** The gate is safety-critical infrastructure. Shipping it without adversarial testing means the entire ecosystem's access control is unverified.

**Scope:** Adversarial test suite, governance rule verification, fail-closed testing, prerequisite bypass testing, audit completeness testing.

**Out of scope:** Performance benchmarks. Load testing. Penetration testing by external parties.

**Child-task themes:**
- Write tests for every governance rule in 003-TQ-STND-governance-model.md
- Test fail-closed: broken config → denial, missing prerequisite file → denial, evaluator error → denial
- Test no implicit grants: unknown capability → denial, unconfigured caller → denial
- Test prerequisite enforcement: cannot bypass prerequisites, cannot skip checks
- Test audit completeness: every evaluation type produces correct audit event
- Write and file evaluation strategy doc

**Dependencies:** Epic 7 (the public interface, so tests run against the real API).

**Supporting docs:** `003-TQ-STND-governance-model.md` (safety defect definitions to test against). Create `007-TQ-SECU-evaluation-strategy.md`.

**Annotation:** Every safety defect in the governance model (Section 6, 7 conditions) must have a test that tries to trigger it and confirms it does not happen. If a test reveals a defect, it is a blocking issue.

---

### Epic 9 — Package the MVP: Operator Docs, Configuration Guide, and Consumer Integration Guide

**Mission:** Make the gate usable. Write the configuration reference, the operator workflow guide, and the consumer integration guide. A platform engineer should be able to configure the gate and a consuming repo should be able to integrate — both from documentation alone.

**Why now:** Working code without docs is unusable code. The operator docs and integration guide are the last gate before the gem is ready for real consumers.

**Scope:** Configuration reference (capabilities.yml, grants.yml format), operator workflow guide (add capability, modify grant, inspect audit logs), consumer integration guide (how to add the gem, call the interface, handle results), README update.

**Out of scope:** Multi-repo deployment automation. UI. Dashboard.

**Child-task themes:**
- Write configuration reference (every field, every type, defaults, validation)
- Write operator workflow guide (add capability, modify grants, emergency lockdown, audit inspection)
- Write consumer integration guide (gem dependency, initialization, evaluate call, result handling)
- Update README to reflect v1 status
- End-to-end validation: follow the integration guide with a test consumer

**Dependencies:** Epics 7 (interface is stable) and 8 (gate is proven safe).

**Supporting docs:** Create operator and integration docs in 000-docs/.

**Annotation:** The consumer integration guide is particularly important. `wild-rails-safe-introspection-mcp` Epic 10 will use this guide to integrate the real gate. Make it clear, concrete, and tested.

---

### Epic 10 — Document Extension Points and Close the v1 Story

**Mission:** Document what the gate is ready to support after v1 and what its architectural limits are. Define the controlled expansion roadmap. Close the v1 story cleanly.

**Why now:** v1 is built. Before moving on, capture what was learned, what is extensible, and what is intentionally out of scope so future sessions do not relitigate.

**Scope:** Planned extension points (new prerequisite types, richer caller matching, policy versioning), integration status with consuming repos, out-of-scope list, lessons learned.

**Out of scope:** Implementing any v2 features.

**Child-task themes:**
- Document planned v2 extension points (attestation prerequisites, time-window prerequisites, caller attributes)
- Document the integration status with wild-rails-safe-introspection-mcp and wild-admin-tools-mcp
- Write the confirmed out-of-scope list
- Update blueprint if v1 experience revealed corrections

**Dependencies:** All prior epics.

**Supporting docs:** Create expansion roadmap in 000-docs/.

**Annotation:** This epic is about preserving clarity. When a future session opens this repo, they should instantly know: what is built, what is proven, what comes next, and what is not in scope.

---

## 4. Cross-Epic Dependency Summary

```
Epic 1 (Foundation)
  └── Epic 2 (Capability Registry)
        └── Epic 3 (Rule Evaluator)
              ├── Epic 4 (Prerequisites)
              │     └── Epic 5 (Session State)
              │           └── Epic 6 (Audit Trail)
              │                 └── Epic 7 (Public Interface)
              │                       └── Epic 8 (Safety Testing)
              │                             └── Epic 9 (MVP Packaging)
              │                                   └── Epic 10 (Expansion Readiness)
              └── (Epic 4 also depends on Epic 2)
```

**Cross-repo dependency:** `wild-rails-safe-introspection-mcp` Epic 10 (capability gate integration) depends on this repo's Epic 7 (public interface) being stable. The introspection repo has already designed a stub interface in its Epic 6 — the real interface from this repo must be compatible.

---

## 5. Document-Backed Execution Notes

| When | Document | Epic |
|------|----------|------|
| Phase 0 | Blueprint | — |
| Phase 0 | Capability model | — |
| Phase 0 | Governance model | — |
| Phase 0 | Architecture decisions | — |
| During Epic 7 | Interface contract | 7 |
| During Epic 8 | Evaluation strategy | 8 |
| During Epic 9 | Configuration reference | 9 |
| During Epic 9 | Operator workflow guide | 9 |
| During Epic 9 | Consumer integration guide | 9 |
| Closing v1 | Expansion roadmap | 10 |

---

## 6. Readiness for Beads

This plan is complete. The next step is to initialize repo-local Beads and create the task structure from this plan.
