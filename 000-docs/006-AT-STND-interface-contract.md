# Interface Contract — wild-capability-gate

**Document type:** Interface standard
**Filed as:** `006-AT-STND-interface-contract.md`
**Status:** Active
**Last updated:** 2026-03-17

---

## Purpose

This document defines the public interface that consuming repos call. It is the stable contract other repos design against. Changes to this interface affect every consumer.

---

## 1. Initialization

```ruby
gate = Wild::CapabilityGate.new(
  config_path: "config/capability_gate",
  audit_log_path: "log/capability_gate.jsonl",  # optional
  session_id: "session-uuid"                     # optional
)
```

### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `config_path` | String | Yes | Path to directory containing `capabilities.yml` and `grants.yml` |
| `audit_log_path` | String | No | Path to JSON Lines audit log file. Created on first write. |
| `session_id` | String | No | Session identifier included in audit events |

### Configuration directory structure

```
config/capability_gate/
  capabilities.yml    # Capability definitions (see Doc 002 Section 4)
  grants.yml          # Caller-to-capability grants (see Doc 002 Section 5)
```

### Error behavior

Configuration errors (missing files, invalid YAML, schema violations) raise at initialization time. Broken config must be caught at startup, not during evaluation.

---

## 2. Evaluate

```ruby
result = gate.evaluate(
  caller: "service-account:introspection-agent",
  capability: :privileged_introspection,
  context: { "admin_tools_enabled" => true }   # optional
)
```

### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `caller` | String | Yes | Caller identity string |
| `capability` | Symbol or String | Yes | Capability name (normalized to Symbol internally) |
| `context` | Hash | No | Runtime context for prerequisite checks (default: `{}`) |

### Return value

Returns an `EvaluationResult` — always. Never raises `StandardError`.

```ruby
result.allowed?              # => true or false
result.denied?               # => true or false
result.reason                # => nil (allowed) or Symbol (:unknown_capability, :not_granted, :prerequisite_not_met, :evaluation_error)
result.details               # => nil or String (human-readable explanation)
result.capability_name       # => Symbol
result.caller_id             # => String
result.prerequisites_checked # => Array of Symbols
result.timestamp             # => Time
```

### Fail-closed guarantee

If any error occurs during evaluation, the result is denial with `reason: :evaluation_error`. The gate never grants access due to an error. See Doc 003 Section 1.

---

## 3. Capabilities

```ruby
caps = gate.capabilities   # => Array of Capability objects
```

Returns all registered capabilities. Each capability exposes:

```ruby
cap.name            # => :privileged_introspection
cap.description     # => "Extended introspection..."
cap.risk_level      # => :elevated
cap.prerequisites   # => Array of Prerequisite objects
cap.prerequisites?  # => true
```

This is read-only. Capabilities cannot be modified at runtime (Doc 003 Section 4).

---

## 4. Stability Guarantees

| Guarantee | Scope |
|-----------|-------|
| `evaluate` signature is stable | v1+ |
| `capabilities` signature is stable | v1+ |
| `EvaluationResult` attributes are stable | v1+ |
| Denial reason symbols are stable | v1+ |
| Config file names (`capabilities.yml`, `grants.yml`) are stable | v1+ |
| New optional parameters may be added | Non-breaking |

Breaking changes require a major version bump and documented migration path.

---

## 5. Integration Pattern

```ruby
# In a consuming repo's initializer or boot sequence:
CAPABILITY_GATE = Wild::CapabilityGate.new(
  config_path: Rails.root.join("config/capability_gate"),
  audit_log_path: Rails.root.join("log/capability_gate.jsonl"),
  session_id: SecureRandom.uuid
)

# Before executing a privileged tool:
result = CAPABILITY_GATE.evaluate(
  caller: current_caller_identity,
  capability: :privileged_introspection,
  context: runtime_context
)

if result.denied?
  log_denial(result)
  return deny_response(result.reason, result.details)
end

# Proceed with privileged operation
```

---

## 6. What This Interface Does NOT Provide

- No HTTP/API surface — the gate is a library, not a service
- No session management — callers manage their own session IDs
- No user/role management — callers are identity strings, not user objects
- No configuration modification — config is loaded at initialization, immutable at runtime
- No audit log reading — the gate writes audit events, consumers read them separately
