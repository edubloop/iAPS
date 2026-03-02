import Foundation

/// Classifies a single GlucoseSegment into a TIREventCategory using a strict
/// priority order. Pure static functions — no state, no DI.
///
/// Priority order (first match wins):
///   1. REBOUND_HIGH
///   2. POST_CONNECTIVITY_GAP
///   3. CONSTRAINT_LIMITED
///   4. RISING_WITHOUT_CARBS
///   5. PERSISTENT_ELEVATION
///   6. UNCLASSIFIED_HIGH  (catch-all)
enum EventClassifier {
    // MARK: - Constants

    /// Window before event start to look for a preceding low reading (REBOUND_HIGH).
    static let reboundLookbackSeconds: TimeInterval = 60 * 60

    /// A preceding low reading within this window makes it a rebound.
    static let reboundMaxLowToHighGapSeconds: TimeInterval = 60 * 60

    /// A CGM gap ending within this window before event start triggers POST_CONNECTIVITY_GAP.
    static let gapToEventWindowSeconds: TimeInterval = 30 * 60

    /// Fraction of maxIOB the IOB must reach to count as "at ceiling".
    static let iobCeilingFraction: Double = 0.95

    /// Event must be above ceiling for this fraction of buckets → CONSTRAINT_LIMITED.
    static let iobConstrainedFraction: Double = 0.50

    /// IOB bucket size (seconds). Match the 5-min CGM interval.
    static let iobBucketSeconds: TimeInterval = 5 * 60

    /// Max tolerated time between an IOB tick and a bucket center to be "close enough".
    static let iobMatchToleranceSeconds: TimeInterval = 7.5 * 60

    /// No carb entry within this window before event start → RISING_WITHOUT_CARBS.
    static let carbLookbackSeconds: TimeInterval = 4 * 60 * 60

    /// Minimum event duration (seconds) for PERSISTENT_ELEVATION.
    static let persistentElevationMinSeconds: TimeInterval = 3 * 60 * 60

    // MARK: - Public API

    /// Returns (category, confidence) for a single segment.
    ///
    /// - Parameters:
    ///   - segment: The high-glucose event to classify.
    ///   - allGlucose: All state-valid glucose readings in the analysis window,
    ///                 sorted chronologically. Used for REBOUND_HIGH look-back.
    ///   - carbEntries: Optional carb entries; nil means data unavailable.
    ///   - iobHistory: Optional IOB ticks; nil means CONSTRAINT_LIMITED is skipped.
    ///   - cgmGaps: Gap intervals from ThresholdCrossingDetector.
    ///   - configuration: Analysis configuration (thresholds, maxIOB, etc.).
    static func classify(
        segment: GlucoseSegment,
        allGlucose: [BloodGlucose],
        carbEntries: [CarbsEntry]?,
        iobHistory: [IOBTick0]?,
        cgmGaps: [DateInterval],
        configuration: TIRAnalysisConfiguration
    ) -> (category: TIREventCategory, confidence: TIREventConfidence) {
        // Priority 1 — REBOUND_HIGH
        if let reboundConfidence = checkReboundHigh(
            segment: segment,
            allGlucose: allGlucose,
            lowThreshold: configuration.lowThresholdMgdL
        ) {
            return (.reboundHigh, reboundConfidence)
        }

        // Priority 2 — POST_CONNECTIVITY_GAP
        if checkPostConnectivityGap(segment: segment, cgmGaps: cgmGaps) {
            return (.postConnectivityGap, .high)
        }

        // Priority 3 — CONSTRAINT_LIMITED (skipped if no IOB data)
        if let iob = iobHistory,
           let constraintConfidence = checkConstraintLimited(
               segment: segment,
               iobHistory: iob,
               maxIOB: configuration.maxIOB
           )
        {
            return (.constraintLimited, constraintConfidence)
        }

        // Priority 4 — RISING_WITHOUT_CARBS
        let (risingWithout, risingConfidence) = checkRisingWithoutCarbs(
            segment: segment,
            carbEntries: carbEntries
        )
        if risingWithout {
            return (.risingWithoutCarbs, risingConfidence)
        }

        // Priority 5 — PERSISTENT_ELEVATION
        let eventDuration = segment.end.timeIntervalSince(segment.start)
        if eventDuration >= persistentElevationMinSeconds {
            let persistentConfidence = checkPersistentElevation(
                segment: segment,
                pumpHistory: nil // pumpHistory passed in via engine; see Track 2
            )
            return (.persistentElevation, persistentConfidence)
        }

        // Priority 6 — catch-all
        return (.unclassifiedHigh, .medium)
    }

