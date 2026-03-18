# Governance Model — wild-capability-gate

**Document type:** Safety standard (moderate depth — Archetype D)
**Filed as:** `003-TQ-STND-governance-model.md`
**Status:** Active
**Last updated:** 2026-03-17

---

## Purpose

The capability gate is safety-critical infrastructure. If it grants access incorrectly, every consuming repo's safety model is compromised. This document defines the governance constraints that prevent that.

---

## 1. Fail-Closed Rule

If the gate cannot complete an evaluation — due to missing configuration, broken prerequisite checks, unresolvable caller identity, or any runtime error — the result is **denial**. Never permission.

This is the single most important safety property of the gate. It must be tested adversarially and proven before any consuming repo integrates.

---

## 2. No Implicit Grants

A capability must be explicitly listed in the grant configuration for a caller to receive it. There is no "default allow" for any capability. Unknown capabilities are denied. Callers without explicit grants are denied.

The only exception is the wildcard caller (`"*"`) in the grant config, which explicitly grants named capabilities to all authenticated callers. Even this is explicit configuration, not implicit behavior.

---

## 3. Prerequisites Are Enforced

If a capability defines prerequisites, they must pass. There is no "skip prerequisites" mode, no override flag, no operator escape hatch that bypasses prerequisite evaluation. If an operator needs to grant a capability without prerequisites, the correct action is to remove the prerequisites from the capability definition in configuration, not to bypass the evaluation engine.

---

## 4. Configuration Immutability at Runtime

Capability definitions, grant rules, and prerequisites are loaded at server startup. They cannot be modified through the public interface at runtime. This prevents:
- An agent from escalating its own capabilities mid-session
- A compromised consumer from modifying gate policy
- Drift between what the operator configured and what the gate enforces

Changes require a restart. This is a feature.

---

## 5. Audit Completeness

Every evaluation — allowed, denied, or errored — produces an audit event. There is no silent evaluation path. The audit log is the evidence that the gate is working correctly. If an evaluation produces no audit event, that is a safety defect.

---

## 6. Safety Defect Definition

A safety defect in the capability gate is any code that would allow:

1. A capability to be granted when the grant configuration does not authorize it
2. A prerequisite to be skipped when it is defined
3. An evaluation to complete without producing an audit event
4. An error to result in permission instead of denial
5. A caller identity to be fabricated or bypassed
6. Configuration to be modified at runtime through the public interface
7. An unknown capability to be granted

These are blocking defects. They must be fixed before the affected code ships.
