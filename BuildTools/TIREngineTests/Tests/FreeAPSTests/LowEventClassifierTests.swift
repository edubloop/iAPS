import XCTest

@testable import FreeAPS

final class LowEventClassifierTests: XCTestCase {
    // MARK: - Test Helpers

    private let baseConfig = TIRAnalysisConfiguration.make(
        highMgdL: 180,
        lowMgdL: 70,
        maxIOB: 5.0
    )

    /// Build a sequence of BloodGlucose readings starting at `start`, 5-min apart.
    private func makeReadings(sgvs: [Int], start: Date) -> [BloodGlucose] {
        sgvs.enumerated().map { i, sgv in
            let ts = start.addingTimeInterval(Double(i) * 5 * 60)
            return BloodGlucose(
                _id: "r_\(i)",
                sgv: sgv,
                date: Decimal(ts.timeIntervalSince1970 * 1000),
                dateString: ts,
                noise: nil,
                glucose: sgv
            )
        }
    }

    /// Build a steady sequence of readings all at `sgv`.
    private func steadyReadings(sgv: Int, count: Int, start: Date) -> [BloodGlucose] {
        makeReadings(sgvs: Array(repeating: sgv, count: count), start: start)
    }

    private func makeContext(
        segmentStart: Date,
        segmentEnd: Date,
        nadir: Int,
        readings: [BloodGlucose],
        allGlucose: [BloodGlucose] = [],
        boluses: [InsulinEvent] = [],
        smbs: [InsulinEvent] = [],
        tempBasals: [TempBasalEvent] = [],
        carbEntries: [CarbsEntry]? = nil,
        exerciseEvents: [ExerciseEvent] = [],
        noiseLevel: Int? = nil
    ) -> LowEventContext {
        LowEventContext(
            segmentStart: segmentStart,
            segmentEnd: segmentEnd,
            nadir: nadir,
            readings: readings,
            allGlucose: allGlucose,
            configuration: baseConfig,
            bolusesInWindow: boluses,
            smbsInWindow: smbs,
            tempBasalsInWindow: tempBasals,
            carbEntries: carbEntries,
            exerciseEvents: exerciseEvents,
            noiseLevel: noiseLevel
        )
    }

    private func makeBolus(units: Double, minutesBefore: Double, segmentStart: Date, isSMB: Bool = false) -> InsulinEvent {
        InsulinEvent(
            timestamp: segmentStart.addingTimeInterval(-minutesBefore * 60),
            units: units,
            isSMB: isSMB,
            eventType: isSMB ? "SMB" : "Bolus"
        )
    }

    private func makeExercise(endMinutesBefore: Double, durationMinutes: Double = 60, segmentStart: Date) -> ExerciseEvent {
        let end = segmentStart.addingTimeInterval(-endMinutesBefore * 60)
        let start = end.addingTimeInterval(-durationMinutes * 60)
        return ExerciseEvent(start: start, end: end, source: .healthkit, notes: "Running")
    }

    private func makeHighReadings(count: Int, minutesBefore: Double, segmentStart: Date) -> [BloodGlucose] {
        let start = segmentStart.addingTimeInterval(-minutesBefore * 60)
        return makeReadings(sgvs: Array(repeating: 210, count: count), start: start)
    }

    // MARK: - COMPRESSION_LOW

    func test_compressionLow_fires_shortDurationRapidRecovery() {
        let now = Date()
        // Readings go low then recover: 69, 63, 69 (recovery rate = (69-63)/5min * 5 = 6 mg/dL per 5min)
        let start = now.addingTimeInterval(-10 * 60)
        let end = now
        let readings = makeReadings(sgvs: [69, 63, 69], start: start)

        let ctx = makeContext(
            segmentStart: start, segmentEnd: end,
            nadir: 63, readings: readings
        )
        let (category, confidence, _) = LowEventClassifier.classify(context: ctx)
        XCTAssertEqual(category, .compressionLow)
        XCTAssertEqual(confidence, .medium) // no elevated noise, not overnight
    }

