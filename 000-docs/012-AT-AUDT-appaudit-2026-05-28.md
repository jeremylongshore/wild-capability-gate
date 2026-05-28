# Operator-Grade Audit — wild-capability-gate

**Document type:** Operator system audit
**Filed as:** `012-AT-AUDT-appaudit-2026-05-28.md`
**Audit date:** 2026-05-28
**Audit subject:** `wild-capability-gate` v0.1.0 (commit on `feat/epic8-adversarial-bz3.2-bz3.6`)
**Audience:** Senior Rails/Ruby engineer reading the repo cold — needs to be operational within 10 minutes.

---

## 1. Mission & boundaries

`wild-capability-gate` is a small, frozen-value-object Ruby gem (≈900 LOC of source, `lib/wild/capability_gate.rb` and 16 sibling files; `wc -l` total = 1626 with double-counts but per-file unique ≈900) whose only job is to answer one question for a consuming Ruby process: *"Is caller `X` granted capability `Y` right now?"* The answer is an `EvaluationResult` object, never an exception. The decision is logged as a JSON Lines record. Configuration is loaded once at process boot and frozen for the life of the process.

The mission lives in the gem's README (`README.md:5-10`), is restated as the repo's identity in `CLAUDE.md:7-11`, and is governed by `000-docs/003-TQ-STND-governance-model.md` (the five-rule safety standard) and `000-docs/006-AT-STND-interface-contract.md` (the public API stability contract).

**Inside the boundary** — what this gem *does*:

- Loads two YAML files (`capabilities.yml`, `grants.yml`) from a config directory and freezes them in memory (`lib/wild/capability_gate/registry.rb:23`, `lib/wild/capability_gate/evaluator/grant_loader.rb:60-74`).
- Runs a four-step decision pipeline on every `evaluate` call: known capability → granted caller → satisfied prerequisites → allow (`lib/wild/capability_gate/evaluator.rb:41-52`).
- Emits one structured audit event per call to an append-only JSON Lines file (`lib/wild/capability_gate/audit/json_lines_writer.rb:26-30`).
- Optionally caches per-(caller, capability) results within a `Session` for the lifetime of that session (`lib/wild/capability_gate/session.rb:33-40`).
- Supports two prerequisite types — `file_exists` and `config_value` — wired through a one-line dispatch table at `lib/wild/capability_gate/prerequisites/checker.rb:15-18`.

**Outside the boundary** — what this gem deliberately is *not*, per `CLAUDE.md:13-19` and `000-docs/011-PP-PLAN-expansion-roadmap.md:36-50`:

- Not an IAM platform. No users, groups, roles, org hierarchies, or identity resolution. The caller is an opaque string the consumer hands in.
- Not a policy engine. No expressions, no conditions beyond `file_exists` / `config_value`. Adding a new condition is a code change, not a config change.
- Not an HTTP service. There is no `bin/`, no Rack app, no server. The gem is loaded in-process.
- Not a log analyzer. It writes JSONL; reading and alerting belong somewhere else (the operator workflow doc says `jq` and stop there — `000-docs/009-OD-GUID-operator-workflow.md:108-122`).
- Not a runtime-mutable system. There is no `add_grant`, `revoke`, `reload`, or `configure` method, and the safety suite at `spec/safety/governance_rules_spec.rb:201-225` asserts their absence.
- Not even published. `000-docs/011-PP-PLAN-expansion-roadmap.md:51` explicitly defers RubyGems publication until a real consumer proves the interface; consumers depend on it via `git:` URL today (see §4).

The mission statement and the not-doing list are mutually reinforcing: every "no" exists so the "yes" can be exhaustively tested. That posture is the whole product.

---

## 2. Runtime architecture

All code lives under one namespace (`Wild::CapabilityGate`) loaded by a single top-level require list in `lib/wild/capability_gate.rb:3-18`. The pattern is classic Ruby gem composition — no autoloader, no Zeitwerk, no Rails coupling — and the entire dependency declared in `wild-capability-gate.gemspec:17` is `yaml` (stdlib). `Gemfile.lock` confirms zero runtime dependencies outside Ruby's standard library.

