# Constants Conventions And Magic Numbers

## Purpose

Track high-impact constants and identify what is centralized vs scattered.

## Central sources

- Loop/runtime config: `FreeAPS/Sources/Config/Config.swift`
- App/UI global config: `FreeAPS/Sources/Models/Configs.swift`
- OpenAPS paths/file constants: `FreeAPS/Sources/APS/OpenAPS/Constants.swift`
- TIR engine constants: `FreeAPS/Sources/Modules/TIRAnalysis/Engine/*.swift`

## High-impact constants currently centralized

- Loop timing in `Config.swift`:
  - `loopIntervalFiveMinutes = 270s` (4.5 minutes)
  - `loopIntervalOneMinute = 50s`
  - `expirationInterval = 10m`
- App-level settings in `IAPSconfig` (`Configs.swift`):
  - layout/shadow baselines (`padding = 60`, `iconSize = 34`, opacities)
  - stats backend URL `https://submit.open-iaps.app`
- TIR engine thresholds:
  - `ThresholdCrossingDetector`: CGM gap `10m`, consolidation `15m`
  - `EventClassifier`: rebound windows `60m`, post-gap window `30m`, carb lookback `4h`, persistent elevation minimum `3h`
  - `TIRRecommendationEngine`: recurrence threshold `3`
- CGM lifecycle constants:
  - `CGMConstants.secondsPerDay = 86_400` in `FreeAPS/Sources/APS/CGM/CGMType.swift`

## Scattered patterns to monitor

- Day-in-seconds literals (`86400`, `8.64E4`) in app code (should be treated as regressions)
- 5-minute and 15-minute windows encoded inline in providers/views/services
- Inline timeout/retry and API path literals outside network config
- View spacing/frame literals repeated heavily in module views
- Sentinel values (for example in plugin helpers) that should be documented

## Known scattered examples (current)

- Day literals (`86400`, `8.64E4`) have been removed from `FreeAPS/Sources` and are now blocked by structural tests.
- Inlined TIR thresholds in provider range breakdown/readiness:
  - `<54`, `54-69`, `70-180`, `181-250`, `>250`
  - full-day readiness threshold `70%` of 288 expected points/day
- Plugin sentinel in `KnownPlugins`: `0xDEAD_BEEF` for unavailable pod reservoir values.
- UI spacing/sizing literals pervasive in views (`padding(8/10/15/20)`, frame widths/heights).

## Structural checks

- `StructuralConventionsTests.test_secondsPerDayLiteralsScopedToAllowlist` now enforces zero raw day literals in `FreeAPS/Sources`.

## Rule of thumb

- If a value is reused or safety-relevant, centralize it.
- If a value remains local by design, keep it in nearest `private enum Config` with clear name.

## Update protocol for agents

When changing constants:

1. Confirm whether a central constant already exists.
2. If adding one, place it in the closest domain config scope.
3. Update this document with file path and intent.
4. Run related tests and summarize behavior impact.

## Derived from

- `FreeAPS/Sources/Config/Config.swift`
- `FreeAPS/Sources/Models/Configs.swift`
- `FreeAPS/Sources/APS/OpenAPS/Constants.swift`
- `FreeAPS/Sources/Modules/TIRAnalysis/Engine/EventClassifier.swift`
- `FreeAPS/Sources/Modules/TIRAnalysis/Engine/ThresholdCrossingDetector.swift`
- `FreeAPS/Sources/Modules/TIRAnalysis/Engine/TIRRecommendationEngine.swift`
- `FreeAPS/Sources/Modules/TIRAnalysis/TIRAnalysisProvider.swift`
- `FreeAPS/Sources/Modules/Home/View/**/*.swift`
- `FreeAPS/Sources/APS/KnownPlugins.swift`
