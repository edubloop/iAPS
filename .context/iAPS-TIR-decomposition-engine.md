# iAPS TIR Decomposition Engine — Feature Spec

## 1. The Problem
If your TIR is 87%, you have 13% out of range. That 13% is not one problem — it's a composite of distinct event types, each costing you a few percentage points. Some are addressable through settings changes, some through behavior changes, some are irreducible noise. Today there is no way to decompose that gap, rank it, or know where to focus.

## 2. Core Concept
The TIR Decomposition Engine continuously analyzes your BG, insulin delivery, carb entries, and settings state to:
1. Segment every out-of-range period into a classified event
2. Attribute each event to a pattern category based on observable data signatures
3. Quantify how many TIR percentage points each category costs you
4. Recommend the highest-impact, most actionable changes — settings or behavior

It does NOT auto-adjust anything. It reads data and produces insights.

## 2.1 Current Implementation Snapshot (dev-ci-hardening)

This spec is broader than current Phase 1A implementation. The following reflects what is currently shipped on `dev-ci-hardening`:

- Data source is user-selectable in **Settings > Extra Features > TIR Insights**:
  - `Nightscout` (default)
  - `HealthKit`
  - No auto/fallback mode.
- Simulator mode and scenario picker are available in the same TIR Insights config screen.
- Summary UI supports `7 / 14 / 30 / 90` day windows.
- Summary enforces a minimum-data readiness gate per selected window:
  - `7d` requires 7 full days
  - `14d` requires 14 full days
  - `30d` requires 30 full days
  - `90d` requires 90 full days
  - A "full day" is >=70% of expected 5-minute glucose points.
  - UI currently shows readiness/confidence indicator and day-progress; insights are still rendered.
  - Simulator mode bypasses this gate.
- Summary includes a visual TIR band breakdown:
  - Very Low, Low, In Range, High, Very High.
- Event presentation is grouped as:
  - **High Patterns**
  - **Low Patterns**
  - **Data Quality**
  - **Unclassified Outliers**
- Current label set in UI includes:
  - `Max Insulin Limit` (display label for constraint-limited highs)
  - `Falling Without Active Insulin` (low pattern)
  - `Unclassified Outliers` with split metrics (`High x% • Low y%`).
- Current recommendation pipeline:
  - Category patterns are aggregated via time-of-day buckets.
  - `TIRRecommendationEngine` emits recommendation rows for recurring patterns (current threshold: `>=3` events).
  - Summary surfaces these in `Patterns & Suggestions`.

All recommendations remain advisory-only; no automatic dosing/settings changes are performed.

## 3. Available Inputs (Strict)
The engine operates ONLY on data the algorithm already captures:

| Input | Source | Granularity |
|-------|--------|-------------|
| BG readings | CGM via iAPS | Every 5 min |
| Basal delivery | Pump via iAPS | Temp basal segments |
| SMB delivery | Algorithm decisions | Each SMB event with rationale |
| Manual boluses | User-initiated | Each bolus with timestamp |
| Carb entries | User-initiated | Grams + timestamp |
| Temp targets | User-set | Start/end + target value |
| IOB | Algorithm-calculated | Every loop cycle |
| COB | Algorithm-calculated | Every loop cycle |
| Settings state | iAPS config | Full settings snapshot |
| Settings changes | User-initiated | Before/after + timestamp |
| Loop status | Algorithm | Open/closed, last successful loop |
| Predictions | Algorithm | ZT, UAM, IOB, COB prediction lines |

Explicitly NOT available:
* Exercise tags
* Pod/site change timestamps (unless inferable from pump events)
* Stress, sleep, illness markers
* Meal composition (only total grams)
* Sensor change timestamps (unless inferable from data gaps)

## 4. Event Classification System

### 4.1 What is an "Event"?
An event is a contiguous period where BG is out of the user's target range. Each event has:

```
Event {
  id: string
  start: timestamp           // BG first exits target range
  end: timestamp             // BG returns to target range
  type: "high" | "low"
  peak_severity: number      // max BG (high) or min BG (low)
  duration_minutes: number
  tir_cost: number           // % of analysis period spent in this event
  category: EventCategory    // see 4.2
  contributing_factors: []   // see 4.3
  confidence: 0-1            // how confident is the attribution
}
```

Event boundaries: An event starts when BG crosses the upper (e.g., 180 mg/dL) or lower (e.g., 70 mg/dL) threshold and ends when BG returns to range for at least 15 minutes (to avoid splitting a single event by brief dips back into range).

### 4.2 Event Categories
Categories are defined by observable data signatures, not by assumed causes. The user interprets the cause; the system describes the pattern.

**HIGH Events (BG above upper target)**

| Category | Signature | Description |
|----------|-----------|-------------|
| `POST_MEAL_SPIKE` | High occurs within 0–3 hr of a carb entry | BG rose after eating. Subcategories below. |
| `POST_MEAL_SPIKE:LATE_BOLUS` | Carb entry preceded bolus by < 5 min or bolus came after carb entry | No pre-bolus window. |
| `POST_MEAL_SPIKE:UNDERBOLUS` | Delivered insulin (bolus + SMBs in 3hr window) was significantly less than what COB would require at current CR | Algorithm couldn't keep up — possible CR issue or carb undercount. |
| `POST_MEAL_SPIKE:DELAYED_RISE` | BG was in range for 1-2 hr post-meal, then rose | Suggests slow-absorbing meal (fat/protein) or delayed gastric emptying. |
| `RISING_WITHOUT_CARBS` | No carb entry within 4 hr before event start; BG rising | Something is driving BG up that isn't a logged meal. Could be: stress, dawn phenomenon, unlogged food, fading site, illness, etc. |
| `PERSISTENT_ELEVATION` | BG above range for > 3 hr continuously; SMBs being delivered but insufficient | Algorithm is trying but can't bring it down. Suggests insulin resistance or constraint hitting. |
| `REBOUND_HIGH` | High event that begins within 1 hr of a low event ending | Overtreatment of a low, or liver glucose dump post-hypo. |
| `POST_CONNECTIVITY_GAP` | High event begins within 30 min of a data gap > 10 min | BG may have been rising during the gap; algorithm couldn't act. Relates to Max Delta-BG Threshold suppressing SMBs. |
| `CONSTRAINT_LIMITED` | During the event, IOB was at or near Max IOB for > 50% of the duration | Algorithm wanted to deliver more insulin but was capped. |

**LOW Events (BG below lower target)**

| Category | Signature | Description |
|----------|-----------|-------------|
| `POST_BOLUS_DROP` | Low occurs within 1–4 hr of a manual bolus | Bolus was too large, or activity/sensitivity was higher than expected. |
| `STACKING_LOW` | Multiple boluses or SMBs in preceding 3 hr with cumulative IOB > 1.5x typical | Insulin stacked from overlapping deliveries. |
| `RAPID_UNEXPLAINED_DROP` | BG dropping > 3 mg/dL/min with no recent bolus increase | Fast drop without obvious insulin cause. User may recognize as exercise, but system just flags the pattern. |
| `OVERNIGHT_LOW` | Low occurring between 00:00–06:00 with no carb entry in preceding 4 hr | Basal may be too high, or residual IOB from dinner bolus. |
| `OVERCORRECTION_LOW` | Low follows a high event where aggressive SMBs were delivered | Algorithm corrected too hard. May indicate AF too high or Max SMB minutes too generous. |
| `GRADUAL_DRIFT_LOW` | BG drifts below range slowly (< 1 mg/dL/min) over > 60 min | Suggests basal slightly too high for current sensitivity. |

### 4.3 Contributing Factors
For each event, the engine identifies which settings or data conditions may have contributed:

```
ContributingFactor {
  factor: string             // e.g., "Max IOB ceiling reached"
  evidence: string           // e.g., "IOB was at 8.0U (Max IOB = 8.0) for 45 of 90 minutes"
  actionable: boolean        // can the user change something?
  suggestion: string | null  // what to consider changing
}
```

Examples of contributing factor checks per event:

For a `PERSISTENT_ELEVATION` event:
* Was IOB at or near Max IOB? → "Max IOB may be limiting correction"
* Were SMBs being suppressed by Max Delta-BG Threshold? → "SMBs paused due to rapid BG change after data gap"
* Was Max SMB Basal Minutes the binding constraint? → "Individual SMBs are small relative to needed correction"
* Did a settings change occur in the preceding 24hr? → "AF was changed from 0.8 to 0.7 yesterday — reduced aggressiveness may be contributing"
* Is TDD significantly different from 14-day average? → "Today's TDD is 30% below your 2-week average, suggesting reduced insulin sensitivity"

For a `RAPID_UNEXPLAINED_DROP`:
* What was IOB at drop onset? → "IOB was 4.2U when rapid drop began — high active insulin on board"
* Was a high temp target active? → "No temp target was set, so Dynamic ISF was active and may have amplified the drop"
* Recent carb entry timing? → "Last carb entry was 2.5 hr ago — late-stage insulin from that bolus may be peaking"

## 5. TIR Decomposition View

### 5.1 Summary Screen

```
┌─────────────────────────────────────────┐
│  YOUR TIR: 87%  (last 14 days)          │
│  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━     │
│                                         │
│  WHERE YOUR 13% OUT-OF-RANGE GOES:      │
│                                         │
│  ▓▓▓▓▓▓░░░░  Post-meal spikes    4.1%   │
│  ▓▓▓▓░░░░░░  Rising w/o carbs    3.2%   │
│  ▓▓▓░░░░░░░  Overcorrection lows 2.1%   │
│  ▓▓░░░░░░░░  Overnight lows      1.8%   │
│  ▓░░░░░░░░░  Rebound highs       1.0%   │
│  ░░░░░░░░░░  Other / noise        0.8%  │
│                                         │
│  TOP OPPORTUNITY:                       │
│  Post-meal spikes without pre-bolus     │
│  account for 2.8% of your out-of-range  │
│  time. [See details →]                  │
└─────────────────────────────────────────┘
```

### 5.2 Category Detail Screen
Tapping a category shows:

```
┌─────────────────────────────────────────┐
│  POST-MEAL SPIKES                       │
│  4.1% of your time — 23 events          │
│                                         │
│  BREAKDOWN:                             │
│  • 15 events: bolus < 5 min before carbs│
│    (2.8% TIR cost)                      │
│    → Pre-bolusing 10-15 min earlier     │
│      could reduce these significantly   │
│                                         │
│  • 5 events: carbs appear underestimated│
│    (0.8% TIR cost)                      │
│    → Avg delivered insulin was 40% more │
│      than initial bolus for these meals │
│                                         │
│  • 3 events: delayed rise pattern       │
│    (0.5% TIR cost)                      │
│    → BG in range for 1-2hr, then rose.  │
│      Slow-absorbing meals. Dynamic CR   │
│      is handling most of this already.  │
│                                         │
│  SETTINGS IN PLAY:                      │
│  • Recommended Bolus %: 80%             │
│    (delivering 80% upfront, 20% via     │
│     SMBs — appropriate for most meals)  │
│  • CR: 1:10 — no obvious mismatch       │
│  • AF: 0.8 — SMB follow-up is moderate  │
└─────────────────────────────────────────┘
```

### 5.3 Settings Risk Audit (Static Analysis)
Independent of outcome data, the engine can evaluate settings configuration for known risky combinations:

