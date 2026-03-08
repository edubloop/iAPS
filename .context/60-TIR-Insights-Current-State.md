# TIR Insights Current State

## Scope

Tracks current implementation state of TIR analysis and recommendation behavior.

## Runtime behavior snapshot

- `runAnalysis(windowDays:)` builds config from live settings and supports data-source selection (`nightscout` or `healthkit`).
- Simulator mode is available and returns synthetic events plus caveats.
- Recommendations are produced by `TIRRecommendationEngine` with recurrence threshold `>= 3` events.
- Readiness requires full-day coverage by selected window and reports remaining days needed.
- Provider currently runs without rolling IOB history (`iobHistory: nil`), so `CONSTRAINT_LIMITED` may be skipped or downgraded.

## Current thresholds and assumptions in provider path

- Analysis window start uses a named constant (`Provider.Config.secondsPerDay`) multiplied by `windowDays`.
- Coverage expected count assumes `288` readings/day (5-minute cadence).
- Full day threshold is `70%` of expected readings.
- Range breakdown buckets currently use:
  - very low `<54`
  - low `54..<70`
  - in range `70...180`
  - high `181...250`
  - very high `>250`

## Authoritative design references

- `.context/iAPS-TIR-decomposition-engine.md`
- `.context/TIR-Phase1A-plan.md`
- `.context/TIR-Phase1A-Track0.md`

## Code locations

- Provider and orchestration: `FreeAPS/Sources/Modules/TIRAnalysis/TIRAnalysisProvider.swift`
- Engine components: `FreeAPS/Sources/Modules/TIRAnalysis/Engine/`
- Data models: `FreeAPS/Sources/Modules/TIRAnalysis/Engine/TIRModels.swift`
- UI surfaces: `FreeAPS/Sources/Modules/TIRAnalysis/View/`

## Test locations

- Main tests: `FreeAPSTests/TIRAnalysis/`
- Portable harness: `BuildTools/TIREngineTests/`
- Script: `BuildTools/run_tir_tests.sh`
- Structural guard tests: `BuildTools/TIREngineTests/Tests/FreeAPSTests/StructuralConventionsTests.swift`

## Harness mirror policy

- `BuildTools/TIREngineTests/Sources/FreeAPS/Engine/` and `BuildTools/TIREngineTests/Tests/FreeAPSTests/` are tracked mirror copies for standalone package testing.
- Treat `FreeAPS/Sources/Modules/TIRAnalysis/Engine/` and `FreeAPSTests/TIRAnalysis/` as canonical edit locations.
- Refresh mirrors via `bash BuildTools/run_tir_tests.sh` before committing TIR engine/test changes.

## Change checklist for TIR edits

1. Update this document with behavior deltas.
2. Verify constants are centralized or intentionally local.
3. Run TIR-focused tests.
4. Summarize impact on confidence/coverage/recommendations.
5. If thresholds or windows changed, also update `.context/40-Constants-Conventions-And-Magic-Numbers.md`.

## Derived from

- TIR docs under `.context/`
- `FreeAPS/Sources/Modules/TIRAnalysis/**`
- `FreeAPSTests/TIRAnalysis/**`
- `BuildTools/TIREngineTests/**`