    func test_compressionLow_highConfidence_withElevatedNoise() {
        let now = Date()
        let start = now.addingTimeInterval(-10 * 60)
        let end = now
        let readings = makeReadings(sgvs: [69, 63, 69], start: start)
        let ctx = makeContext(
            segmentStart: start, segmentEnd: end,
            nadir: 63, readings: readings,
            noiseLevel: 3
        )
        let (category, confidence, _) = LowEventClassifier.classify(context: ctx)
        XCTAssertEqual(category, .compressionLow)
        XCTAssertEqual(confidence, .high)
    }

    func test_compressionLow_doesNotFire_whenDurationTooLong() {
        let now = Date()
        // 35-min duration exceeds the 30-min max
        let start = now.addingTimeInterval(-35 * 60)
        let end = now
        // Build readings: first falls to nadir then recovers within the 35-min window
        let readings = makeReadings(sgvs: [68, 64, 63, 64, 68, 68, 68], start: start)
        let ctx = makeContext(
            segmentStart: start, segmentEnd: end,
            nadir: 63, readings: readings
        )
        let (category, _, _) = LowEventClassifier.classify(context: ctx)
        XCTAssertNotEqual(category, .compressionLow)
    }

    func test_compressionLow_doesNotFire_whenNadirTooLow() {
        let now = Date()
        let start = now.addingTimeInterval(-10 * 60)
        let end = now
        // Nadir = 50 < 54 minimum
        let readings = makeReadings(sgvs: [60, 50, 60], start: start)
        let ctx = makeContext(
            segmentStart: start, segmentEnd: end,
            nadir: 50, readings: readings
        )
        let (category, _, _) = LowEventClassifier.classify(context: ctx)
        XCTAssertNotEqual(category, .compressionLow)
    }

    func test_compressionLow_doesNotFire_withSignificantBolus() {
        let now = Date()
        let start = now.addingTimeInterval(-10 * 60)
        let end = now
        let readings = makeReadings(sgvs: [69, 63, 69], start: start)
        // 1.0U bolus 1h before — exceeds 0.5U compression threshold
        let boluses = [makeBolus(units: 1.0, minutesBefore: 60, segmentStart: start)]
        let ctx = makeContext(
            segmentStart: start, segmentEnd: end,
            nadir: 63, readings: readings, boluses: boluses
        )
        let (category, _, _) = LowEventClassifier.classify(context: ctx)
        XCTAssertNotEqual(category, .compressionLow)
    }

    // MARK: - OVERCORRECTION_LOW

    func test_overcorrectionLow_fires_withLargeBolus() {
        let now = Date()
        let start = now.addingTimeInterval(-25 * 60)
        let end = now
        let readings = steadyReadings(sgv: 65, count: 5, start: start)
        // 1.5U bolus 2h before (in the 1-4h window)
        let boluses = [makeBolus(units: 1.5, minutesBefore: 120, segmentStart: start)]
        let ctx = makeContext(
            segmentStart: start, segmentEnd: end,
            nadir: 63, readings: readings, boluses: boluses
        )
        let (category, _, factors) = LowEventClassifier.classify(context: ctx)
        XCTAssertEqual(category, .overcorrectionLow)
        XCTAssertFalse(factors.isEmpty)
    }

    func test_overcorrectionLow_highConfidence_whenCorrectionOnlyWithPriorHigh() {
        let now = Date()
        let start = now.addingTimeInterval(-25 * 60)
        let end = now
        let readings = steadyReadings(sgv: 65, count: 5, start: start)
        let boluses = [makeBolus(units: 2.0, minutesBefore: 120, segmentStart: start)]
        // Add prior high readings (within 4h before low start)
        let highReadings = makeHighReadings(count: 4, minutesBefore: 180, segmentStart: start)
        let ctx = makeContext(
            segmentStart: start, segmentEnd: end,
            nadir: 62, readings: readings,
            allGlucose: highReadings,
            boluses: boluses,
            carbEntries: [] // explicitly no carbs
        )
        let (category, confidence, _) = LowEventClassifier.classify(context: ctx)
        XCTAssertEqual(category, .overcorrectionLow)
        XCTAssertEqual(confidence, .high)
    }

