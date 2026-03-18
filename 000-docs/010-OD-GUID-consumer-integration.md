# Consumer Integration Guide — wild-capability-gate

**Document type:** Operator guide
**Filed as:** `010-OD-GUID-consumer-integration.md`
**Status:** Active
**Last updated:** 2026-03-17

---

## Who this is for

Developers building repos that consume the capability gate — primarily `wild-rails-safe-introspection-mcp` and `wild-admin-tools-mcp`.

---

## 1. Add the dependency

Add to your `Gemfile`:

```ruby
gem 'wild-capability-gate', path: '../wild-capability-gate'
```

(In v1, the gate is a path-referenced gem. It is not published to RubyGems yet.)

```bash
bundle install
```

---

## 2. Create configuration files

Create a config directory in your consuming repo:

```
config/capability_gate/
  capabilities.yml
  grants.yml
```

See the [Configuration Reference](008-OD-GUID-configuration-reference.md) for the full format.

Minimal example:

```yaml
# config/capability_gate/capabilities.yml
capabilities:
  - name: basic_introspection
    description: "Read-only schema inspection"
    risk_level: standard
    prerequisites: []
```

```yaml
# config/capability_gate/grants.yml
grants:
  - caller: "*"
    capabilities:
      - basic_introspection
```

---

## 3. Initialize the gate

Initialize once at application boot. The gate is immutable after construction.

```ruby
require 'wild/capability_gate'

CAPABILITY_GATE = Wild::CapabilityGate.new(
  config_path: "config/capability_gate",
  audit_log_path: "log/capability_gate.jsonl",  # optional
  session_id: SecureRandom.uuid                  # optional
)
```

**If config is broken, this raises immediately.** Catch initialization errors at the application boot level, not per-request.

---

## 4. Evaluate before privileged operations

```ruby
result = CAPABILITY_GATE.evaluate(
  caller: current_caller_identity,
  capability: :privileged_introspection,
  context: { "admin_tools_enabled" => app_config.admin_tools_enabled }
)

if result.denied?
  # Log the denial and return an error response
  logger.warn("Capability denied: #{result.reason} — #{result.details}")
  return error_response(result.reason)
end

# Proceed with the privileged operation
```

---

## 5. Handle results

The `evaluate` method always returns an `EvaluationResult`. It never raises.

```ruby
result.allowed?              # true or false
result.denied?               # true or false
result.reason                # nil (allowed) or :unknown_capability, :not_granted,
                             #   :prerequisite_not_met, :evaluation_error
result.details               # nil or human-readable String
result.capability_name       # Symbol (e.g., :privileged_introspection)
result.caller_id             # String (e.g., "service-account:agent")
result.prerequisites_checked # Array of Symbols (e.g., [:file_exists])
result.timestamp             # Time
```

### Denial handling patterns

```ruby
case result.reason
when :unknown_capability
  # Bug in the consumer — capability name is wrong
  raise "Unknown capability: #{result.capability_name}"
when :not_granted
  # Caller is not authorized — expected for unprivileged callers
  deny_with_403(result)
when :prerequisite_not_met
  # Prerequisites not satisfied — expected for unconfigured environments
  deny_with_precondition_failed(result)
when :evaluation_error
  # Internal error — unexpected, investigate
  alert_and_deny(result)
end
```

---

## 6. List available capabilities

```ruby
CAPABILITY_GATE.capabilities.each do |cap|
  puts "#{cap.name} (#{cap.risk_level}): #{cap.description}"
  puts "  Prerequisites: #{cap.prerequisites.map(&:type).join(', ')}" if cap.prerequisites?
end
```

This is useful for building admin dashboards or introspection endpoints that show what the gate knows about.

---

## 7. Caller identity

The caller identity is an opaque string. The gate does not interpret it — it just compares it against grant entries.

Conventions used in the Wild ecosystem:

| Pattern | Example |
|---------|---------|
| Service account | `"service-account:introspection-agent"` |
| MCP server | `"mcp-server:rails-introspection"` |
| Wildcard (all callers) | `"*"` in grants config |

Choose a consistent convention for your consuming repo and document it.

---

## 8. What to expect

### The gate will...
- Return `allowed` or `denied` for every evaluation
- Log every evaluation to the audit log (if configured)
- Deny unknown capabilities
- Deny unconfigured callers
- Enforce all prerequisites without exception
- Return denial (not raise) on internal errors

### The gate will NOT...
- Manage sessions for you (pass your own `session_id`)
- Modify configuration at runtime
- Provide an HTTP API (it's a library)
- Persist state between processes
- Tell you which capabilities to define (that's your domain decision)

---

## 9. Assumptions consumers must NOT make

- Do not assume capabilities are granted by default. Everything starts denied.
- Do not assume prerequisites can be skipped. There is no override.
- Do not cache evaluation results outside the gate. The gate has its own session cache.
- Do not parse denial `details` strings programmatically. Use `reason` symbols instead.
- Do not assume the public API will expand. The interface is intentionally minimal.
