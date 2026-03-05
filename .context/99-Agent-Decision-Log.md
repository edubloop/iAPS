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
