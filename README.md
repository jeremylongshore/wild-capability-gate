# wild-capability-gate

> Part of the **[wild ecosystem](https://github.com/intent-solutions-io/wild-rails-ai-ops)** — 10 Ruby gems for running AI agents inside Rails apps under capability control.

Governed access control for sensitive AI tool capabilities.

## What it does

A Ruby gem that gates access to privileged operations. Before a consuming repo executes a sensitive tool, it asks the gate: "Is this caller allowed to do this?" The gate checks grants, evaluates prerequisites, and returns an allowed/denied result.

Every evaluation is:
- **Fail-closed** — errors produce denial, never permission
- **Prerequisite-enforced** — capabilities can require proof (attestation files, config flags) before granting
- **Audited** — every decision is logged as a structured JSON Lines event
- **Immutable at runtime** — configuration is loaded at startup and cannot be changed through the API

## What it does not do

- Not a full IAM platform. No users, groups, roles, or org hierarchies.
- Not a policy engine. It gates capabilities, not arbitrary decisions.
- Not an HTTP service. It's a library consumed in-process.
- Not a UI. Operator visibility comes from audit logs and config inspection.

## Core concepts

**Capability** — a named, scoped access grant for a category of privileged operation (e.g., `:privileged_introspection`, `:admin_tools`). Each has a risk level (`standard`, `elevated`, `critical`) and optional prerequisites.

**Prerequisite** — a condition that must be true before a capability is granted, even if the caller has an explicit grant. v1 supports `file_exists` (a file must be present) and `config_value` (a runtime config key must match an expected value).

**Grant** — a mapping from a caller identity string to a list of capabilities. Grants are configured in YAML. The wildcard caller `"*"` grants to all callers.

**Denial** — the default. Unknown capabilities are denied. Unconfigured callers are denied. Failed prerequisites are denied. Errors are denied. Every denial carries a reason symbol and human-readable details.

## Quick start

```ruby
require 'wild/capability_gate'

# Initialize from a config directory containing capabilities.yml and grants.yml
gate = Wild::CapabilityGate.new(
  config_path: "config/capability_gate",
  audit_log_path: "log/capability_gate.jsonl"
)

# Check before executing a privileged operation
result = gate.evaluate(
  caller: "service-account:introspection-agent",
  capability: :privileged_introspection
)

if result.allowed?
  # proceed
else
  puts "Denied: #{result.reason} — #{result.details}"
end
```

## Configuration

The gate reads two YAML files from the config directory:

**capabilities.yml** — defines what capabilities exist:

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
```

**grants.yml** — defines who can use them:

```yaml
grants:
  - caller: "service-account:introspection-agent"
    capabilities:
      - basic_introspection
      - privileged_introspection

  - caller: "*"
    capabilities:
      - basic_introspection
```

See [Configuration Reference](000-docs/008-OD-GUID-configuration-reference.md) for full details.

## Safety posture

The gate defaults to denial. Five governance rules are enforced and proven by adversarial tests:

1. **Fail-closed** — any error during evaluation returns denial
2. **No implicit grants** — everything must be explicitly configured
3. **Prerequisites enforced** — no skip mode, no override, no escape hatch
4. **Immutable at runtime** — configuration cannot be modified through the public interface
5. **Audit complete** — every evaluation produces a structured log entry

All 7 safety defect conditions from the governance model have adversarial tests confirming they cannot be triggered.

## Running tests

```bash
bundle install
bundle exec rspec       # 224 examples, 0 failures
bundle exec rubocop     # 42 files, 0 offenses
```

## Status

**v1 MVP complete** — capability registry, rule evaluator, prerequisite checking, session caching, audit trail, public interface, and safety testing are all implemented and verified.

## Documentation

| Document | Description |
|----------|-------------|
| [Configuration Reference](000-docs/008-OD-GUID-configuration-reference.md) | Every config field, validation rule, and prerequisite type |
| [Operator Workflow Guide](000-docs/009-OD-GUID-operator-workflow.md) | Add capabilities, modify grants, lockdown, inspect audit logs |
| [Consumer Integration Guide](000-docs/010-OD-GUID-consumer-integration.md) | How to integrate from a consuming repo |
| [Interface Contract](000-docs/006-AT-STND-interface-contract.md) | Public API signatures and stability guarantees |
| [Capability Model](000-docs/002-AT-STND-capability-model.md) | Data structures and evaluation semantics |
| [Governance Model](000-docs/003-TQ-STND-governance-model.md) | Safety rules and defect definitions |

## Part of the Wild ecosystem

This is the cross-cutting access control layer for the [Wild](https://github.com/jeremylongshore) ecosystem of AI operational tooling. It is consumed by `wild-rails-safe-introspection-mcp`, `wild-admin-tools-mcp`, and other repos that need governed capability gating.

## License

Intent Solutions Proprietary
