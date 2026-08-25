# REVIEW.md

Reviewer law for `wild-capability-gate`, the repository the automated pull-request reviewer
(MiniMax, two advisory lanes) must apply. This is not a style guide. Style is already settled by
`bundle exec rubocop` in CI, and the reviewer must not restate it.

## What this repo is, and why review is risk-ordered

`wild-capability-gate` is a Ruby gem that answers one question for the rest of the Wild ecosystem:
"is this caller allowed to perform this privileged operation?" The README states it is consumed in-process by MCP
servers such as `wild-rails-safe-introspection-mcp` and `wild-admin-tools-mcp`, and the repo
blueprint names those two as the first and second consumers. That integration lives in their
repositories, so nothing in this repo evidences it. If the gate returns
`allowed?` when it should not, every consuming repo's safety model is compromised at once, and there
is no second gate downstream. Review in this order of risk:

1. Anything that can turn a denial into a permission (fail-open).
2. Anything that lets a prerequisite, a grant check, or the audit write be skipped.
3. Anything that leaks caller-supplied or operator-supplied values into the audit log or into a
   returned `details` string.
4. Ordinary correctness bugs in loading, caching, and serialization.
5. Everything else, which is usually not worth a comment.

## Authority

`000-docs/003-TQ-STND-governance-model.md` governs safety and its Section 6 list of seven safety
defects is the definition of a blocking bug. `000-docs/002-AT-STND-capability-model.md` governs the
decision tree and audit event schema, and `000-docs/006-AT-STND-interface-contract.md` governs the
public API surface. Where a pull request description and a canonical doc disagree, the doc wins.

## The invariants. None of these may regress.

- **INV-1 fail closed, and the guarantee lives on `Gate`.** `Gate#evaluate` always returns an
  `EvaluationResult` and never raises: it rescues `StandardError` and converts it to a denial with
  reason `:evaluation_error`. `Evaluator#evaluate` carries no rescue of its own and can raise on
  malformed input, so it is fail closed only because `Gate` wraps it. A nil `capability_name` raises
  `NoMethodError` on the `to_sym` at the top of `Evaluator#evaluate`, and the repo's own governance
  spec proves that case only through `Gate`. Treat that as load bearing: a new caller that reaches
  `Evaluator#evaluate` without going through `Gate#evaluate` loses the guarantee. Any new code path
  that can raise past the `Gate` rescue, return `nil`, return a truthy non-result, or default a
  decision to allow is a blocking defect. In this repo "fail closed" means precisely: every abnormal
  outcome (missing config, unreadable file, unknown prerequisite type, checker exception, nil caller,
  nil capability) resolves, at the `Gate` boundary, to a denial that still carries a reason symbol.
- **INV-2 no implicit grants.** Denial is the default. Unknown capability denies with
  `:unknown_capability`. A caller with no matching `Grant` denies with `:not_granted`. The only
  broad match is the explicit `"*"` wildcard in `grants.yml`. Treat any new matcher (prefix, regex,
  glob, case-insensitive compare, `start_with?`, `include?`) in `Grant#matches_caller?` as a
  privilege-escalation change and demand its own adversarial spec.
- **INV-3 prerequisites are always enforced.** `Prerequisites::Checker::CHECKERS` is a closed
  dispatch table and an unregistered type must fail, not pass. There is no skip mode, no override
  flag, no `force:` keyword, no environment variable that bypasses a check. A new checker must
  fail closed inside its own `rescue`, exactly as `FileExistsChecker` and `ConfigValueChecker` do.
- **INV-4 the ordering of check, allow, audit.** `Evaluator#evaluate` computes the result through
  the ordered chain then calls `emit_audit` before returning. Every evaluation that reaches
  `Evaluator#evaluate` emits one event, allowed or denied, subject to two real limits a reviewer must
  hold rather than assume away: `emit_audit` returns immediately when no `audit_writer` was
  configured, and the `:evaluation_error` denial built inside `Gate#evaluate`'s rescue never reaches
  `emit_audit` at all, so that one path is unaudited today and no spec asserts an event for it. A new
  early `return` inserted above `emit_audit`, or a second denial path built outside
  `Evaluator#evaluate`, creates a silent evaluation path, which is safety defect 3 in the governance
  model.