    /// Variant that accepts pumpHistory for PERSISTENT_ELEVATION SMB check.
    /// This is the canonical signature used by TIRAnalysisEngine.
    static func classify(
        segment: GlucoseSegment,
        allGlucose: [BloodGlucose],
        carbEntries: [CarbsEntry]?,
        iobHistory: [IOBTick0]?,
        pumpHistory: [PumpHistoryEvent]?,
        cgmGaps: [DateInterval],
        configuration: TIRAnalysisConfiguration
    ) -> (category: TIREventCategory, confidence: TIREventConfidence) {
        // Priority 1 — REBOUND_HIGH
        if let reboundConfidence = checkReboundHigh(
            segment: segment,
            allGlucose: allGlucose,
            lowThreshold: configuration.lowThresholdMgdL
        ) {
            return (.reboundHigh, reboundConfidence)
        }

        // Priority 2 — POST_CONNECTIVITY_GAP
        if checkPostConnectivityGap(segment: segment, cgmGaps: cgmGaps) {
            return (.postConnectivityGap, .high)
        }

        // Priority 3 — CONSTRAINT_LIMITED
        if let iob = iobHistory,
           let constraintConfidence = checkConstraintLimited(
               segment: segment,
               iobHistory: iob,
               maxIOB: configuration.maxIOB
           )
        {
            return (.constraintLimited, constraintConfidence)
        }

        // Priority 4 — RISING_WITHOUT_CARBS
        let (risingWithout, risingConfidence) = checkRisingWithoutCarbs(
            segment: segment,
            carbEntries: carbEntries
        )
        if risingWithout {
            return (.risingWithoutCarbs, risingConfidence)
        }

        // Priority 5 — PERSISTENT_ELEVATION
        let eventDuration = segment.end.timeIntervalSince(segment.start)
        if eventDuration >= persistentElevationMinSeconds {
            let persistentConfidence = checkPersistentElevation(
                segment: segment,
                pumpHistory: pumpHistory
            )
            return (.persistentElevation, persistentConfidence)
        }

        // Priority 6 — catch-all
        return (.unclassifiedHigh, .medium)
    }

    // MARK: - Individual category checks

    /// REBOUND_HIGH: a reading below lowThreshold occurred within 60 min before segment.start.
    /// Returns nil if condition not met, otherwise the confidence level.
    static func checkReboundHigh(
        segment: GlucoseSegment,
        allGlucose: [BloodGlucose],
        lowThreshold: Double
    ) -> TIREventConfidence? {
        let lookbackStart = segment.start.addingTimeInterval(-reboundLookbackSeconds)

        let precedingLows = allGlucose.filter {
            $0.dateString >= lookbackStart &&
                $0.dateString < segment.start &&
                Double(ThresholdCrossingDetector.sgvValue($0)) < lowThreshold
        }

        guard !precedingLows.isEmpty else { return nil }

        // Check the most recent low reading is within the rebound window.
        let mostRecentLow = precedingLows.max(by: { $0.dateString < $1.dateString })!
        let gapToEvent = segment.start.timeIntervalSince(mostRecentLow.dateString)
        guard gapToEvent <= reboundMaxLowToHighGapSeconds else { return nil }

        // Confidence: medium if only one low reading found (could be noise).
        return precedingLows.count >= 2 ? .high : .medium
    }

