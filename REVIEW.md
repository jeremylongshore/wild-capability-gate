# REVIEW.md

Reviewer law for `wild-capability-gate`, the repository the automated pull-request reviewer
(MiniMax, two advisory lanes) must apply. This is not a style guide. Style is already settled by
`bundle exec rubocop` in CI, and the reviewer must not restate it.

## What this repo is, and why review is risk-ordered

`wild-capability-gate` is a Ruby gem that answers one question for the rest of the Wild ecosystem:
"is this caller allowed to perform this privileged operation?" It is consumed in-process by MCP
servers such as `wild-rails-safe-introspection-mcp` and `wild-admin-tools-mcp`. If it returns
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

- **INV-1 fail closed.** `Gate#evaluate` and `Evaluator#evaluate` return an `EvaluationResult` and
  never raise. `Gate#evaluate` rescues `StandardError` and converts it to a denial with reason
  `:evaluation_error`. Any new code path that can raise past that rescue, return `nil`, return a
  truthy non-result, or default a decision to allow is a blocking defect. In this repo "fail closed"
  means precisely: every abnormal outcome (missing config, unreadable file, unknown prerequisite
  type, checker exception, nil caller, nil capability) resolves to a denial that still carries a
  reason symbol.
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
  the ordered chain then calls `emit_audit` before returning. Every evaluation, allowed or denied,
  emits one event. A new early `return` inserted above `emit_audit` creates a silent evaluation
  path, which is safety defect 3 in the governance model.
- **INV-5 immutable after construction.** `Capability`, `Grant`, `Prerequisite`, `Evaluator`,
  `Registry`, and `Audit::JsonLinesWriter` all call `freeze`. Adding a writer, an `attr_writer`, a
  mutating setter, or a public method that reloads config at runtime breaks configuration
  immutability and lets an agent escalate its own capabilities mid-session.
- **INV-6 config parsing stays hostile.** `Registry::ConfigLoader` uses
  `YAML.safe_load(content, permitted_classes: [Symbol])`. Any move to `YAML.load`,
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
state and must never appear in a diff. `planning/beads-import.md` is ignored. `lib/wild/capability_gate/version.rb`
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