**Entry point.** `Wild::CapabilityGate.new(...)` in `lib/wild/capability_gate.rb:24-26` is a thin alias to `Wild::CapabilityGate::Gate.new(...)`. The `Gate` class (`lib/wild/capability_gate/gate.rb:16-72`) is the only public surface. It owns two collaborators it constructs at init:

1. `@evaluator` — an `Evaluator` (`lib/wild/capability_gate/evaluator.rb:17`) built via `Evaluator.from_files(...)`, which itself instantiates a `Registry` from `capabilities.yml` and an array of `Grant` objects from `grants.yml`. The evaluator optionally holds an audit writer and a session id.
2. `@registry` — a second `Registry` loaded from the same `capabilities.yml`. This is a deliberate duplicate: `Gate#capabilities` returns from `@registry` (`gate.rb:48-50`), `@evaluator` uses its own internal registry to answer evaluation questions. Two registries from the same file. Memory cost is trivial; the duplication is mildly awkward and worth noting (see §8).

**Object graph at runtime** (in-process, single Ruby VM):

```
Gate
 ├── Evaluator (frozen)
 │    ├── Registry (frozen) ← {Capability, ...} all frozen value objects
 │    ├── [Grant, ...] (frozen array of frozen Grants)
 │    ├── Audit::JsonLinesWriter (frozen, path-only)
 │    └── session_id (frozen string)
 └── Registry (frozen) ← second copy, lookup-only
```

`Session` and `Session::Store` (`lib/wild/capability_gate/session.rb`, `session/store.rb`) exist as a parallel path: a caller that wants caching can construct a `Session` and call `session.evaluate(evaluator, ...)`. **Nothing in `Gate` wires `Session` in automatically.** The session layer is an optional caching adapter the consumer holds itself; the public `Gate#evaluate` path never goes through it. This is unmentioned in the README and is only implied by the integration guide.

**Data flow on a single call** (path numbers are line numbers in `lib/wild/capability_gate/evaluator.rb`):

```
Gate#evaluate (gate.rb:40)
  → rescue StandardError → deny_with_error (gate.rb:42-44, 63-70)
  → Evaluator#evaluate (evaluator.rb:41)
      → check_capability_known   (line 45 → 56-64)   nil-or-Denied
      → check_caller_granted     (line 46 → 66-74)   nil-or-Denied
      → check_prerequisites      (line 47 → 76-89)   nil-or-Denied
          → Prerequisites::Checker.new + check_all   (prerequisites/checker.rb:26-36)
              → CHECKERS[type].check (file_exists or config_value)
      → allow_with_prerequisites (line 48 → 91-100)  Allowed
      → emit_audit               (line 50 → 106-117) write-or-swallow
  → return EvaluationResult
```

The `||` chain at lines 45-48 of `evaluator.rb` is the entire decision engine. Each guard returns either `nil` (passes through) or an `EvaluationResult.denied(...)` (short-circuits the chain). The final `allow_with_prerequisites` is reached only when all three checks return nil. Result is always one of four reasons: `:unknown_capability`, `:not_granted`, `:prerequisite_not_met`, `:evaluation_error` (`lib/wild/capability_gate/evaluation_result.rb:11-16`).

**In-process vs IPC.** Everything is in-process. The audit writer opens the JSONL file, appends one line, closes (`audit/json_lines_writer.rb:27-29`). There is no fsync, no lock — POSIX `O_APPEND` on a local filesystem is the only concurrency guarantee. Two processes writing to the same audit log file are atomic per-line on Linux as long as each line fits in `PIPE_BUF` (4096 bytes); a long `context` hash could violate that. Not currently documented as a constraint.

**Freezing.** Almost every constructed object calls `freeze` at the end of `initialize` (e.g. `evaluator.rb:25`, `gate.rb` does not — the gate itself is mutable so it can hold its collaborators, but every collaborator is frozen). This is the immutability backbone that backs the Rule 4 safety claim.

---

## 3. The critical path

Trace: an admin agent calls a privileged tool, the gate decides, the audit log records the decision.

**Setup** (in the consumer's boot, `wild-admin-tools-mcp` pattern per `000-docs/010-OD-GUID-consumer-integration.md` and the consumer's own `lib/wild_admin_tools_mcp/identity/gate_client.rb`):