    /// POST_CONNECTIVITY_GAP: any CGM gap ended within 30 min before segment.start.
    static func checkPostConnectivityGap(
        segment: GlucoseSegment,
        cgmGaps: [DateInterval]
    ) -> Bool {
        let cutoff = segment.start.addingTimeInterval(-gapToEventWindowSeconds)
        return cgmGaps.contains { gap in
            gap.end >= cutoff && gap.end <= segment.start
        }
    }

    /// CONSTRAINT_LIMITED: ≥50% of 5-min buckets during the event have IOB ≥ maxIOB * 0.95.
    /// Returns nil if IOB coverage is too sparse to judge (< 1 tick per 10 min average),
    /// or if maxIOB is zero (undefined).
    static func checkConstraintLimited(
        segment: GlucoseSegment,
        iobHistory: [IOBTick0],
        maxIOB: Double
    ) -> TIREventConfidence? {
        guard maxIOB > 0 else { return nil }

        let ceiling = maxIOB * iobCeilingFraction
        let eventDuration = segment.end.timeIntervalSince(segment.start)
        guard eventDuration > 0 else { return nil }

        // Build 5-min bucket centers across the event.
        let bucketCount = max(1, Int(eventDuration / iobBucketSeconds))
        var atCeilingCount = 0
        var matchedCount = 0

        for b in 0 ..< bucketCount {
            let bucketCenter = segment.start.addingTimeInterval(Double(b) * iobBucketSeconds + iobBucketSeconds / 2)
            // Find the nearest IOB tick within tolerance.
            if let nearest = iobHistory.min(by: {
                abs($0.time.timeIntervalSince(bucketCenter)) < abs($1.time.timeIntervalSince(bucketCenter))
            }), abs(nearest.time.timeIntervalSince(bucketCenter)) <= iobMatchToleranceSeconds {
                matchedCount += 1
                if NSDecimalNumber(decimal: nearest.iob).doubleValue >= ceiling {
                    atCeilingCount += 1
                }
            }
        }

        guard matchedCount > 0 else { return nil }

        // Require at least 1 match per 10 min on average for meaningful coverage.
        let minExpectedMatches = max(1, Int(eventDuration / (10 * 60)))
        let confidence: TIREventConfidence = matchedCount >= minExpectedMatches ? .high : .medium

        let fraction = Double(atCeilingCount) / Double(matchedCount)
        guard fraction >= iobConstrainedFraction else { return nil }

        return confidence
    }

    /// RISING_WITHOUT_CARBS: no real carb entry within 4 hr before segment.start.
    /// Returns (isMatch, confidence). Confidence is `low` when carb stream is nil.
    static func checkRisingWithoutCarbs(
        segment: GlucoseSegment,
        carbEntries: [CarbsEntry]?
    ) -> (Bool, TIREventConfidence) {
        guard let carbs = carbEntries else {
            // No carb data at all — we can't confirm absence.
            // Still flag it but at low confidence.
            return (true, .low)
        }

        let lookbackStart = segment.start.addingTimeInterval(-carbLookbackSeconds)
        let recentCarbs = carbs.filter { entry in
            // Use actualDate if available, else createdAt.
            let entryDate = entry.actualDate ?? entry.createdAt
            // Exclude FPU synthetic entries; only count real food.
            let isFPU = entry.isFPU ?? false
            let hasRealCarbs = entry.carbs > 0
            return !isFPU && hasRealCarbs
                && entryDate >= lookbackStart
                && entryDate <= segment.start
        }

        if recentCarbs.isEmpty {
            return (true, .high)
        }
        return (false, .high) // carbs found — not this category
    }

    /// PERSISTENT_ELEVATION confidence check.
    /// `high` when an SMB was found in pump history during the event.
    /// `medium` otherwise (duration still qualifies, but can't confirm SMB delivery).
    static func checkPersistentElevation(
        segment: GlucoseSegment,
        pumpHistory: [PumpHistoryEvent]?
    ) -> TIREventConfidence {
        guard let history = pumpHistory else { return .medium }
        let hasSMB = history.contains { event in
            let isSmb = event.isSMB == true || event.type == .smb
            return isSmb && event.timestamp >= segment.start && event.timestamp <= segment.end
        }
        return hasSMB ? .high : .medium
    }
}
