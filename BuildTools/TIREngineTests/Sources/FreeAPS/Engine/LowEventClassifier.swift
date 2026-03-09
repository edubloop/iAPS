import Foundation

/// Classifies a single low-glucose segment into a TIREventCategory using a strict
/// priority order. Pure static functions — no state, no DI.
///
/// Priority order (first match wins):
///   1. COMPRESSION_LOW
///   2. OVERCORRECTION_LOW
///   3. STACKING_LOW
///   4. ACTIVITY_RELATED_LOW
///   5. REBOUND_LOW
///   6. BASAL_TOO_AGGRESSIVE
///   7. FALLING_WITHOUT_ACTIVE_INSULIN
///   8. PERSISTENT_LOW
///   9. UNCLASSIFIED_LOW  (catch-all)
enum LowEventClassifier {
    // MARK: - Constants

    // Compression Low
    static let compressionMaxDurationMinutes = 30
    static let compressionMinRecoveryRatePerFiveMin: Double = 2.0 // mg/dL per 5-min interval
    static let compressionMinNadir = 54
    static let compressionBolusThreshold: Double = 0.5 // units
    static let compressionBolusLookbackSeconds: TimeInterval = 2 * 3600

    // Overcorrection Low
    static let overcorrectionLookbackMinSeconds: TimeInterval = 1 * 3600
    static let overcorrectionLookbackMaxSeconds: TimeInterval = 4 * 3600
    static let overcorrectionMinBolus: Double = 1.0 // units
    static let overcorrectionMaxBolusEvents = 2

    // Stacking Low
    static let stackingSMBCountThreshold = 3
    static let stackingSMBWindowSeconds: TimeInterval = 60 * 60
    static let stackingBolusCountThreshold = 2
    static let stackingBolusWindowSeconds: TimeInterval = 90 * 60

    // Activity Related
    static let activityLookbackSeconds: TimeInterval = 4 * 3600

    // Rebound Low
    static let reboundLookbackSeconds: TimeInterval = 90 * 60

    // Basal Too Aggressive
    static let basalNoBolusWindowSeconds: TimeInterval = 3 * 3600
    static let basalNoCarbWindowSeconds: TimeInterval = 3 * 3600
    static let basalMaxBolusThreshold: Double = 0.5 // units

    // Falling Without Active Insulin (existing thresholds preserved)
    static let fallingNoInsulinWindowSeconds: TimeInterval = 75 * 60
    static let fallingNoCarbWindowSeconds: TimeInterval = 2 * 3600
    static let fallingMinNadir = 54

    // Persistent Low
    static let persistentMinDurationSeconds: TimeInterval = 45 * 60

    // MARK: - Public API

    /// Returns (category, confidence, factors) for a single low segment.
    static func classify(
        context: LowEventContext
    ) -> (category: TIREventCategory, confidence: TIREventConfidence, factors: [TIRContributingFactor]) {
        // Priority 1 — COMPRESSION_LOW
        if let result = checkCompressionLow(context: context) { return result }

        // Priority 2 — OVERCORRECTION_LOW
        if let result = checkOvercorrectionLow(context: context) { return result }

        // Priority 3 — STACKING_LOW
        if let result = checkStackingLow(context: context) { return result }

        // Priority 4 — ACTIVITY_RELATED_LOW
        if let result = checkActivityRelated(context: context) { return result }

        // Priority 5 — REBOUND_LOW
        if let result = checkReboundLow(context: context) { return result }

        // Priority 6 — BASAL_TOO_AGGRESSIVE
        if let result = checkBasalTooAggressive(context: context) { return result }

        // Priority 7 — FALLING_WITHOUT_ACTIVE_INSULIN
        if let result = checkFallingWithoutActiveInsulin(context: context) { return result }

        // Priority 8 — PERSISTENT_LOW
        if let result = checkPersistentLow(context: context) { return result }

        // Priority 9 — catch-all
        return (.unclassifiedLow, .medium, [])
    }

    // MARK: - Feature Extraction