    func test_overcorrectionLow_doesNotFire_withTooManyBolusEvents() {
        let now = Date()
        let start = now.addingTimeInterval(-25 * 60)
        let end = now
        let readings = steadyReadings(sgv: 65, count: 5, start: start)
        // 3 bolus events exceeds the max of 2
        let boluses = [
            makeBolus(units: 0.6, minutesBefore: 60, segmentStart: start),
            makeBolus(units: 0.6, minutesBefore: 90, segmentStart: start),
            makeBolus(units: 0.6, minutesBefore: 120, segmentStart: start)
        ]
        let ctx = makeContext(
            segmentStart: start, segmentEnd: end,
            nadir: 63, readings: readings, boluses: boluses
        )
        let (category, _, _) = LowEventClassifier.classify(context: ctx)
        XCTAssertNotEqual(category, .overcorrectionLow)
    }

    func test_overcorrectionLow_doesNotFire_withTooSmallBolus() {
        let now = Date()
        let start = now.addingTimeInterval(-25 * 60)
        let end = now
        let readings = steadyReadings(sgv: 65, count: 5, start: start)
        // 0.8U < 1.0U minimum
        let boluses = [makeBolus(units: 0.8, minutesBefore: 120, segmentStart: start)]
        let ctx = makeContext(
            segmentStart: start, segmentEnd: end,
            nadir: 63, readings: readings, boluses: boluses
        )
        let (category, _, _) = LowEventClassifier.classify(context: ctx)
        XCTAssertNotEqual(category, .overcorrectionLow)
    }

    // MARK: - STACKING_LOW

    func test_stackingLow_fires_withThreeSMBsInSixtyMinutes() {
        let now = Date()
        let start = now.addingTimeInterval(-25 * 60)
        let end = now
        let readings = steadyReadings(sgv: 65, count: 5, start: start)
        let smbs = [
            makeBolus(units: 0.35, minutesBefore: 50, segmentStart: start, isSMB: true),
            makeBolus(units: 0.35, minutesBefore: 30, segmentStart: start, isSMB: true),
            makeBolus(units: 0.35, minutesBefore: 10, segmentStart: start, isSMB: true)
        ]
        let ctx = makeContext(
            segmentStart: start, segmentEnd: end,
            nadir: 62, readings: readings, smbs: smbs
        )
        let (category, confidence, _) = LowEventClassifier.classify(context: ctx)
        XCTAssertEqual(category, .stackingLow)
        XCTAssertEqual(confidence, .high)
    }

    func test_stackingLow_fires_withTwoBolusesInNinetyMinutes() {
        let now = Date()
        let start = now.addingTimeInterval(-25 * 60)
        let end = now
        let readings = steadyReadings(sgv: 65, count: 5, start: start)
        // 2 non-SMB boluses in 90-min window, total 0.9U < 1.0U overcorrectionLow threshold.
        // overcorrectionLow requires total >= 1.0U, so these avoid that check and hit stackingLow.
        let boluses = [
            makeBolus(units: 0.45, minutesBefore: 80, segmentStart: start),
            makeBolus(units: 0.45, minutesBefore: 40, segmentStart: start)
        ]
        let ctx = makeContext(
            segmentStart: start, segmentEnd: end,
            nadir: 62, readings: readings, boluses: boluses
        )
        let (category, confidence, _) = LowEventClassifier.classify(context: ctx)
        XCTAssertEqual(category, .stackingLow)
        XCTAssertEqual(confidence, .high)
    }

    func test_stackingLow_doesNotFire_withTwoSMBsOnly() {
        let now = Date()
        let start = now.addingTimeInterval(-25 * 60)
        let end = now
        let readings = steadyReadings(sgv: 65, count: 5, start: start)
        let smbs = [
            makeBolus(units: 0.35, minutesBefore: 40, segmentStart: start, isSMB: true),
            makeBolus(units: 0.35, minutesBefore: 20, segmentStart: start, isSMB: true)
        ]
        let ctx = makeContext(
            segmentStart: start, segmentEnd: end,
            nadir: 62, readings: readings, smbs: smbs
        )
        let (category, _, _) = LowEventClassifier.classify(context: ctx)
        XCTAssertNotEqual(category, .stackingLow)
    }

