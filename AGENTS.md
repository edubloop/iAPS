# AGENTS

Purpose: give a fresh coding agent a fast, safe entrypoint to this repository.

## Read this first

1. `.context/README.md`
2. `.context/01-Quickstart-For-Agents.md`
3. `.context/10-Architecture-Map.md`
4. `.context/90-Domain-Glossary-And-Safety-Guardrails.md`

Then choose task-specific docs from the routing section below.

## Safety and scope

- This project is a DIY automated insulin delivery app. Treat logic changes as safety-sensitive.
- Prefer small, auditable changes.
- Do not silently change dosing-related thresholds, timing windows, or units.
- When changing safety-relevant constants, update `.context/40-Constants-Conventions-And-Magic-Numbers.md`.

## Task routing

- TIR or recommendation logic: `.context/60-TIR-Insights-Current-State.md`
- Networking, endpoints, retries, URLs: `.context/30-Network-Endpoints-And-URL-Schemes.md`
- UI look, colors, spacing, typography: `.context/50-UI-Tokens-And-Layout-Conventions.md`
- Persistence and model contracts: `.context/20-Data-Contracts-And-Retention.md`
- Build/test expectations: `.context/70-Testing-Matrix.md`
- Branching, CI, and release flow: `.context/80-Branch-Release-CI-Policy.md`

## Working conventions for agents

- Prefer existing central constants over new literals.
- If a literal is unavoidable, place it in the closest `Config`/constants scope and explain why.
- Avoid duplicate endpoint/scheme strings across modules.
- Keep feature docs and code in sync when touching architecture, constants, or behavior.

## Do not do without explicit user approval

- Create new top-level directories or reorganize repository structure.
- Add, remove, or upgrade dependencies (SwiftPM, CocoaPods, Ruby gems) or change lockfiles.
- Change provider chain/order, DI wiring precedence, or fallback order between data sources.
- Modify dosing-related defaults, thresholds, timing windows, units, or recommendation severity policy.
- Change network endpoints, authentication flows, URL schemes, or remote command behavior.
- Change CI/release workflows, signing settings, bundle identifiers, app groups, or fastlane lanes.
- Introduce new telemetry/upload destinations or new persistence locations for sensitive data.
- Run destructive git/history operations (`reset --hard`, force push, history rewrite).

## Ask-first triggers

- The change affects architecture, execution order, or data-source precedence.
- The change affects dependencies, external interfaces, release pipeline, or security posture.
- The change modifies safety-sensitive behavior beyond a localized bug fix.

## Minimum verification before final response

- Run targeted tests for changed module(s), at least fast path from `.context/70-Testing-Matrix.md`.
- If changing algorithms or thresholds, run related unit tests and summarize behavioral impact.
- If adding/changing constants, confirm whether centralized or intentionally local.

## Source-of-truth anchors

- Core app code: `FreeAPS/Sources/`
- TIR engine: `FreeAPS/Sources/Modules/TIRAnalysis/`
- OpenAPS paths/constants: `FreeAPS/Sources/APS/OpenAPS/Constants.swift`
- Network layer: `FreeAPS/Sources/Services/Network/`
- Existing domain docs: `.context/iAPS-context.md`, `.context/iAPS-TIR-decomposition-engine.md`