    /// Extract numerical feature vector for clustering analysis.
    static func extractFeatures(context: LowEventContext, category: TIREventCategory) -> LowEventFeatures {
        let durationMinutes = Int(context.segmentEnd.timeIntervalSince(context.segmentStart) / 60)
        let rateOfFall = computeRateOfFall(context: context)
        let rateOfRecovery = computeRateOfRecovery(context: context)

        let smbCutoff = context.segmentStart.addingTimeInterval(-stackingSMBWindowSeconds)
        let smbCount1h = context.smbsInWindow.filter { $0.timestamp >= smbCutoff }.count

        let carbCutoff = context.segmentStart.addingTimeInterval(-2 * 3600)
        let carbsConsumed2h: Double
        if let carbs = context.carbEntries {
            carbsConsumed2h = carbs
                .filter {
                    ($0.actualDate ?? $0.createdAt) >= carbCutoff && ($0.actualDate ?? $0.createdAt) <= context.segmentStart }
                .filter { !($0.isFPU ?? false) && $0.carbs > 0 }
                .reduce(0.0) { $0 + NSDecimalNumber(decimal: $1.carbs).doubleValue }
        } else {
            carbsConsumed2h = 0
        }

        let totalBolus4h = totalBolusInWindow(
            boluses: context.bolusesInWindow, smbs: context.smbsInWindow,
            from: context.segmentStart.addingTimeInterval(-overcorrectionLookbackMaxSeconds),
            to: context.segmentStart
        )

        let hour = Calendar.current.component(.hour, from: context.segmentStart)

        return LowEventFeatures(
            nadirMgdL: context.nadir,
            durationMinutes: durationMinutes,
            rateOfFall: rateOfFall,
            rateOfRecovery: rateOfRecovery,
            totalBolusUnits4h: totalBolus4h,
            smbCount1h: smbCount1h,
            carbsConsumed2h: carbsConsumed2h,
            exerciseInLookback: !context.exerciseEvents.isEmpty,
            hourOfDay: hour,
            isOvernight: hour >= 0 && hour < 6,
            category: category
        )
    }

    // MARK: - Individual Category Checks

    /// COMPRESSION_LOW: short-duration, rapid-recovery low with no significant insulin action.
    /// These are CGM artifacts (sleeping on sensor) rather than true hypoglycemia.
    static func checkCompressionLow(
        context: LowEventContext
    ) -> (category: TIREventCategory, confidence: TIREventConfidence, factors: [TIRContributingFactor])? {
        let durationMinutes = context.segmentEnd.timeIntervalSince(context.segmentStart) / 60
        guard durationMinutes < Double(compressionMaxDurationMinutes) else { return nil }
        guard context.nadir >= compressionMinNadir else { return nil }

        // Rapid recovery check: rate of recovery ≥ threshold
        let recovery = computeRateOfRecovery(context: context)
        guard recovery >= compressionMinRecoveryRatePerFiveMin else { return nil }

        // No significant bolus in lookback
        let lookback = context.segmentStart.addingTimeInterval(-compressionBolusLookbackSeconds)
        let totalBolus = totalBolusInWindow(
            boluses: context.bolusesInWindow, smbs: context.smbsInWindow,
            from: lookback, to: context.segmentStart
        )
        guard totalBolus < compressionBolusThreshold else { return nil }

        // Confidence: high if noise elevated OR overnight; medium otherwise
        let hasElevatedNoise = (context.noiseLevel ?? 0) >= 2
        let hour = Calendar.current.component(.hour, from: context.segmentStart)
        let isOvernight = hour >= 0 && hour < 6
        let confidence: TIREventConfidence = (hasElevatedNoise || isOvernight) ? .high : .medium

        var factors = [
            TIRContributingFactor(
                factor: "Rapid recovery pattern",
                evidence: String(
                    format: "Low lasted %.0f min with rapid recovery (%.1f mg/dL per 5 min). Nadir %d mg/dL.",
                    durationMinutes, recovery, context.nadir
                ),
                actionable: false,
                suggestion: "Likely a CGM compression artifact. Verify with fingerstick if concerned."
            )
        ]
        if hasElevatedNoise {
            factors.append(TIRContributingFactor(
                factor: "Elevated CGM noise",
                evidence: "Noise level \(context.noiseLevel ?? 0) during low segment",
                actionable: false,
                suggestion: nil
            ))
        }
        return (.compressionLow, confidence, factors)
    }