    // MARK: - ACTIVITY_RELATED_LOW

    func test_activityRelatedLow_fires_withExerciseWithinFourHours() {
        let now = Date()
        let start = now.addingTimeInterval(-25 * 60)
        let end = now
        let readings = steadyReadings(sgv: 65, count: 5, start: start)
        let exercise = [makeExercise(endMinutesBefore: 60, segmentStart: start)]
        let ctx = makeContext(
            segmentStart: start, segmentEnd: end,
            nadir: 62, readings: readings,
            exerciseEvents: exercise
        )
        let (category, confidence, _) = LowEventClassifier.classify(context: ctx)
        XCTAssertEqual(category, .activityRelatedLow)
        XCTAssertEqual(confidence, .high)
    }

    func test_activityRelatedLow_doesNotFire_withoutExercise() {
        let now = Date()
        let start = now.addingTimeInterval(-25 * 60)
        let end = now
        let readings = steadyReadings(sgv: 65, count: 5, start: start)
        let ctx = makeContext(
            segmentStart: start, segmentEnd: end,
            nadir: 62, readings: readings
        )
        let (category, _, _) = LowEventClassifier.classify(context: ctx)
        XCTAssertNotEqual(category, .activityRelatedLow)
    }

    func test_activityRelatedLow_doesNotFire_whenExerciseTooFarBack() {
        let now = Date()
        let start = now.addingTimeInterval(-25 * 60)
        let end = now
        let readings = steadyReadings(sgv: 65, count: 5, start: start)
        // Exercise ended 5h ago — beyond the 4h window
        let exercise = [makeExercise(endMinutesBefore: 300, segmentStart: start)]
        let ctx = makeContext(
            segmentStart: start, segmentEnd: end,
            nadir: 62, readings: readings,
            exerciseEvents: exercise
        )
        let (category, _, _) = LowEventClassifier.classify(context: ctx)
        XCTAssertNotEqual(category, .activityRelatedLow)
    }

    // MARK: - REBOUND_LOW

    func test_reboundLow_fires_withPrecedingHigh() {
        let now = Date()
        let start = now.addingTimeInterval(-25 * 60)
        let end = now
        let readings = steadyReadings(sgv: 65, count: 5, start: start)
        // 3 high readings 60 min before the low
        let highReadings = makeHighReadings(count: 3, minutesBefore: 60, segmentStart: start)
        let ctx = makeContext(
            segmentStart: start, segmentEnd: end,
            nadir: 62, readings: readings,
            allGlucose: highReadings
        )
        let (category, confidence, _) = LowEventClassifier.classify(context: ctx)
        XCTAssertEqual(category, .reboundLow)
        XCTAssertEqual(confidence, .high) // >= 2 high readings
    }

    func test_reboundLow_mediumConfidence_withOneHighReading() {
        let now = Date()
        let start = now.addingTimeInterval(-25 * 60)
        let end = now
        let readings = steadyReadings(sgv: 65, count: 5, start: start)
        let highReadings = makeHighReadings(count: 1, minutesBefore: 60, segmentStart: start)
        let ctx = makeContext(
            segmentStart: start, segmentEnd: end,
            nadir: 62, readings: readings,
            allGlucose: highReadings
        )
        let (category, confidence, _) = LowEventClassifier.classify(context: ctx)
        XCTAssertEqual(category, .reboundLow)
        XCTAssertEqual(confidence, .medium)
    }

    func test_reboundLow_doesNotFire_whenHighTooFarBack() {
        let now = Date()
        let start = now.addingTimeInterval(-25 * 60)
        let end = now
        let readings = steadyReadings(sgv: 65, count: 5, start: start)
        // High readings 2h before — beyond 90-min window
        let highReadings = makeHighReadings(count: 3, minutesBefore: 120, segmentStart: start)
        let ctx = makeContext(
            segmentStart: start, segmentEnd: end,
            nadir: 62, readings: readings,
            allGlucose: highReadings
        )
        let (category, _, _) = LowEventClassifier.classify(context: ctx)
        XCTAssertNotEqual(category, .reboundLow)
    }

    // MARK: - BASAL_TOO_AGGRESSIVE