```ruby
gate = Wild::CapabilityGate.new(
  config_path: "config/capability_gate",
  audit_log_path: "log/capability_gate.jsonl",
  session_id: SecureRandom.uuid
)
client = WildAdminToolsMcp::Identity::GateClient.new(gate: gate)
```

**The call** (a hypothetical MCP request to perform `clear_cache`):

```ruby
client.authorize(session_context, "clear_cache", params: { scope: "fragments" })
```

Step-by-step:

1. `GateClient#authorize` (`wild-admin-tools-mcp/lib/wild_admin_tools_mcp/identity/gate_client.rb:10-26`) builds the capability name `:"admin_tools.clear_cache"` and calls `@gate.evaluate(caller: session_context.caller_id, capability: :"admin_tools.clear_cache", context: { action_params: { scope: "fragments" } })`.
2. `Gate#evaluate` (`lib/wild/capability_gate/gate.rb:40-44`) immediately delegates to `@evaluator.evaluate(...)` wrapped in a `rescue StandardError`. The rescue is the Rule 1 fail-closed safety net for *every* downstream failure — config bugs, NPEs, prereq checker bombs.
3. `Evaluator#evaluate` (`lib/wild/capability_gate/evaluator.rb:41-52`) normalises `capability_name` to a Symbol and runs the `||` chain.
4. `check_capability_known` looks the symbol up in `@registry` via `Registry#known?` (`registry.rb:37-39`). Suppose `:"admin_tools.clear_cache"` is *not* in `capabilities.yml` — the registry returns false, an `EvaluationResult.denied(reason: :unknown_capability)` is built and short-circuits the chain.
5. Suppose instead it *is* registered. The chain falls through to `check_caller_granted` (`evaluator.rb:66-74`), which scans `@grants` looking for any `Grant` whose `matches_caller?` is true AND `grants_capability?` is true (`lib/wild/capability_gate/grant.rb:24-30`). If no grant matches, denial with `:not_granted`.
6. `check_prerequisites` (`evaluator.rb:76-89`) fetches the `Capability` from the registry, and if it has any prerequisites, hands them to `Prerequisites::Checker#check_all` (`prerequisites/checker.rb:26-36`). The checker iterates, dispatching each prerequisite by `type` to either `FileExistsChecker.check` or `ConfigValueChecker.check` via the `CHECKERS` constant. First failure short-circuits with a `CheckResult.failed(details:)`. Result is denial with `:prerequisite_not_met` and the failure details.
7. If all three checks pass, `allow_with_prerequisites` (`evaluator.rb:91-100`) builds `EvaluationResult.allowed(...)`.
8. `emit_audit` (`evaluator.rb:106-117`) runs unconditionally if `@audit_writer` is set. It calls `Audit::Event.from_evaluation(result, registry: @registry, session_id: @session_id, context: context)` (`audit/event.rb:22-25`), which assembles a 10-field hash matching the schema in `002-AT-STND-capability-model.md` Section 8, then `@audit_writer.write(event)` opens the JSONL file with `'a'`, JSON-encodes the hash, writes one line. Any exception inside `emit_audit` is silently rescued (`evaluator.rb:113-116`) — audit failure must not become an evaluation failure.
9. The `EvaluationResult` is returned. `GateClient#authorize` reads `result.allowed?` and wraps the session context accordingly.

Nine lines of source code per call, plus YAML deserialisation that happened at boot.

---

## 4. Integration points

The gem is currently consumed by exactly one repo: `wild-admin-tools-mcp`. The integration is git-pinned, not RubyGems-published.