    /// OVERCORRECTION_LOW: significant bolus or correction in the 1–4h before the low.
    static func checkOvercorrectionLow(
        context: LowEventContext
    ) -> (category: TIREventCategory, confidence: TIREventConfidence, factors: [TIRContributingFactor])? {
        let lookbackStart = context.segmentStart.addingTimeInterval(-overcorrectionLookbackMaxSeconds)
        let lookbackEnd = context.segmentStart.addingTimeInterval(-overcorrectionLookbackMinSeconds)

        // Boluses in the 1–4h window before the low
        let relevantBoluses = context.bolusesInWindow.filter {
            $0.timestamp >= lookbackStart && $0.timestamp <= context.segmentStart
        }
        let relevantSMBs = context.smbsInWindow.filter {
            $0.timestamp >= lookbackStart && $0.timestamp <= context.segmentStart
        }

        // Count distinct bolus events (not SMBs — those are stacking)
        let bolusEvents = relevantBoluses.filter { !$0.isSMB }
        guard bolusEvents.count >= 1, bolusEvents.count <= overcorrectionMaxBolusEvents else { return nil }

        let totalBolus = bolusEvents.reduce(0.0) { $0 + $1.units }
        guard totalBolus >= overcorrectionMinBolus else { return nil }

        // Check if this was a correction-only (no carbs) vs meal bolus
        let carbLookback = context.segmentStart.addingTimeInterval(-overcorrectionLookbackMaxSeconds)
        let hadRecentCarbs: Bool
        if let carbs = context.carbEntries {
            hadRecentCarbs = carbs.contains { entry in
                let d = entry.actualDate ?? entry.createdAt
                let isFPU = entry.isFPU ?? false
                return !isFPU && entry.carbs > 0 && d >= carbLookback && d <= context.segmentStart
            }
        } else {
            hadRecentCarbs = false
        }

        // Check if there was a prior high (correction scenario)
        let hadPriorHigh = context.allGlucose.contains {
            $0.dateString >= lookbackStart &&
                $0.dateString < context.segmentStart &&
                Double(ThresholdCrossingDetector.sgvValue($0)) > context.configuration.highThresholdMgdL
        }

        // Confidence: high if correction-only (no carbs, prior high); medium if meal bolus
        let confidence: TIREventConfidence = (!hadRecentCarbs && hadPriorHigh) ? .high : .medium

        let bolusDetail = bolusEvents.map { event in
            String(format: "%.1fU at %@", event.units, Self.timeFormatter.string(from: event.timestamp))
        }.joined(separator: ", ")

        var factors = [
            TIRContributingFactor(
                factor: hadRecentCarbs ? "Meal bolus before low" : "Correction bolus before low",
                evidence: "\(bolusDetail) — total \(String(format: "%.1f", totalBolus))U in \(bolusEvents.count) dose(s)",
                actionable: true,
                suggestion: hadPriorHigh
                    ? "Review correction factor (ISF). The correction dose may be too aggressive."
                    : "Review insulin-to-carb ratio. The meal bolus may be too large."
            )
        ]
        if hadPriorHigh {
            let priorPeak = context.allGlucose
                .filter { $0.dateString >= lookbackStart && $0.dateString < context.segmentStart }
                .map { ThresholdCrossingDetector.sgvValue($0) }.max() ?? 0
            factors.append(TIRContributingFactor(
                factor: "Prior high before correction",
                evidence: "Peak \(priorPeak) mg/dL before the correction that led to this low",
                actionable: false,
                suggestion: nil
            ))
        }

        return (.overcorrectionLow, confidence, factors)
    }