    func test_basalTooAggressive_fires_noBolusNoCarbs() {
        let now = Date()
        // Long enough to not be compression-like, no insulin or carbs
        let start = now.addingTimeInterval(-40 * 60)
        let end = now
        let readings = steadyReadings(sgv: 65, count: 8, start: start)
        let ctx = makeContext(
            segmentStart: start, segmentEnd: end,
            nadir: 62, readings: readings,
            carbEntries: [] // explicitly no carbs
        )
        let (category, _, _) = LowEventClassifier.classify(context: ctx)
        XCTAssertEqual(category, .basalTooAggressive)
    }

    func test_basalTooAggressive_doesNotFire_withSignificantBolus() {
        let now = Date()
        let start = now.addingTimeInterval(-40 * 60)
        let end = now
        let readings = steadyReadings(sgv: 65, count: 8, start: start)
        // 0.6U bolus 2h before — exceeds 0.5U threshold
        let boluses = [makeBolus(units: 0.6, minutesBefore: 120, segmentStart: start)]
        let ctx = makeContext(
            segmentStart: start, segmentEnd: end,
            nadir: 62, readings: readings, boluses: boluses,
            carbEntries: []
        )
        let (category, _, _) = LowEventClassifier.classify(context: ctx)
        XCTAssertNotEqual(category, .basalTooAggressive)
    }

    // MARK: - FALLING_WITHOUT_ACTIVE_INSULIN

    func test_fallingWithoutActiveInsulin_fires_noRecentInsulinOrCarbs() {
        let now = Date()
        // 20-min duration (below 45 min for persistent), nadir >= 54
        let start = now.addingTimeInterval(-20 * 60)
        let end = now
        let readings = steadyReadings(sgv: 65, count: 4, start: start)
        // Bolus was 80 min ago (outside 75-min window)
        let boluses = [makeBolus(units: 0.6, minutesBefore: 80, segmentStart: start)]
        let ctx = makeContext(
            segmentStart: start, segmentEnd: end,
            nadir: 60, readings: readings, boluses: boluses,
            carbEntries: []
        )
        let (category, confidence, _) = LowEventClassifier.classify(context: ctx)
        XCTAssertEqual(category, .fallingWithoutActiveInsulin)
        XCTAssertEqual(confidence, .medium)
    }

    func test_fallingWithoutActiveInsulin_doesNotFire_withNadirBelowThreshold() {
        let now = Date()
        let start = now.addingTimeInterval(-20 * 60)
        let end = now
        let readings = steadyReadings(sgv: 50, count: 4, start: start)
        let ctx = makeContext(
            segmentStart: start, segmentEnd: end,
            nadir: 50, readings: readings // nadir < 54
        )
        let (category, _, _) = LowEventClassifier.classify(context: ctx)
        XCTAssertNotEqual(category, .fallingWithoutActiveInsulin)
    }

    // MARK: - PERSISTENT_LOW

    func test_persistentLow_fires_withLongDurationAndSomeInsulin() {
        let now = Date()
        // 50-min duration (>= 45 min)
        let start = now.addingTimeInterval(-50 * 60)
        let end = now
        let readings = steadyReadings(sgv: 65, count: 10, start: start)
        // 0.6U bolus 30 min before — prevents basalTooAggressive and fallingWithoutActiveInsulin
        // but too small for overcorrectionLow (< 1.0U)
        let boluses = [makeBolus(units: 0.6, minutesBefore: 30, segmentStart: start)]
        let ctx = makeContext(
            segmentStart: start, segmentEnd: end,
            nadir: 62, readings: readings, boluses: boluses,
            carbEntries: []
        )
        let (category, _, _) = LowEventClassifier.classify(context: ctx)
        XCTAssertEqual(category, .persistentLow)
    }

    func test_persistentLow_doesNotFire_withShortDuration() {
        let now = Date()
        // 30-min duration < 45 min
        let start = now.addingTimeInterval(-30 * 60)
        let end = now
        let readings = steadyReadings(sgv: 65, count: 6, start: start)
        let boluses = [makeBolus(units: 0.6, minutesBefore: 30, segmentStart: start)]
        let ctx = makeContext(
            segmentStart: start, segmentEnd: end,
            nadir: 62, readings: readings, boluses: boluses,
            carbEntries: []
        )
        let (category, _, _) = LowEventClassifier.classify(context: ctx)
        XCTAssertNotEqual(category, .persistentLow)
    }