```
┌─────────────────────────────────────────┐
│  SETTINGS AUDIT                         │
│                                         │
│  ⚠ WATCH                               │
│  Your Max Delta-BG Threshold is 0.2     │
│  (default). With UAM enabled, 0.3 is    │
│  recommended to avoid SMB suppression   │
│  after CGM reconnection gaps.           │
│                                         │
│  ⚠ WATCH                               │
│  Autosens Max is 1.5 and AF is 1.1      │
│  with Sigmoid enabled. At BG 250+,      │
│  effective sensitivity multiplier can    │
│  reach ~1.65x. Combined with your Max   │
│  IOB of 8U, this leaves headroom but    │
│  verify this matches your intent.       │
│                                         │
│  ✓ OK                                   │
│  Max SMB Basal Minutes (30) with your   │
│  basal rate (1.2 U/hr) = max SMB of     │
│  0.6U. This is reasonable for your      │
│  typical correction needs.              │
│                                         │
│  ✓ OK                                   │
│  Threshold is set appropriately         │
│  relative to your target range.         │
└─────────────────────────────────────────┘
```

## 6. Recommendation Framework

### 6.1 Recommendation Types
Each recommendation is one of:

| Type | Description | Example |
|------|-------------|---------|
| `SETTINGS_CHANGE` | Adjust a specific iAPS setting | "Consider increasing Max IOB from 8 to 10" |
| `BEHAVIOR_CHANGE` | Change user behavior | "Pre-bolus 10-15 min before meals over 40g carbs" |
| `INVESTIGATION` | Something the system can't resolve — user needs to interpret | "Rising-without-carbs events cluster between 14:00-17:00 on weekdays. Do you recognize a pattern?" |
| `MONITORING` | No action yet, but watch this | "Overnight lows have increased from 1/week to 3/week over the past month. If this continues, consider reducing basal by 10% in the 00:00-06:00 window." |

### 6.2 Recommendation Structure

```
Recommendation {
  priority: 1-5            // 1 = highest impact
  type: RecommendationType
  title: string            // one-line summary
  detail: string           // full explanation with evidence
  tir_impact_estimate: number  // estimated TIR points recoverable
  confidence: 0-1          // how confident in attribution
  risk: "none" | "low" | "medium"  // risk of the suggested change
  affected_settings: []    // which settings are involved
  evidence_window: {       // time range of supporting data
    start: timestamp
    end: timestamp
    event_count: number
  }
  reversibility: string    // how to undo if it doesn't work
}
```

### 6.3 Prioritization Logic
Recommendations are ranked by:

```
priority_score = tir_impact_estimate × confidence × actionability_weight
```

Where `actionability_weight`:
* `SETTINGS_CHANGE` with single setting = 1.0
* `BEHAVIOR_CHANGE` = 0.8 (harder to execute consistently)
* `SETTINGS_CHANGE` with multiple interacting settings = 0.7 (more complex)
* `INVESTIGATION` = 0.5 (may not lead to action)
* `MONITORING` = 0.3 (future-oriented)

Risk acts as a modifier: medium risk halves the score, ensuring safe recommendations surface first.

### 6.4 Safety Constraints on Recommendations
The engine will NEVER recommend:
* Increasing Max IOB by more than 25% in a single recommendation
* Disabling any safety feature (Threshold, Max IOB, Max SMB limits)
* Changing more than 2 settings simultaneously
* Aggressive changes without at least 7 days of supporting data
* Changes that would increase time-below-range if current time-below is already > 4%

The engine will ALWAYS:
* Show the reversibility path ("if this doesn't help in 3 days, revert to X")
* Flag if a recommendation addresses a symptom vs. root cause
* Note when the system can't distinguish between competing explanations

## 7. Attribution Logic — Deep Dive

### 7.1 The Attribution Problem
A BG of 210 mg/dL at 3pm could be caused by:
1. Insufficient CR for lunch (settings)
2. Carbs underestimated by user (behavior)
3. Stress hormones (unobservable)
4. Fading pod site (unobservable, but partially inferable)
5. Unusually sedentary afternoon (unobservable)
6. All of the above in combination

The engine cannot determine the true cause. It can determine:
* The observable signature of the event
* Which settings were binding during the event
* Whether the pattern recurs across multiple events
* What changed relative to the user's baseline

