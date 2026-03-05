# Domain Glossary And Safety Guardrails

## Domain terms (starter)

- TIR: Time in Range
- IOB: Insulin On Board
- COB: Carbohydrates On Board
- SMB: Super Micro Bolus
- UAM: Unannounced Meal
- ISF: Insulin Sensitivity Factor
- IC/CR: Insulin-to-Carb ratio
- Temp target/profile override: temporary therapy parameter adjustments
- Autosens: automatic sensitivity adjustment logic
- OpenAPS: reference algorithm stack executed by the app

## Safety guardrails for code changes

- Treat dosing logic and thresholds as safety-sensitive.
- Avoid silent changes to units, timing windows, and recommendation criteria.
- Prefer explicit naming for constants and thresholds.
- Favor small, auditable diffs with focused tests.
- Keep advisory features (TIR insights) clearly non-enactment; do not route recommendations directly into therapy actions.
- When changing thresholds in analysis or classification, update `.context/40-Constants-Conventions-And-Magic-Numbers.md`.

## High-risk areas

- APS loop logic under `FreeAPS/Sources/APS/`
- TIR recommendation and classification logic under `FreeAPS/Sources/Modules/TIRAnalysis/Engine/`
- Network behaviors that influence remote commands/config import
- Storage retention windows and file contracts in `FreeAPS/Sources/APS/Storage/`

## Derived from

- `.context/iAPS-context.md`
- `.context/iAPS-TIR-decomposition-engine.md`
- `README.md`
- `FAQ.md`
