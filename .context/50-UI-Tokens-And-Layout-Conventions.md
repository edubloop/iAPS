# UI Tokens And Layout Conventions

## Token sources

- SwiftUI color tokens: `FreeAPS/Sources/Helpers/Color+Extensions.swift`
- UIKit color bridge: `FreeAPS/Sources/Helpers/UIColor.swift`
- Loop UI palette mapping: `FreeAPS/Sources/APS/Extensions/LoopUIColorPalette+Default.swift`
- App-level UI config values: `FreeAPS/Sources/Models/Configs.swift`
- Reusable modifiers/backgrounds: `FreeAPS/Sources/Views/ViewModifiers.swift`

## Concrete shared tokens in use

- Semantic colors include `loopGreen`, `loopYellow`, `loopRed`, `insulin`, `carbs`, `warning`, `zt`, `uam`.
- Palette adapters bridge these into LoopKit chart/state palettes via `LoopUIColorPalette.default`.
- Shared app visual constants from `IAPSconfig`:
  - `padding`, `iconSize`, `backgroundOpacity`
  - `shadowOpacity`, `glassShadowOpacity`, `shadowFraction`
  - header/chart/preview background color choices
- Shared custom fonts are defined in `Font` extension inside `Configs.swift`.

## Current convention

- Prefer semantic colors (`.insulin`, `.loopGreen`, etc.) over ad-hoc RGB values
- Prefer shared config values (`IAPSconfig.*`) for repeated layout values
- Use local `private enum Config` inside complex views for view-specific constants

## Known drift areas

- Inline spacing (`padding(4/8/10/15/20)`) and frame sizes are widespread
- Some views maintain their own mini token sets not reused across modules
- `MainChartView` has a large local `Config` block with many numeric values; useful locally but not reused globally.

## Guidance for new changes

- Reuse existing semantic color and font definitions first
- If introducing a repeated spacing/size value, promote it to local `Config` or shared config depending on reuse scope
- Avoid introducing new literal values in multiple files without naming them
- For per-view constants, prefer `private enum Config` at top of view file.
- For cross-module values, prefer `IAPSconfig` or dedicated helper extensions.

## Derived from

- `FreeAPS/Sources/Helpers/Color+Extensions.swift`
- `FreeAPS/Sources/Helpers/UIColor.swift`
- `FreeAPS/Sources/APS/Extensions/LoopUIColorPalette+Default.swift`
- `FreeAPS/Sources/Models/Configs.swift`
- `FreeAPS/Sources/Views/ViewModifiers.swift`
- `FreeAPS/Sources/Modules/Home/View/**/*.swift`
