# Architecture Map

## Top-level runtime areas

- APS core and loop orchestration: `FreeAPS/Sources/APS/`
  - Loop manager and enactment orchestration: `APSManager.swift`, `OpenAPS/OpenAPS.swift`
  - Device integration boundary: `DeviceDataManager.swift`
  - Persisted runtime stores: `APS/Storage/*.swift`
- Network services: `FreeAPS/Sources/Services/Network/`
  - Nightscout API client: `NightscoutAPI.swift`
  - iAPS stats/profile backend client: `Database.swift`
- Domain services: `FreeAPS/Sources/Services/`
  - HealthKit writes: `HealthKit/HealthKitManager.swift`
  - Watch integration: `WatchManager/`
  - Contact trick: `ContactTrick/`
- App modules and views: `FreeAPS/Sources/Modules/`
  - Home/dashboard: `Modules/Home/`
  - TIR insights: `Modules/TIRAnalysis/`
- Shared models/config: `FreeAPS/Sources/Models/`, `FreeAPS/Sources/Config/`

## Data flow (high level)

1. Inputs: CGM/pump/settings state enters via plugins and `DeviceDataManager`.
2. Processing: OpenAPS scripts and app orchestration produce suggestions/enactments.
3. Persistence: file-based records under OpenAPS paths plus CoreData support tables.
4. Analysis: TIR provider composes glucose/carbs/pump data and calls pure TIR engines.
5. Presentation: SwiftUI modules render Home/Stats/TIR and act on state models.
6. Optional remote sync: Nightscout/network services fetch/upload treatment and profile data.
7. Error propagation: `NightscoutManager.fetchTreatments` propagates errors (return type `Error`) so the TIR provider can detect fetch failures vs legitimate empty results. Failures are surfaced as `TIRAnalysisResult.warnings[]` and bound to `TIRAnalysisStateModel.analysisError` for UI display. All other NightscoutManager fetch methods retain `Never` error type (swallowed) until Phase 3.

## Key source-of-truth files

- OpenAPS file names and path conventions: `FreeAPS/Sources/APS/OpenAPS/Constants.swift`
- Runtime config constants: `FreeAPS/Sources/Config/Config.swift`
- Global UI/app config values: `FreeAPS/Sources/Models/Configs.swift`
- TIR engine entry points: `FreeAPS/Sources/Modules/TIRAnalysis/`
- Plugin behavior switchboard: `FreeAPS/Sources/APS/KnownPlugins.swift`

## Home module refresh model

- `Home.StateModel` uses a `setNeedsRefresh(_ sections: Set<RefreshSection>)` debounce pattern (100ms).
- Observer callbacks (`glucoseDidUpdate`, `suggestionDidUpdate`, `pumpHistoryDidUpdate`, `enactedSuggestionDidUpdate`, `settingsDidChange`) mark dirty sections instead of calling setup methods directly.
- A single `flushPendingRefresh()` call coalesces all pending sections after the debounce window, preventing redundant overlapping fetches and mixed-time-slice UI state.

## CoreData threading model

- `CoreDataStorage` provides both synchronous (`performAndWait`) and async (`@MainActor async`) variants for `fetchGlucose`, `fetchInsulinData`, and `fetchLoopStats`.
- UI callers in `HomeStateModel` use the async variants via `Task { @MainActor in ... }`, so the main run loop is not held while CoreData executes I/O.
- Managed objects remain safely on `viewContext` (main thread). Non-UI callers continue using synchronous variants.

## Change routing guide

- Need to adjust storage behavior: start in `FreeAPS/Sources/APS/Storage/`
- Need endpoint/retry changes: start in `FreeAPS/Sources/Services/Network/`
- Need recommendation logic changes: start in `FreeAPS/Sources/Modules/TIRAnalysis/Engine/`
- Need chart or home UI changes: start in `FreeAPS/Sources/Modules/Home/View/`
- Need external app URLs/plugin IDs: start in `FreeAPS/Sources/APS/CGM/CGMType.swift` and `FreeAPS/Sources/APS/KnownPlugins.swift`

## Derived from

- `FreeAPS/Sources/APS/`
- `FreeAPS/Sources/Services/`
- `FreeAPS/Sources/Modules/`
- `.context/iAPS-context.md`
