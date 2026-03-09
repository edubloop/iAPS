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

- Date: 2026-03-09
- Area: Phase 1 — Error semantics and failure visibility
- Decision: Added `warnings: [String]` to `TIRAnalysisResult`; `TIRAnalysisStateModel.analysisError: String?` bound to joined warnings; `TIRSummaryView` shows orange triangle banner when non-nil. Changed `NightscoutManager.fetchTreatments` protocol from `Never` → `Error` and removed `replaceError(with: [])` in the impl; added `NightscoutError.unavailable` thrown when Nightscout is not reachable. Removed catch block from `NightscoutAPI.fetchTreatments` (re-throws). `TIRAnalysisProvider.fetchNightscoutTreatments` now catches errors and returns a `notice: String?`. Provider collects notices into `analysisWarnings` and passes them to the final result. All other NightscoutManager methods retain `Never` error type.
- Why: UI could not distinguish "analysis ran but empty" from "Nightscout unreachable"; silent treatment fetch failures degraded low-event classification quality with no user-visible signal.
- Code refs: `TIRModels.swift`, `TIRAnalysisStateModel.swift`, `TIRSummaryView.swift`, `TIRAnalysisProvider.swift`, `NightscoutManager.swift`, `NightscoutAPI.swift`
- Doc refs updated: `.context/10-Architecture-Map.md`, `.context/60-TIR-Insights-Current-State.md`

- Date: 2026-03-09
- Area: Phase 0 — Critical bug fixes
- Decision: (0A) Fixed DispatchGroup hang in `NightscoutConfigStateModel.importSettings()` — two early-return paths (network error, non-2xx HTTP) and a mimeType fall-through path were missing `group.leave()`, causing a 5-second UI freeze. Added `group.leave()` to all missing paths and an `else` branch for the mimeType check. (0B) Replaced force cast `response as! HTTPURLResponse` in `NetworkService` with a safe `guard let ... as? HTTPURLResponse`. (0C) Added `count` parameter to `NightscoutAPI.fetchTreatments` and `NightscoutManager.fetchTreatments`; TIR provider now scales count as `max(500, windowDays * 100)` to prevent silent insulin-context truncation on larger analysis windows.
- Why: Production bugs (hang, unsafe cast) and silent data quality degradation for multi-week TIR windows.
- Code refs: `NightscoutConfigStateModel.swift`, `NetworkService.swift`, `NightscoutAPI.swift`, `NightscoutManager.swift`, `TIRAnalysisProvider.swift`
- Doc refs updated: `.context/30-Network-Endpoints-And-URL-Schemes.md`, `.context/60-TIR-Insights-Current-State.md`

- Date: 2026-03-09
- Area: Phase 4 — Performance polish
- Decision: (4A) Fixed O(n²) glucose pagination in `NightscoutManager.fetchGlucose` — changed `acc: [BloodGlucose]` accumulator to `chunks: [[BloodGlucose]]` and flatten with `Array(chunks.joined())` only on termination. Each page now appends a small array reference instead of copying the full accumulator. (4B) Added `categoryCache: [TIREventCategory: [TIREvent]]` to `TIRAnalysisResult` (both canonical and harness mirrors), computed once in an explicit `init` from `events`. `events(for:)`, `tirCost(for:)`, and `pattern(for:)` now read from cache — O(1) per category instead of O(n) per call. (4C) Removed duplicate `@Published var maxIOB` and `@Published var maxCOB` from `HomeStateModel`; redirected `HomeRootView` from `state.maxIOB/maxCOB` to `state.data.maxIOB/maxCOB`. `ChartModel` is now the single owner; assignment happens once in `setupData()` / `settingsDidChange` instead of twice.
- Why: Paginating 90-day glucose backfill with copying accumulator was quadratic in page count. Category filter repeated per render for N categories × M events. Two identical `@Published` properties set from the same source at the same time added needless state and observer churn.
- Code refs: `FreeAPS/Sources/Services/Network/NightscoutManager.swift`, `FreeAPS/Sources/Modules/TIRAnalysis/Engine/TIRModels.swift`, `BuildTools/TIREngineTests/Sources/FreeAPS/Engine/TIRModels.swift`, `FreeAPS/Sources/Modules/Home/HomeStateModel.swift`, `FreeAPS/Sources/Modules/Home/View/HomeRootView.swift`
- Doc refs updated: `.context/99-Agent-Decision-Log.md`

