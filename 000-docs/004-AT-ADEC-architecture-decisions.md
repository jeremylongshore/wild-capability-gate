# Architecture Decisions — wild-capability-gate

**Document type:** Architecture decision record
**Filed as:** `004-AT-ADEC-architecture-decisions.md`
**Status:** Active
**Last updated:** 2026-03-17

---

## Decision 1: Ruby Gem, Not a Standalone Service

**Context:** The gate could be a separate network service (HTTP API, gRPC) or a Ruby gem that consuming repos depend on directly.

**Decision:** Ruby gem. Consuming repos add it as a dependency and call it in-process.

**Rationale:** The primary consumers are Ruby repos. An in-process gem eliminates network latency, service discovery, and deployment complexity. The gate's interface is a single method call — it does not need HTTP routing. A gem is simpler to test, simpler to version, and simpler to integrate.

**Trade-off:** All consumers must be Ruby. If a non-Ruby consumer appears, a thin service wrapper can be added later. This is an acceptable deferred cost for v1 simplicity.

---

## Decision 2: YAML Configuration, Not Database-Driven

**Context:** Capability definitions and grant rules could be stored in a database (dynamic, queryable) or in YAML files (static, version-controlled).

**Decision:** YAML files loaded at startup.

**Rationale:** YAML files are version-controlled, reviewable in PRs, and auditable through git history. Database-driven configuration introduces state management, migration concerns, and the risk of runtime modification. For v1, the number of capabilities and grants is small enough that YAML is adequate. The files are explicit and inspectable.

**Trade-off:** Adding or changing capabilities requires a restart. At the scale of v1 (single-digit capabilities), this is acceptable.

---

## Decision 3: Session-Scoped State, Not Persistent State

**Context:** Capability evaluation results could be cached per-session (ephemeral) or persisted across sessions (durable).

**Decision:** Session-scoped. Each session starts with no cached evaluations. Results are cached within the session only.

**Rationale:** Persistent state introduces synchronization problems: what if a grant is revoked but a cached allowance persists? Session-scoped state is simpler and safer. The cost is re-evaluation at session start, which is negligible for YAML-based configuration.

---

## Decision 4: Fail-Closed Error Handling, No Exceptions

**Context:** When an error occurs during evaluation (broken config, missing file for prerequisite check), the gate could raise an exception or return a denial.

**Decision:** Return a denial result. Never raise an exception from the public interface.

**Rationale:** If the gate raises an exception, the consuming repo must handle it — and if the handler is wrong (or missing), the tool might execute without an access check. A denial result is always safe. The consuming repo's control flow stays simple: check `result.allowed?`, proceed or deny.

The denial result includes `reason: :evaluation_error` and `details` with the error class so operators can diagnose the issue from logs.

---

## Decision 5: Minimal Public Interface

**Context:** The public interface could expose multiple methods (check capability, list capabilities, inspect grants, modify configuration) or a single evaluation method.

**Decision:** One primary method: `gate.evaluate(caller:, capability:, context:)`. Plus `gate.capabilities` for listing known capabilities (read-only, for tool discovery).

**Rationale:** A minimal interface is easier to stabilize, easier to test, and harder to misuse. Consuming repos need exactly one thing: "can this caller do this?" Everything else is operator tooling, not consumer API.

---

## Decision 6: Caller Identity Is a String, Not an Object

**Context:** The gate needs to know who is calling. The identity could be a rich object (with roles, attributes, metadata) or a simple string identifier.

**Decision:** String identifier (e.g., `"service-account:introspection-agent"`). The gate matches this against the grant configuration's `caller` field.

**Rationale:** The gate does not manage identities. It receives an identity string from the consuming repo's auth layer and matches it against grant rules. Keeping the identity simple avoids coupling the gate to any specific identity provider or auth system. If richer identity matching is needed later (attributes, roles), the grant configuration can be extended without changing the public interface.
