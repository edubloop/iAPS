@testable import FreeAPS
import XCTest

// TC-08 through TC-20 — TIRAnalysisEngine + EventClassifier unit tests.
// All tests are synchronous (pure functions).
class TIRAnalysisEngineTests: XCTestCase {
    // MARK: - Helpers

    /// Standard 14-day window anchored to a fixed reference date for reproducibility.
    private let windowEnd = Date(timeIntervalSinceReferenceDate: 800_000_000) // fixed
    private var windowStart: Date { windowEnd.addingTimeInterval(-14 * 86400) }

    private func makeConfig(
        highMgdL: Double = 180,
        lowMgdL: Double = 70,
        maxIOB: Double = 8.0
    ) -> TIRAnalysisConfiguration {
        TIRAnalysisConfiguration(
            highThresholdMgdL: highMgdL,
            lowThresholdMgdL: lowMgdL,
            maxIOB: maxIOB,
            windowStart: windowStart,
            windowEnd: windowEnd,
            units: .mmolL
        )
    }

    /// Build a BloodGlucose at a given offset (seconds) from windowStart.
    private func g(sgv: Int, offset: TimeInterval, noise: Int = 1) -> BloodGlucose {
        let date = windowStart.addingTimeInterval(offset)
        return BloodGlucose(
            sgv: sgv,
            date: Decimal(date.timeIntervalSince1970 * 1000),
            dateString: date,
            noise: noise
        )
    }

    /// Build a contiguous block of above-threshold readings.
    /// `start`: offset from windowStart. Interval: 5 min. Count: number of readings.
    private func highBlock(
        sgv: Int = 200,
        start: TimeInterval,
        count: Int
    ) -> [BloodGlucose] {
        (0 ..< count).map { i in g(sgv: sgv, offset: start + TimeInterval(i * 5 * 60)) }
    }

    private func makeInput(
        glucose: [BloodGlucose],
        carbs: [CarbsEntry]? = nil,
        pump: [PumpHistoryEvent]? = nil,
        iob: [IOBTick0]? = nil,
        config: TIRAnalysisConfiguration? = nil
    ) -> TIRAnalysisInput {
        TIRAnalysisInput(
            glucose: glucose,
            carbEntries: carbs,
            pumpHistory: pump,
            iobHistory: iob,
            configuration: config ?? makeConfig()
        )
    }

    private func analyze(_ input: TIRAnalysisInput) -> [TIREvent] {
        TIRAnalysisEngine.analyze(input)
    }

    // MARK: - TC-08: REBOUND_HIGH detection

    func test_TC08_reboundHigh() {
        var glucose: [BloodGlucose] = []
        // Low readings 30 min before the high event
        for i in 0 ..< 4 {
            glucose.append(g(sgv: 60, offset: TimeInterval(i * 5 * 60))) // t=0..15
        }
        // In-range transition (brief)
        glucose.append(g(sgv: 90, offset: 20 * 60))
        // High event starts at t=25
        glucose.append(contentsOf: highBlock(start: 25 * 60, count: 8))

        let events = analyze(makeInput(glucose: glucose, carbs: []))
        XCTAssertFalse(events.isEmpty, "Should detect at least one event")
        let highEvent = events.first(where: { $0.type == "high" })!
        XCTAssertEqual(highEvent.category, .reboundHigh)
        XCTAssertEqual(highEvent.confidence, .high)
        XCTAssertEqual(highEvent.contributingFactors.first?.factor, "Recent low before rebound")
    }

    // MARK: - TC-09: POST_CONNECTIVITY_GAP detection

    func test_TC09_postConnectivityGap() {
        var glucose: [BloodGlucose] = []
        // Normal readings, then a 15-min gap (no readings t=60..75), then high
        for i in 0 ..< 12 {
            glucose.append(g(sgv: 140, offset: TimeInterval(i * 5 * 60))) // t=0..55
        }
        // Gap of 15 min (60..75 — no readings)
        // High readings starting at t=76 (within 30 min of gap end at ~75)
        glucose.append(contentsOf: highBlock(start: 76 * 60, count: 8))

        let events = analyze(makeInput(glucose: glucose, carbs: []))
        XCTAssertFalse(events.isEmpty)
        let highEvent = events.first!
        XCTAssertEqual(highEvent.category, .postConnectivityGap)
        XCTAssertEqual(highEvent.confidence, .high)
        XCTAssertEqual(highEvent.contributingFactors.first?.factor, "Recent CGM data gap")
    }

    // MARK: - TC-10: CONSTRAINT_LIMITED with IOB at ceiling

