# TIR Insights Current State

## Scope

Tracks current implementation state of TIR analysis and recommendation behavior.

## Runtime behavior snapshot

- `runAnalysis(windowDays:)` builds config from live settings and supports data-source selection (`nightscout` or `healthkit`).
- Default analysis window is **7 days** (configurable to 14/30/90).
- Simulator mode is available and returns synthetic events plus caveats. Scenarios: `mixed_realistic`, `rebound_heavy`, `post_gap_heavy`, `constraint_limited`, `low_heavy`.
- Recommendations are produced by `TIRRecommendationEngine` with recurrence threshold `>= 3` events.
- Recommendations carry a `RecommendationSource` discriminator:
  - `.pattern` — from glucose event patterns only
  - `.settingsAudit` — from a settings finding with no matching pattern
  - `.crossReferenced` — pattern evidence + settings context combined
- Settings audit findings (from `TIRSettingsAuditor`) are cross-referenced with glucose patterns via a **7-rule mapping table** in `TIRRecommendationEngine`:
  - High: `constraintLimited↔maxIOB`, `risingWithoutCarbs↔sigmoidAutosens`, `reboundHigh↔sigmoidAutosens`, `persistentElevation↔maxSMBBasalMinutes`, `postConnectivityGap↔maxDeltaUAM`
  - Low: `overcorrectionLow↔sigmoidAutosens`, `stackingLow↔maxSMBBasalMinutes`
- All recommendation types appear in a single unified "Patterns & Suggestions" section (no separate Settings Audit section in the summary UI).
- Readiness requires full-day coverage by selected window and reports remaining days needed.
- Provider currently runs without rolling IOB history (`iobHistory: nil`), so `CONSTRAINT_LIMITED` may be skipped or downgraded.

## Low event classification (current)

Low glucose events are now classified by `LowEventClassifier` (pure static engine, `Engine/LowEventClassifier.swift`) using 9-priority strict-ordering:

| Priority | Category | Key Trigger |
|---|---|---|
| 1 | `COMPRESSION_LOW` | Duration < 30 min, rapid recovery ≥ 2 mg/dL per 5 min, nadir ≥ 54, no bolus > 0.5U in 2h |
| 2 | `OVERCORRECTION_LOW` | 1–2 bolus events totaling ≥ 1.0U in 1–4h before |
| 3 | `STACKING_LOW` | ≥ 3 SMBs in 60 min OR ≥ 2 boluses in 90 min before |
| 4 | `ACTIVITY_RELATED_LOW` | Exercise event within 0–4h (explicit data only — never guesses) |
| 5 | `REBOUND_LOW` | Reading above highThreshold within 90 min before |
| 6 | `BASAL_TOO_AGGRESSIVE` | No bolus > 0.5U in 3h, no carbs in 3h |
| 7 | `FALLING_WITHOUT_ACTIVE_INSULIN` | No SMB/bolus in 75 min, no carbs in 2h, nadir ≥ 54 |
| 8 | `PERSISTENT_LOW` | Duration ≥ 45 min |
| 9 | `UNCLASSIFIED_LOW` | Catch-all |

Insulin context for low classification comes from **Nightscout treatment history** (full analysis window via `fetchTreatments(since:until:count:)`), not local pump storage (24h cap). `TIRAnalysisProvider.mapTreatmentsToInsulinEvents()` maps `NigtscoutTreatment` → `InsulinEvent`/`TempBasalEvent`. When Nightscout is unavailable, arrays are empty and insulin-dependent categories are skipped gracefully.

Fetch count scales with analysis window: `max(500, windowDays * 100)`. This prevents silent truncation of insulin context on 14d/30d/90d windows.

Exercise events come from: (1) Nightscout `nsExercise` treatments (excluding iAPS-generated overrides), (2) HealthKit workouts via `TIRHealthKitReader.fetchWorkouts(from:to:)`.

`LowEventClassifier.extractFeatures(context:category:)` produces a `LowEventFeatures` numerical vector for future clustering/ML analysis.

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

## Error handling

- `TIRAnalysisResult` carries a `warnings: [String]` field populated when partial data was detected during analysis.
- `TIRAnalysisStateModel.analysisError: String?` is set to the joined warnings string after each run; cleared at run start.
- `TIRSummaryView` displays a yellow triangle banner when `analysisError != nil` — distinguishes "analysis failed" from "empty result" in the UI.
- Current trigger: Nightscout treatment fetch failure populates a warning: "Treatment data unavailable — insulin context excluded from low event classification."
- `NightscoutManager.fetchTreatments` now returns `AnyPublisher<[NigtscoutTreatment], Error>` (propagates); `NightscoutError.unavailable` is thrown when Nightscout is not configured or network is unreachable.
- `NightscoutAPI.fetchTreatments` no longer swallows errors — catch block removed, errors propagate to manager.

## Authoritative design references

- `.context/iAPS-TIR-decomposition-engine.md`
- `.context/TIR-Phase1A-plan.md`
- `.context/TIR-Phase1A-Track0.md`

## Code locations

- Provider and orchestration: `FreeAPS/Sources/Modules/TIRAnalysis/TIRAnalysisProvider.swift`
- Engine components: `FreeAPS/Sources/Modules/TIRAnalysis/Engine/`
- Data models (incl. `RecommendationSource`, `AuditCheckID`): `FreeAPS/Sources/Modules/TIRAnalysis/Engine/TIRModels.swift`
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
