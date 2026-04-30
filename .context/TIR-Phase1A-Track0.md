# TIR Decomposition Phase 1A - Track 0

This document defines the data contract and coverage validation approach used by the Phase 1A MVP.

## 1) Canonical Models

These models are analysis-only and advisory-only.

### Event

```json
{
  "id": "evt_20260301T0940Z_001",
  "start": "2026-03-01T09:40:00Z",
  "end": "2026-03-01T10:25:00Z",
  "type": "high",
  "peak_severity": 212,
  "duration_minutes": 45,
  "tir_cost": 0.22,
  "category": "PERSISTENT_ELEVATION",
  "confidence": "high",
  "contributing_factors": []
}
```

### ContributingFactor

```json
{
  "factor": "Max IOB ceiling reached",
  "evidence": "IOB was at 8.0U (Max IOB 8.0) for 43 of 78 minutes",
  "actionable": true,
  "suggestion": "Review Max IOB in context of recent lows before considering increase"
}
```

### Recommendation

```json
{
  "priority": 1,
  "type": "SETTINGS_CHANGE",
  "title": "Persistent highs are frequently constraint-limited",
  "detail": "Constraint-limited highs account for 2.1 TIR points in the last 14 days.",
  "tir_impact_estimate": 2.1,
  "confidence": 0.84,
  "risk": "low",
  "affected_settings": ["Max IOB", "Max SMB Basal Minutes"],
  "evidence_window": {
    "start": "2026-02-16T00:00:00Z",
    "end": "2026-03-01T23:59:59Z",
    "event_count": 12
  },
  "reversibility": "Revert to prior values if low events increase in 3 days"
}
```

### WindowCoverage

```json
{
  "window_days": 14,
  "analysis_end": "2026-03-01T23:59:59Z",
  "metrics": {
    "glucose": { "has_data": true, "record_count": 4032 },
    "insulin_basal": { "has_data": true, "record_count": 988 },
    "insulin_bolus": { "has_data": true, "record_count": 75 },
    "carbs": { "has_data": false, "record_count": 0 }
  },
  "caveats": [
    "Carb records missing in this window; meal-specific high subcategories downgraded"
  ]
}
```

## 2) Category Scope for Phase 1A

Enabled categories:

- `PERSISTENT_ELEVATION`
- `RISING_WITHOUT_CARBS`
- `REBOUND_HIGH`
- `POST_CONNECTIVITY_GAP`
- `CONSTRAINT_LIMITED`

Deferred categories:

- Meal subcategories requiring reliable carb alignment (`POST_MEAL_SPIKE:*`)
- Low-event recommendation categories

## 3) Confidence Policy

- `high`: required data for category + factors available in window
- `medium`: category computable but one key factor source is partial
- `low`: category/factors rely on missing carb stream or inferred-only context

Any insight with carb incompleteness must include a caveat in UI/report output.

## 4) Data Source Mapping

Primary source preference by metric:

1. Glucose: Tidepool `cbg` -> Apple Health `BloodGlucose` -> iAPS local `monitor/glucose.json`
2. Insulin basal/bolus: Tidepool `basal`/`bolus` -> iAPS local pump history
3. Carbs: Apple Health `DietaryCarbohydrates` -> iAPS local `monitor/carbhistory.json` / `upload/uploaded-carbs.json`
4. Settings context: iAPS `settings/*.json` + `preferences.json`

## 5) Historical Modeling Note (Deprecated)

During early Phase 1A prototyping, an external local data directory was used to model coverage assumptions and sanity-check source completeness.

That directory-based workflow is now deprecated for Phase 1A documentation and should not be treated as an active dependency.

The standalone modeling helper script used during that phase (`BuildTools/tir_coverage_report.py`) has been retired from this branch.

Current source of truth for Phase 1A validation:

- data-contract definitions in this document
- fixture examples in `.context/fixtures/tir/phase1a-model-examples.json`
- in-repo engine tests under `FreeAPSTests/TIRAnalysis/` and `BuildTools/TIREngineTests/`

## 6) Fixture

Sample objects for parser/validator smoke tests are stored in:

- `.context/fixtures/tir/phase1a-model-examples.json`
