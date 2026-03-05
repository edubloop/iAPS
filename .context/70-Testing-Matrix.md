# Testing Matrix

## Minimum fast-path expectations

- TIR module changes:
  - Run `BuildTools/run_tir_tests.sh`
  - Run targeted tests under `FreeAPSTests/TIRAnalysis/` when applicable
  - Include structural checks from `StructuralConventionsTests`

- Network/service changes:
  - Run nearest service tests if present
  - Run `swift test --package-path BuildTools/TIREngineTests --filter StructuralConventionsTests/test_nightscoutProfileEndpointLiteralScopedToAllowlist`
  - Validate endpoint/timeout/retry values match service-level configs

- UI-only changes:
  - Run affected module tests if any
  - Verify compile and key screen rendering path

## Structural lint-style tests (lightweight)

- File: `BuildTools/TIREngineTests/Tests/FreeAPSTests/StructuralConventionsTests.swift`
- Rules currently enforced:
  - `test_secondsPerDayLiteralsScopedToAllowlist`
  - `test_nightscoutProfileEndpointLiteralScopedToAllowlist`
  - `test_deepLinkSchemesScopedToKnownFiles`
- Run only these checks:
  - `swift test --package-path BuildTools/TIREngineTests --filter StructuralConventionsTests`

## TIR mirror sync expectation

- TIR package harness files are tracked and intentionally mirrored.
- Before committing TIR engine/test edits, run `bash BuildTools/run_tir_tests.sh` to refresh:
  - `BuildTools/TIREngineTests/Sources/FreeAPS/Engine/*.swift`
  - `BuildTools/TIREngineTests/Tests/FreeAPSTests/*.swift`

## Before final response

1. Report what tests were run.
2. Report failures or skipped checks explicitly.
3. If algorithm/threshold changed, include behavior impact summary.
4. If constants/endpoints/schemes changed, state whether structural checks passed.

## Common test sources

- `FreeAPSTests/`
- `BuildTools/TIREngineTests/`
- `BuildTools/run_tir_tests.sh`

## Derived from

- `.context/TIR-Phase1A-plan.md`
- `BuildTools/run_tir_tests.sh`
- Existing test tree under repository
