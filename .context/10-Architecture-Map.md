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

## Key source-of-truth files

- OpenAPS file names and path conventions: `FreeAPS/Sources/APS/OpenAPS/Constants.swift`
- Runtime config constants: `FreeAPS/Sources/Config/Config.swift`
- Global UI/app config values: `FreeAPS/Sources/Models/Configs.swift`
- TIR engine entry points: `FreeAPS/Sources/Modules/TIRAnalysis/`
- Plugin behavior switchboard: `FreeAPS/Sources/APS/KnownPlugins.swift`

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
