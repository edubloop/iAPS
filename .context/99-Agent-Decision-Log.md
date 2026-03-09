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

- Date: 2026-03-05
- Area: Endpoint and deep-link deduplication
- Decision: Consolidated app/deep-link URL literals into `CGMExternalAppURLs`, introduced `CGMConstants.secondsPerDay`, and switched Nightscout profile import to `NightscoutAPI.Config` constants
- Why: Reduce drift risk between call sites and central network/URL configuration
- Code refs: `FreeAPS/Sources/APS/CGM/CGMType.swift`, `FreeAPS/Sources/APS/KnownPlugins.swift`, `FreeAPS/Sources/APS/CGM/AppGroupCGM/AppGroupSource.swift`, `FreeAPS/Sources/Services/Network/NightscoutAPI.swift`, `FreeAPS/Sources/Modules/NightscoutConfig/NightscoutConfigStateModel.swift`
- Doc refs updated: `.context/30-Network-Endpoints-And-URL-Schemes.md`

- Date: 2026-03-05
- Area: Day-literal normalization
- Decision: Removed raw `86400`/`8.64E4` literals from `FreeAPS/Sources` and tightened structural checks to enforce zero tolerance in app sources
- Why: Reduce magic-number drift and make time-unit intent auditable and consistent
- Code refs: `FreeAPS/Sources/APS/APSManager.swift`, `FreeAPS/Sources/APS/Storage/CoreDataStorage.swift`, `FreeAPS/Sources/Modules/Stat/View/StatsView.swift`, `FreeAPS/Sources/Modules/Home/View/Header/CurrentGlucoseView.swift`, `FreeAPS/Sources/Modules/Dynamic/DynamicStateModel.swift`, `FreeAPS/Sources/Views/ViewModifiers.swift`, `FreeAPS/Sources/Modules/TIRAnalysis/Engine/TIRModels.swift`, `FreeAPS/Sources/Modules/TIRAnalysis/TIRAnalysisProvider.swift`, `BuildTools/TIREngineTests/Tests/FreeAPSTests/StructuralConventionsTests.swift`
- Doc refs updated: `.context/40-Constants-Conventions-And-Magic-Numbers.md`

- Date: 2026-03-08
- Area: TIR Insights UI refinements
- Decision: Default analysis window changed from 14 to 7 days. Removed coverage caveat section (inline data source instead). Moved Patterns & Suggestions directly below summary card. Adopted `.borderedProminent` button style for Run Analysis. Moved button below summary text. Added 24h Last Updated timestamp. Removed events count from summary. Redesigned home tile: left-aligned, dynamic data source label, chevron indicator.
- Why: Improve information density, reduce visual noise, make the interface consistent with app conventions
- Code refs: `TIRAnalysisStateModel.swift`, `TIRSummaryView.swift`, `HomeRootView.swift`, `HomeStateModel.swift`
- Doc refs updated: `.context/60-TIR-Insights-Current-State.md`, `.context/50-UI-Tokens-And-Layout-Conventions.md`

- Date: 2026-03-09
- Area: TIR low event classification — full pipeline
- Decision: Added 5 new cause-oriented low categories (compressionLow, overcorrectionLow, stackingLow, activityRelatedLow, basalTooAggressive) via a new pure static `LowEventClassifier` engine. Fetches full treatment history from Nightscout (replacing the 24h local pump data cap). Cross-reference rules expanded from 5 to 7 (added overcorrectionLow↔sigmoidAutosens, stackingLow↔maxSMBBasalMinutes). Added `lowHeavy` simulation scenario. Total test suite: 131 tests, 0 failures.
- Why: Knowing that a low happened is insufficient for actionable guidance; knowing it was from stacking, overcorrection, activity, basal aggression, or sensor compression enables specific recommendations. Nightscout treatments provide full-window insulin context that local pump storage cannot.
- Code refs: `Engine/LowEventClassifier.swift` (new), `TIRModels.swift` (InsulinEvent, TempBasalEvent, ExerciseEvent, LowEventContext, LowEventFeatures), `NightscoutAPI.swift` (fetchTreatments), `NightscoutManager.swift`, `TIRHealthKitReader.swift` (fetchWorkouts), `TIRAnalysisProvider.swift` (treatment mapping, context builder, lowHeavy scenario), `TIRRecommendationEngine.swift` (5 new recs, 2 new cross-ref rules), `TIRSummaryView.swift` (Low Patterns section), `BuildTools/TIREngineTests/Tests/FreeAPSTests/LowEventClassifierTests.swift` (42 tests)
- Doc refs updated: `.context/60-TIR-Insights-Current-State.md`, `.context/70-Testing-Matrix.md`

- Date: 2026-03-08
- Area: TIR recommendation engine — settings audit integration
- Decision: Merged settings audit into unified Patterns & Suggestions via cross-referencing engine. Added `AuditCheckID` enum to `TIRSettingsAuditFinding`, `RecommendationSource` enum and optional `category` to `TIRRecommendation`. Implemented 5 cross-reference rules mapping pattern categories to audit checks, with deduplication (cross-refs replace plain pattern recs). Removed standalone Settings Audit section from `TIRSummaryView`. Added 11 new tests (62 total, 61 passing).
- Why: Connect the dots between settings concerns and observed glucose patterns for richer, more actionable recommendations instead of presenting them as disconnected observations
- Code refs: `TIRModels.swift`, `TIRSettingsAuditor.swift`, `TIRRecommendationEngine.swift`, `TIRAnalysisProvider.swift`, `TIRSummaryView.swift`, `TIRRecommendationEngineTests.swift`
- Doc refs updated: `.context/TIR-Phase1A-plan.md`, `.context/60-TIR-Insights-Current-State.md`, `.context/iAPS-TIR-decomposition-engine.md`, `.context/70-Testing-Matrix.md`