| Layer | Source file | What it does |
|---|---|---|
| Dependency declaration | `wild-admin-tools-mcp/Gemfile:7-13` | `gem 'wild-capability-gate', git: '.../wild-capability-gate', branch: 'main'` for CI/prod; falls back to `path: '../wild-capability-gate'` when `USE_LOCAL_CAPABILITY_GATE=true` for local dev |
| Gemspec dependency | `wild-admin-tools-mcp/wild-admin-tools-mcp.gemspec:20` | `spec.add_dependency 'wild-capability-gate', '~> 0.1'` |
| Authorization adapter | `wild-admin-tools-mcp/lib/wild_admin_tools_mcp/identity/gate_client.rb:10-26` | Wraps `gate.evaluate(...)` per admin action, converts result into `SessionContext#with_gate_result` and re-raises any unexpected error as `GateError` |
| Health probe | `wild-admin-tools-mcp/lib/wild_admin_tools_mcp/identity/gate_health_check.rb:10-26` | Calls `authorize` with a synthetic `__health_probe__` action to confirm the gate is wired |
| Integration spec | `wild-admin-tools-mcp/000-docs/010-AT-ADEC-capability-gate-integration.md` | The architecture decision record on this repo's side that pins the integration shape |
| Safety spec | `wild-admin-tools-mcp/spec/safety/gate_failure_spec.rb` | Adversarial test asserting the consumer fails closed when the gate is unconfigured or errors |

The dual-mode Gemfile pattern (git default, path override via env var) is a deliberate ecosystem convention — `wild-admin-tools-mcp/CLAUDE.md` § "Dependency Strategy" calls it out: *"Path dependencies are never used in CI. This ensures reproducible builds everywhere."* The gem is consumed but not stabilised; bumping `wild-capability-gate`'s `main` branch is currently sufficient to update consumers, but there is no tag-pin, no semver gate, and no automated downstream test trigger.

There are no other consumers in `~/000-projects/wild/`. The expansion roadmap (`000-docs/011-PP-PLAN-expansion-roadmap.md:91-107`) names `wild-rails-safe-introspection-mcp` as the next intended consumer; that repo is unaware of the gate today.

---

## 5. Failure modes & blast radius

The gate's whole job is to fail safely, so the interesting failure modes are about *how* it fails and what the blast radius is when something downstream of the gate breaks.

