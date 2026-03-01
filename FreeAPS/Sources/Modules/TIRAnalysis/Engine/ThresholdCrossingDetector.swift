import Foundation

/// Converts a raw [BloodGlucose] array into consolidated above-threshold segments
/// and a list of CGM data gaps, applying the 15-minute in-range consolidation rule.
///
/// Pure static functions — no state, fully testable without DI.
enum ThresholdCrossingDetector {
    // MARK: - Constants

    /// Two consecutive readings more than this apart constitute a CGM gap.
    static let cgmGapThresholdSeconds: TimeInterval = 10 * 60

    /// An in-range dip shorter than this bridges two high runs into one event.
    static let consolidationWindowSeconds: TimeInterval = 15 * 60

    // MARK: - Public API

    /// Primary entry point. Returns (segments, cgmGaps) ready for EventClassifier.
    ///
    /// - Parameters:
    ///   - glucose: Raw readings in any order. Invalid readings (isStateValid == false) are excluded.
    ///   - highThreshold: Upper range limit in mg/dL.
    ///   - windowStart: Readings before this date are ignored.
    ///   - windowEnd: Readings after this date are ignored.
    static func detect(
        in glucose: [BloodGlucose],
        highThreshold: Double,
        windowStart: Date,
        windowEnd: Date
    ) -> (segments: [GlucoseSegment], cgmGaps: [DateInterval]) {
        // Step 1: Filter to window, exclude invalid readings, sort chronologically.
        let sorted = glucose
            .filter { $0.dateString >= windowStart && $0.dateString <= windowEnd }
            .filter { $0.isStateValid }
            .sorted { $0.dateString < $1.dateString }

        guard sorted.count >= 2 else {
            return ([], detectGaps(in: sorted))
        }

        // Step 2: Detect CGM gaps on the filtered-but-not-yet-consolidated list.
        let gaps = detectGaps(in: sorted)

        // Step 3: Build raw above-threshold runs.
        let rawRuns = buildRawRuns(from: sorted, highThreshold: highThreshold)

        // Step 4: Apply 15-minute consolidation rule.
        let consolidated = consolidate(runs: rawRuns, allReadings: sorted)

        // Step 5: Drop single-reading segments (noise at boundary).
        let segments = consolidated.filter { $0.readings.count >= 2 }

        return (segments, gaps)
    }

    // MARK: - Internal helpers

    /// Extracts the best SGV value from a reading: sgv ?? glucose ?? 0.
    static func sgvValue(_ r: BloodGlucose) -> Int {
        r.sgv ?? r.glucose ?? 0
    }

    // MARK: - CGM gap detection

    static func detectGaps(in sorted: [BloodGlucose]) -> [DateInterval] {
        guard sorted.count >= 2 else { return [] }
        var gaps: [DateInterval] = []
        for i in 0 ..< sorted.count - 1 {
            let gap = sorted[i + 1].dateString.timeIntervalSince(sorted[i].dateString)
            if gap > cgmGapThresholdSeconds {
                gaps.append(DateInterval(start: sorted[i].dateString, end: sorted[i + 1].dateString))
            }
        }
        return gaps
    }

    // MARK: - Raw run extraction

    /// Builds contiguous runs of readings strictly above `highThreshold`.
    /// Also splits a run when consecutive above-threshold readings are more than
    /// `consolidationWindowSeconds` apart (missing data gap during a high event).
    static func buildRawRuns(from sorted: [BloodGlucose], highThreshold: Double) -> [[BloodGlucose]] {
        var runs: [[BloodGlucose]] = []
        var current: [BloodGlucose] = []

        for reading in sorted {
            let val = Double(sgvValue(reading))
            if val > highThreshold {
                // Split on time gaps between consecutive high readings (no in-range readings
                // bridging them, just missing data). Treat a long gap as an event break.
                if let prev = current.last {
                    let gap = reading.dateString.timeIntervalSince(prev.dateString)
                    if gap > consolidationWindowSeconds {
                        runs.append(current)
                        current = []
                    }
                }
                current.append(reading)
            } else {
                if !current.isEmpty {
                    runs.append(current)
                    current = []
                }
            }
        }
        if !current.isEmpty {
            runs.append(current)
        }
        return runs
    }

    // MARK: - 15-minute consolidation

    /// Merges adjacent above-threshold runs when the in-range gap between them
    /// is < 15 minutes. The bridging in-range readings are included in the merged
    /// segment's reading list (useful for Track 2 factor analysis).
    static func consolidate(runs: [[BloodGlucose]], allReadings: [BloodGlucose]) -> [GlucoseSegment] {
        guard !runs.isEmpty else { return [] }

        // Convert raw runs into mutable segment candidates.
        var segments: [MutableSegment] = runs.map { MutableSegment(readings: $0) }

        var merged = true
        while merged {
            merged = false
            var result: [MutableSegment] = []
            var i = 0
            while i < segments.count {
                if i + 1 < segments.count {
                    let current = segments[i]
                    let next = segments[i + 1]
                    let gapDuration = next.start.timeIntervalSince(current.end)
                    if gapDuration <= consolidationWindowSeconds {
                        // Merge: collect bridging in-range readings between the two segments.
                        let bridge = allReadings.filter {
                            $0.dateString > current.end && $0.dateString < next.start
                        }
                        let mergedReadings = current.readings + bridge + next.readings
                        result.append(MutableSegment(readings: mergedReadings))
                        i += 2
                        merged = true
                        continue
                    }
                }
                result.append(segments[i])
                i += 1
            }
            segments = result
        }

        return segments.map { $0.toSegment() }
    }

    // MARK: - Mutable intermediate type

    private struct MutableSegment {
        var readings: [BloodGlucose]

        var start: Date { readings.first!.dateString }
        var end: Date { readings.last!.dateString }
        var peakSgv: Int { readings.map { ThresholdCrossingDetector.sgvValue($0) }.max() ?? 0 }

        func toSegment() -> GlucoseSegment {
            GlucoseSegment(
                readings: readings,
                start: start,
                end: end,
                peakSgv: peakSgv
            )
        }
    }
}