    func test_TC10_constraintLimited_withIOBData() {
        // 4-hour high event
        let highReadings = highBlock(start: 0, count: 48) // 48 × 5 min = 4 hr
        let eventStart = windowStart
        let maxIOB = 8.0

        // IOB history: 60% of ticks at ceiling (>= 7.6 = 8.0 * 0.95)
        var iobHistory: [IOBTick0] = []
        for i in 0 ..< 48 {
            let t = eventStart.addingTimeInterval(TimeInterval(i * 5 * 60))
            let iobValue: Decimal = i % 5 == 0 ? Decimal(7.0) : Decimal(7.7) // ~80% at ceiling
            iobHistory.append(IOBTick0(time: t, iob: iobValue, activity: 0))
        }

        let events = analyze(makeInput(
            glucose: highReadings,
            carbs: [],
            pump: nil,
            iob: iobHistory,
            config: makeConfig(maxIOB: maxIOB)
        ))

        XCTAssertFalse(events.isEmpty)
        XCTAssertEqual(events[0].category, .constraintLimited)
        XCTAssertEqual(events[0].confidence, .high)
        XCTAssertEqual(events[0].contributingFactors.first?.factor, "Max IOB ceiling reached")
    }

    // MARK: - TC-11: CONSTRAINT_LIMITED skipped when IOB is nil → falls through

    func test_TC11_constraintLimitedSkipped_whenIOBNil() {
        // 4-hour high event, no carbs in window → should fall to RISING_WITHOUT_CARBS
        let highReadings = highBlock(start: 0, count: 48)
        let events = analyze(makeInput(
            glucose: highReadings,
            carbs: [], // empty but non-nil → RISING_WITHOUT_CARBS high confidence
            pump: nil,
            iob: nil // IOB missing → skip CONSTRAINT_LIMITED
        ))

        XCTAssertFalse(events.isEmpty)
        XCTAssertEqual(events[0].category, .risingWithoutCarbs)
    }

    // MARK: - TC-12: RISING_WITHOUT_CARBS with carb stream available (no carbs found)

    func test_TC12_risingWithoutCarbs_carbStreamPresent_noRecentCarbs() {
        let highReadings = highBlock(start: 5 * 60 * 60, count: 12) // starts at t=5h, 1h event
        // A carb entry 6 hours before event start — outside the 4h lookback window
        let carbDate = windowStart.addingTimeInterval(5 * 60 * 60 - 6 * 60 * 60)
        let oldCarb = CarbsEntry(
            id: nil, createdAt: carbDate, actualDate: nil,
            carbs: 40, fat: nil, protein: nil, note: nil, enteredBy: nil, isFPU: false
        )

        let events = analyze(makeInput(glucose: highReadings, carbs: [oldCarb]))

        XCTAssertFalse(events.isEmpty)
        XCTAssertEqual(events[0].category, .risingWithoutCarbs)
        XCTAssertEqual(events[0].confidence, .high)
    }

    // MARK: - TC-13: RISING_WITHOUT_CARBS confidence is low when carb stream is nil

    func test_TC13_risingWithoutCarbs_carbStreamNil_confidenceLow() {
        // 3-hour event (just at PERSISTENT_ELEVATION threshold), carbs = nil
        // RISING_WITHOUT_CARBS fires before PERSISTENT_ELEVATION in priority
        let highReadings = highBlock(start: 0, count: 24) // 2h — below PE threshold
        let events = analyze(makeInput(glucose: highReadings, carbs: nil, iob: nil))

        XCTAssertFalse(events.isEmpty)
        XCTAssertEqual(events[0].category, .risingWithoutCarbs)
        XCTAssertEqual(events[0].confidence, .low)
    }

    // MARK: - TC-14: PERSISTENT_ELEVATION with SMBs present

    func test_TC14_persistentElevation_withSMBs() {
        // 4-hour event, carbs present (so RISING_WITHOUT_CARBS doesn't fire)
        let eventStartOffset: TimeInterval = 0
        let highReadings = highBlock(start: eventStartOffset, count: 48)
        let eventStart = windowStart.addingTimeInterval(eventStartOffset)

        // Carb entry 1h before event (within 4h window → cancels RISING_WITHOUT_CARBS)
        let carbDate = windowStart.addingTimeInterval(eventStartOffset - 60 * 60)
        let carb = CarbsEntry(
            id: nil, createdAt: carbDate, actualDate: nil,
            carbs: 30, fat: nil, protein: nil, note: nil, enteredBy: nil, isFPU: false
        )

        // SMB bolus during the event
        let smb = PumpHistoryEvent(
            id: "smb1",
            type: .smb,
            timestamp: eventStart.addingTimeInterval(30 * 60),
            isSMB: true
        )

        let events = analyze(makeInput(glucose: highReadings, carbs: [carb], pump: [smb], iob: nil))

        XCTAssertFalse(events.isEmpty)
        XCTAssertEqual(events[0].category, .persistentElevation)
        XCTAssertEqual(events[0].confidence, .high)
        XCTAssertEqual(events[0].contributingFactors.first?.factor, "Automated correction activity observed")
    }

