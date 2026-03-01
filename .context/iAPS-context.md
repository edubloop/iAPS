# iAPS Closed-Loop Insulin Delivery System — Product Context File
Purpose: Ground all feature development, UX decisions, and architecture choices in real-world user needs. This document captures how people actually live with DIY closed-loop insulin delivery — the daily rhythms, edge cases, emotional stakes, and failure modes that the app must handle.
Status: V1 — Refined via user interview Last updated: 2026-03-01 Primary user: Interviewed veteran closed-loop user (8 years experience), technical background
1. What iAPS Is
iAPS is an open-source iOS app that automates insulin delivery for people with Type 1 diabetes. It implements the OpenAPS algorithm (oref0) to close the loop between a continuous glucose monitor (CGM) and an insulin pump, adjusting insulin dosing every 5 minutes to keep blood glucose in a target range.
Lineage & Forks
* OpenAPS (2015) → ran on Raspberry Pi / Intel Edison, no phone UI
* Loop (iOS) → different algorithm, deterministic, requires carb entry
* AndroidAPS (Android) → OpenAPS algorithm on Android
* FreeAPS → fork of Loop with auto-bolus capability
* FreeAPS X → OpenAPS algorithm reimplemented on iOS by Ivan Valkou
* iAPS → fork of FreeAPS X with additional features (Dynamic ISF/IC)
* Trio → community fork of iAPS (post-v2.3.3 split over dev practices)
* Tidepool Loop → FDA-cleared (Jan 2023) version of Loop; not yet launched commercially
Core Algorithm Concepts
* Temporary Basal Rates: Adjusts background insulin delivery up or down
* Super Micro Boluses (SMB): Small automatic bolus doses to bring BG to target faster
* Unannounced Meals (UAM): Detects rising BG and doses insulin even without carb entry
* Dynamic ISF: Insulin Sensitivity Factor changes based on current BG (more insulin needed when BG is high)
* Dynamic IC (Carb Ratio): Insulin-to-carb ratio adjusts dynamically
* Autotune: Background process that analyzes historical data and recommends adjustments to basal rates, ISF, and ICR. When enabled, its calculated values replace your profile values as the baseline for autosens. Operates conservatively with strict divergence limits.
* Adjustment Factor (AF): The single most-tweaked parameter — controls aggressiveness of Dynamic ISF
1b. Interviewed User Specific Setup & Context
Hardware
* Pump: Omnipod DASH (Bluetooth LE, no bridge device needed)
* CGM: Dexcom G7 (latest generation, ~30 min warmup, no separate transmitter, smaller profile)
* Phone: iPhone (specific model TBD)
* Codebase: iAPS main branch (3.x) — building/modifying his own fork
Experience Level
* 8 years on closed-loop systems — veteran user, not learning the basics
* Fully running Dynamic ISF + Dynamic IC + Sigmoid function
* Overnight management is hands-off (trusts the algorithm)
* Mix approach to meals: announces big meals with bolus calculator, skips carb entry for small meals/snacks, lets UAM handle the tail
Who This Is For
* Primarily personal use, with intent to share with family/friends with T1D
* Not aiming for community-wide release, but the quality bar is "shareable"
Modification Scope
* Full stack: UI/UX + algorithm behavior + integrations (Watch, Nightscout, HealthKit)
* This is not a cosmetic reskin — it's a rethinking of how the app works
Priority-Ranked Development Goals
1. Smarter settings / AI-assisted tuning — the #1 priority (see Section 12)
2. Better data visualization & insights over time
3. Better Apple Watch as primary interaction surface
4. Simpler, cleaner UI with fewer screens
5. More reliable connectivity / fewer loop breaks (lowest priority — DASH + G7 is already solid)
Key Pain Points (From Interview)
* Settings confusion: Too many overlapping settings with unclear cross-effects. Hard to know which knob to turn and what side-effects it will have on other parameters.
* Autotune's behavioral bias: Autotune actually adjusts basal rates, ISF, and ICR (not just basal). However, in this user's experience it tends to ratchet basal upward without proportional reductions — creating a drift that requires manual correction. The docs confirm Autotune is "slow" and has "strict limits to prevent too much divergence from set settings," which may explain why it incrementally increases but rarely decreases. This is a real-world pattern, not a documented design intent.
* Apple Watch experience: Current Watch app is insufficient as a primary interaction surface; the user wants to be able to manage most daily interactions from the wrist.
Exercise Patterns
* Pilates: Strength-focused; initially raises BG (stress/cortisol response), then stabilizes
* Swimming: Causes BG to drop faster than typical cardio
* Core insight: Exercise alone is manageable. Exercise + active IOB from a recent meal bolus is the real challenge — the combination amplifies drops unpredictably. Easiest to exercise fasted or well after meal insulin has cleared.
Regularly Encountered Edge Cases
* Travel across time zones: Disrupts basal profiles, meal timing, sleep schedule
* Stress / adrenaline spikes: Work presentations, high-stakes situations cause BG to rise independent of food; algorithm may not respond fast enough
* Not a frequent issue: Alcohol, sick days, high-fat meals (these exist but aren't the primary design targets)
CGM Devices
Device Connection Notes Dexcom G5 Bluetooth LE Older, still supported Dexcom G6 Bluetooth LE Most common in DIY community Dexcom ONE / ONE+ Bluetooth LE Budget Dexcom variant, supported in iAPS 3.x Dexcom G7 Bluetooth LE Newer, smaller, no separate transmitter FreeStyle Libre 1 Via transmitter (e.g., MiaoMiao, Bubble) Requires third-party transmitter FreeStyle Libre 2 (European) / 2 Plus Bluetooth European versions only; direct BLE connection Medtronic Enlite Via RileyLink Legacy, supported but rarely used with iAPS Nightscout as CGM Network Can use Nightscout as a CGM data source
Insulin Pumps
Pump Connection Notes Omnipod DASH Bluetooth LE Most popular current choice Omnipod Eros RileyLink required Legacy but still used (cheaper/donated pods) DANA-i / DANA RS Bluetooth LE More common outside US. DANA RS firmware 3 only. Medtrum TouchCare Nano Bluetooth LE Tubeless patch pump, supported in iAPS 3.x Medtronic x15/x22/x23 RileyLink required Legacy pumps. x23 firmware 2.4 or lower only.
Bridge Devices (for older pumps)
* RileyLink, OrangeLink, EmaLink, DiaLink — Bluetooth-to-RF bridge
* Connectivity issues with these are a major pain point
Phone Requirements
* iPhone 8 or newer, running iOS 17+ (per iAPS 3.x requirements)
* Battery life is critical — the phone must maintain Bluetooth connections to pump + CGM all day
3. User Personas & Demographics
Primary User Segments
A. Tech-Savvy Adult (Self-managing)
* Age 20-50, Type 1 diagnosed in childhood/teens
* Comfortable building from source code via Xcode or GitHub Actions
* Motivated by superior glycemic control vs. commercial systems
* Likely active in Discord/Facebook communities
* May have tried Loop first and migrated for Dynamic ISF / UAM
B. Parent/Caregiver (Managing for a child)
* Child age 3-15 with T1D
* Nightscout remote monitoring is critical (watching from work/school)
* Remote bolus capability is a must-have
* Highly variable insulin needs (growth, unpredictable eating, sports)
* The "cognitive load" falls on the parent, not the child
C. Clinician-Guided User
* Endocrinologist or diabetes educator sets up the system
* User may not deeply understand the algorithm
* ~4,000+ starts done by high-volume clinicians
* Settings are configured once and rarely touched by the user
* Biggest challenge: "un-training" micromanagement habits
D. Experienced Looper Migrating
* Coming from Loop, AndroidAPS, or commercial HCL (Omnipod 5, Tandem Control-IQ)
* Frustrated with limitations: fixed ISF, mandatory carb counting, restrictive targets
* Needs to recalibrate expectations (different settings, different behavior)
* Migration path: settings don't transfer automatically
4. Daily Life Use Cases
4.1 Routine Day (The "Happy Path")
Morning Wake-Up
* Glance at phone: BG in range? Green loop icon? ✓
* CGM trend arrow flat or slightly rising
* Algorithm has been managing overnight basal automatically
* User action: None required
Breakfast (Announced Meal)
* Open app → Meal bolus calculator
* Enter estimated carbs (e.g., 45g)
* App shows "Recommended Bolus" (e.g., 80% of full dose per Recommended Bolus Percentage setting)
* User confirms bolus → pump delivers
* Algorithm handles the remaining ~20% via SMBs as BG rises
* Pre-bolus timing matters: Ideally bolus 10-20 min before eating
Mid-Morning (Algorithm Working)
* Loop runs every 5 minutes
* BG drifting slightly high → algorithm increases temp basal + delivers SMB
* BG trending toward target → algorithm reduces basal
* User action: None — occasional glance at phone/watch
Lunch (Partially Announced)
* Quick lunch, estimates carbs roughly, boluses
* If carb estimate is off, UAM detects the residual rise and delivers additional SMBs
* This is the key advantage over Loop: graceful handling of inaccurate carb counts
Afternoon Snack (Unannounced Meal)
* Eats an apple without entering anything in the app
* BG starts rising → UAM kicks in → SMBs delivered
* Results in a temporary spike but algorithm brings it back
* Many experienced users skip carb entry for small meals/snacks
Dinner (Full Announced Meal)
* Larger meal, more careful carb counting
* Uses the bolus calculator
* May use extended/dual wave approach for high-fat meals (e.g., pizza)
* Algorithm adjusts over the next 3-4 hours
Bedtime
* Check BG trending → should be heading toward target
* Algorithm manages overnight completely
* This is where closed-loop shines: preventing overnight lows and dawning highs
4.2 Exercise
Planned Exercise (e.g., gym session, run)
* Set a Temp Target (higher target, e.g., 140-160 mg/dL) 30-60 min before
* This triggers specific algorithm behavior depending on settings:
   * With "High Temptarget Raises Sensitivity" enabled: autosens assumes increased sensitivity → less insulin delivered
   * With "Exercise Mode" enabled: sets insulin delivery to zero during the high temp target
   * Important: Either setting temporarily disables Dynamic ISF, reverting to autosens. This is by design — Dynamic ISF's aggressiveness is counterproductive during exercise.
* Some users also reduce basal via profile percentage (e.g., 75%)
* Post-exercise: BG may drop for hours afterward (delayed effect)
* Pain point: Getting the timing right is hard; too little prep → hypo during exercise
Unplanned Activity (e.g., walking, yard work)
* No time to pre-set temp target
* BG starts dropping → algorithm reduces/suspends basal
* May still need fast-acting carbs (glucose tabs, juice)
* UAM helps on the other side: if BG rebounds after carb treatment
4.3 Sleep / Overnight
* Algorithm manages entirely
* Handles dawn phenomenon (early morning BG rise) via increased basal/SMBs
* Prevents overnight lows by reducing/suspending insulin
* Remote monitoring via Nightscout: Parents can watch a child's BG remotely
* Remote bolus capability via Nightscout announcements
* Alarms for extreme highs/lows can be configured
4.4 High-Fat / High-Protein Meals
* Pizza, pasta, fried food → delayed BG rise (2-4 hours post-meal)
* Standard bolus handles initial carbs; extended/delayed rise is harder
* Dynamic ISF helps: as BG rises later, algorithm responds more aggressively
* Some users split bolus manually or use the meal calculator + let UAM handle the tail
4.5 Alcohol Consumption
* Alcohol suppresses liver glucose production → increased hypo risk
* May need to raise temp target or reduce profile percentage
* Algorithm will try to reduce insulin, but delayed effects are tricky
* High-risk scenario: Impaired judgment + suppressed glucose + delayed meals
4.6 Illness / Sick Days
* Stress hormones cause insulin resistance → BG runs high
* May need to increase Adjustment Factor temporarily
* Risk of DKA if insulin delivery is insufficient
* Must monitor ketones (finger-stick blood ketone meter)
* Vomiting/nausea: Can't eat but still need insulin → complex management
* Fallback: If pump/CGM fails during illness, revert to manual pen injections
* Sick day guidance: Check BG every 1-2 hours, check ketones, stay hydrated
4.7 Travel / Time Zone Changes
* Crossing time zones disrupts basal profiles (time-of-day dependent)
* Need to update phone clock → basal schedule shifts
* Airport security: May need to explain pump/CGM devices
* Carrying supplies: Extra pods, sensors, insulin, backup pen
* CGM connectivity: International phone settings can disrupt Bluetooth
4.8 Site Changes (Pump & CGM)
* Pump site (infusion set / pod change): Every 2-3 days
   * New site absorption varies → BG may be unstable for first few hours
   * Schedule changes to avoid overlapping with meals
   * Occlusion alarms if site is bad
* CGM sensor change: Every 10-14 days (Dexcom G6: 10 days, G7: 10 days, Libre: 14 days)
   * New sensor warmup period (G7: ~30 min, G6: 2 hours, Libre: 1 hour) → no CGM data → loop stops entirely and reverts to scheduled basal
   * G7 overlap trick: The G7 warmup begins when the release mechanism physically inserts the filament, not when you activate in the app. Apply the new sensor ~45 min before the old one expires, let the warmup happen passively while still receiving data from the old sensor, then activate the new sensor in the app once 30+ min have passed. This creates virtually zero data gap and keeps the loop running continuously.
   * Some users of other CGMs overlap sensors similarly to minimize gaps
   * Inaccurate readings early in sensor life → algorithm may make wrong decisions
4.9 Intimacy / Wearing Devices
* Pump tubing (if tubed pump) gets in the way
* Pod placement matters for comfort and clothing
* Some users disconnect briefly (tubed pumps) — algorithm handles the gap
* Emotional dimension: Visibility of devices affects body image and self-consciousness
5. Edge Cases & Failure Modes
5.1 Connectivity Loss
* CGM → Phone: Bluetooth drops → no glucose data → loop stops → current temp basal expires (max 30 min) → reverts to scheduled basal profile
* Phone → Pump: Bluetooth drops → can't adjust insulin → alarm. Pump continues delivering whatever temp basal was last set until it expires.
* Loop status indicators: Green = looping normally. Yellow = no loop cycle completed for >5 min. Red = no loop for >10 min.
* Cause: Distance between devices, electromagnetic interference, phone restart, battery death
* Frequency: Eros pods + RileyLink are worst; DASH pods are more reliable
* Impact: Minutes without looping are generally fine; hours become dangerous (especially post-meal when SMBs are needed)
* This is the #1 frustration cited by users
5.2 CGM Inaccuracy
* Compression lows: Lying on sensor → falsely low reading → algorithm suspends insulin → actual BG rises
* First-day sensor inaccuracy → algorithm over/under-doses
* Calibration issues (Libre requires transmitter-dependent calibration)
* Sensor failure mid-use → sudden loss of data
5.3 Pump Failures
* Pod occlusion → insulin not delivered → BG skyrockets
* Pod falls off (sweat, movement, adhesive failure)
* Insulin spoilage (heat exposure) → reduced potency
* Reservoir empty alarm → need to change immediately
* Critical: When pump failure is discovered, immediately turn off closed loop. iAPS may believe more IOB was delivered than actually was (phantom IOB), causing it to under-deliver insulin once a new pump is connected. Wait for calculated IOB to drop before re-enabling closed loop.
* "Rewind Resets Autosens" (recommended ON for OmniPod) resets sensitivity data on pod change, since absorption characteristics differ by site
5.4 Algorithm Misbehavior
* Stacking: Too many SMBs in quick succession → hypo
* Over-aggressive Dynamic ISF settings → dangerous lows
* Under-aggressive settings → persistent highs
* Prediction lines are unreliable for first 24 hours of use
* "Wrong insulin type" selected → incorrect insulin curve → bad dosing
* CGM data gap overreaction: When Bluetooth drops for 15-20 minutes (common), iAPS sees a sudden jump (e.g., 98 → 135 mg/dL) instead of the gradual rise that actually occurred. The algorithm interprets this as a rapid spike and may recommend an excessively large correction bolus — even with IOB already on board. The Dexcom Follow app can backfill missing glucose readings to reconstruct a smooth curve, but iAPS currently cannot. This means the bolus calculator and SMB logic are operating on misleading delta-BG data after any connectivity gap. This is both a UX problem (user sees a scary jump and overreacts) and an algorithm problem (SMB/correction math uses inflated rate-of-change).
5.5 Phone-Related Issues
* Battery death → loop stops → no data → no alarms
* iOS update breaks app (DIY builds need rebuilding after iOS updates)
* App crash / background termination
* App certificate expiration (7-day free Xcode profile, 90-day TestFlight via GitHub Actions, or 365-day paid direct install)
* Phone storage full → app can't log data
5.6 Human Error
* Bolusing wrong amount (app shows recommended, user changes it)
* Duplicate remote bolus (Nightscout latency → parent sends bolus twice)
* Forgetting to re-enable closed loop after manual override
* Not carrying backup supplies (pen, glucose tabs)
* Misidentifying carb count dramatically
6. Emotional & Psychological Dimensions
Decision Fatigue
* Diabetes requires hundreds of micro-decisions daily
* Closed-loop reduces this significantly but doesn't eliminate it
* The remaining decisions (meals, exercise, site changes) still carry cognitive load
* Key value prop: "I don't think about my diabetes much at all"
Trust in the Algorithm
* Initial phase: Anxiety about letting software control insulin
* Intermediate: Learning to stop micromanaging (hard for experienced T1Ds)
* Advanced: "Set and forget" confidence — the system becomes invisible
* Un-training micromanagement is one of the biggest challenges
Alarm Fatigue
* Too many alerts → users start ignoring them
* Repeated connectivity alarms at night disrupt sleep
* Balancing safety (must alert for genuine lows) vs. noise
Body Image & Visibility
* Wearing multiple devices (pump, CGM, possibly bridge device)
* Visible tubing, pods on skin, CGM sensor
* Young people especially sensitive to peer perception
* Design implication: Discreet interaction (Apple Watch bolusing) is highly valued
Burnout
* Diabetes is 24/7/365 — there is no vacation
* Even with automation, supplies management, insurance battles, and site changes persist
* "Downtime" between sensor sessions or during failures feels like regression
* Community support (Discord, Facebook groups) is a crucial emotional lifeline
7. Key Settings & Configuration Mental Model
Initial Setup (Done once, with clinician or community guidance)
* Basal rate profile (time-of-day insulin rates)
* Insulin Sensitivity Factor (ISF) — how much 1 unit drops BG
* Carb Ratio (CR) — how many grams of carbs 1 unit covers
* Target glucose range
* Insulin type (determines activity curve: Humalog, Novorapid, Fiasp, Lyumjev, etc.)
* Max IOB (safety cap on insulin-on-board)
* Max SMB settings (size limits for automatic boluses)
* Recommended Bolus Percentage (default: 80%)
Dynamic Features (Enabled progressively)
1. Closed Loop → algorithm adjusts basal
2. SMB + UAM → algorithm can auto-bolus
3. Dynamic ISF → sensitivity varies with BG level
4. Dynamic IC → carb ratio varies with BG level
5. Sigmoid function → alternative to logarithmic Dynamic ISF curve
The Single Ongoing Adjustment
* Adjustment Factor (AF) — the only parameter most users tweak after initial setup
* Controls how aggressively Dynamic ISF and Dynamic CR scale
* Higher AF = more aggressive across all BG levels (not just high BG). The logarithmic formula means the absolute insulin increase is larger at higher BG, but the entire curve shifts.
* AF is not a safety limiter — it biases all dynamic calculations simultaneously
* BCDiabetes protocol: Set safeties in first 24 hours, then only AF changes
Safety Guardrails
* Max IOB
* Max SMB Basal Minutes
* Max Delta-BG Threshold for SMB
* SMB delivery ratio
* Bolus increment (0.05U for OmniPod)
8. Data & Monitoring Ecosystem
In-App Data
* Real-time BG graph with prediction lines (ZT, UAM, IOB, COB curves)
* IOB (Insulin on Board)
* COB (Carbs on Board)
* Temp basal / SMB history
* Loop status icon (green = looping, yellow = warning, red = not looping)
Nightscout (Remote Monitoring)
* Web-based dashboard showing BG, insulin, carbs, predictions
* Remote caregivers can monitor in real-time
* Remote commands: bolus, suspend pump, temp basal, resume looping
* 10-minute minimum between remote commands (safety feature)
* Critical for parents of children with T1D
Reporting & Review
* Tidepool: Upload BG/insulin/carb data for endo review
* Apple Health: Sync BG and insulin data
* Autotune recommendations visible in settings
* AGP (Ambulatory Glucose Profile) reports for clinic visits
Key Metrics (Standard Targets)
Metric Target Gold Standard Time in Range (70-180 mg/dL) >70% >80-90% achievable with iAPS Time Below Range (<70) <4% <1% achievable Time Below 54 <1% <0.5% HbA1c <7% <6.5% for some iAPS users Coefficient of Variation <36% Lower = more stable
9. Build & Distribution Model
How Users Get the App
* Not on the App Store — must be self-built
* Build via Xcode on Mac (Mac-Xcode Build): Requires signing with Apple Developer certificate. Free account = 7-day provisioning profile (must rebuild weekly). Paid ($99/yr) = 365-day profile.
* Build via GitHub Actions (Browser Build — no Mac required): Uses TestFlight distribution. App must be updated every 90 days. Setup is involved but subsequent builds are trivial — a single click from anywhere.
* TestFlight builds can be easily shared with family members (requires Apple ID age 13+)
* Must rebuild when iOS updates break compatibility or certificate expires
Implications for Development
* Users are a mix of technical (can read code) and non-technical (followed a tutorial)
* Community documentation is the primary onboarding mechanism
* Breaking changes have real clinical consequences
* Test coverage and stability are life-critical, not just nice-to-have
10. Competitive & Regulatory Landscape
Commercial Alternatives
System Algorithm Meal Bolus Required? Customizability Omnipod 5 Proprietary Yes (hybrid) Low — limited targets Tandem Control-IQ Proprietary Yes (hybrid) Low — fixed targets Medtronic 780G Proprietary Yes (hybrid) Medium — adjustable target CamAPS FX MPC-based Yes (hybrid) Medium — aggressiveness slider iLet Bionic Pancreas Proprietary No (fully closed) Very low — weight-only input
Why Users Choose DIY Over Commercial
* Adjustable targets: Commercial systems have restrictive glucose targets
* Dynamic ISF/IC: Not available in any commercial system
* UAM / unannounced meals: Commercial systems require carb entry
* Interoperability: Choose your own pump + CGM combo
* Community-driven innovation: Features ship faster than commercial FDA cycles
* Control: Advanced users want to tune aggressiveness
Regulatory Status
* iAPS / Trio: No regulatory approval anywhere; used at user's own risk
* Tidepool Loop: FDA-cleared (Jan 2023) but not commercially launched (no ACE pump partner)
* AndroidAPS: Used in the CREATE clinical trial (NEJM published results); CE mark pathway being explored
* #WeAreNotWaiting ethos: Users accept risk in exchange for superior control
11. North Star Vision: System-Wide Adaptive Tuning
"Autotune's concept is right — learn from data and adjust settings — but it only touches basal rates and it doesn't work well. What if that concept could be applied across the entire app?"
The Problem
iAPS has dozens of interrelated settings (basal rates, ISF, CR, AF, Max IOB, SMB limits, Dynamic ISF/IC toggles, Sigmoid parameters, bolus percentage, etc.). These settings have cross-effects that are poorly documented and hard to reason about. Changing one parameter often has unexpected downstream consequences on another.
Current Autotune only adjusts basal rates based on ~2 weeks of historical data, and it exhibits an upward-only ratchet — it increases basal but rarely decreases it, requiring manual resets.
The Vision
A system-wide learning loop that:
* Ingests the full data picture: BG readings, insulin delivery (basal + bolus + SMB), carb entries, exercise events, time of day, sensor accuracy, IOB curves
* Identifies confounders: "Your post-lunch spike wasn't a carb ratio problem — you had active stress hormones from your 2pm meeting"
* Recommends (or auto-applies with user approval) adjustments across all settings, not just basal
* Explains why a change is being suggested, not just what
* Can reduce settings as well as increase them (bidirectional tuning)
* Learns user-specific patterns over time (the user's Pilates pattern, travel adaptation, etc.)
Why This Is Hard
* Confounders are numerous: stress, exercise type/timing, meal composition, hydration, sleep quality, sensor accuracy, site absorption variability
* Attribution is ambiguous: A post-meal spike could be caused by carb undercount, delayed absorption, stress, or a fading pump site
* Safety constraints: Auto-adjusting insulin delivery settings has life-critical safety implications; aggressive changes could cause dangerous lows
* Data sparsity: Some patterns only emerge over weeks; others are one-off events
* The current OpenAPS algorithm (oref0) is JavaScript running locally — compute and model complexity are constrained
Design Principles for This Feature
1. Transparency over magic: Always show the reasoning, never silently change a setting
2. Bidirectional: Must be willing to recommend less insulin, not just more
3. Confounder-aware: Distinguish between "your ISF is wrong" and "you were stressed today"
4. Progressive autonomy: Start with recommendations → graduate to auto-apply with guard rails
5. Scoped learning windows: Different settings need different lookback periods (basal = 2 weeks, meal response = per-meal, exercise = per-activity-type)
12. Development Principles for This Fork
Based on the interviewed user profile (8-year veteran, full-stack developer, sharing with family/friends):
1. Don't dumb it down, make it legible: The audience knows diabetes. The problem isn't too many features — it's unclear relationships between features.
2. Watch-first for daily ops, Phone for tuning: Daily interactions (glance at BG, confirm a bolus, set a temp target) should be achievable from Apple Watch. Deep settings, data review, and tuning stay on the phone.
3. Insights over data dumps: Raw prediction lines and IOB/COB numbers are necessary but insufficient. The app should surface interpretive insights: "You tend to spike after lunch on days you skip pre-bolus" or "Your AF may be too aggressive — you had 3 lows this week that followed SMB clusters."
4. Safety is non-negotiable but shouldn't be noisy: Guard rails must exist but shouldn't create alarm fatigue. Distinguish between "informational" (sensor warmup) and "actionable" (genuine low predicted) notifications.
5. Settings should have dependency maps: When a user changes AF, the app should show what other parameters are affected and in what direction. No setting should feel like it exists in isolation.
13. iAPS Advanced Settings Reference
Source: iAPS documentation (bcdiabetes.github.io/freeapsdocs + iaps.readthedocs.io via GitHub source) This section maps every Advanced Settings group, its key parameters, formulas, cross-effects, and defaults.
13.1 Autosens, Dynamic ISF/ICR & Adjust Basal (Concepts)
Autosens reviews the last 8 hours and 24 hours of data every loop cycle (5 min). It calculates an `autosens.ratio` representing how sensitive/resistant the user is compared to their profile, then makes conservative temporary adjustments to basal rates, BG target, and ISF. It always picks the more conservative of the 8hr vs 24hr calculation (to avoid over-dosing). Autosens does NOT adjust ICR.
If Autotune is enabled, autosens uses Autotune-calculated ICR/ISF/basal as its baseline instead of profile values.
Dynamic ISF replaces autosens's ISF formula with a more aggressive one. Core formula (logarithmic, default):

```
autosens.ratio = profile.sens * AF * TDD * log((BG/peak) + 1) / 1800
New ISF = profile ISF / autosens.ratio

```

Variables: `profile.sens` (profile ISF in mg/dL), `AF` (Adjustment Factor), `TDD` (weighted average of total daily dose), `BG` (current blood glucose in mg/dL), `peak` (insulin peak activity parameter, typically 120 min for standard rapid-acting insulin).
Key cross-effects of Dynamic ISF:
* AF scales the entire curve — higher AF = more insulin at every BG level
* TDD is a major input — a day with more insulin → more aggressive ISF tomorrow
* Temporarily disabled when High Temp Target + "High Temptarget Raises Sensitivity" is enabled
* Limited by `autosens max` and `autosens min` safety bounds
Dynamic CR uses the same formula to also adjust carb ratio:

```
autosens.ratio = profile.sens * AF * TDD * log((BG/peak) + 1) / 1800
New CR = profile CR / autosens.ratio

```

Safety dampener: When `autosens.ratio > 1`, it's made less aggressive: `new.ratio = (ratio - 1)/2 + 1`
Adjust Basal replaces autosens's basal adjustment with a TDD-dependent formula:

```
autosens.ratio = Weighted Average TDD / 14-day average TDD
New Basal = profile basal * autosens.ratio

```

13.2 Sigmoid Function (Concept)
Replaces the logarithmic function for Dynamic ISF/CR calculations. Key differences:
* Logarithmic: Curve rises steeply at low BG, flattens at high BG → more aggressive at low-to-mid range
* Sigmoid: S-shaped curve bounded by autosens min/max → more predictable at extremes, steepness controlled by AF
* With Sigmoid, AF controls the steepness of the curve (how fast sensitivity changes between readings)
* Autosens Max/Min influence both the curve limits AND its steepness when using Sigmoid
* TDD has less impact on adjustments with Sigmoid (more BG-dependent)
* Recommended starting AF for Sigmoid: 0.4-0.5 (lower than logarithmic's 0.5-0.8)
* Desmos graphs available for both formulas to visualize before changing settings
13.3 Dynamic Settings (Preferences)
Setting Default Range Effect Enable Dynamic ISF Off Toggle Replaces autosens ISF calculation Enable Dynamic CR Off Toggle Adds dynamic carb ratio adjustment Adjustment Factor (AF) 0.8 0.1-2.0+ Scales aggressiveness of Dynamic ISF/CR. NOT a safety limiter. Use Sigmoid Function Off Toggle Replaces log with sigmoid for Dynamic ISF/CR Adjust Basal Off Toggle TDD-based basal adjustment instead of autosens Weighted Average of TDD 0.65 0-1 0.65 = 65% last 24hr + 35% last 14 days. Higher = more reactive to recent data. Threshold Derived from target mg/dL Safety floor: suspends all insulin delivery (SMBs halted, 0 U/hr temp basal) when any prediction goes below this. Cannot be set lower than default for your target.
Cross-effect map for AF:
* AF ↑ → Dynamic ISF more aggressive → lower ISF → more correction insulin
* AF ↑ → Dynamic CR more aggressive → lower CR → larger meal boluses
* AF ↑ → Sigmoid curve steeper → faster transitions between sensitivity levels
* AF affects ALL dynamic calculations simultaneously — cannot tune ISF aggression independently of CR aggression
13.4 FreeAPS X Settings
Setting Default Effect Recommended Bolus Percentage 80% Fraction of calculated meal bolus delivered upfront. Remaining handled by SMBs. Glucose Units mmol/L Toggle between mmol/L and mg/dL Remote Control Off Enable Nightscout remote commands (bolus, suspend, temp basal) Recommended Insulin Fraction — Increase to reduce initial post-meal spiking (risk of lows if carbs miscounted or ICR too aggressive)
13.5 OpenAPS Main Settings
Key parameters include:
* Insulin Type: Determines the insulin activity curve. The Dynamic ISF formula uses a `peak` parameter (default ~120 min for standard rapid-acting insulin like Humalog/Novorapid). The insulin divisor varies: Lyumjev=75, Fiasp=65, standard rapid=55. Wrong selection = wrong IOB calculation = wrong dosing decisions across the entire system.
* Max IOB: Maximum insulin on board above basal. Primary safety limiter. Set too low = algorithm can't correct highs. Set too high = risk of dangerous lows.
* Max Daily Safety Multiplier: Limits basal to X times the max daily scheduled basal rate.
* Current Basal Safety Multiplier: Limits basal to X times the current scheduled basal rate.
* Autosens Max / Min: Bounds on how much autosens/Dynamic ISF can adjust sensitivity. Wider range = more freedom for dynamic adjustment, but also more risk of over/under-dosing. With Sigmoid enabled, these also affect the curve's steepness.
13.6 OpenAPS Other Settings
Includes:
* Rewind Resets Autosens: Reset autosens data on pump site change (recommended ON for OmniPod)
* Use Custom Peak Time: Override default insulin peak time
* Suspend Zeros IOB: Whether pump suspension zeros out IOB calculation
* Bolus Snooze DIA Divisor: How long after a bolus before auto-corrections resume
* Remaining Carbs Fraction / Cap: How iAPS estimates remaining carbs on board
13.7 iAPS SMB Settings
SMB decision precedence (in order):
1. Disable SMB when high temp target is set (unless "Allow SMB With High Temptarget" enabled)
2. Enable SMB/UAM if "Always On" (unless disabled by high temp target)
3. Enable SMB/UAM while COB exists
4. Enable SMB/UAM for 6 hours after any carb entry
5. Enable SMB/UAM if low temp target is set
Setting Default Effect Enable SMB Always Off Most common ON setting; allows correction boluses at all times Max Delta-BG Threshold SMB 0.2 Safety check: if BG change between readings is too large, SMBs suspended. 0.3 recommended for closed loop with UAM. Enable UAM Off Detect and dose for unannounced meals (rising BG without carb entry) Max SMB Basal Minutes 30 Limits SMB size to X minutes of basal rate. Increase if struggling with fasting highs. Max UAM SMB Basal Minutes 30 Limits UAM SMB size. Increase if struggling with meal/hormonal highs. SMB Delivery Ratio 0.5 iAPS delivers this fraction of required insulin as SMB. Default = half. SMB Interval 3 Minutes between SMB deliveries
Cross-effect note: Max Delta-BG Threshold directly relates to the CGM data gap problem (Section 5.4). After a connectivity gap, the apparent delta-BG can exceed this threshold, causing SMBs to be incorrectly suspended even though BG is actually rising steadily.
13.8 OpenAPS Targets Settings
* High Temptarget Raises Sensitivity: When a high temp target is set, autosens assumes increased sensitivity → less insulin. Useful for exercise.
* Low Temptarget Lowers Sensitivity: When a low temp target is set, autosens assumes decreased sensitivity → more insulin. Useful for pre-meal.
* Sensitivity Raises Target: If autosens detects increased sensitivity, raise BG target to reduce hypo risk.
* Resistance Lowers Target: If autosens detects increased resistance, lower BG target to be more aggressive.
* Exercise Mode: Alternative to "High Temptarget Raises Sensitivity". Sets insulin delivery to zero when a high temp target is active.
13.9 Settings Cross-Effect Summary
This is the "dependency map" that doesn't exist in the current app but should:

```
AF ──────────┬──→ Dynamic ISF (more/less aggressive ISF)
             ├──→ Dynamic CR (more/less aggressive carb ratio)
             └──→ Sigmoid steepness (if enabled)

TDD (24hr) ──┬──→ Dynamic ISF formula
             ├──→ Dynamic CR formula
             ├──→ Adjust Basal formula (via Weighted Avg)
             └──→ Autotune recommendations

Weighted Avg TDD ──→ Adjust Basal only (how reactive to recent vs historical)

Autosens Max/Min ──┬──→ Bounds on ALL autosens.ratio calculations
                   └──→ Sigmoid curve limits AND steepness

Autotune ──→ Replaces profile ISF/ICR/Basal as baseline for autosens
             (when enabled, autosens adjusts FROM Autotune values, not profile)

Max IOB ──┬──→ Caps total automatic insulin delivery
          └──→ Limits effective SMB + temp basal combined

Max SMB Basal Minutes ──→ Caps individual SMB size
Max UAM SMB Basal Minutes ──→ Caps UAM-triggered SMB size
SMB Delivery Ratio ──→ Fraction of needed insulin given per cycle

High Temp Target ──┬──→ DISABLES Dynamic ISF (reverts to autosens)
                   ├──→ Disables SMBs (unless "Allow SMB With High Temptarget")
                   └──→ Raises sensitivity (if "High Temptarget Raises Sensitivity" on)

Threshold ──→ Emergency brake: suspends ALL delivery when predicted BG < threshold

Insulin Type ──→ Peak parameter ──→ Dynamic ISF formula + IOB curve ──→ ALL dosing

```

14. Glossary of Key Terms
Term Meaning AF Adjustment Factor — controls aggressiveness of Dynamic ISF BG Blood Glucose CGM Continuous Glucose Monitor COB Carbs on Board — estimated active carbohydrates CR / ICR Carb Ratio / Insulin-to-Carb Ratio DIA Duration of Insulin Action Dynamic IC Carb ratio that varies with current BG level Dynamic ISF Insulin Sensitivity Factor that varies with current BG level HCL Hybrid Closed Loop IOB Insulin on Board — estimated active insulin ISF Insulin Sensitivity Factor — how much 1 unit drops BG Max IOB Safety cap on total insulin on board oref0 OpenAPS reference algorithm (JavaScript) Sigmoid Alternative curve function for Dynamic ISF (vs. logarithmic) SMB Super Micro Bolus — small automatic bolus doses TDD Total Daily Dose — all insulin (basal + bolus) for one day TIR Time in Range (70-180 mg/dL) UAM Unannounced Meals — algorithm detects rising BG without carb entry