    func test_persistentLow_highConfidence_whenNadirBelow54() {
        let now = Date()
        let start = now.addingTimeInterval(-50 * 60)
        let end = now
        let readings = steadyReadings(sgv: 50, count: 10, start: start)
        let boluses = [makeBolus(units: 0.6, minutesBefore: 30, segmentStart: start)]
        let ctx = makeContext(
            segmentStart: start, segmentEnd: end,
            nadir: 50, readings: readings, boluses: boluses,
            carbEntries: []
        )
        let (category, confidence, _) = LowEventClassifier.classify(context: ctx)
        XCTAssertEqual(category, .persistentLow)
        XCTAssertEqual(confidence, .high)
    }

    // MARK: - UNCLASSIFIED_LOW (catch-all)

    func test_unclassifiedLow_whenNoOtherCategoryMatches() {
        let now = Date()
        // nadir < 54 (prevents compression, fallingWithoutActiveInsulin)
        // duration < 45 min (prevents persistentLow)
        // bolus 0.6U (prevents basalTooAggressive (total >= 0.5U), prevents overcorrection (< 1.0U))
        // no SMBs, no exercise, no prior high
        let start = now.addingTimeInterval(-20 * 60)
        let end = now
        let readings = steadyReadings(sgv: 45, count: 4, start: start)
        let boluses = [makeBolus(units: 0.6, minutesBefore: 60, segmentStart: start)]
        let ctx = makeContext(
            segmentStart: start, segmentEnd: end,
            nadir: 45, readings: readings, boluses: boluses,
            carbEntries: []
        )
        let (category, _, _) = LowEventClassifier.classify(context: ctx)
        XCTAssertEqual(category, .unclassifiedLow)
    }

    // MARK: - Priority ordering

    func test_stackingBeatsActivity_whenBothPresent() {
        let now = Date()
        let start = now.addingTimeInterval(-25 * 60)
        let end = now
        let readings = steadyReadings(sgv: 65, count: 5, start: start)
        // 3 SMBs (stacking, priority 3) + exercise (activity, priority 4) — stacking wins
        let smbs = [
            makeBolus(units: 0.35, minutesBefore: 50, segmentStart: start, isSMB: true),
            makeBolus(units: 0.35, minutesBefore: 30, segmentStart: start, isSMB: true),
            makeBolus(units: 0.35, minutesBefore: 10, segmentStart: start, isSMB: true)
        ]
        let exercise = [makeExercise(endMinutesBefore: 60, segmentStart: start)]
        let ctx = makeContext(
            segmentStart: start, segmentEnd: end,
            nadir: 62, readings: readings,
            smbs: smbs, exerciseEvents: exercise
        )
        let (category, _, _) = LowEventClassifier.classify(context: ctx)
        XCTAssertEqual(category, .stackingLow)
    }

    func test_activityBeatsRebound_whenBothPresent() {
        let now = Date()
        let start = now.addingTimeInterval(-25 * 60)
        let end = now
        let readings = steadyReadings(sgv: 65, count: 5, start: start)
        // Exercise (priority 4) + prior high (rebound, priority 5) — activity wins
        let exercise = [makeExercise(endMinutesBefore: 60, segmentStart: start)]
        let highReadings = makeHighReadings(count: 3, minutesBefore: 70, segmentStart: start)
        let ctx = makeContext(
            segmentStart: start, segmentEnd: end,
            nadir: 62, readings: readings,
            allGlucose: highReadings,
            exerciseEvents: exercise
        )
        let (category, _, _) = LowEventClassifier.classify(context: ctx)
        XCTAssertEqual(category, .activityRelatedLow)
    }

