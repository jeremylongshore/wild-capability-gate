# Expansion Roadmap — wild-capability-gate

**Document type:** Planning roadmap
**Filed as:** `011-PP-PLAN-expansion-roadmap.md`
**Status:** Active
**Last updated:** 2026-03-17

---

## Purpose

This document captures what v1 includes, what it intentionally excludes, what extension points exist for v2, and the current integration status with consuming repos. It exists so future sessions do not relitigate settled decisions.

---

## 1. What v1 includes

| Component | Status |
|-----------|--------|
| Capability registry (YAML-configured) | Implemented, tested |
| Rule evaluator (grant matching + decision pipeline) | Implemented, tested |
| Prerequisite checking (`file_exists`, `config_value`) | Implemented, tested |
| Session-scoped evaluation caching with TTL | Implemented, tested |
| Audit trail (JSON Lines, append-only) | Implemented, tested |
| Public interface (`Gate.evaluate`, `Gate.capabilities`) | Implemented, tested, documented |
| Fail-closed error handling | Implemented, adversarially tested |
| Adversarial safety tests (all 5 governance rules, all 7 defect conditions) | Complete |
| CI with Gemini code review via WIF | Active |
| Operator docs, config reference, integration guide | Complete |

**Test coverage:** 224 examples, 0 failures, 0 rubocop offenses.

---

## 2. Confirmed out-of-scope for v1

These items were considered and explicitly excluded. They are not bugs or missing features — they are deliberate boundaries.

| Item | Why excluded |
|------|-------------|
| Complex attestation workflows (signed documents, multi-party approval) | Adds significant complexity. `file_exists` covers the v1 use case. |
| Time-window prerequisites (capability only valid during certain hours) | No real v1 use case. Add when an operator actually needs it. |
| Caller attribute matching (regex, prefix, role-based) | Exact string match is sufficient. Richer matching adds ambiguity. |
| Dynamic policy updates (runtime config reload) | Immutability at runtime is a safety feature, not a limitation. |
| HTTP/API surface | The gate is a library, not a service. Consuming repos provide the API layer. |
| Dashboard or UI | Operator visibility comes from audit logs and `jq`. |
| Cross-session capability persistence | Sessions start clean by design. Persistence changes the trust model. |
| External identity providers (OAuth, OIDC) | Callers are opaque strings. Identity resolution belongs to the consumer. |
| Audit log analysis or alerting | The gate writes events. Analysis belongs in the telemetry/observability layer. |
| RubyGems publication | v1 is consumed via path reference. Publish when the interface is proven stable by real consumers. |

---

## 3. Planned v2 extension points

These are areas where the architecture was designed to support future extension. None require v1 changes.

### 3.1 New prerequisite types

The prerequisite system is extensible. New types are added by:
1. Creating a new checker class in `lib/wild/capability_gate/prerequisites/`
2. Registering it in `Prerequisites::Checker`

**Likely candidates:**

| Type | Description | When to add |
|------|-------------|------------|
| `attestation_signed` | Requires a signed attestation document with a specific hash or content | When operators need cryptographic proof, not just file existence |
| `time_window` | Capability only valid during specified hours/days | When time-sensitive operations emerge |
| `caller_attribute` | Match caller against patterns (prefix, regex, role) | When the ecosystem has enough callers to need grouping |
| `env_variable` | Require a specific environment variable to be set | When deployment-level gating is needed |

### 3.2 Richer audit events

The `Audit::Event` schema can be extended with additional fields without breaking existing consumers:

- `duration_ms` — how long the evaluation took
- `cache_hit` — whether the result came from session cache
- `prerequisites_detail` — per-prerequisite pass/fail detail

### 3.3 Configuration validation CLI

A standalone `wild-capability-gate validate config/capability_gate/` command that validates config without starting an application. Currently, validation happens at initialization time.

### 3.4 Policy versioning

Add an optional `version` field to `capabilities.yml` so operators can track when definitions changed and correlate with audit log events.

---

## 4. Integration status with consuming repos

### wild-rails-safe-introspection-mcp

**Status:** Not yet integrated. The introspection server's Epic 6 defined a stub capability gate interface. The real gate (this repo) implements the interface those stubs designed against.

**Integration path:** Add `wild-capability-gate` as a path gem, replace stubs with real `Gate.evaluate` calls, configure `capabilities.yml` and `grants.yml` for the introspection server's tool set.

**Blocking on:** The introspection server reaching its integration epic.

### wild-admin-tools-mcp

**Status:** Not yet created as a repo. Planned as a consumer of the gate for administrative operations.

**Integration path:** Same pattern as introspection server. Higher-risk capabilities with stronger prerequisites.

### Other repos

`wild-hook-ops`, `wild-session-telemetry`, and `wild-skillops-registry` may consume the gate in later phases. No integration work is planned yet.

---

## 5. Risks that remain

| Risk | Mitigation |
|------|-----------|
| First real consumer may surface interface gaps | Interface contract (Doc 006) is intentionally minimal. Only `evaluate` and `capabilities`. |
| Audit log file can grow unbounded | Document log rotation in operator guide. Not a gate concern — standard ops. |
| Session cache has no size limit | TTL-based expiry prevents stale entries. Size limits can be added if real load testing reveals a concern. |
| No standalone config validation | Validation happens at boot. A CLI tool is a v2 extension point. |