    // MARK: - TC-15: UNCLASSIFIED_HIGH for short events

    func test_TC15_unclassifiedHigh_shortEvent() {
        // 90-min event (below 3h PE threshold), no carbs, no gap, no IOB, no rebound
        let highReadings = highBlock(start: 4 * 60 * 60, count: 18) // 90 min, starts well after window start

        let events = analyze(makeInput(
            glucose: highReadings,
            carbs: [ // A carb entry within 4h window → RISING_WITHOUT_CARBS doesn't fire
                CarbsEntry(
                    id: nil,
                    createdAt: windowStart.addingTimeInterval(3 * 60 * 60),
                    actualDate: nil, carbs: 20,
                    fat: nil, protein: nil, note: nil, enteredBy: nil, isFPU: false
                )
            ],
            pump: nil,
            iob: nil
        ))

        XCTAssertFalse(events.isEmpty)
        XCTAssertEqual(events[0].category, .unclassifiedHigh)
    }

    // MARK: - TC-16: Stable ID reproducibility

    func test_TC16_stableID_reproducible() {
        let readings = highBlock(start: 0, count: 6)
        let input = makeInput(glucose: readings, carbs: [])
        let run1 = analyze(input)
        let run2 = analyze(input)

        XCTAssertFalse(run1.isEmpty)
        XCTAssertEqual(run1.map(\.id), run2.map(\.id), "IDs must be deterministic across reruns")
    }

    // MARK: - TC-17: Stable ID uniqueness for distinct events

    func test_TC17_stableID_uniqueForDistinctEvents() {
        var readings: [BloodGlucose] = []
        // Three separate high events with > 15 min in-range gaps between them
        readings += highBlock(start: 0, count: 4)
        readings += (0 ..< 4).map { g(sgv: 140, offset: TimeInterval((25 + $0 * 5) * 60)) } // in-range
        readings += highBlock(start: 50 * 60, count: 4)
        readings += (0 ..< 4).map { g(sgv: 140, offset: TimeInterval((75 + $0 * 5) * 60)) } // in-range
        readings += highBlock(start: 100 * 60, count: 4)

        let events = analyze(makeInput(glucose: readings, carbs: []))

        XCTAssertEqual(events.count, 3, "Should detect 3 separate events")
        let ids = events.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "All event IDs must be unique")
    }

    // MARK: - TC-18: tirCost calculation

    func test_TC18_tirCostCalculation() {
        // Single 60-minute high event in a 14-day window.
        let highReadings = highBlock(start: 0, count: 12) // 12 × 5 min = 60 min
        let events = analyze(makeInput(glucose: highReadings, carbs: []))

        XCTAssertEqual(events.count, 1)
        let windowMinutes = 14.0 * 24.0 * 60.0
        let expectedCost = 55.0 / windowMinutes // first→last reading span = 11 intervals × 5 min = 55 min
        XCTAssertEqual(events[0].tirCost, expectedCost, accuracy: 0.0001)
    }

    // MARK: - TC-19: Fixture JSON round-trip (Track 0 contract alignment)

    func test_TC19_fixtureRoundTrip() throws {
        let fixtureJSON = """
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
        """
        let data = fixtureJSON.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let event = try decoder.decode(TIREvent.self, from: data)

        XCTAssertEqual(event.id, "evt_20260301T0940Z_001")
        XCTAssertEqual(event.type, "high")
        XCTAssertEqual(event.peakSeverity, 212)
        XCTAssertEqual(event.durationMinutes, 45)
        XCTAssertEqual(event.tirCost, 0.22, accuracy: 0.001)
        XCTAssertEqual(event.category, .persistentElevation)
        XCTAssertEqual(event.confidence, .high)
        XCTAssertTrue(event.contributingFactors.isEmpty)
    }

    // MARK: - TC-20: Peak severity is always stored in mg/dL

    func test_TC20_peakSeverityInMgdL() {
        // Readings with known sgv values
        var readings: [BloodGlucose] = []
        readings.append(g(sgv: 190, offset: 0))
        readings.append(g(sgv: 220, offset: 5 * 60)) // peak
        readings.append(g(sgv: 210, offset: 10 * 60))

        let events = analyze(makeInput(glucose: readings, carbs: [], config: makeConfig()))

        XCTAssertEqual(events.count, 1)
        // peakSeverity must equal the raw sgv value (220 mg/dL), not mmol/L (≈12.2)
        XCTAssertEqual(events[0].peakSeverity, 220)
    }
}
