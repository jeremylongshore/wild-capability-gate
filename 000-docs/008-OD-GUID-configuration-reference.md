# Configuration Reference — wild-capability-gate

**Document type:** Operator guide
**Filed as:** `008-OD-GUID-configuration-reference.md`
**Status:** Active
**Last updated:** 2026-03-17

---

## Overview

The capability gate loads its configuration from a directory containing two YAML files. Configuration is loaded once at initialization and cannot be modified at runtime.

```
config/capability_gate/
  capabilities.yml    # What capabilities exist and what they require
  grants.yml          # Who is allowed to use which capabilities
```

---

## capabilities.yml

Defines the capabilities the gate knows about.

### Structure

```yaml
capabilities:
  - name: basic_introspection
    description: "Read-only schema inspection"
    risk_level: standard
    prerequisites: []

  - name: privileged_introspection
    description: "Full runtime introspection including live data"
    risk_level: elevated
    prerequisites:
      - type: file_exists
        path: "config/safety-attestation-introspection.md"

  - name: admin_tools
    description: "Administrative operations on the target application"
    risk_level: critical
    prerequisites:
      - type: file_exists
        path: "config/safety-attestation-admin.md"
      - type: config_value
        key: admin_tools_enabled
        value: true
```

### Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `name` | String | Yes | Unique identifier. Becomes a Ruby Symbol internally. |
| `description` | String | No | Human-readable explanation. Defaults to `""`. |
| `risk_level` | String | Yes | One of: `standard`, `elevated`, `critical`. |
| `prerequisites` | Array | No | Conditions that must be met before granting. Defaults to `[]`. |

### Risk levels

| Level | Meaning |
|-------|---------|
| `standard` | Low-risk, read-only operations |
| `elevated` | Sensitive data access, broader scope |
| `critical` | Operations that could cause significant harm |

Risk levels are informational for v1 — they appear in audit events and capability listings but do not change evaluation behavior. All capabilities follow the same evaluation pipeline regardless of risk level.

### Prerequisite types

| Type | Parameters | Passes when |
|------|-----------|-------------|
| `file_exists` | `path` (String) | The file at `path` exists on the filesystem |
| `config_value` | `key` (String), `value` (any) | `context[key]` equals `value` at evaluation time |

Prerequisites are evaluated in order. The first failure short-circuits — remaining prerequisites are not checked.

### Validation errors

The loader raises at initialization if:
- The file is missing or not readable
- YAML syntax is invalid
- Top-level `capabilities` key is missing or not an array
- A capability is missing `name` or `risk_level`
- `risk_level` is not one of the three valid values
- Duplicate capability names exist

---

## grants.yml

Defines which callers can use which capabilities.

### Structure

```yaml
grants:
  - caller: "service-account:introspection-agent"
    capabilities:
      - basic_introspection
      - privileged_introspection

  - caller: "service-account:admin-agent"
    capabilities:
      - basic_introspection
      - admin_tools

  - caller: "*"
    capabilities:
      - basic_introspection
```

### Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `caller` | String | Yes | Caller identity to match. `"*"` matches all callers. |
| `capabilities` | Array of Strings | Yes | Capability names this caller is granted. |

### Matching rules

- Caller matching is **exact string comparison** (no regex, no prefix matching)
- The wildcard `"*"` matches any caller identity string
- A caller can appear in multiple grant entries — capabilities are additive
- Capabilities listed in grants must exist in `capabilities.yml` or they will never match (no error, just never granted)

### Validation errors

The loader raises at initialization if:
- The file is missing or not readable
- YAML syntax is invalid
- Top-level `grants` key is missing or not an array
- A grant is missing `caller` or `capabilities`
- `capabilities` is not an array of strings

---

## What is NOT configurable

- **Evaluation order** — always: known? → granted? → prerequisites? → allow
- **Fail-closed behavior** — cannot be disabled
- **Audit emission** — cannot be turned off (but audit_log_path is optional at the Gate level)
- **Prerequisite bypass** — no skip mode, no override flag
- **Runtime modification** — configuration is immutable after initialization
