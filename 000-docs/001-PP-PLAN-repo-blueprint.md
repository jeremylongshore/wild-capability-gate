# wild-capability-gate — Repo Blueprint

**Document type:** Canonical repo blueprint
**Filed as:** `001-PP-PLAN-repo-blueprint.md`
**Repo:** `wild-capability-gate`
**Archetype:** D — Coordination / Registry
**Status:** Active — v1 complete
**Last updated:** 2026-03-17

---

## 1. Purpose

This is the canonical blueprint for `wild-capability-gate`. It defines the repo's mission, boundaries, architecture direction, and planning expectations before implementation begins.

---

## 2. Repo Mission

`wild-capability-gate` provides governed access control for sensitive AI tool capabilities across the Wild ecosystem.

It ensures that higher-risk tools are not available to an agent or operator until the required safety prerequisites are satisfied, the caller's identity is verified, and the access decision is logged. The gate is the mechanism that transforms "this tool exists" into "this tool is allowed for this caller in this context."

Other repos in the ecosystem — starting with `wild-rails-safe-introspection-mcp` and `wild-admin-tools-mcp` — will integrate against this repo's public interface to enforce capability-level access control on their tool surfaces.

---

## 3. Problem Statement

AI agents increasingly have access to powerful tools. But not all tools should be available to all callers at all times. Some tools carry higher risk: they access sensitive data, perform privileged operations, or have broader blast radius.

Without a capability gate, the only access control is "the tool exists and you can call it." That is the equivalent of giving everyone root. The alternative is embedding ad-hoc access checks into every tool handler in every repo — which is inconsistent, untestable, and unmaintainable.

`wild-capability-gate` centralizes capability access control into a reusable, testable, auditable layer. Repos declare which capabilities require gating. The gate evaluates access rules. The decision is logged. Consuming repos get a clean interface they can call before executing a privileged tool.

---

## 4. Core Product Vision

The gate is not a product users interact with directly. It is infrastructure that other repos consume. Its value is invisible when it works correctly: privileged tools are available to authorized callers and denied to everyone else.

**Capability definitions, not tool definitions.**
The gate does not know or care what tools do. It knows about capabilities — named, scoped, versioned access grants. A capability might map to one tool or several. The gate evaluates "does this caller have capability X?" — the calling repo decides which tools require that capability.

**Prerequisite-based gating.**
Some capabilities require prerequisites before they can be unlocked: a safety document must exist, an operator attestation must be on file, a configuration must be verified. The gate supports prerequisite checks as part of the evaluation.

**Session-scoped access state.**
Capability evaluations are session-scoped. A capability granted at the start of a session remains granted for the session. Capabilities are not cached across sessions. Each session starts clean.

**Conservative by default.**
If a capability is not explicitly granted, it is denied. Unknown capabilities are denied. Expired or revoked grants are denied. The gate errs on the side of refusal.

**Reusable interface for consuming repos.**
The gate exposes a clean, minimal interface: `gate.evaluate(caller:, capability:, context:) → EvaluationResult`. Consuming repos call this interface before executing privileged tools. The interface is stable and documented in `006-AT-STND-interface-contract.md`.

---

## 5. Non-Goals and Boundaries

**Not a full IAM platform.**
This is not an org-wide identity and access management system. It does not manage users, groups, roles, or org hierarchies. It evaluates capability access for a given caller in a given context.

