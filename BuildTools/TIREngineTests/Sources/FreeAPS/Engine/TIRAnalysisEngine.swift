import Foundation

/// Orchestrates the full Track 1 pipeline:
///   1. ThresholdCrossingDetector  → segments + gaps
///   2. EventClassifier            → category + confidence per segment
///   3. Stable ID assignment
///   4. tirCost computation
///   5. Return [TIREvent] sorted by start ascending
///
/// Pure static function — no shared mutable state, safe to call from any queue.
enum TIRAnalysisEngine {
    // MARK: - Public API

    /// Analyse the input and return a classified event stream.
    ///
    /// - Returns: Events sorted by `start` ascending. Empty if no glucose data.
    static func analyze(_ input: TIRAnalysisInput) -> [TIREvent] {
        guard !input.glucose.isEmpty else { return [] }

        let config = input.configuration

        // Step 1: Detect high segments + CGM gaps.
        let (segments, gaps) = ThresholdCrossingDetector.detect(
            in: input.glucose,
            highThreshold: config.highThresholdMgdL,
            windowStart: config.windowStart,
            windowEnd: config.windowEnd
        )

        guard !segments.isEmpty else { return [] }

        // The classifier needs all state-valid glucose sorted chronologically
        // for REBOUND_HIGH look-back (not just the above-threshold subset).
        let allSortedGlucose = input.glucose
            .filter { $0.isStateValid }
            .sorted { $0.dateString < $1.dateString }

        // Step 2: Compute total window duration for tirCost.
        let windowMinutes = config.windowEnd.timeIntervalSince(config.windowStart) / 60.0
        let safeWindowMinutes = max(windowMinutes, 1.0) // guard against zero-length windows in tests

        // Step 3: Sort segments by start for stable ordinal assignment.
        let sortedSegments = segments.sorted { $0.start < $1.start }

        // Step 4: Classify each segment and build TIREvent.
        var events: [TIREvent] = []
        var ordinalsByMinute: [String: Int] = [:]

        for segment in sortedSegments {
            let (category, confidence, factors) = EventClassifier.classify(
                segment: segment,
                allGlucose: allSortedGlucose,
                carbEntries: input.carbEntries,
                iobHistory: input.iobHistory,
                pumpHistory: input.pumpHistory,
                cgmGaps: gaps,
                configuration: config
            )

            // Stable ID: "evt_yyyyMMddTHHmmZ_001"
            let minuteKey = stableMinuteKey(from: segment.start)
            let ordinal = (ordinalsByMinute[minuteKey] ?? 0) + 1
            ordinalsByMinute[minuteKey] = ordinal
            let eventID = "evt_\(minuteKey)_\(String(format: "%03d", ordinal))"

            let durationMin = segment.durationMinutes
            let tirCost = Double(durationMin) / safeWindowMinutes

            let event = TIREvent(
                id: eventID,
                start: segment.start,
                end: segment.end,
                type: "high",
                peakSeverity: segment.peakSgv,
                durationMinutes: durationMin,
                tirCost: tirCost,
                category: category,
                confidence: confidence,
                contributingFactors: factors
            )
            events.append(event)
        }

        return events.sorted { $0.start < $1.start }
    }

    // MARK: - Stable ID helper

    /// Formats a Date as "yyyyMMdd'T'HHmm'Z'" in UTC for use in event IDs.
    /// Example: 2026-03-01 09:40:00 UTC → "20260301T0940Z"
    static func stableMinuteKey(from date: Date) -> String {
        idFormatter.string(from: date)
    }

    private static let idFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd'T'HHmm'Z'"
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
}
