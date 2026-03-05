# Quickstart For Agents

## First 15 minutes

1. Read `AGENTS.md` and `.context/README.md`.
2. Skim `.context/10-Architecture-Map.md` and `.context/90-Domain-Glossary-And-Safety-Guardrails.md`.
3. Open the task-specific context doc for your area.
4. Inspect current git state before edits (`git status --short --branch`).

## Repo orientation

- Core app: `FreeAPS/Sources/`
- App tests: `FreeAPSTests/`
- TIR test harness: `BuildTools/TIREngineTests/`
- Plugin packages: top-level directories like `LoopKit/`, `OmniKit/`, `NightscoutRemoteCGM/`, `LibreTransmitter/`

## Fast commands

- TIR-focused fast path: `bash BuildTools/run_tir_tests.sh`
- TIR package direct run: `swift test --package-path BuildTools/TIREngineTests`
- Structural convention checks only: `swift test --package-path BuildTools/TIREngineTests --filter StructuralConventionsTests`

## Fast validation defaults

- If editing TIR engine/provider: run `BuildTools/run_tir_tests.sh`.
- If editing app logic outside TIR: run nearest module/unit tests first.
- If changing constants/thresholds/endpoints: run structural convention tests in `BuildTools/TIREngineTests`.
- If changing safety-sensitive logic: summarize behavior impact, not just test pass/fail.

## Where this quickstart is derived from

- `README.md`
- `AGENTS.md`
- `.context/TIR-Phase1A-plan.md`
- `.context/ReleasePlaybook.md`
- `BuildTools/run_tir_tests.sh`
- `BuildTools/TIREngineTests/Tests/FreeAPSTests/StructuralConventionsTests.swift`
- Directory layout under repository root