| Failure | What happens | Blast radius | Citation |
|---|---|---|---|
| `capabilities.yml` missing or malformed at boot | `ConfigError` raised from `Registry::ConfigLoader#read_yaml` propagates out of `Gate.new`. Consumer process refuses to start. | Whole consumer process — by design. Bad config never silently turns into permissive evaluation. | `registry/config_loader.rb:44-54`, asserted in `governance_rules_spec.rb:77-86` |
| `grants.yml` missing or malformed at boot | Same as above with `GrantConfigError`. | Same — boot-time failure. | `evaluator/grant_loader.rb:42-52` |
| Duplicate capability name in `capabilities.yml` | `DuplicateCapabilityError` at boot. | Boot fails. | `registry.rb:60-63` |
| Unknown `risk_level` in `capabilities.yml` | `ArgumentError` from `Capability#validate_risk_level`, wrapped to `ConfigError` with the offending index. | Boot fails. | `capability.rb:47-53`, `registry/config_loader.rb:77-78` |
| Unknown prerequisite `type` (e.g. operator adds a type the code doesn't know yet) | Two cases, both fail-closed. Parse-time: `Prerequisite#validate_type` raises `ArgumentError` → wrapped to `ConfigError` → boot fails (`prerequisite.rb:23-29`). Hypothetical race where type slips through: `Checker#check_one` returns `CheckResult.failed(details: 'no checker registered...')` → `:prerequisite_not_met` (`prerequisites/checker.rb:43-47`). | Either boot fails, or every call to the affected capability denies until config is fixed. Never permissive. | Above lines + adversarial coverage in `safety_defects_spec.rb` |
| Evaluator raises mid-call (NPE, bad input, anything) | `Gate#evaluate`'s outer `rescue StandardError` catches it, returns `EvaluationResult.denied(reason: :evaluation_error, details: "evaluation failed: <ErrorClass>")`. Audit event is *not* written for this path because the error happened before `emit_audit` ran. | One denied call. No process exit. **Caveat:** the `:evaluation_error` denial is the one denial reason that does not produce an audit event in the current code — Rule 5 (audit completeness) has a documented gap here. | `gate.rb:42-44, 63-70`; gap visible by inspection of the rescue clause |
| Audit log write fails (disk full, permission error, path missing) | `emit_audit`'s inner `rescue StandardError` silently swallows the exception. Evaluation result is returned normally. | One missing audit event. **The decision was already made**; the gate honors fail-closed semantics for the evaluation but is deliberately *fail-open* on audit emission, on the explicit reasoning that "a broken audit log must not cause the gate to raise" (`evaluator.rb:104-117`). | `evaluator.rb:113-116` |
| `caller: nil` passed to `evaluate` | `String(nil)` coerces to `""`. The wildcard grant `"*"` matches `""`, so a wildcard-granted capability is *allowed* for an empty caller. Documented behavior asserted in `governance_rules_spec.rb:55-62`. | One allowed call with an empty `caller_id` in the audit log. Defensible per the doctrine ("the wildcard is explicit config, not implicit behavior"), but worth flagging to anyone who confuses "anonymous" with "denied". | `evaluator.rb:43`, `grant.rb:28-30` |
| `capability: nil` passed to `evaluate` | `nil.to_sym` raises NoMethodError, caught by Gate's outer rescue → `:evaluation_error` denial. | One denied call. | `governance_rules_spec.rb:64-69` |
| Two processes writing to the same audit log concurrently | Per-line atomic for short lines (<4 KB on Linux) via `O_APPEND`. Long `context` payloads could interleave. | Audit log corruption for one line. Not gated against. | Implicit in `audit/json_lines_writer.rb:27-29` — no explicit lock, no fsync |

Error class hierarchy is minimal and lives close to the loaders: `Registry::DuplicateCapabilityError`, `Registry::ConfigLoader::ConfigError`, `Evaluator::GrantLoader::GrantConfigError`. There is no shared `Wild::CapabilityGate::Error` base class — consumers `rescue StandardError` if they want to catch boot-time failure (and the safety suite does exactly that, `governance_rules_spec.rb:73-75, 82-85`).

---

## 6. Trade-off analysis

The ADRs in `000-docs/004-AT-ADEC-architecture-decisions.md` cover six decisions. Three matter most operationally; one further decision is implicit and worth surfacing.

| Decision | Chosen | Alternative | Why | Cost | When it breaks |
|---|---|---|---|---|---|
| **1. Gem, not service** (ADR-1, `004-AT-ADEC:10-18`) | In-process Ruby gem | Standalone HTTP/gRPC policy service | Zero network latency, zero ops cost, zero deploy story, trivially testable; consumer-call is just a method call | Locks the consumer ecosystem to Ruby; a Python or Go consumer needs a wrapper or a reimplementation; updating policy requires redeploying every consumer | First non-Ruby consumer arrives, or a policy hotfix becomes needed across 4+ consumer fleets simultaneously |
| **2. YAML at boot, not DB-driven** (ADR-2, `004-AT-ADEC:22-30`) | Two YAML files loaded once, frozen | RDBMS-backed grants with an admin UI | Diffable in PRs, auditable via `git log`, no runtime mutation surface, no migration story; the immutability is a *safety feature* not an accident | Every capability or grant change requires a process restart of every consumer (operator workflow §1-6 says "Restart required" five times); ops gets noisy when grants change often | When the operator population grows past ~10 capabilities or grants change daily; a frequent-change shop will want a DB or an admin tool |
| **3. Session-scoped cache, no persistence** (ADR-3, `004-AT-ADEC:34-42`) | `Session` holds a `{(caller, capability) → result}` hash for its TTL | Persistent decision cache (Redis, Memcached) | A revoked grant during a session cannot leak as a cached allowance after restart; cold-start re-evaluation is cheap because YAML is already in memory | Every new session pays the full pipeline cost for every first-time check; high-fanout, short-lived sessions get no benefit | When evaluation gets expensive (e.g. a future prereq type does network or filesystem work on every call) and the same session does the same check thousands of times — likely fine in v1, worth revisiting in v2 |
| **4. Fail-closed by `rescue StandardError`** (ADR-4, `004-AT-ADEC:46-53`) | Outer rescue on `Gate#evaluate` converts every exception to denial | Let exceptions propagate, document the contract, expect consumers to rescue | Consumers never need to rescue; a missing rescue cannot become an accidental permit | The original exception is *erased* — only `e.class` makes it into the denial details (`gate.rb:68`); message and backtrace are dropped before they reach the operator. Diagnosing repeat `:evaluation_error` denials requires reproducing the failure under test, which can be costly | When a real bug emerges in production and the operator has only `"evaluation failed: RuntimeError"` in the audit log with no message, no backtrace, no context |
| **5. Implicit: audit emission is fail-open** (`evaluator.rb:113-116`) | Audit write failure is swallowed silently | Re-raise audit failure, or re-deny the call if audit cannot be written | Keeps Rule 1 (fail-closed evaluation) decoupled from Rule 5 (audit completeness); a full disk does not cascade into a denial storm | Rule 5's audit-completeness guarantee has a known gap whenever the audit writer errors; operators have no signal that audit events are being lost | When the audit log path becomes unwritable (filled disk, permission change after deploy, NFS hiccup) and no health probe is checking write-ability — audit-evidence-of-evaluation silently goes to zero |
| **6. String caller identity** (ADR-6, `004-AT-ADEC:67-72`) | Caller is `String`, matched exact or wildcard | Rich identity object (roles, attributes, claims) | Zero coupling to any identity provider; consumer's auth layer is fully external; wildcard plus exact-match covers ~80% of grant patterns trivially | Cannot express "any caller with prefix `service-account:`" or role-based grants without changes; operator must enumerate every caller. Wildcard matching empty string (see §5) is a subtle footgun | When the consumer fleet grows past ~20 distinct caller identities and grants become repetitive copy-paste in `grants.yml` |

The crucial through-line: every decision optimises for *uncertainty about correctness over uncertainty about flexibility*. The cost is paid in operator restart cycles, lost exception context, and the silent audit-emission gap. For v1 the trade is correct. For v2 the friction will become felt by operators before it becomes felt by safety auditors.

---

## 7. Operator playbook

The gem does not ship a binary, a rake task, or a CLI. All operational verbs are *configuration edits + consumer restart*. The operator interacts with three artifacts: `capabilities.yml`, `grants.yml`, and the JSONL audit log.

**Deploy** — there is no deploy. The gem is loaded by a consumer process (`wild-admin-tools-mcp`, etc.). Operator changes a YAML file in the consumer's config directory, commits, deploys the consumer normally. The gate has no independent lifecycle.

**Smoke test before rollout.** From the consumer repo:

```bash
bundle exec rspec    # Gate's own suite: 224 examples, 0 failures (README:90)
bundle exec rubocop  # 42 files, 0 offenses (README:91)
```

There is no `wild-capability-gate validate config/` CLI in v1 — the operator workflow doc admits this at `000-docs/009-OD-GUID-operator-workflow.md:185-190` and the expansion roadmap names it as a v2 candidate (`011-PP-PLAN-expansion-roadmap.md:82-84`). Validation happens at consumer boot. If config is bad, the consumer's `Wild::CapabilityGate.new(...)` raises and the consumer fails to start. **The smoke test for new config is "the consumer comes up."**

**Roll back.** Revert the YAML files (and the corresponding application config changes that depend on capability or grant names). Restart the consumer. Mandate from `009-OD-GUID-operator-workflow.md:23, 39, 49, 67, 95, 112`: every operational change is followed by "**Restart required.**" There is no hot reload.

**Emergency lockdown.** Replace `grants.yml` with `grants: []` and restart the consumer (`009-OD-GUID-operator-workflow.md:60-66`). Every evaluation will then deny with `:not_granted`. There is no faster path — no kill switch, no env-var override.

**Inspect audit logs.** It is a JSON Lines file, one line per evaluation. The canonical recipes (`009-OD-GUID-operator-workflow.md:108-122`):

```bash
tail -20 log/capability_gate.jsonl | jq .
grep '"result":"denied"' log/capability_gate.jsonl | jq .
grep '"caller_id":"service-account:agent"' log/capability_gate.jsonl | jq 'select(.result=="denied")'
jq -r .result log/capability_gate.jsonl | sort | uniq -c
```

Each line carries the 10-field schema from `audit/event.rb:52-61`: `event`, `timestamp`, `caller_id`, `capability`, `risk_level`, `result`, `reason`, `prerequisites_checked`, `prerequisites_passed`, `session_id`, `context`. Log rotation is the operator's problem — the writer only appends and the expansion roadmap calls this out as out-of-scope (`011-PP-PLAN-expansion-roadmap.md:117`).

**Recover from a "stuck gate."** The gate has no in-flight state — every call is independent and the session cache is in-process memory. "Stuck" means one of: (a) the consumer process is wedged (kill and restart the consumer; the gate comes back exactly as configured), (b) a capability is denying when it should allow (read the most recent audit event for that capability — `reason` tells you whether the issue is `unknown_capability`, `not_granted`, `prerequisite_not_met`, or `evaluation_error`; the `details` field disambiguates within prereq failures), (c) audit events stopped appearing (check disk space and write permissions on the audit log path — the gate is silently fail-open on audit emission per `evaluator.rb:113-116`).

The reason-table at `009-OD-GUID-operator-workflow.md:135-141` is the operator's diagnostic flow-chart and it is accurate.

---

## 8. Recommendations for v2

What's good is genuinely good — the safety invariants are tested adversarially, the dependency footprint is one stdlib module, the public interface is two methods. The cracks are about *operability and scale*, not correctness.

**1. The `:evaluation_error` audit gap.** When `Gate#evaluate`'s outer rescue fires, no audit event is written for that call (the exception unwinds before `emit_audit` runs in `evaluator.rb`). Rule 5 says *"every evaluation produces an audit event"* and the safety tests confirm it for `:unknown_capability`, `:not_granted`, and `:prerequisite_not_met` (`governance_rules_spec.rb:234-274`) — but no test asserts an audit event is produced for `:evaluation_error`. Either close the gap (have `Gate#deny_with_error` write a degraded audit event before returning) or document it explicitly as a known carve-out from Rule 5.

**2. The duplicate-registry construction in `Gate.new`.** `gate.rb:31-32` builds an `Evaluator` (which builds its own `Registry` internally via `Evaluator.from_files`) and then independently builds a second `Registry` from the same YAML file for `Gate#capabilities`. That's twice the YAML parse, twice the memory. Fix: have `Evaluator` expose its registry, or refactor `Gate` to construct the `Registry` once and pass it into the `Evaluator`.

**3. The silently-swallowed audit write failure.** `evaluator.rb:113-116` is correct on the *evaluation* side (don't let audit cascade into denial), but offers no signal to operators that audit has degraded. At minimum, write to STDERR once (with a deduper). Ideally, expose a callback or counter so operators can health-probe audit emission. As written, an unwritable audit path produces zero alarms and an audit log frozen at last-good event.

**4. The error message-erasure in `:evaluation_error`.** `gate.rb:68` puts only `e.class` into denial details. The message and backtrace are dropped. In a production debugging scenario where the same denial reason keeps recurring, the operator has to reproduce the failure under test to learn anything. Including `e.message` (with a length cap) and emitting `e.backtrace.first(5)` to STDERR would cost little and pay off in the first real incident.

**5. No standalone config validator.** `bundle exec rspec` validates the *test* config, not the operator's actual deployment config. The expansion roadmap names a `validate` CLI as a v2 extension (`011-PP-PLAN-expansion-roadmap.md:82-84`); this is the right call and should land before the gem ships to RubyGems.

**6. No release pin between consumer and gate.** `wild-admin-tools-mcp/Gemfile` floats on `branch: 'main'`. Tag releases, publish to RubyGems (the roadmap is explicit about deferring this until a real consumer proves the interface — `wild-admin-tools-mcp` is now that consumer), and pin consumers to versions. Without this, any push to `wild-capability-gate@main` is a silent upgrade for every consumer at their next `bundle install`.

**7. Wildcard-matches-empty-string is a footgun.** A `caller: nil` (probably a bug in the consumer's auth layer) becomes `""`, which matches `"*"`. Documented as intentional (`governance_rules_spec.rb:55-62`), but a consumer that passes anonymous traffic through to the gate by accident will silently allow whatever the wildcard grants. Either tighten `Grant#matches_caller?` to reject empty caller against wildcard, or require consumers to opt in.

**8. The session-caching layer is documented nowhere a consumer would find it.** `Session` and `Session::Store` are real, tested, and unused by `Gate`. The interface contract (`006-AT-STND-interface-contract.md`) doesn't mention them; the consumer-integration guide doesn't show them. Either wire them into `Gate` as an opt-in (`session: my_session`) or remove them from the public namespace until v2.

None of these are blocking. The gem ships v1 honestly. They are the next round.

---

**End of audit.**