- **INV-5 immutable after construction.** `Capability`, `Grant`, `Prerequisite`, `Evaluator`,
  `Registry`, and `Audit::JsonLinesWriter` all call `freeze`. Adding a writer, an `attr_writer`, a
  mutating setter, or a public method that reloads config at runtime breaks configuration
  immutability and lets an agent escalate its own capabilities mid-session.
- **INV-6 config parsing stays hostile.** Both YAML entry points use
  `YAML.safe_load(content, permitted_classes: [Symbol])`: `Registry::ConfigLoader` for
  `capabilities.yml` and `Evaluator::GrantLoader` for `grants.yml`. Any move to `YAML.load`,
  `YAML.unsafe_load`, `aliases: true`, or a widened `permitted_classes` is a deserialization hole in
  a file an operator edits by hand, and is a blocking finding.
- **INV-7 the public surface stays two methods.** `Gate#evaluate` and `Gate#capabilities`. New
  public methods on `Gate` need a matching change to the interface contract doc in the same pull
  request, or they are scope creep on a stability guarantee other repos design against.

## Defect classes to hunt, with this repo's actual shapes

**Fail-open.** A rescue narrowed from `StandardError` to a specific class, so an unexpected error
escapes to the consumer instead of denying. A `||` chain in `Evaluator#evaluate` reordered so
`allow_with_prerequisites` can be reached before the grant check. `check_prerequisites` returning
early (which means "no objection") on an error path rather than returning a denial. A checker that
returns `nil` instead of a `CheckResult`, since `nil.satisfied?` would raise and, if the raise is
swallowed anywhere, could read as "no failure".

**Cache poisoning across contexts.** `Session#evaluate` keys its cache on `(caller_id,
capability_name)` only and deliberately ignores `context`. That is documented, and it means a
`config_value` prerequisite evaluated once under a permissive context returns `allowed` for the rest
of the session under any context. Scrutinize any change that widens the cache (longer TTL, a shared
or process-global store, caching inside `Evaluator`, a cross-session store) because it extends the
blast radius of that known trade-off. A change that starts caching in a place the docs do not cover
needs its own reasoning in the pull request.

**Audit gaps.** `emit_audit` intentionally swallows write failures so a broken log cannot break
evaluation. That is correct and must not become a broader swallow that also hides a failure to build
the event. Watch for: an evaluation path added outside `Evaluator#evaluate`, a `Session` cache hit
being treated as "no evaluation, no event" in a way that hides repeated privileged use, a change to
`Audit::Event::VALID_RESULTS` or `to_h` keys that silently breaks a downstream log parser, and any
weakening of the append-only `File.open(@path, 'a')` write in `JsonLinesWriter`.

**Sensitive value leakage.** The audit event serializes the caller-supplied `context` hash verbatim,
and `ConfigValueChecker` interpolates both the expected and the actual value into its `details`
string, which then travels into `EvaluationResult#details` and into the log. Flag any change that
puts more operator or caller data into `details` or `context`, and flag any new checker that echoes
a secret-shaped value (token, key, password, connection string) into a message. Never reproduce a
suspected secret in a review comment: name the file, the line, and the fix.

**Path and identity handling.** `FileExistsChecker` calls `File.exist?` on an operator-supplied
path from `capabilities.yml`. Flag any evolution of that checker into reading, writing, globbing,
executing, or following a caller-controlled path from `context`, since prerequisite paths are
config-owned and must not become caller-owned. Likewise `String(caller_id)` is the whole of identity
normalization; any trimming, downcasing, or unescaping there changes who matches a grant.

