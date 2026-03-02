# Phase 1A — TIR Decomposition Engine: Status & Roadmap

> **Scope constraint:** All changes live exclusively on `dev-ci-hardening`. This work is experimental and is **not intended for upstream merge** unless it proves highly successful later. No changes to shared frameworks (LoopKit, OmniKit, etc.) or upstream-facing APIs.

---

## Current State vs. Workplan

| Track | Deliverable | Status |
|-------|-------------|--------|
| **0** | Data contract (`.context/TIR-Phase1A-Track0.md`) | ✅ Complete |
| **0** | Fixture JSON (`.context/fixtures/tir/phase1a-model-examples.json`) | ✅ Complete |
| **0** | Coverage validator (`BuildTools/tir_coverage_report.py`) | ✅ Complete |
| **1** | `TIRModels.swift` — all engine data types | ✅ Complete |
| **1** | `ThresholdCrossingDetector.swift` — segment detection | ✅ Complete |
| **1** | `EventClassifier.swift` — 6-category priority classifier | ✅ Complete |
| **1** | `TIRAnalysisEngine.swift` — pure orchestrator | ✅ Complete |
| **1** | 21 XCTests passing via standalone Swift Package | ✅ Complete |
| **1** | `FreeAPSSettings.tirAnalysisEnabled = false` | ✅ Complete |
| **1** | Xcode project registration (all 10 files, both targets) | ✅ Complete |
| **2** | `TIRHealthKitReader.swift` — HealthKit glucose + carbs fetch | ✅ Complete |
| **2** | `WindowCoverage` + `TIRAnalysisResult` in `TIRModels.swift` | ✅ Complete |
| **2** | `TIRAnalysisProvider` — DI wiring → `TIRAnalysisEngine.analyze()` | ✅ Complete |
| **2** | `TIRAnalysisStateModel` — `@Published` results + `triggerAnalysis()` | ✅ Complete |
| **2** | `TIRAnalysisDataFlow` — `runAnalysis(windowDays:)` protocol method | ✅ Complete |
| **3** | Contributing factor population | ✅ Complete |
| **4** | Settings audit — static analysis of `FreeAPSSettings` + `Preferences` | ✅ Complete |
| **5** | SwiftUI summary screen + category detail screen | ✅ Complete |
| **5** | Settings audit screen | ✅ Complete |

---

## Critical Architectural Constraint

**iAPS file storage retains only 24 hours** for all three data types:
- `GlucoseStorage.retrieveRaw()` — 24 h (`monitor/glucose.json`)
- `CarbsStorage.recent()` — 1 day (`monitor/carbhistory.json`)
- `PumpHistoryStorage.recent()` — 1 day (`monitor/pumphistory.json`)
- IOB — **no rolling history at all**; only current snapshot (`monitor/iob.json`)

### Runtime vs Offline Data Strategy (Unified)

To avoid ambiguity between docs, data sources are split by execution context:

- **Runtime in-app analysis (what ships in iAPS):**
  - Glucose + carbs source: selectable (`Nightscout` or `HealthKit`) via TIR Insights config
  - Default source: `Nightscout` (`tirDataSource = "nightscout"`)
  - Nightscout path requires URL/API secret and `nightscoutFetchEnabled`; upload strongly recommended if no external uploader
  - Pump history / SMB evidence: iAPS file storage (`monitor/pumphistory*.json`, ~24 h)
  - IOB history: currently unavailable as rolling series; `CONSTRAINT_LIMITED` may downgrade/skip

- **Offline validation and development analysis (what we run outside app):**
  - Tidepool export (`TidepoolExport.json`) for long-range glucose + basal + bolus
  - Apple Health export (`apple_health_export/export.xml`) for long-range glucose + carbs
  - Local iAPS records (`monitor/`, `settings/`, `preferences.json`, `logs/`) for recent context

This keeps runtime behavior deterministic and privacy-safe while allowing richer validation during development.

---

## Track 3 — Contributing Factors

### Goal
Populate `contributingFactors: [TIRContributingFactor]` in each `TIREvent` when classifier evidence is available.

### Per-category factor evidence
| Category | Factor text |
|----------|------------|
| `CONSTRAINT_LIMITED` | "IOB was at Xu (Max IOB Xu) for Y of Z buckets" |
| `POST_CONNECTIVITY_GAP` | "CGM gap of N minutes ended Z minutes before event" |
| `PERSISTENT_ELEVATION` | "N SMBs delivered (X.Xu total) — algorithm was responding" |
| `REBOUND_HIGH` | "Low of Xmg/dL ended N minutes before this event" |

### Files to modify
- `FreeAPS/Sources/Modules/TIRAnalysis/Engine/EventClassifier.swift` — return factors alongside (category, confidence)
- `FreeAPS/Sources/Modules/TIRAnalysis/Engine/TIRAnalysisEngine.swift` — pass factors into `TIREvent`

---

## Track 4 — Settings Audit (Static)

### Goal
Pure static analysis of `FreeAPSSettings` + `Preferences`. No loop data needed. Runs independently of the event engine.