    /// STACKING_LOW: multiple insulin deliveries in rapid succession before the low.
    static func checkStackingLow(
        context: LowEventContext
    ) -> (category: TIREventCategory, confidence: TIREventConfidence, factors: [TIRContributingFactor])? {
        let smbCutoff = context.segmentStart.addingTimeInterval(-stackingSMBWindowSeconds)
        let recentSMBs = context.smbsInWindow.filter { $0.timestamp >= smbCutoff && $0.timestamp <= context.segmentStart }
        let smbMatch = recentSMBs.count >= stackingSMBCountThreshold

        let bolusCutoff = context.segmentStart.addingTimeInterval(-stackingBolusWindowSeconds)
        let recentBoluses = context.bolusesInWindow.filter {
            !$0.isSMB && $0.timestamp >= bolusCutoff && $0.timestamp <= context.segmentStart
        }
        let bolusMatch = recentBoluses.count >= stackingBolusCountThreshold

        guard smbMatch || bolusMatch else { return nil }

        let allEvents = (recentSMBs.map { $0 } + recentBoluses.map { $0 })
        let totalUnits = allEvents.reduce(0.0) { $0 + $1.units }

        let factor: TIRContributingFactor
        if smbMatch {
            factor = TIRContributingFactor(
                factor: "SMB stacking",
                evidence: String(
                    format: "%d SMBs delivered in 60 min before low (%.1fU total)",
                    recentSMBs.count, recentSMBs.reduce(0.0) { $0 + $1.units }
                ),
                actionable: true,
                suggestion: "Review SMB frequency and max SMB basal minutes settings."
            )
        } else {
            factor = TIRContributingFactor(
                factor: "Bolus stacking",
                evidence: String(
                    format: "%d boluses in 90 min before low (%.1fU total)",
                    recentBoluses.count, totalUnits
                ),
                actionable: true,
                suggestion: "Consider waiting longer between corrections to observe the effect of active insulin."
            )
        }

        return (.stackingLow, .high, [factor])
    }

    /// ACTIVITY_RELATED_LOW: explicit exercise data within 0–4h before the low.
    /// Never guesses — only fires when exercise data is present.
    static func checkActivityRelated(
        context: LowEventContext
    ) -> (category: TIREventCategory, confidence: TIREventConfidence, factors: [TIRContributingFactor])? {
        guard !context.exerciseEvents.isEmpty else { return nil }

        let lookbackStart = context.segmentStart.addingTimeInterval(-activityLookbackSeconds)
        let relevantExercise = context.exerciseEvents.filter { event in
            // Exercise ended within 4h before low start, or was in progress during the low
            (event.end >= lookbackStart && event.end <= context.segmentStart) ||
                (event.start <= context.segmentEnd && event.end >= context.segmentStart)
        }
        guard let exercise = relevantExercise.first else { return nil }

        let gapMinutes = context.segmentStart.timeIntervalSince(exercise.end) / 60
        let inProgress = exercise.start <= context.segmentEnd && exercise.end >= context.segmentStart
        let timingDetail = inProgress
            ? "during exercise"
            : String(format: "%.0f min after exercise ended", max(0, gapMinutes))

        let factor = TIRContributingFactor(
            factor: "Exercise-associated low",
            evidence: "Low occurred \(timingDetail). Activity: \(exercise.notes ?? exercise.source.rawValue).",
            actionable: true,
            suggestion: "Consider pre-exercise carbs, reduced basal, or an exercise override profile."
        )

        return (.activityRelatedLow, .high, [factor])
    }