**Test theatre.** `spec/safety/` is the proof that the seven governance defects cannot be triggered.
A pull request that changes evaluation logic while deleting, skipping, or loosening a safety spec is
removing the evidence rather than the defect. Adversarial specs must assert on the denial reason
symbol, not merely on `denied?`.

## Generated, ignored, or otherwise not hand-edited

`Gemfile.lock` is git-ignored by design for a gem. `.beads/` and `.dolt/` are ignored task-tracking
state and must never appear in a diff. `planning/` is tracked, including `planning/beads-import.md`, which is not
git-ignored; it is excluded from the reviewer's diff by the workflow's `EXCLUDE_PATTERNS`, so it can
appear in a commit but must never draw a review comment. `lib/wild/capability_gate/version.rb`
is the single version source and should change in a release commit, not incidentally. If any of
these show up in a pull request, that alone is the finding.

## Do not spend comments on these

- Rubocop-enforced style, layout, line length, frozen string literals, or naming. CI runs rubocop
  with zero tolerated offenses already.
- RSpec structure preferences, `let` versus instance variables, or describe-block wording.
- Requests for YARD documentation on a private method.
- Asking for features the repo explicitly rejects: users, roles, org hierarchy, an HTTP service, a
  policy engine, a UI, a database, or cross-process session sharing. See the "What This Repo Does
  NOT Do" section of `CLAUDE.md` before proposing an addition.
- Re-litigating the architecture decisions in `000-docs/004-AT-ADEC-architecture-decisions.md` (gem
  not service, YAML not database, session-scoped state, immutable registry) unless the pull request
  is changing one, in which case require a dated decision record.

## Anti-ratchet and posture

On a re-review after new pushes the bar does not rise. Drop findings the update resolved, and do not
invent new objections on unchanged lines already accepted. Prefer a few high-conviction findings over
a long list. If the change is correct, keeps every invariant, and carries the safety specs that prove
it, reply `lgtm`. Both reviewer lanes are advisory only, are never a required check, and never block
a merge. The deterministic gate is the `CI` workflow: `bundle exec rspec` and `bundle exec rubocop`
on Ruby 3.2 and 3.3.

## Sources

Every claim above that asserts something about this codebase was read out of the tree at commit
`699fbd1`, the head of the `ci/minimax-review` branch, and is cited here by file and line. A claim
without a citation in this list is not a claim this document is making.

**Risk framing and consumers**

- Consumed by MCP servers: `README.md:134`, `000-docs/001-PP-PLAN-repo-blueprint.md:147`,
  `000-docs/001-PP-PLAN-repo-blueprint.md:149` (blueprint calls them first and second consumer)
- No second gate downstream, gate is a library not an MCP server: `CLAUDE.md:22`

**Authority**

- Seven safety defects, Section 6: `000-docs/003-TQ-STND-governance-model.md:55-67`
- Decision tree: `000-docs/002-AT-STND-capability-model.md:110-134`
- Audit event schema, Section 8: `000-docs/002-AT-STND-capability-model.md:153-173`
- Public API surface: `000-docs/006-AT-STND-interface-contract.md:16-105`,
  stability table `000-docs/006-AT-STND-interface-contract.md:107-117`

**INV-1 fail closed**

- `Gate#evaluate` rescues `StandardError`: `lib/wild/capability_gate/gate.rb:40-44`
- Denial with reason `:evaluation_error`: `lib/wild/capability_gate/gate.rb:63-70`
- `Evaluator#evaluate` has no rescue: `lib/wild/capability_gate/evaluator.rb:41-52`
- The `to_sym` that raises on a nil capability: `lib/wild/capability_gate/evaluator.rb:42`
- Nil capability proven denied only through `Gate`:
  `spec/safety/governance_rules_spec.rb:64-69`
- Raising evaluator proven to deny: `spec/safety/safety_defects_spec.rb:120-156`
- `DENIAL_REASONS` symbol list: `lib/wild/capability_gate/evaluation_result.rb:11-16`

**INV-2 no implicit grants**

