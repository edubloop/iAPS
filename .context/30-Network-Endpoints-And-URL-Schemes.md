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

- Canonical app/deep-link URL constants: `FreeAPS/Sources/APS/CGM/CGMType.swift` (`CGMExternalAppURLs`)
- Plugin-specific URL mappings consume canonical constants: `FreeAPS/Sources/APS/KnownPlugins.swift`
- AppGroup source mappings consume canonical constants: `FreeAPS/Sources/APS/CGM/AppGroupCGM/AppGroupSource.swift`
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
- Repeated deep-link strings outside `CGMExternalAppURLs`

## Request builder (NightscoutAPI)

- All `NightscoutAPI` endpoint methods use a private `makeRequest(baseURL:path:queryItems:method:constrainedNetwork:addSecret:)` helper.
- The builder centralizes: `URLComponents` construction, `timeoutInterval`, `allowsConstrainedNetworkAccess`, and `api-secret` header injection.
- Methods that use the iAPS stats backend (`uploadStats`, `uploadPrefs`, `uploadSettings`, `uploadSettingsToDatabase`, `fetchVersion`) pass `baseURL: IAPSconfig.statURL` and `addSecret: false`.
- Methods return `missingURLPublisher()` (a `Fail<T, NightscoutAPI.Error.missingURL>`) if the builder cannot produce a valid URL.
- Force-unwraps (`url!`) and most `try!` JSON encoding calls have been eliminated; encoding failures map to `nil` body (the upload will be rejected by the server, not crash the app).

## Recently consolidated

- `NightscoutConfigStateModel.importSettings()` now uses:
  - `NightscoutAPI.Config.profilePath`
  - `NightscoutAPI.Config.timeout`

## Treatment fetch count

- `NightscoutAPI.fetchTreatments(sinceDate:untilDate:count:)` accepts a `count` parameter (default 500).
- `NightscoutManager.fetchTreatments(since:until:count:)` passes it through.
- TIR provider scales count with window: `max(500, windowDays * 100)` to avoid silent truncation on longer analysis windows.

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