    func test_reboundBeatsBasal_whenBothCouldApply() {
        let now = Date()
        let start = now.addingTimeInterval(-25 * 60)
        let end = now
        let readings = steadyReadings(sgv: 65, count: 5, start: start)
        // Prior high within 90 min (rebound, priority 5) + no insulin/carbs (basal, priority 6)
        let highReadings = makeHighReadings(count: 3, minutesBefore: 60, segmentStart: start)
        let ctx = makeContext(
            segmentStart: start, segmentEnd: end,
            nadir: 62, readings: readings,
            allGlucose: highReadings,
            carbEntries: []
        )
        let (category, _, _) = LowEventClassifier.classify(context: ctx)
        XCTAssertEqual(category, .reboundLow)
    }

    // MARK: - Graceful degradation

    func test_emptyInsulinArrays_doesNotCrash() {
        let now = Date()
        let start = now.addingTimeInterval(-25 * 60)
        let end = now
        let readings = steadyReadings(sgv: 65, count: 5, start: start)
        let ctx = makeContext(
            segmentStart: start, segmentEnd: end,
            nadir: 62, readings: readings
            // boluses and smbs default to []
        )
        // Should not crash; overcorrectionLow and stackingLow are skipped gracefully
        let (category, _, _) = LowEventClassifier.classify(context: ctx)
        XCTAssertNotEqual(category, .overcorrectionLow)
        XCTAssertNotEqual(category, .stackingLow)
    }

    func test_nilCarbEntries_doesNotCrash() {
        let now = Date()
        let start = now.addingTimeInterval(-25 * 60)
        let end = now
        let readings = steadyReadings(sgv: 65, count: 5, start: start)
        let ctx = makeContext(
            segmentStart: start, segmentEnd: end,
            nadir: 62, readings: readings,
            carbEntries: nil // explicit nil
        )
        _ = LowEventClassifier.classify(context: ctx)
        // Just verify no crash
    }

    func test_emptyReadings_doesNotCrash() {
        let now = Date()
        let start = now.addingTimeInterval(-25 * 60)
        let end = now
        let ctx = makeContext(
            segmentStart: start, segmentEnd: end,
            nadir: 65, readings: [] // empty readings
        )
        _ = LowEventClassifier.classify(context: ctx)
    }

    // MARK: - Feature extraction

    func test_extractFeatures_correctNadir() {
        let now = Date()
        let start = now.addingTimeInterval(-25 * 60)
        let end = now
        let readings = steadyReadings(sgv: 65, count: 5, start: start)
        let ctx = makeContext(
            segmentStart: start, segmentEnd: end,
            nadir: 55, readings: readings
        )
        let features = LowEventClassifier.extractFeatures(context: ctx, category: .unclassifiedLow)
        XCTAssertEqual(features.nadirMgdL, 55)
    }

    func test_extractFeatures_correctDuration() {
        let now = Date()
        let start = now.addingTimeInterval(-30 * 60) // 30 minutes ago
        let end = now
        let readings = steadyReadings(sgv: 65, count: 6, start: start)
        let ctx = makeContext(
            segmentStart: start, segmentEnd: end,
            nadir: 62, readings: readings
        )
        let features = LowEventClassifier.extractFeatures(context: ctx, category: .unclassifiedLow)
        XCTAssertEqual(features.durationMinutes, 30)
    }

    func test_extractFeatures_countsSMBsInOneHour() {
        let now = Date()
        let start = now.addingTimeInterval(-25 * 60)
        let end = now
        let readings = steadyReadings(sgv: 65, count: 5, start: start)
        let smbs = [
            makeBolus(units: 0.35, minutesBefore: 50, segmentStart: start, isSMB: true), // within 1h
            makeBolus(units: 0.35, minutesBefore: 30, segmentStart: start, isSMB: true), // within 1h
            makeBolus(units: 0.35, minutesBefore: 70, segmentStart: start, isSMB: true) // outside 1h
        ]
        let ctx = makeContext(
            segmentStart: start, segmentEnd: end,
            nadir: 62, readings: readings, smbs: smbs
        )
        let features = LowEventClassifier.extractFeatures(context: ctx, category: .stackingLow)
        XCTAssertEqual(features.smbCount1h, 2) // only 2 within 60 min
    }