- `:unknown_capability` denial: `lib/wild/capability_gate/evaluator.rb:56-64`
- `:not_granted` denial: `lib/wild/capability_gate/evaluator.rb:66-74`
- `Grant#matches_caller?` and the `"*"` wildcard: `lib/wild/capability_gate/grant.rb:10`,
  `lib/wild/capability_gate/grant.rb:20-22`, `lib/wild/capability_gate/grant.rb:28-30`
- `String(caller_id)` is the whole of identity normalization:
  `lib/wild/capability_gate/evaluator.rb:43`, `lib/wild/capability_gate/grant.rb:15`

**INV-3 prerequisites always enforced**

- `Prerequisites::Checker::CHECKERS` closed dispatch table:
  `lib/wild/capability_gate/prerequisites/checker.rb:15-18`
- Unregistered type fails rather than passes:
  `lib/wild/capability_gate/prerequisites/checker.rb:43-47`
- Short circuit on first failure: `lib/wild/capability_gate/prerequisites/checker.rb:26-36`
- Checkers fail closed inside their own rescue:
  `lib/wild/capability_gate/prerequisites/file_exists_checker.rb:18-19`,
  `lib/wild/capability_gate/prerequisites/config_value_checker.rb:23-24`
- No skip mode, override flag, `force:` keyword, or environment bypass: verified by
  `grep -rn "ENV\|force:" lib/`, which returns nothing

**INV-4 check, allow, audit ordering**

- Ordered chain then `emit_audit` then return: `lib/wild/capability_gate/evaluator.rb:45-51`
- `emit_audit` no-ops without a writer: `lib/wild/capability_gate/evaluator.rb:106-107`
- `emit_audit` swallows write failures by design: `lib/wild/capability_gate/evaluator.rb:113-117`
- The unaudited `:evaluation_error` path: `lib/wild/capability_gate/gate.rb:42-44` returns
  `lib/wild/capability_gate/gate.rb:63-70` without reaching `emit_audit`
- The three denial reasons that are proven audited: `spec/safety/governance_rules_spec.rb:233-277`,
  `spec/safety/safety_defects_spec.rb:98-115`
- `Audit::Event::VALID_RESULTS`: `lib/wild/capability_gate/audit/event.rb:14`
- `Audit::Event#to_h` keys: `lib/wild/capability_gate/audit/event.rb:52-61`
- Append-only write: `lib/wild/capability_gate/audit/json_lines_writer.rb:26-30`

**INV-5 immutable after construction**

- `Capability`: `lib/wild/capability_gate/capability.rb:19`
- `Grant`: `lib/wild/capability_gate/grant.rb:17`
- `Prerequisite`: `lib/wild/capability_gate/prerequisite.rb:18`
- `Evaluator`: `lib/wild/capability_gate/evaluator.rb:25`
- `Registry`: `lib/wild/capability_gate/registry.rb:22`, index frozen at
  `lib/wild/capability_gate/registry.rb:67`
- `Audit::JsonLinesWriter`: `lib/wild/capability_gate/audit/json_lines_writer.rb:21`
- Also frozen, though not named in the invariant: `EvaluationResult`
  (`lib/wild/capability_gate/evaluation_result.rb:52`), `Prerequisites::CheckResult`
  (`lib/wild/capability_gate/prerequisites/check_result.rb:32`), `Audit::Event`
  (`lib/wild/capability_gate/audit/event.rb:42`). `Session` is deliberately not frozen because it
  holds the cache: `lib/wild/capability_gate/session.rb:27`
- No public mutators, proven: `spec/safety/safety_defects_spec.rb:191-216`,
  `spec/safety/governance_rules_spec.rb:200-231`

**INV-6 hostile config parsing**

- `Registry::ConfigLoader`: `lib/wild/capability_gate/registry/config_loader.rb:46`
- `Evaluator::GrantLoader`: `lib/wild/capability_gate/evaluator/grant_loader.rb:44`

**INV-7 two-method public surface**