**Not a policy engine for everything.**
The gate evaluates capability access. It does not enforce data access policies (that's the query guard in `wild-rails-safe-introspection-mcp`), hook execution policies (that's `wild-hook-ops`), or permission model correctness (that's `wild-permission-analyzer`).

**Not an MCP server.**
The gate does not expose MCP tools. It is a library or service that MCP servers consume. It lives behind the MCP layer, not on it.

**Not an analytics or reporting tool.**
The gate logs access decisions. Analyzing those logs for patterns, anomalies, or insights belongs in the observability pipeline repos, not here.

**Not a UI.**
There is no dashboard, no admin panel, no web interface. The gate is a programmatic interface with configuration files. Operator visibility comes from audit logs and configuration inspection.

---

## 6. Primary Users and Consumers

**Consuming repos** — `wild-rails-safe-introspection-mcp`, `wild-admin-tools-mcp`, and potentially `wild-hook-ops`. These repos call the gate's interface to check capability access before executing privileged tools.

**Operators** — platform engineers who configure capability definitions, set prerequisites, and manage access grants through configuration files.

**Security reviewers** — teams that audit capability access decisions through the gate's log output.

### Key use cases

1. **Check tool access before execution** — a consuming repo calls `gate.evaluate(caller:, capability:, context:)` before running a privileged query tool.
2. **Deny and explain** — when access is denied, the gate returns a reason: "capability not granted," "prerequisite not met," "caller not authorized." The consuming repo can surface this to the agent.
3. **Audit a session's access decisions** — an operator reviews the gate's log for a session to see which capabilities were checked, granted, or denied.
4. **Configure capability prerequisites** — an operator sets a prerequisite that capability `:admin_tools` requires attestation document `safety-attestation-admin.md` to exist before the capability can be granted.

---

## 7. Architecture Direction

### Major components

**Capability registry**
A configuration-driven registry of known capabilities. Each capability has a name, a description, a risk level, and optionally a set of prerequisites. The registry is loaded at startup from YAML configuration.

**Rule evaluator**
The core logic. Given a caller, a capability, and a context, the evaluator checks: is this capability known? Does the caller meet the grant requirements? Are all prerequisites satisfied? Returns allowed or denied with a reason.

**Session state manager**
Tracks capability evaluation results within a session. Once a capability is evaluated, the result is cached for the session. Each new session starts clean.

**Prerequisite checker**
Evaluates prerequisite conditions. Prerequisites can include: file existence checks (does a safety document exist?), configuration checks (is a feature flag enabled?), attestation checks (has an operator signed off?).

**Audit emitter**
Every capability evaluation — whether granted or denied — produces a structured audit event. Events include: caller identity, capability name, evaluation result, prerequisites checked, timestamp.

**Public interface**
The minimal, stable interface consuming repos call:
```ruby
gate = Wild::CapabilityGate.new(config_path: "config/capability_gate")
result = gate.evaluate(caller: "service-account:agent", capability: :privileged_introspection)
result.allowed?   # => true/false
result.reason     # => nil or :unknown_capability, :not_granted, :prerequisite_not_met, :evaluation_error
```

### Language

Ruby. The primary consumers are Ruby repos. The gate is a Ruby gem.

---

## 8. Governance Posture

The gate is itself a safety-critical component. If the gate is wrong — if it grants access when it should deny, or fails open instead of closed — the safety model of every consuming repo is compromised.

**Fail closed.** If the gate encounters an error during evaluation, the result is denial, not permission.

**No implicit grants.** A capability must be explicitly configured to be grantable. Unknown capabilities are denied.

**Prerequisites are enforced, not advisory.** If a prerequisite is defined, it must pass. There is no "skip prerequisites" mode.

**Audit is mandatory.** Every evaluation produces a log entry. There is no silent evaluation path.

**Configuration is startup-only.** Capability definitions and grant rules are loaded at startup. They cannot be modified at runtime through the public interface.

---

## 9. Relationship to Other Wild Repos

**`wild-rails-safe-introspection-mcp`** — First consumer. The introspection server's Epic 6 stubs a capability gate interface. This repo implements the real thing behind that interface. The introspection server will call the gate before executing privileged tools.

**`wild-admin-tools-mcp`** — Second likely consumer. Admin tools carry higher risk (they can mutate state). The gate is critical here — it should enforce that admin capabilities require stronger prerequisites.

**`wild-hook-ops`** — May use the gate for hook execution authorization. Depends on whether hooks need capability-level gating.

**`wild-session-telemetry`** — May consume gate audit events as telemetry input. The gate does not depend on the telemetry repo, but can emit events in a format the telemetry layer can ingest.

**`wild-skillops-registry`** — May eventually register capabilities from the gate. Later-phase concern.

---

## 10. Risks and Design Tensions

**Usefulness vs. lockdown.** A gate that denies everything is safe but prevents repos from working. The default configuration must be conservative but not crippling — enough default capabilities should be grantable for basic operation.

**Interface stability vs. evolving needs.** Consuming repos will design against the gate's interface early. If the interface changes frequently, it creates rework. But the interface must be simple enough to stabilize quickly.

**Prerequisite complexity vs. operator burden.** Powerful prerequisite checks (file existence, attestation, feature flags) are useful but add configuration burden. Start with simple prerequisite types and add complexity only when real use cases demand it.

**Centralized control vs. repo autonomy.** The gate centralizes access control, which creates a single point of policy. If the gate is wrong, multiple repos are affected. This is the intended trade-off: centralized control is easier to audit and harder to misconfigure than scattered ad-hoc checks.

---

## 11. MVP Recommendation

A credible v1 should do the following:

- **Capability registry** — YAML-configured, loaded at startup, with name/description/risk-level/prerequisites per capability
- **Rule evaluator** — checks caller identity against grant configuration, checks prerequisites, returns allowed/denied with reason
- **Simple prerequisite types** — file existence and configuration value checks (no complex attestation workflows yet)
- **Session state** — caches evaluation results per session
- **Audit logging** — every evaluation logged as structured JSON
- **Fail-closed behavior** — errors result in denial
- **Clean public interface** — `gate.evaluate(caller:, capability:, context:)` returning a result object
- **Strong tests** — every grant/denial path tested, fail-closed behavior proven

**What v1 does not include:** complex attestation workflows, UI, API endpoints, dynamic policy updates, cross-session capability persistence, integration with external identity providers.

---

## 12. Current Status

**v1 complete.** All 10 epics are implemented and verified:

- Capability registry, rule evaluator, prerequisite checking, session caching, audit trail, public interface
- Adversarial safety tests proving all governance rules and defect conditions
- Operator docs, config reference, integration guide, and production-ready README
- 224 examples, 0 failures; CI with Gemini code review

See `005-PP-PLAN-epic-build-plan.md` for the full execution history.

---

## 13. Next Steps

- Consumer integration: `wild-rails-safe-introspection-mcp` and `wild-admin-tools-mcp` integrate against the stable interface
- Extension points documented in `011-PP-PLAN-expansion-roadmap.md` for v2 planning