    func test_extractFeatures_exerciseInLookback() {
        let now = Date()
        let start = now.addingTimeInterval(-25 * 60)
        let end = now
        let readings = steadyReadings(sgv: 65, count: 5, start: start)
        let exercise = [makeExercise(endMinutesBefore: 60, segmentStart: start)]
        let ctx = makeContext(
            segmentStart: start, segmentEnd: end,
            nadir: 62, readings: readings,
            exerciseEvents: exercise
        )
        let features = LowEventClassifier.extractFeatures(context: ctx, category: .activityRelatedLow)
        XCTAssertTrue(features.exerciseInLookback)
    }

    func test_extractFeatures_noExercise() {
        let now = Date()
        let start = now.addingTimeInterval(-25 * 60)
        let end = now
        let readings = steadyReadings(sgv: 65, count: 5, start: start)
        let ctx = makeContext(
            segmentStart: start, segmentEnd: end,
            nadir: 62, readings: readings
        )
        let features = LowEventClassifier.extractFeatures(context: ctx, category: .unclassifiedLow)
        XCTAssertFalse(features.exerciseInLookback)
    }

    // MARK: - totalBolusInWindow helper

    func test_totalBolusInWindow_sumsCorrectly() {
        let now = Date()
        let from = now.addingTimeInterval(-4 * 3600)
        let to = now
        let events = [
            InsulinEvent(timestamp: now.addingTimeInterval(-3600), units: 1.0, isSMB: false, eventType: "Bolus"),
            InsulinEvent(timestamp: now.addingTimeInterval(-1800), units: 0.5, isSMB: true, eventType: "SMB"),
            InsulinEvent(
                timestamp: now.addingTimeInterval(-5 * 3600),
                units: 2.0,
                isSMB: false,
                eventType: "Bolus"
            ) // outside window
        ]
        let total = LowEventClassifier.totalBolusInWindow(boluses: [events[0]], smbs: [events[1]], from: from, to: to)
        XCTAssertEqual(total, 1.5, accuracy: 0.001)
    }

    func test_totalBolusInWindow_emptyArrays_returnsZero() {
        let now = Date()
        let total = LowEventClassifier.totalBolusInWindow(
            boluses: [], smbs: [],
            from: now.addingTimeInterval(-3600), to: now
        )
        XCTAssertEqual(total, 0.0)
    }

    // MARK: - Rate helpers

    func test_computeRateOfRecovery_positiveWhenRising() {
        let now = Date()
        let start = now.addingTimeInterval(-10 * 60)
        // Readings: 69 → 63 → 69 (nadir in middle, recovers)
        let readings = makeReadings(sgvs: [69, 63, 69], start: start)
        let ctx = makeContext(
            segmentStart: start, segmentEnd: now,
            nadir: 63, readings: readings
        )
        let rate = LowEventClassifier.computeRateOfRecovery(context: ctx)
        XCTAssertGreaterThan(rate, 0, "Recovery rate should be positive when glucose rises after nadir")
        XCTAssertGreaterThanOrEqual(rate, LowEventClassifier.compressionMinRecoveryRatePerFiveMin)
    }

    func test_computeRateOfFall_positiveWhenFalling() {
        let now = Date()
        let start = now.addingTimeInterval(-10 * 60)
        // Readings: 80 → 70 → 63 (falling)
        let readings = makeReadings(sgvs: [80, 70, 63], start: start)
        let ctx = makeContext(
            segmentStart: start, segmentEnd: now,
            nadir: 63, readings: readings
        )
        let rate = LowEventClassifier.computeRateOfFall(context: ctx)
        XCTAssertGreaterThan(rate, 0, "Rate of fall should be positive when glucose drops")
    }

    func test_computeRateOfFall_zeroWithSingleReading() {
        let now = Date()
        let readings = [BloodGlucose(
            _id: "r0", sgv: 63,
            date: Decimal(now.timeIntervalSince1970 * 1000),
            dateString: now, glucose: 63
        )]
        let ctx = makeContext(
            segmentStart: now, segmentEnd: now.addingTimeInterval(5 * 60),
            nadir: 63, readings: readings
        )
        let rate = LowEventClassifier.computeRateOfFall(context: ctx)
        XCTAssertEqual(rate, 0.0)
    }
}