- `Gate#evaluate`: `lib/wild/capability_gate/gate.rb:40`
- `Gate#capabilities`: `lib/wild/capability_gate/gate.rb:48`
- Module-level convenience constructor delegating to `Gate.new`:
  `lib/wild/capability_gate.rb:24-26`

**Cache poisoning across contexts**

- Cache key is `(caller_id, capability_name)`: `lib/wild/capability_gate/session.rb:59-61`
- Cache hit returns before re-evaluating, so no new audit event:
  `lib/wild/capability_gate/session.rb:33-40`
- The trade-off is documented: `lib/wild/capability_gate/session.rb:13-15`,
  `000-docs/004-AT-ADEC-architecture-decisions.md:34`
- In-process store, no cross-process sharing: `lib/wild/capability_gate/session/store.rb:9-11`

**Sensitive value leakage**

- Audit event serializes caller-supplied `context` verbatim:
  `lib/wild/capability_gate/audit/event.rb:41`, `lib/wild/capability_gate/audit/event.rb:60`
- `ConfigValueChecker` interpolates expected and actual into `details`:
  `lib/wild/capability_gate/prerequisites/config_value_checker.rb:34-37`
- That string travels into `EvaluationResult#details`:
  `lib/wild/capability_gate/prerequisites/checker.rb:32`,
  `lib/wild/capability_gate/evaluator.rb:84-88`

**Path and identity handling**

- `FileExistsChecker` calls `File.exist?` on a config-owned path:
  `lib/wild/capability_gate/prerequisites/file_exists_checker.rb:14-17`
- Prerequisite params come from `capabilities.yml`, not from `context`:
  `lib/wild/capability_gate/registry/config_loader.rb:98-105`

**Test theatre**

- `spec/safety/safety_defects_spec.rb` maps one describe block to each of the seven governance
  defects: lines `37`, `70`, `98`, `120`, `159`, `191`, `218`
- `spec/safety/governance_rules_spec.rb` maps to the five governance rules: lines `43`, `93`, `148`,
  `200`, `233`
- Adversarial specs assert on the reason symbol, for example
  `spec/safety/safety_defects_spec.rb:78`, `spec/safety/safety_defects_spec.rb:130`,
  `spec/safety/safety_defects_spec.rb:223`

**Generated, ignored, or not hand-edited**

- `Gemfile.lock`, `.beads/`, `.dolt/`, `pkg/`, `vendor/bundle/` ignored: `.gitignore:2-7`,
  `.gitignore:9-14`
- `planning/` is tracked, not ignored: `git ls-files planning` returns four files, and
  `git check-ignore planning/beads-import.md` exits 1
- `planning/beads-import.md` excluded from the reviewer diff:
  `.github/workflows/minimax-review.yml:56`
- `version.rb` is the single version source, read by the gemspec:
  `lib/wild/capability_gate/version.rb:5`, `wild-capability-gate.gemspec:3`,
  `wild-capability-gate.gemspec:7`

**Rejected features and settled style**

- No users, roles, org hierarchy, policy engine, UI: `CLAUDE.md:18-23`
- Gem not service, YAML not database, session-scoped state, minimal interface:
  `000-docs/004-AT-ADEC-architecture-decisions.md:10`,
  `000-docs/004-AT-ADEC-architecture-decisions.md:22`,
  `000-docs/004-AT-ADEC-architecture-decisions.md:34`,
  `000-docs/004-AT-ADEC-architecture-decisions.md:56`
- Rubocop runs with no tolerated offenses: `.github/workflows/ci.yml:28-29`, config `.rubocop.yml:1-31`

**Deterministic gate**

- `bundle exec rspec` and `bundle exec rubocop` on Ruby 3.2 and 3.3:
  `.github/workflows/ci.yml:12-14`, `.github/workflows/ci.yml:25-29`
- Both review lanes advisory, in no job's `needs`: `.github/workflows/minimax-review.yml:58-67`,
  `.github/workflows/minimax-review.yml:154-164`
