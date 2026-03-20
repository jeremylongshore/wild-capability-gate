# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] — 2026-03-17

### Added

#### Epic 1: Foundation
- Repo scaffold, gem skeleton, configuration, error hierarchy
- Capability model with YAML-based capability definitions

#### Epic 2: Capability Registry
- `Registry::ConfigLoader` — YAML capability and grant loading
- `Registry::CapabilityStore` — in-memory capability registry
- Capability schema validation

#### Epic 3: Rule Evaluator
- `Evaluation::RuleEvaluator` — core evaluation engine
- Grant matching with wildcard support
- Context-based evaluation

#### Epic 4: Prerequisite Checking
- Prerequisite chain validation wired into evaluation pipeline
- Circular dependency detection

#### Epic 5: Session-Scoped State
- Session-scoped evaluation caching
- Cache invalidation on context change

#### Epic 6: Audit Trail
- Structured audit trail for capability evaluations
- Queryable audit log with filtering

#### Epic 7: Public Interface
- `WildCapabilityGate.evaluate` — public API for consuming repos
- Clean consumer-facing interface

#### Epic 8: Safety Testing
- Adversarial validation suite
- Safety invariant tests

#### Epic 9: MVP Packaging
- Operator documentation and integration guide
- Configuration reference

#### Epic 10: V1 Close
- Updated epic build plan status to v1 complete
- Final doc sweep and coherence check

### Documentation
- 12 canonical docs in 000-docs/
- Complete doc index with filing code reference

### Test Coverage
- 224 examples, 0 failures
- Unit, integration, and adversarial test suites

### Quality
- 0 rubocop offenses
- CI green on Ruby 3.2 and 3.3
- Gemini code review on all PRs
