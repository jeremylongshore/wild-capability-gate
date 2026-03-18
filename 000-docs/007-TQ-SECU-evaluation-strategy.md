# Evaluation Strategy — wild-capability-gate

**Document type:** Security evaluation strategy
**Filed as:** `007-TQ-SECU-evaluation-strategy.md`
**Status:** Active
**Last updated:** 2026-03-17

---

## Purpose

This document describes how the capability gate's safety claims are verified through adversarial testing. Every governance rule from Doc 003 and every safety defect condition has a corresponding test that proves the gate behaves correctly.

---

## 1. Test Structure

Safety tests are organized in `spec/safety/`:

| File | Coverage |
|------|----------|
| `governance_rules_spec.rb` | All 5 governance rules from Doc 003 Sections 1-5 |
| `safety_defects_spec.rb` | All 7 safety defect conditions from Doc 003 Section 6 |

These tests run against the public interface (`Wild::CapabilityGate::Gate`), not internal implementation details.

---

## 2. Governance Rule Coverage

| Rule | Doc 003 Section | Tests | Verified behavior |
|------|----------------|-------|-------------------|
| Fail-Closed | 1 | 5 | Runtime errors → denial, nil inputs handled, config errors raise at boot |
| No Implicit Grants | 2 | 4 | Unknown capabilities denied, unconfigured callers denied, empty grants denied |
| Prerequisites Enforced | 3 | 4 | Missing files denied, wrong config values denied, no skip/override possible |
| Configuration Immutability | 4 | 4 | No public mutator methods, frozen objects, no add/remove/grant/revoke |
| Audit Completeness | 5 | 5 | Every evaluation type produces audit event, one event per evaluation |

---

## 3. Safety Defect Coverage

| Defect | Doc 003 Section 6 | Tests | Attack vector tested |
|--------|-------------------|-------|---------------------|
| 1. Unauthorized grant | #1 | 3 | Cross-caller grant, wildcard scope escape, partial name match |
| 2. Prerequisite bypass | #2 | 2 | Granted caller with unsatisfied prereq, multi-prereq short-circuit |
| 3. Silent evaluation | #3 | 2 | Audit event count matches evaluation count, all denial types logged |
| 4. Error grants permission | #4 | 3 | RuntimeError, TypeError, ArgumentError — all return denial |
| 5. Caller identity fabrication | #5 | 3 | SQL injection in caller string, empty caller, identity fidelity |
| 6. Runtime config modification | #6 | 2 | Public API surface audit, array mutation attempt |
| 7. Unknown capability granted | #7 | 4 | Fabricated names, similar names, empty string, numeric names |

---

## 4. Bug Found and Fixed

During adversarial testing, one fail-closed gap was discovered and fixed:

**Bug:** When `capability: nil` was passed to `gate.evaluate`, the error handler `deny_with_error` itself raised `NoMethodError` because `EvaluationResult.denied(capability_name: nil)` calls `nil.to_sym`.

**Fix:** `deny_with_error` now falls back to `:unknown` when capability is nil: `capability_name: capability || :unknown`.

**Significance:** This proves the value of adversarial testing — a subtle edge case in the error handler could have caused the gate to raise instead of denying, violating the fail-closed rule.

---

## 5. What Is NOT Tested

- Performance under load (not a v1 concern)
- Concurrent access (gate is in-process, no shared mutable state)
- External penetration testing (out of scope for library)
- Audit log file permissions (OS-level concern)
- Network-based attacks (gate is not a service)

---

## 6. Confidence Assessment

All 5 governance rules and all 7 safety defect conditions are covered by adversarial tests. The test suite runs in under 0.3 seconds and requires no external dependencies. Every test runs against the public interface, proving that safety guarantees hold at the API boundary, not just internally.