### 7.2 Recurrence as Signal
A single `RISING_WITHOUT_CARBS` event tells you almost nothing — it could be anything. But if you have 12 `RISING_WITHOUT_CARBS` events over 14 days, and 9 of them occur between 05:00-08:00, that's dawn phenomenon and the recommendation is to look at basal rates in that window.

If `POST_MEAL_SPIKE:UNDERBOLUS` events are consistently associated with dinner but not lunch, the recommendation is to consider time-of-day CR ratios.

The engine's power comes from aggregating events within a category and looking for clustering by:
* Time of day
* Day of week
* Proximity to other events (e.g., lows always follow highs = overcorrection cycle)
* Proximity to settings changes
* TDD trend (rising TDD = increasing resistance)
* Days since last inferable pod change (if detectable via basal delivery pattern reset)

### 7.3 Inferring Unlogged Events
Some events that aren't explicitly logged can be inferred:

| Inferred Event | Signal |
|---------------|--------|
| Possible pod/site change | Basal delivery pattern resets (new pod priming bolus visible in data); TDD shifts; IOB resets if "Rewind Resets Autosens" is ON |
| Possible sensor change | Data gap of 1-2 hours (warmup period); BG reading characteristics change (noise profile, calibration offset) |
| Possible unlogged carbs | BG rising pattern consistent with meal absorption curve, but no carb entry; UAM detected by algorithm |
| Possible high activity | Rapid BG drop with low/declining IOB, no recent bolus explaining it; temp target set to exercise value (150+) |
| Possible illness/resistance | Multi-day TDD increase > 20% above 14-day average; persistent highs despite aggressive SMB delivery; Max IOB frequently reached |

These inferences carry lower confidence and are flagged as such.

### 7.4 Settings Change Impact Analysis
When the user changes a setting, the engine runs a before/after comparison:

```
Settings Change Impact {
  setting: "AF"
  old_value: 0.8
  new_value: 0.9
  change_date: timestamp

  before_period: {  // 7 days before change
    tir: 85%
    avg_bg: 142
    time_below: 2.1%
    events_high: 14
    events_low: 3
  }

  after_period: {  // 7 days after change
    tir: 88%
    avg_bg: 136
    time_below: 3.8%
    events_high: 9
    events_low: 7
  }

  assessment: "AF increase improved TIR by 3 points and reduced
    high events. However, time-below-range nearly doubled from
    2.1% to 3.8%, and low events increased from 3 to 7.
    The highs improved but at the cost of more lows.
    Consider keeping AF at 0.9 but raising Threshold by
    5-10 mg/dL to protect the low end."

  confounders_noted: [
    "TDD was 8% higher in the after-period, which independently
     affects Dynamic ISF. Some of the BG reduction may be from
     higher TDD rather than the AF change."
  ]
}
```

## 8. Data Architecture

### 8.1 Event Store
Every loop cycle (every 5 minutes), snapshot:

```json
{
  "timestamp": "2025-03-01T14:30:00Z",
  "bg": 165,
  "iob": 4.2,
  "cob": 28,
  "tdd_24hr": 42.5,
  "tdd_14day_avg": 38.2,
  "temp_basal_rate": 2.1,
  "smb_delivered": 0.3,
  "predictions": {
    "zt": [165, 158, 152],
    "iob": [165, 150, 138],
    "uam": [165, 172, 175],
    "cob": [165, 160, 148]
  },
  "constraints_active": {
    "max_iob_limited": false,
    "max_smb_limited": false,
    "delta_bg_threshold_limited": false,
    "threshold_suspended": false
  },
  "settings_hash": "abc123",
  "loop_status": "closed"
}
```

### 8.2 Settings Snapshots
On every settings change, store full settings state:

```json
{
  "hash": "abc123",
  "timestamp": "2025-02-28T10:00:00Z",
  "settings": {
    "af": 0.8,
    "dynamic_isf": true,
    "dynamic_cr": true,
    "sigmoid": true,
    "max_iob": 8.0,
    "max_smb_basal_minutes": 30,
    "max_uam_smb_basal_minutes": 30,
    "smb_delivery_ratio": 0.5,
    "max_delta_bg_threshold": 0.2,
    "threshold": 65,
    "weighted_avg_tdd": 0.65,
    "autosens_max": 1.5,
    "autosens_min": 0.7,
    "recommended_bolus_pct": 80,
    "insulin_type": "lyumjev",
    "basal_profile": [],
    "isf_profile": [],
    "cr_profile": []
  }
}
```

### 8.3 Event Detection Pipeline

```
Raw BG stream
  → Threshold crossing detector (enter/exit range)
  → Event boundary consolidation (15-min return-to-range rule)
  → Event classification (pattern matching against categories)
  → Contributing factor analysis (check constraints, settings, context)
  → Event storage

Periodic aggregation (daily + on-demand):
  → Group events by category
  → Calculate per-category TIR cost
  → Detect clustering (time-of-day, day-of-week, settings regime)
  → Generate/update recommendations
  → Rank by priority score
```

### 8.4 Storage Considerations
* Loop cycle snapshots: ~500 bytes × 288/day × 30 days = ~4.1 MB/month
* Event records: ~1-5 KB each × ~5-15/day = ~1-2 MB/month
* Settings snapshots: ~2 KB each × infrequent = negligible
* Total: ~6 MB/month — easily local storage on iPhone

## 9. Phase 1 Scope (MVP)

### 9.1 Event Detection + Classification
* Threshold crossing detection with boundary consolidation
* Classification into the categories defined in Section 4.2
* Start with HIGH events only (more common, lower safety risk in recommendations)

### 9.2 TIR Decomposition Summary
* The summary view from Section 5.1
* Per-category TIR cost calculation
* Configurable analysis window (7 / 14 / 30 days)

### 9.3 Basic Contributing Factor Analysis
* For each event: was Max IOB reached? Was SMB suppressed? Was there a recent data gap?
* No clustering analysis yet — just per-event annotation

### 9.4 Settings Audit (Static)
* The known-risk checks from Section 5.3
* No outcome data needed — pure settings analysis
* Encode the dependency map from Context File Section 13.9 as rules

### What to defer:
* LOW event classification and recommendations (Phase 2 — higher safety sensitivity)
* Clustering analysis (time-of-day, day-of-week patterns)
* Settings change impact analysis (before/after comparison)
* Inferred events (pod changes, sensor changes)
* Behavior change recommendations (start with settings-only)
* Recommendation confidence scoring
* Trend detection (gradual shifts over weeks)

## 10. Open Questions

1. **Where does this run?** Options: (a) within iAPS app as a new module, (b) as a companion app reading from shared HealthKit/Nightscout data, (c) as a Nightscout plugin. Each has different data access and build/distribution implications.

2. **Analysis window defaults.** 14 days seems right for most patterns, but dawn phenomenon might need 30 days and post-settings-change analysis needs exactly the period since the change. Should the user control this or should the system auto-select per category?

3. **Threshold definitions.** The spec uses 180/70 mg/dL as example thresholds. Should these match the user's iAPS target range, their personal targets, or standardized clinical thresholds? User's target range is probably right since that's what they're optimizing against.

4. **Notification strategy.** Should insights be push notifications, a badge on a tab, or purely on-demand? Given alarm fatigue concerns from the context file, probably on-demand with a subtle indicator when new insights are available.

5. **Interaction with existing Autotune.** If the engine recommends a basal change and Autotune is also adjusting basals, these could conflict. Need to define whether recommendations account for Autotune's pending adjustments.

6. **How opinionated should recommendations be?** "Consider increasing Max IOB" vs "Increase Max IOB from 8 to 10." The latter is more useful but carries more responsibility. Phase 1 could be directional only ("consider increasing") with specific values in Phase 2 once the system has proven its attribution accuracy.
