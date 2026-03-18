# Capability Model — wild-capability-gate

**Document type:** Interface contract / standard
**Filed as:** `002-AT-STND-capability-model.md`
**Status:** Active
**Last updated:** 2026-03-17

---

## Purpose

This document defines the capability model — the core data structures and evaluation semantics that the gate uses. Other repos design their integration against this model. Changes to this model affect every consumer.

---

## 1. What Is a Capability

A capability is a named, scoped access grant for a specific kind of privileged operation. It is not a tool, not a permission, not a role. It is the answer to: "Is this caller allowed to do this category of thing in this context?"

A capability has:

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `name` | Symbol | Yes | Unique identifier (e.g., `:privileged_introspection`) |
| `description` | String | Yes | Human-readable explanation of what this capability grants |
| `risk_level` | Symbol | Yes | `:standard`, `:elevated`, or `:critical` |
| `prerequisites` | Array | No | Conditions that must be true before the capability can be granted |

---

## 2. Risk Levels

| Level | Meaning | Default behavior |
|-------|---------|-----------------|
| `:standard` | Low-risk operations. Read-only, metadata-only, or non-sensitive. | Granted to any authenticated caller by default. |
| `:elevated` | Higher-risk operations. Access to sensitive data or broader scope. | Requires explicit grant configuration. |
| `:critical` | Operations that could cause significant harm if misused. | Requires explicit grant + prerequisite satisfaction. |

---

## 3. Prerequisite Types

Prerequisites are conditions evaluated before a capability can be granted. v1 supports:

| Type | Semantics | Example |
|------|-----------|---------|
| `file_exists` | A specific file path must exist on the filesystem | `{ type: file_exists, path: "config/safety-attestation.md" }` |
| `config_value` | A configuration key must equal an expected value | `{ type: config_value, key: "admin_tools_enabled", value: true }` |

Future types (not v1): `attestation_signed`, `time_window`, `caller_attribute`.

---

## 4. Capability Configuration Format

```yaml
# config/capabilities.yml

capabilities:
  - name: basic_introspection
    description: "Read-only schema and record inspection for allowed models"
    risk_level: standard
    prerequisites: []

  - name: privileged_introspection
    description: "Extended introspection with broader model access and higher row caps"
    risk_level: elevated
    prerequisites:
      - type: file_exists
        path: "config/safety-attestation-introspection.md"

  - name: admin_tools
    description: "Write-capable administrative operations"
    risk_level: critical
    prerequisites:
      - type: file_exists
        path: "config/safety-attestation-admin.md"
      - type: config_value
        key: admin_tools_enabled
        value: true
```

---

## 5. Grant Configuration Format

```yaml
# config/grants.yml

grants:
  # Grant by caller identity
  - caller: "service-account:introspection-agent"
    capabilities:
      - basic_introspection
      - privileged_introspection

  - caller: "service-account:admin-agent"
    capabilities:
      - basic_introspection
      - admin_tools

  # Wildcard: all authenticated callers get standard capabilities
  - caller: "*"
    capabilities:
      - basic_introspection
```

---

## 6. Evaluation Semantics

```
evaluate(caller, capability, context)
  │
  ▼
Is capability known?
  │  no → DENY (unknown_capability)
  │  yes
  ▼
Is caller granted this capability?
  │  no → DENY (not_granted)
  │  yes
  ▼
Are all prerequisites satisfied?
  │  no → DENY (prerequisite_not_met: which one)
  │  yes
  ▼
ALLOW
  │
  ▼
Log the evaluation result (allowed or denied)
```

---

## 7. Evaluation Result Object

```ruby
result = gate.evaluate(caller:, capability:, context:)

result.allowed?          # => true or false
result.denied?           # => true or false
result.reason            # => nil (if allowed) or reason symbol
result.details           # => nil or human-readable explanation
result.capability_name   # => :privileged_introspection
result.caller_id         # => "service-account:introspection-agent"
result.prerequisites_checked  # => [:file_exists, :config_value]
result.timestamp         # => Time
```

---

## 8. Audit Event Format

Every evaluation produces:

```json
{
  "event": "capability_evaluation",
  "timestamp": "ISO 8601",
  "caller_id": "service-account:introspection-agent",
  "capability": "privileged_introspection",
  "risk_level": "elevated",
  "result": "allowed | denied",
  "reason": null,
  "prerequisites_checked": ["file_exists"],
  "prerequisites_passed": true,
  "session_id": "uuid",
  "context": {}
}
```

---

## 9. Fail-Closed Semantics

If any step in evaluation raises an error — configuration missing, prerequisite check fails to run, caller identity cannot be resolved — the result is **denial**, not permission.

The denial reason is `evaluation_error` and the details include the error class (but not a full stack trace, to avoid information leakage).
