# Agent Decision Log

Use this file to keep short, date-stamped decisions that affect future agent sessions.

## Entry format

- Date:
- Area:
- Decision:
- Why:
- Code refs:
- Doc refs updated:

## Seed entries

- Date: 2026-03-05
- Area: Agent onboarding docs
- Decision: Added root `AGENTS.md` and numbered `.context` guide set
- Why: Reduce repeated rediscovery of architecture, constants, and safety conventions
- Code refs: `AGENTS.md`, `.context/*.md`
- Doc refs updated: `.context/README.md`

- Date: 2026-03-05
- Area: Lightweight structural quality checks
- Decision: Added `StructuralConventionsTests` with three lint-style tests for day literals, Nightscout profile endpoint literal scope, and deep-link scheme scope
- Why: Catch common drift/magic-number regressions with near-zero runtime overhead
- Code refs: `BuildTools/TIREngineTests/Tests/FreeAPSTests/StructuralConventionsTests.swift`
- Doc refs updated: `.context/30-Network-Endpoints-And-URL-Schemes.md`, `.context/40-Constants-Conventions-And-Magic-Numbers.md`, `.context/70-Testing-Matrix.md`
