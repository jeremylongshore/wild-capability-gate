# Operator Workflow Guide — wild-capability-gate

**Document type:** Operator guide
**Filed as:** `009-OD-GUID-operator-workflow.md`
**Status:** Active
**Last updated:** 2026-03-17

---

## Who this is for

Platform engineers or operators who configure and maintain capability gate deployments. This guide covers common operational tasks.

---

## 1. Add a new capability

Edit `capabilities.yml`:

```yaml
capabilities:
  # ... existing capabilities ...
  - name: bulk_export
    description: "Export large datasets from the application"
    risk_level: elevated
    prerequisites:
      - type: file_exists
        path: "config/safety-attestation-export.md"
```

Then grant it to the appropriate callers in `grants.yml`:

```yaml
grants:
  # ... existing grants ...
  - caller: "service-account:export-agent"
    capabilities:
      - bulk_export
```

**Restart required.** Configuration is loaded at initialization. Changes take effect on next application restart.

---

## 2. Grant a capability to a caller

Add an entry to `grants.yml`:

```yaml
grants:
  - caller: "service-account:new-agent"
    capabilities:
      - basic_introspection
```

Or add to an existing caller's list:

```yaml
grants:
  - caller: "service-account:existing-agent"
    capabilities:
      - basic_introspection
      - privileged_introspection   # newly added
```

**Restart required.**

---

## 3. Revoke a capability

Remove the capability from the caller's `capabilities` list in `grants.yml`. Or remove the entire grant entry.

**Restart required.**

---

## 4. Emergency lockdown

To deny all access immediately, replace `grants.yml` with:

```yaml
grants: []
```

**Restart required.** This denies every evaluation with `:not_granted`.

To lock down a specific capability, remove it from all grant entries. Callers will receive `:not_granted` for that capability.

---

## 5. Add a prerequisite to an existing capability

Edit `capabilities.yml` to add the prerequisite:

```yaml
capabilities:
  - name: privileged_introspection
    description: "Full runtime introspection"
    risk_level: elevated
    prerequisites:
      - type: file_exists
        path: "config/safety-attestation-introspection.md"
      - type: config_value                              # newly added
        key: introspection_approved
        value: true
```

After restart, callers who were previously granted this capability will now be denied unless the new prerequisite is also satisfied.

**Restart required.**

---

## 6. Remove a prerequisite

Edit `capabilities.yml` to remove the prerequisite from the array. After restart, the capability will be granted without that check.

This is the correct way to "bypass" a prerequisite — change the configuration, not the evaluation engine.

**Restart required.**

---

## 7. Inspect the audit log

The audit log is a JSON Lines file (one JSON object per line). Each line records one evaluation:

```bash
# View recent evaluations
tail -20 log/capability_gate.jsonl | jq .

# Find all denials
grep '"result":"denied"' log/capability_gate.jsonl | jq .

# Find denials for a specific caller
grep '"caller_id":"service-account:agent"' log/capability_gate.jsonl | jq 'select(.result == "denied")'

# Count evaluations by result
jq -r .result log/capability_gate.jsonl | sort | uniq -c
```

Each audit event contains:

| Field | Description |
|-------|-------------|
| `event` | Always `"capability_evaluation"` |
| `timestamp` | ISO 8601 UTC |
| `caller_id` | Who requested the capability |
| `capability` | What was requested |
| `risk_level` | Risk level of the capability |
| `result` | `"allowed"` or `"denied"` |
| `reason` | Why denied (null if allowed) |
| `prerequisites_checked` | Which prerequisite types were evaluated |
| `prerequisites_passed` | Whether all prerequisites passed |
| `session_id` | Session identifier (if configured) |
| `context` | Runtime context passed to the evaluation |

---

## 8. Understand denial reasons

| Reason | Meaning | What to check |
|--------|---------|---------------|
| `unknown_capability` | Capability name not in `capabilities.yml` | Check spelling. Check `capabilities.yml`. |
| `not_granted` | Caller not authorized for this capability | Check `grants.yml`. Is the caller listed? Is the capability in their list? |
| `prerequisite_not_met` | Prerequisite condition failed | Check `details` field. Is the required file present? Is the config value correct? |
| `evaluation_error` | Internal error during evaluation | Check application logs. This should not happen in normal operation. |

---

## 9. Validate configuration before deploying

```bash
# Run the test suite — includes config loading tests
bundle exec rspec

# Lint the codebase
bundle exec rubocop
```

There is no standalone config validator binary in v1. Validation happens at initialization time. If your config is broken, the gate will raise immediately — it will not start with bad config.