    /// REBOUND_LOW: reading above highThreshold within 90 min before the low start.
    /// This is the "post-high crash" — the algorithm overcorrected a high.
    static func checkReboundLow(
        context: LowEventContext
    ) -> (category: TIREventCategory, confidence: TIREventConfidence, factors: [TIRContributingFactor])? {
        let lookbackStart = context.segmentStart.addingTimeInterval(-reboundLookbackSeconds)
        let highThreshold = context.configuration.highThresholdMgdL

        let precedingHighs = context.allGlucose.filter {
            $0.dateString >= lookbackStart &&
                $0.dateString < context.segmentStart &&
                Double(ThresholdCrossingDetector.sgvValue($0)) > highThreshold
        }
        guard !precedingHighs.isEmpty else { return nil }

        let priorPeak = precedingHighs.map { ThresholdCrossingDetector.sgvValue($0) }.max() ?? 0
        let confidence: TIREventConfidence = precedingHighs.count >= 2 ? .high : .medium

        let factor = TIRContributingFactor(
            factor: "Recent high before low",
            evidence: String(
                format: "Peak %d mg/dL within 90 min before this low (nadir %d mg/dL, drop of %d)",
                priorPeak, context.nadir, priorPeak - context.nadir
            ),
            actionable: true,
            suggestion: "Review correction intensity and timing to reduce rebound lows."
        )

        return (.reboundLow, confidence, [factor])
    }

    /// BASAL_TOO_AGGRESSIVE: low without bolus or carb activity — suggests basal is driving it.
    static func checkBasalTooAggressive(
        context: LowEventContext
    ) -> (category: TIREventCategory, confidence: TIREventConfidence, factors: [TIRContributingFactor])? {
        let durationMinutes = context.segmentEnd.timeIntervalSince(context.segmentStart) / 60

        // Must not match compression pattern (duration > 30 min or no rapid recovery)
        if durationMinutes < Double(compressionMaxDurationMinutes) {
            let recovery = computeRateOfRecovery(context: context)
            if recovery >= compressionMinRecoveryRatePerFiveMin, context.nadir >= compressionMinNadir {
                return nil // Looks like compression, let that classifier handle it
            }
        }

        // No significant bolus in 3h
        let bolusLookback = context.segmentStart.addingTimeInterval(-basalNoBolusWindowSeconds)
        let totalBolus = totalBolusInWindow(
            boluses: context.bolusesInWindow, smbs: context.smbsInWindow,
            from: bolusLookback, to: context.segmentStart
        )
        guard totalBolus < basalMaxBolusThreshold else { return nil }

        // No carbs in 3h (rules out meal-related scenarios)
        let carbLookback = context.segmentStart.addingTimeInterval(-basalNoCarbWindowSeconds)
        if let carbs = context.carbEntries {
            let hadCarbs = carbs.contains { entry in
                let d = entry.actualDate ?? entry.createdAt
                let isFPU = entry.isFPU ?? false
                return !isFPU && entry.carbs > 0 && d >= carbLookback && d <= context.segmentStart
            }
            if hadCarbs { return nil }
        }

        let hour = Calendar.current.component(.hour, from: context.segmentStart)
        let isOvernight = hour >= 0 && hour < 6
        let confidence: TIREventConfidence = isOvernight ? .high : .medium

        let factor = TIRContributingFactor(
            factor: "No recent bolus or carb activity",
            evidence: String(
                format: "No bolus > %.1fU in 3h and no carbs in 3h before this %@ low (nadir %d mg/dL)",
                basalMaxBolusThreshold,
                isOvernight ? "overnight" : "daytime",
                context.nadir
            ),
            actionable: true,
            suggestion: isOvernight
                ? "Review overnight basal rate for this time period."
                : "Review basal profile and consider whether activity or absorption variability contributed."
        )

        return (.basalTooAggressive, confidence, [factor])
    }

    /// FALLING_WITHOUT_ACTIVE_INSULIN: no recent insulin action, no carbs, unexplained drift.
    /// Preserved from original implementation.
    static func checkFallingWithoutActiveInsulin(
        context: LowEventContext
    ) -> (category: TIREventCategory, confidence: TIREventConfidence, factors: [TIRContributingFactor])? {
        guard context.nadir >= fallingMinNadir else { return nil }

        // No SMB or bolus in 75 min
        let insulinLookback = context.segmentStart.addingTimeInterval(-fallingNoInsulinWindowSeconds)
        let hadInsulin = (context.bolusesInWindow + context.smbsInWindow).contains {
            $0.timestamp >= insulinLookback && $0.timestamp <= context.segmentStart
        }
        guard !hadInsulin else { return nil }

        // No carbs in 2h
        let carbLookback = context.segmentStart.addingTimeInterval(-fallingNoCarbWindowSeconds)
        if let carbs = context.carbEntries {
            let hadCarbs = carbs.contains { entry in
                let d = entry.actualDate ?? entry.createdAt
                return d >= carbLookback && d <= context.segmentStart
            }
            if hadCarbs { return nil }
        }

        let factor = TIRContributingFactor(
            factor: "Drop without active insulin",
            evidence: "No recent insulin or carb activity detected before this low (nadir \(context.nadir) mg/dL)",
            actionable: true,
            suggestion: "Consider basal, activity, or meal-timing contributors."
        )

        return (.fallingWithoutActiveInsulin, .medium, [factor])
    }

