@testable import FreeAPS
import XCTest

// TC-01 through TC-07 — ThresholdCrossingDetector unit tests.
// All tests are synchronous (pure functions, no async/await needed).
class TIRThresholdCrossingDetectorTests: XCTestCase {

    // MARK: - Helpers

    private let highThreshold: Double = 180
    private let window = DateInterval(
        start: Date(timeIntervalSinceReferenceDate: 0),
        end: Date(timeIntervalSinceReferenceDate: 86400) // 24 h
    )

    private func makeGlucose(
        sgv: Int,
        at offset: TimeInterval, // seconds from window start
        noise: Int = 1
    ) -> BloodGlucose {
        let date = window.start.addingTimeInterval(offset)
        return BloodGlucose(
            sgv: sgv,
            date: Decimal(date.timeIntervalSince1970 * 1000),
            dateString: date,
            noise: noise
        )
    }

    private func detect(_ glucose: [BloodGlucose]) -> (segments: [GlucoseSegment], cgmGaps: [DateInterval]) {
        ThresholdCrossingDetector.detect(
            in: glucose,
            highThreshold: highThreshold,
            windowStart: window.start,
            windowEnd: window.end
        )
    }

    // MARK: - TC-01: Single uninterrupted high segment

    func test_TC01_singleHighSegment() {
        // 10 readings at 5-min intervals, all above 180 mg/dL.
        let glucose = (0 ..< 10).map { i in
            makeGlucose(sgv: 190, at: TimeInterval(i * 5 * 60))
        }

        let (segments, _) = detect(glucose)

        XCTAssertEqual(segments.count, 1)
        let seg = segments[0]
        XCTAssertEqual(seg.durationMinutes, 9 * 5) // 45 min (first to last reading)
        XCTAssertEqual(seg.peakSgv, 190)
        XCTAssertEqual(seg.readings.count, 10)
    }

    // MARK: - TC-02: Brief in-range dip is consolidated (< 15 min gap)

    func test_TC02_consolidationBridgesShortInRangeGap() {
        // 8 above-threshold readings, then 2 in-range readings < 15 min apart, then 4 more above.
        var glucose: [BloodGlucose] = []
        // Above: t=0..35 (8 readings × 5 min)
        for i in 0 ..< 8 {
            glucose.append(makeGlucose(sgv: 200, at: TimeInterval(i * 5 * 60)))
        }
        // In-range gap: t=40, t=45 (2 readings, 10 min gap total — < 15 min)
        glucose.append(makeGlucose(sgv: 170, at: 40 * 60))
        glucose.append(makeGlucose(sgv: 175, at: 45 * 60))
        // Above: t=50..65 (4 readings × 5 min)
        for i in 0 ..< 4 {
            glucose.append(makeGlucose(sgv: 195, at: TimeInterval((50 + i * 5) * 60)))
        }

        let (segments, _) = detect(glucose)

        XCTAssertEqual(segments.count, 1, "Short in-range dip should be consolidated into one segment")
        XCTAssertGreaterThan(segments[0].durationMinutes, 45)
    }

    // MARK: - TC-03: Long in-range period splits into two events

    func test_TC03_longInRangeGapSplitsEvents() {
        var glucose: [BloodGlucose] = []
        // Above: t=0..15 (4 readings)
        for i in 0 ..< 4 {
            glucose.append(makeGlucose(sgv: 200, at: TimeInterval(i * 5 * 60)))
        }
        // In-range: t=20..35 (4 readings, 20-min gap — > 15 min)
        for i in 0 ..< 4 {
            glucose.append(makeGlucose(sgv: 150, at: TimeInterval((20 + i * 5) * 60)))
        }
        // Above: t=40..55 (4 readings)
        for i in 0 ..< 4 {
            glucose.append(makeGlucose(sgv: 210, at: TimeInterval((40 + i * 5) * 60)))
        }

        let (segments, _) = detect(glucose)

        XCTAssertEqual(segments.count, 2, "Long in-range gap should produce two separate segments")
    }

    // MARK: - TC-04: Invalid readings are excluded

    func test_TC04_invalidReadingsExcluded() {
        var glucose: [BloodGlucose] = []
        // Valid above-threshold readings
        glucose.append(makeGlucose(sgv: 200, at: 0))
        glucose.append(makeGlucose(sgv: 205, at: 5 * 60))
        glucose.append(makeGlucose(sgv: 200, at: 10 * 60))
        // Invalid: noise == 4 — should be excluded (cannot bridge gap)
        glucose.append(makeGlucose(sgv: 160, at: 15 * 60, noise: 4))
        // Valid above-threshold again — this should be a SEPARATE segment (gap > 15 min if invalid excluded)
        glucose.append(makeGlucose(sgv: 195, at: 30 * 60))
        glucose.append(makeGlucose(sgv: 190, at: 35 * 60))

        let (segments, _) = detect(glucose)

        // With the noise=4 reading excluded, the gap is 20 min → two separate segments.
        XCTAssertEqual(segments.count, 2)
        for seg in segments {
            for reading in seg.readings {
                XCTAssertTrue(reading.isStateValid, "Invalid readings must not appear in segments")
            }
        }
    }

    // MARK: - TC-05: CGM gap detection

    func test_TC05_cgmGapDetected() {
        var glucose: [BloodGlucose] = []
        glucose.append(makeGlucose(sgv: 150, at: 0))
        glucose.append(makeGlucose(sgv: 155, at: 5 * 60))
        // 15-min gap here (next reading at 20 min)
        glucose.append(makeGlucose(sgv: 160, at: 20 * 60))
        glucose.append(makeGlucose(sgv: 162, at: 25 * 60))

        let (_, gaps) = detect(glucose)

        XCTAssertEqual(gaps.count, 1)
        XCTAssertGreaterThan(gaps[0].duration, ThresholdCrossingDetector.cgmGapThresholdSeconds)
    }

    func test_TC05b_noGapWhenReadingsAreContinuous() {
        let glucose = (0 ..< 6).map { i in makeGlucose(sgv: 150, at: TimeInterval(i * 5 * 60)) }
        let (_, gaps) = detect(glucose)
        XCTAssertTrue(gaps.isEmpty)
    }

    // MARK: - TC-06: Window boundary filtering

    func test_TC06_readingsOutsideWindowIgnored() {
        var glucose: [BloodGlucose] = []
        // Before window
        glucose.append(makeGlucose(sgv: 200, at: -60 * 60))
        // Inside window
        glucose.append(makeGlucose(sgv: 200, at: 0))
        glucose.append(makeGlucose(sgv: 200, at: 5 * 60))
        glucose.append(makeGlucose(sgv: 200, at: 10 * 60))
        // After window (> 24 h)
        glucose.append(makeGlucose(sgv: 200, at: 25 * 60 * 60))

        let (segments, _) = detect(glucose)

        // Only the 3 in-window readings should be considered.
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].readings.count, 3)
    }

    // MARK: - TC-07: Empty input

    func test_TC07_emptyInputReturnsEmpty() {
        let (segments, gaps) = detect([])
        XCTAssertTrue(segments.isEmpty)
        XCTAssertTrue(gaps.isEmpty)
    }
}
