# Data Contracts And Retention

## What this doc tracks

- Persisted file contracts and naming conventions
- Retention windows and pruning behavior
- Model-level assumptions that downstream modules depend on

## Core contracts to document and keep current

- OpenAPS file keys/paths in `FreeAPS/Sources/APS/OpenAPS/Constants.swift`
- Storage logic in `FreeAPS/Sources/APS/Storage/`:
  - `GlucoseStorage.swift`
  - `AnnouncementsStorage.swift`
  - `TempTargetsStorage.swift`
  - `CarbsStorage.swift`
  - `OverrideStorage.swift`

## Known retention conventions (examples to verify when changing)

- Glucose file storage keeps ~24h of records (`GlucoseStorage.storeGlucose`, filter using `+24.hours`), in `monitor/glucose.json`.
- Carbs file storage keeps ~1 day of records (`CarbsStorage.storeCarbs`, filter using `+1.days`), in `monitor/carbhistory.json`.
- Temp targets keep active-day horizon (`TempTargetsStorage`, filter using `+1.days`), in `settings/temptargets.json`.
- Announcements use recency windows of 10 minutes (`AnnouncementsStorage.Config.recentInterval`) and retain only recent day-scale entries.
- CGM state treatments are retained ~30 days for sensor-session context (`GlucoseStorage`, `monitor/cgm-state.json`).
- CoreData insulin activity cleanup uses two windows in `CoreDataStorage.saveInsulinData`:
  - delete future artifacts from `firstDate - 60s`
  - delete entries older than 1 day (`firstDate - 1.days.timeInterval`)

## Invariants to preserve

- Units and timestamp semantics must remain stable across producer/consumer modules
- File names under OpenAPS paths are compatibility-sensitive
- Any retention change must be called out in PR notes and test coverage
- TIR runtime caveat: pump history is effectively recent-window only; IOB rolling history is currently unavailable in provider path

## Derived from

- `FreeAPS/Sources/APS/OpenAPS/Constants.swift`
- `FreeAPS/Sources/APS/Storage/GlucoseStorage.swift`
- `FreeAPS/Sources/APS/Storage/CarbsStorage.swift`
- `FreeAPS/Sources/APS/Storage/TempTargetsStorage.swift`
- `FreeAPS/Sources/APS/Storage/AnnouncementsStorage.swift`
- `FreeAPS/Sources/APS/Storage/CoreDataStorage.swift`
- `FreeAPS/Sources/Modules/TIRAnalysis/TIRAnalysisProvider.swift`
- `.context/TIR-Phase1A-Track0.md`
- `.context/TIR-Phase1A-plan.md`