- Date: 2026-03-09
- Area: Phase 3A/3B — NightscoutAPI request builder and force-unwrap elimination
- Decision: Extracted private `makeRequest(baseURL:path:queryItems:method:constrainedNetwork:addSecret:)` helper in `NightscoutAPI`. All 23 endpoint methods now use it, eliminating ~200 lines of `URLComponents` boilerplate. Methods now `guard let request = makeRequest(...)` and return `missingURLPublisher()` (`Fail<T, NightscoutAPI.Error.missingURL>`) on failure instead of force-unwrapping `components.url!`. All `try!` JSON encoding calls changed to `try?`; encoding failures produce a nil body (server-side rejection, no crash). Stats/version methods pass `baseURL: IAPSconfig.statURL` and `addSecret: false` to the builder.
- Why: 23 copies of 8-line URLComponents boilerplate accumulated drift risk and multiple force-unwrap (`url!`, `try!`) crash paths. Centralized builder enforces consistent timeout, constrained-network, and auth-header policy across all endpoints.
- Code refs: `FreeAPS/Sources/Services/Network/NightscoutAPI.swift`
- Doc refs updated: `.context/30-Network-Endpoints-And-URL-Schemes.md`, `AGENTS.md`

- Date: 2026-03-09
- Area: Phase 2 — CoreData threading and Home observer coalescing
- Decision: (2A) Added three `@MainActor async` CoreData variants (`fetchGlucoseAsync`, `fetchInsulinDataAsync`, `fetchLoopStatsAsync`) using `withCheckedContinuation` + `viewContext.perform` to yield the run loop during I/O. Updated three `HomeStateModel` setup methods (`setupGlucose`, `setupActivity`, `setupLoopStats`) to call async variants via `Task { @MainActor [weak self] in ... }`. (2B) Introduced `RefreshSection` enum + `setNeedsRefresh(_ sections: Set<RefreshSection>)` debounce pattern (100ms via `Task.sleep`) in `HomeStateModel`. Observer callbacks (`glucoseDidUpdate`, `suggestionDidUpdate`, `pumpHistoryDidUpdate`, `enactedSuggestionDidUpdate`, `settingsDidChange`) now mark dirty sections; a single `flushPendingRefresh()` coalesces all pending sections after the debounce window.
- Why: CoreData `performAndWait` on main thread blocked UI during observer callbacks. Single events were triggering 3-6 overlapping setup methods causing mixed-time-slice state and redundant fetches.
- Code refs: `FreeAPS/Sources/APS/Storage/CoreDataStorage.swift` (async variants), `FreeAPS/Sources/Modules/Home/HomeStateModel.swift` (RefreshSection, debounce, updated callers)
- Doc refs updated: `.context/10-Architecture-Map.md`

- Date: 2026-03-08
- Area: TIR recommendation engine — settings audit integration
- Decision: Merged settings audit into unified Patterns & Suggestions via cross-referencing engine. Added `AuditCheckID` enum to `TIRSettingsAuditFinding`, `RecommendationSource` enum and optional `category` to `TIRRecommendation`. Implemented 5 cross-reference rules mapping pattern categories to audit checks, with deduplication (cross-refs replace plain pattern recs). Removed standalone Settings Audit section from `TIRSummaryView`. Added 11 new tests (62 total, 61 passing).
- Why: Connect the dots between settings concerns and observed glucose patterns for richer, more actionable recommendations instead of presenting them as disconnected observations
- Code refs: `TIRModels.swift`, `TIRSettingsAuditor.swift`, `TIRRecommendationEngine.swift`, `TIRAnalysisProvider.swift`, `TIRSummaryView.swift`, `TIRRecommendationEngineTests.swift`
- Doc refs updated: `.context/TIR-Phase1A-plan.md`, `.context/60-TIR-Insights-Current-State.md`, `.context/iAPS-TIR-decomposition-engine.md`, `.context/70-Testing-Matrix.md`
