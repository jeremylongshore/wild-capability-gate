# wild-capability-gate

Governed access control for sensitive AI tool capabilities across the Wild ecosystem.

## What This Is

A Ruby gem that provides prerequisite-based capability gating for AI tool execution. Consuming repos call the gate before running privileged tools. The gate evaluates whether the caller has the required capability, checks that prerequisites are satisfied, and returns an allowed/denied result with a reason.

Every evaluation is:
- **Fail-closed** — errors result in denial, not permission
- **Prerequisite-enforced** — capabilities can require proof before granting
- **Audited** — every evaluation is logged with caller, capability, result, and context
- **Session-scoped** — evaluations are cached per session, no cross-session persistence

## Part of the Wild Ecosystem

This is the cross-cutting access control layer for the [wild](../) ecosystem. It is consumed by `wild-rails-safe-introspection-mcp`, `wild-admin-tools-mcp`, and potentially other repos.

See `../CLAUDE.md` for ecosystem-level context.

## Status

**Epic 7 complete** — the full pipeline is implemented and wrapped in a stable public interface. Consuming repos can integrate via `Wild::CapabilityGate.new(config_path:)`, call `gate.evaluate(caller:, capability:, context:)`, and inspect `gate.capabilities`. Fail-closed error handling ensures evaluation errors return denial, never raise. Ready for Epic 8 (Safety Testing).

- Canonical blueprint: `000-docs/001-PP-PLAN-repo-blueprint.md`
- Capability model: `000-docs/002-AT-STND-capability-model.md`
- Build plan: `000-docs/005-PP-PLAN-epic-build-plan.md`
- Task tracking: Beads (repo-local, run `bd list`)

## License

Intent Solutions Proprietary
