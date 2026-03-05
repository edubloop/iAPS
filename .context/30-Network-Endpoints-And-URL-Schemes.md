# Network Endpoints And URL Schemes

## Central network config sources

- Nightscout API config: `FreeAPS/Sources/Services/Network/NightscoutAPI.swift`
- Generic database API config: `FreeAPS/Sources/Services/Network/Database.swift`

## Canonical endpoint constants (current)

- Nightscout (`NightscoutAPI.Config`):
  - `/api/v1/entries/sgv.json`
  - `/api/v1/entries.json`
  - `/api/v1/treatments.json`
  - `/api/v1/devicestatus.json`
  - `/api/v1/profile.json`
  - `/upload.php`, `/vcheck.php`
  - Retry/timeout: `retryCount = 2`, `timeout = 60`
- Database (`Database.Config`):
  - `/upload.php`, `/vcheck.php`, `/download.php?token=`, `&section=profile_list`
  - Retry/timeout: `retryCount = 2`, `timeout = 60`

## Deep-link and external app URL sources

- CGM URL schemes: `FreeAPS/Sources/APS/CGM/CGMType.swift`
- Plugin-specific URL mappings: `FreeAPS/Sources/APS/KnownPlugins.swift`
- Nightscout remote CGM localhost mapping: `NightscoutRemoteCGM/NightscoutRemoteCGM/NightscoutRemoteCGM.swift`
- Dexcom Share servers and paths: `dexcom-share-client-swift/ShareClient/ShareClient.swift`

## Known app/deep-link schemes (current)

- Dexcom: `dexcomgcgm://`, `dexcomg6://`, `dexcomg7://`
- External CGM apps: `xdripswift://`, `libredirect://`
- Libre handoff: `freeaps-x://libre-transmitter`
- Localhost remaps in NightscoutRemoteCGM:
  - `http://127.0.0.1:1979` -> `spikeapp://`
  - `http://127.0.0.1:17580` -> `diabox://`

## Conventions

- Prefer centralized endpoint and timeout/retry constants in service-level `Config` enums
- Avoid re-declaring URL paths in feature modules when a network service already defines them
- Keep app URL schemes in a single authoritative mapping where possible

## Known duplication risks to avoid

- Timeout/retry literals (`60`, `2`) repeated outside network services
- Duplicated API paths like `/api/v1/profile.json`
- Repeated deep-link strings across `CGMType` and plugin helpers

## Current non-centralized callsite to watch

- `NightscoutConfigStateModel.importSettings()` currently inlines:
  - `path = "/api/v1/profile.json"`
  - `timeout: TimeInterval = 60`
  This should stay in sync with `NightscoutAPI.Config` until consolidated.

## Structural checks

- See `BuildTools/TIREngineTests/Tests/FreeAPSTests/StructuralConventionsTests.swift`:
  - `test_nightscoutProfileEndpointLiteralScopedToAllowlist`
  - `test_deepLinkSchemesScopedToKnownFiles`

## Derived from

- `FreeAPS/Sources/Services/Network/*.swift`
- `FreeAPS/Sources/APS/CGM/CGMType.swift`
- `FreeAPS/Sources/APS/KnownPlugins.swift`
- `NightscoutRemoteCGM/**/NightscoutRemoteCGM.swift`
- `dexcom-share-client-swift/ShareClient/*.swift`