    /// PERSISTENT_LOW: extended time below range (≥ 45 min).
    static func checkPersistentLow(
        context: LowEventContext
    ) -> (category: TIREventCategory, confidence: TIREventConfidence, factors: [TIRContributingFactor])? {
        let durationSeconds = context.segmentEnd.timeIntervalSince(context.segmentStart)
        guard durationSeconds >= persistentMinDurationSeconds else { return nil }

        let durationMinutes = Int(durationSeconds / 60)
        let confidence: TIREventConfidence = context.nadir < 54 ? .high : .medium

        let factor = TIRContributingFactor(
            factor: "Sustained low duration",
            evidence: "Low range persisted for \(durationMinutes) minutes (nadir \(context.nadir) mg/dL)",
            actionable: true,
            suggestion: "Review basal profile and correction strategy around this period."
        )

        return (.persistentLow, confidence, [factor])
    }

    // MARK: - Helpers

    /// Sum of bolus + SMB units in a time window.
    static func totalBolusInWindow(
        boluses: [InsulinEvent],
        smbs: [InsulinEvent],
        from: Date,
        to: Date
    ) -> Double {
        let allInWindow = (boluses + smbs).filter { $0.timestamp >= from && $0.timestamp <= to }
        return allInWindow.reduce(0.0) { $0 + $1.units }
    }

    /// Rate of glucose fall approaching the nadir (mg/dL per 5-min interval).
    /// Computed from the segment start to the nadir reading.
    static func computeRateOfFall(context: LowEventContext) -> Double {
        let sorted = context.readings.sorted { $0.dateString < $1.dateString }
        guard sorted.count >= 2 else { return 0 }

        // Find the nadir reading
        guard let nadirReading = sorted
            .min(by: { ThresholdCrossingDetector.sgvValue($0) < ThresholdCrossingDetector.sgvValue($1) })
        else { return 0 }

        let firstReading = sorted.first!
        let intervalMinutes = nadirReading.dateString.timeIntervalSince(firstReading.dateString) / 60
        guard intervalMinutes > 0 else { return 0 }

        let drop = Double(ThresholdCrossingDetector.sgvValue(firstReading) - ThresholdCrossingDetector.sgvValue(nadirReading))
        return drop / intervalMinutes * 5.0 // normalize to per-5-min
    }

    /// Rate of glucose recovery from the nadir (mg/dL per 5-min interval).
    /// Computed from the nadir reading to the segment end.
    static func computeRateOfRecovery(context: LowEventContext) -> Double {
        let sorted = context.readings.sorted { $0.dateString < $1.dateString }
        guard sorted.count >= 2 else { return 0 }

        // Find the nadir reading
        guard let nadirReading = sorted
            .min(by: { ThresholdCrossingDetector.sgvValue($0) < ThresholdCrossingDetector.sgvValue($1) })
        else { return 0 }

        let lastReading = sorted.last!
        let intervalMinutes = lastReading.dateString.timeIntervalSince(nadirReading.dateString) / 60
        guard intervalMinutes > 0 else { return 0 }

        let rise = Double(ThresholdCrossingDetector.sgvValue(lastReading) - ThresholdCrossingDetector.sgvValue(nadirReading))
        return rise / intervalMinutes * 5.0 // normalize to per-5-min
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()
}