### Key checks (from spec §5.3)
| Check | Fields | Risky Condition |
|-------|--------|-----------------|
| Sigmoid + high autosensMax | `preferences.sigmoid`, `autosensMax` | sigmoid=true AND autosensMax > 1.5 |
| Delta-BG threshold + UAM | `preferences.maxDeltaBGthreshold` | < 0.25 with UAM enabled → SMBs over-suppressed post-gap |
| Max IOB vs daily needs | `preferences.maxIOB` | maxIOB = 0 or very low → CONSTRAINT_LIMITED events likely |
| Max SMB size reasonableness | `preferences.maxSMBBasalMinutes`, basal rate | computed max SMB vs typical correction needs |

### New file
- `FreeAPS/Sources/Modules/TIRAnalysis/Engine/TIRSettingsAuditor.swift`

```swift
enum AuditSeverity { case watch, ok }

struct TIRSettingsAuditFinding {
    let severity: AuditSeverity
    let message: String
    let suggestion: String?
}

struct TIRSettingsAuditReport {
    let findings: [TIRSettingsAuditFinding]
}

enum TIRSettingsAuditor {
    static func audit(settings: FreeAPSSettings, preferences: Preferences) -> TIRSettingsAuditReport
}
```

---

## Track 5 — SwiftUI UI

### Goal
Usable summary flow with grouped pattern presentation, source selection, simulator controls, and clearer audit guidance.

### Views (3)
1. **`TIRSummaryView`** — 7/14/30/90-day windows, TIR zone bar (very low/low/in-range/high/very high), grouped breakdown sections
2. **`TIRCategoryDetailView`** — event list per category/group with duration + severity + factor chips
3. **`TIRSettingsAuditView`** — plain-language findings (What we see / Why it matters / What to try)

### Navigation
- Entry point: row in existing Home → Statistics/Insights section; sheet presented; gated by `tirAnalysisEnabled`
- Settings controls: **TIR Insights** drill-in screen under **Extra Features** (enable, data source, simulator on/off, scenario picker)
- No new tab required

### Current grouped presentation
- **High Patterns:** Rebound High, Persistent Elevation, Rising Without Carbs, Max Insulin Limit
- **Low Patterns:** Rebound Low, Persistent Low, Falling Without Active Insulin
- **Data Quality:** Post Connectivity Gap
- **Unclassified Outliers:** combined row with split metrics (`High x% • Low y%`)

### Files
```
FreeAPS/Sources/Modules/TIRAnalysis/View/
├── TIRRootView.swift
├── TIRSummaryView.swift
├── TIRCategoryDetailView.swift
└── TIRSettingsAuditView.swift
```

---

## Recommended Build Order

Track 3 → Track 4 → Track 5

Each track is independently committable.

---

## Key Reference Files

| File | Purpose |
|------|---------|
| `FreeAPS/Sources/Modules/TIRAnalysis/Engine/TIRModels.swift` | All engine + result types |
| `FreeAPS/Sources/Modules/TIRAnalysis/Engine/EventClassifier.swift` | Category + confidence; Track 3 adds factors |
| `FreeAPS/Sources/Modules/TIRAnalysis/Engine/TIRAnalysisEngine.swift` | Orchestrator; Track 3 threads factors through |
| `FreeAPS/Sources/Modules/TIRAnalysis/Engine/TIRSettingsAuditor.swift` | Static settings-risk checks for Track 4 |
| `FreeAPS/Sources/Modules/TIRAnalysis/TIRHealthKitReader.swift` | HealthKit fetch layer (read-only) |
| `FreeAPS/Sources/Modules/TIRAnalysis/TIRAnalysisProvider.swift` | Data fetch + engine call |
| `FreeAPS/Sources/Modules/TIRAnalysis/TIRAnalysisStateModel.swift` | @Published state + triggerAnalysis() |
| `FreeAPS/Sources/Modules/TIRAnalysis/View/TIRRootView.swift` | Track 5 modal entry for TIR insights |
| `FreeAPS/Sources/Modules/TIRAnalysis/View/TIRSummaryView.swift` | Track 5 summary + navigation |
| `FreeAPS/Sources/Services/HealthKit/HealthKitManager.swift` | Existing write service — do NOT modify |
| `FreeAPS/Sources/Models/FreeAPSSettings.swift` | `high`, `low`, `units`, `tirAnalysisEnabled`, simulator flags, `tirDataSource` |
| `FreeAPS/Sources/Models/Preferences.swift` | `maxIOB`, `maxDeltaBGthreshold`, `sigmoid`, `autosensMax` |
| `BuildTools/run_tir_tests.sh` | Run TIR engine tests via standalone Swift Package |
| `BuildTools/add_tir_analysis_to_xcode.rb` | Register new files in Xcode project (idempotent) |
| `.context/TIR-Phase1A-Track0.md` | Canonical event contract + confidence policy |
| `.context/fixtures/tir/phase1a-model-examples.json` | Round-trip fixture for TC-19 |

---

## Test Infrastructure

Engine tests run via a standalone Swift Package (no Xcode submodule dependencies needed):

```bash
bash BuildTools/run_tir_tests.sh
```

Copies engine source + test files fresh before each run, then executes `swift test` on macOS.
Current baseline is 32 tests passing before any commit.
