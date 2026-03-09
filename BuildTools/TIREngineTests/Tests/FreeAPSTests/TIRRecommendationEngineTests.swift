import XCTest

@testable import FreeAPS

final class TIRRecommendationEngineTests: XCTestCase {
    // MARK: - Helpers

    private func makePattern(
        category: TIREventCategory,
        eventCount: Int,
        overnight: Int = 0,
        morning: Int = 0,
        afternoon: Int = 0,
        evening: Int = 0
    ) -> TIRCategoryPattern {
        TIRCategoryPattern(
            category: category,
            eventCount: eventCount,
            tirCost: Double(eventCount) * 0.01,
            timeOfDayBuckets: TimeOfDayBuckets(
                overnight: overnight,
                morning: morning,
                afternoon: afternoon,
                evening: evening
            ),
            recurrenceDays: min(eventCount, 7)
        )
    }

    // MARK: - Threshold tests

    func test_zeroEvents_noRecommendation() {
        let pattern = makePattern(category: .reboundHigh, eventCount: 0)
        let recs = TIRRecommendationEngine.recommend(patterns: [pattern])
        XCTAssertTrue(recs.isEmpty)
    }

    func test_oneEvent_noRecommendation() {
        let pattern = makePattern(category: .reboundHigh, eventCount: 1)
        let recs = TIRRecommendationEngine.recommend(patterns: [pattern])
        XCTAssertTrue(recs.isEmpty)
    }

    func test_twoEvents_noRecommendation() {
        let pattern = makePattern(category: .reboundHigh, eventCount: 2)
        let recs = TIRRecommendationEngine.recommend(patterns: [pattern])
        XCTAssertTrue(recs.isEmpty)
    }

    func test_threeEvents_producesRecommendation() {
        let pattern = makePattern(category: .reboundHigh, eventCount: 3)
        let recs = TIRRecommendationEngine.recommend(patterns: [pattern])
        XCTAssertEqual(recs.count, 1)
        XCTAssertEqual(recs[0].category, .reboundHigh)
    }

    func test_fourEvents_producesRecommendation() {
        let pattern = makePattern(category: .persistentLow, eventCount: 4)
        let recs = TIRRecommendationEngine.recommend(patterns: [pattern])
        XCTAssertEqual(recs.count, 1)
    }

    // MARK: - Category coverage tests

    func test_allPatternedCategories_produceRecommendations() {
        let categories: [TIREventCategory] = [
            // High categories
            .postConnectivityGap, .reboundHigh, .risingWithoutCarbs,
            .constraintLimited, .persistentElevation,
            // Low categories
            .compressionLow, .overcorrectionLow, .stackingLow, .activityRelatedLow,
            .reboundLow, .basalTooAggressive, .persistentLow, .fallingWithoutActiveInsulin
        ]
        for category in categories {
            let pattern = makePattern(category: category, eventCount: 3)
            let recs = TIRRecommendationEngine.recommend(patterns: [pattern])
            XCTAssertEqual(recs.count, 1, "Expected recommendation for \(category)")
        }
    }

    func test_unclassifiedCategories_neverProduceRecommendations() {
        for category in [TIREventCategory.unclassifiedHigh, .unclassifiedLow] {
            let pattern = makePattern(category: category, eventCount: 10)
            let recs = TIRRecommendationEngine.recommend(patterns: [pattern])
            XCTAssertTrue(recs.isEmpty, "Unclassified categories should never produce recommendations")
        }
    }

    // MARK: - Depth tests

    func test_reboundHigh_isSpecific() {
        let pattern = makePattern(category: .reboundHigh, eventCount: 3)
        let recs = TIRRecommendationEngine.recommend(patterns: [pattern])
        XCTAssertEqual(recs[0].depth, .specific)
    }

    func test_persistentElevation_isObservational() {
        let pattern = makePattern(category: .persistentElevation, eventCount: 3)
        let recs = TIRRecommendationEngine.recommend(patterns: [pattern])
        XCTAssertEqual(recs[0].depth, .observational)
    }

    func test_reboundLow_isSpecific() {
        let pattern = makePattern(category: .reboundLow, eventCount: 3)
        let recs = TIRRecommendationEngine.recommend(patterns: [pattern])
        XCTAssertEqual(recs[0].depth, .specific)
    }

    // MARK: - Time-of-day dominant period in text

    func test_dominantPeriod_appearsInDetail() {
        // overnight dominant: 4/4 events overnight
        let pattern = makePattern(category: .persistentLow, eventCount: 4, overnight: 4)
        let recs = TIRRecommendationEngine.recommend(patterns: [pattern])
        XCTAssertEqual(recs.count, 1)
        XCTAssertTrue(recs[0].detail.contains("overnight"), "Detail should mention dominant period")
    }

    func test_noDominantPeriod_noTimeLabel() {
        // Evenly spread — no dominant period
        let pattern = makePattern(category: .persistentLow, eventCount: 4, overnight: 1, morning: 1, afternoon: 1, evening: 1)
        let recs = TIRRecommendationEngine.recommend(patterns: [pattern])
        XCTAssertEqual(recs.count, 1)
        // None of the period labels should appear
        let detail = recs[0].detail
        for period in ["overnight", "morning", "afternoon", "evening"] {
            XCTAssertFalse(detail.contains(period), "Evenly spread pattern should not name a period in detail")
        }
    }

    // MARK: - Multiple pattern input

    func test_mixedThresholds_onlySufficientPatternsReturned() {
        let patterns = [
            makePattern(category: .reboundHigh, eventCount: 5), // above threshold
            makePattern(category: .reboundLow, eventCount: 2), // below threshold
            makePattern(category: .persistentLow, eventCount: 3) // at threshold
        ]
        let recs = TIRRecommendationEngine.recommend(patterns: patterns)
        XCTAssertEqual(recs.count, 2)
        XCTAssertTrue(recs.contains { $0.category == .reboundHigh })
        XCTAssertTrue(recs.contains { $0.category == .persistentLow })
    }

    func test_emptyPatterns_returnsEmpty() {
        let recs = TIRRecommendationEngine.recommend(patterns: [])
        XCTAssertTrue(recs.isEmpty)
    }

    // MARK: - TimeOfDayBuckets

    func test_dominantPeriod_requiresFiftyPercentMajority() {
        // 3/6 = 50% — boundary, should be dominant
        let buckets = TimeOfDayBuckets(overnight: 3, morning: 1, afternoon: 1, evening: 1)
        XCTAssertEqual(buckets.dominantPeriod, "overnight")

        // 2/6 = 33% — not dominant
        let buckets2 = TimeOfDayBuckets(overnight: 2, morning: 2, afternoon: 1, evening: 1)
        XCTAssertNil(buckets2.dominantPeriod)
    }

    func test_emptyBuckets_noDominantPeriod() {
        let buckets = TimeOfDayBuckets(overnight: 0, morning: 0, afternoon: 0, evening: 0)
        XCTAssertNil(buckets.dominantPeriod)
        XCTAssertEqual(buckets.total, 0)
    }

    // MARK: - Audit cross-referencing tests

    private func makeAuditReport(findings: [TIRSettingsAuditFinding]) -> TIRSettingsAuditReport {
        TIRSettingsAuditReport(findings: findings)
    }

    private func watchFinding(
        _ checkID: AuditCheckID,
        message: String = "Test message",
        suggestion: String? = nil
    ) -> TIRSettingsAuditFinding {
        TIRSettingsAuditFinding(checkID: checkID, severity: .watch, message: message, suggestion: suggestion)
    }

    private func okFinding(_ checkID: AuditCheckID) -> TIRSettingsAuditFinding {
        TIRSettingsAuditFinding(checkID: checkID, severity: .ok, message: "OK", suggestion: nil)
    }

    func test_nilAuditReport_matchesOriginalBehavior() {
        let pattern = makePattern(category: .reboundHigh, eventCount: 3)
        let withNil = TIRRecommendationEngine.recommend(patterns: [pattern], auditReport: nil)
        let withoutArg = TIRRecommendationEngine.recommend(patterns: [pattern])
        XCTAssertEqual(withNil.count, withoutArg.count)
        XCTAssertEqual(withNil[0].headline, withoutArg[0].headline)
        XCTAssertEqual(withNil[0].source, .pattern)
    }

    func test_watchFinding_producesAuditOnlyRecommendation() {
        let report = makeAuditReport(findings: [watchFinding(.maxIOB, message: "Max IOB is 0U", suggestion: "Increase it")])
        let recs = TIRRecommendationEngine.recommend(patterns: [], auditReport: report)
        XCTAssertEqual(recs.count, 1)
        XCTAssertNil(recs[0].category)
        XCTAssertEqual(recs[0].source, .settingsAudit)
        XCTAssertTrue(recs[0].detail.contains("Max IOB is 0U"))
        XCTAssertTrue(recs[0].detail.contains("Increase it"))
    }

    func test_okFinding_doesNotProduceRecommendation() {
        let report = makeAuditReport(findings: [okFinding(.maxIOB)])
        let recs = TIRRecommendationEngine.recommend(patterns: [], auditReport: report)
        XCTAssertTrue(recs.isEmpty)
    }

    func test_constraintLimited_plus_maxIOBWatch_producesCrossRef() {
        let pattern = makePattern(category: .constraintLimited, eventCount: 4)
        let report = makeAuditReport(findings: [watchFinding(.maxIOB, message: "Max IOB is 0U")])
        let recs = TIRRecommendationEngine.recommend(patterns: [pattern], auditReport: report)
        XCTAssertEqual(recs.count, 1)
        XCTAssertEqual(recs[0].source, .crossReferenced)
        XCTAssertEqual(recs[0].category, .constraintLimited)
        XCTAssertTrue(recs[0].headline.contains("Max IOB"))
    }

    func test_crossRef_suppressesPlainPatternRec() {
        let pattern = makePattern(category: .constraintLimited, eventCount: 5)
        let report = makeAuditReport(findings: [watchFinding(.maxIOB)])
        let recs = TIRRecommendationEngine.recommend(patterns: [pattern], auditReport: report)
        let constraintRecs = recs.filter { $0.category == .constraintLimited }
        XCTAssertEqual(constraintRecs.count, 1)
        XCTAssertEqual(constraintRecs[0].source, .crossReferenced)
    }

    func test_crossRefFinding_notDuplicatedAsAuditOnly() {
        let pattern = makePattern(category: .constraintLimited, eventCount: 3)
        let report = makeAuditReport(findings: [watchFinding(.maxIOB)])
        let recs = TIRRecommendationEngine.recommend(patterns: [pattern], auditReport: report)
        let auditOnly = recs.filter { $0.source == .settingsAudit }
        XCTAssertTrue(auditOnly.isEmpty)
    }

    func test_belowThresholdPattern_producesAuditOnlyNotCrossRef() {
        let pattern = makePattern(category: .constraintLimited, eventCount: 2)
        let report = makeAuditReport(findings: [watchFinding(.maxIOB, message: "Max IOB low")])
        let recs = TIRRecommendationEngine.recommend(patterns: [pattern], auditReport: report)
        XCTAssertEqual(recs.count, 1)
        XCTAssertEqual(recs[0].source, .settingsAudit)
        XCTAssertNil(recs[0].category)
    }

    func test_patternWithOkAudit_producesPlainPatternOnly() {
        let pattern = makePattern(category: .constraintLimited, eventCount: 3)
        let report = makeAuditReport(findings: [okFinding(.maxIOB)])
        let recs = TIRRecommendationEngine.recommend(patterns: [pattern], auditReport: report)
        XCTAssertEqual(recs.count, 1)
        XCTAssertEqual(recs[0].source, .pattern)
    }

    func test_reboundHigh_plus_sigmoidWatch_producesCrossRef() {
        let pattern = makePattern(category: .reboundHigh, eventCount: 3)
        let report = makeAuditReport(findings: [watchFinding(.sigmoidAutosens, message: "Sigmoid is steep")])
        let recs = TIRRecommendationEngine.recommend(patterns: [pattern], auditReport: report)
        let crossRefs = recs.filter { $0.source == .crossReferenced }
        XCTAssertEqual(crossRefs.count, 1)
        XCTAssertEqual(crossRefs[0].category, .reboundHigh)
        XCTAssertTrue(crossRefs[0].detail.contains("Sigmoid is steep"))
    }

    func test_persistentElevation_plus_smbMinutesWatch_producesCrossRef() {
        let pattern = makePattern(category: .persistentElevation, eventCount: 5)
        let report = makeAuditReport(findings: [watchFinding(.maxSMBBasalMinutes, message: "SMB cap high")])
        let recs = TIRRecommendationEngine.recommend(patterns: [pattern], auditReport: report)
        let crossRefs = recs.filter { $0.source == .crossReferenced }
        XCTAssertEqual(crossRefs.count, 1)
        XCTAssertEqual(crossRefs[0].category, .persistentElevation)
    }

    func test_postConnectivityGap_plus_maxDeltaWatch_producesCrossRef() {
        let pattern = makePattern(category: .postConnectivityGap, eventCount: 4)
        let report = makeAuditReport(findings: [watchFinding(.maxDeltaUAM, message: "Delta low")])
        let recs = TIRRecommendationEngine.recommend(patterns: [pattern], auditReport: report)
        let crossRefs = recs.filter { $0.source == .crossReferenced }
        XCTAssertEqual(crossRefs.count, 1)
        XCTAssertEqual(crossRefs[0].category, .postConnectivityGap)
        XCTAssertTrue(crossRefs[0].detail.contains("Delta low"))
    }

    // MARK: - Multi-finding deduplication tests

    func test_multipleFindings_oneConsumedByXref_otherSurfacesAsAuditOnly() {
        // constraintLimited pattern + two watch findings: maxIOB (has cross-ref rule) + sigmoidAutosens (no matching pattern)
        let pattern = makePattern(category: .constraintLimited, eventCount: 4)
        let report = makeAuditReport(findings: [
            watchFinding(.maxIOB, message: "IOB low"),
            watchFinding(.sigmoidAutosens, message: "Sigmoid steep")
        ])
        let recs = TIRRecommendationEngine.recommend(patterns: [pattern], auditReport: report)
        // maxIOB → consumed by cross-ref with constraintLimited
        let crossRefs = recs.filter { $0.source == .crossReferenced }
        XCTAssertEqual(crossRefs.count, 1)
        XCTAssertEqual(crossRefs[0].category, .constraintLimited)
        // sigmoidAutosens → no matching pattern above threshold, so audit-only
        let auditOnly = recs.filter { $0.source == .settingsAudit }
        XCTAssertEqual(auditOnly.count, 1)
        XCTAssertTrue(auditOnly[0].detail.contains("Sigmoid steep"))
        // no plain pattern rec for constraintLimited (suppressed by cross-ref)
        let plainPattern = recs.filter { $0.source == .pattern }
        XCTAssertTrue(plainPattern.isEmpty)
    }

    func test_twoPatterns_twoFindings_bothCrossRef() {
        // Two patterns that each have a matching cross-ref rule
        let patterns = [
            makePattern(category: .constraintLimited, eventCount: 3),
            makePattern(category: .postConnectivityGap, eventCount: 5)
        ]
        let report = makeAuditReport(findings: [
            watchFinding(.maxIOB, message: "IOB cap hit"),
            watchFinding(.maxDeltaUAM, message: "Delta threshold low")
        ])
        let recs = TIRRecommendationEngine.recommend(patterns: patterns, auditReport: report)
        let crossRefs = recs.filter { $0.source == .crossReferenced }
        XCTAssertEqual(crossRefs.count, 2)
        XCTAssertTrue(crossRefs.contains { $0.category == .constraintLimited })
        XCTAssertTrue(crossRefs.contains { $0.category == .postConnectivityGap })
        // Both findings consumed — no audit-only recs
        let auditOnly = recs.filter { $0.source == .settingsAudit }
        XCTAssertTrue(auditOnly.isEmpty)
        // Both plain pattern recs suppressed
        let plain = recs.filter { $0.source == .pattern }
        XCTAssertTrue(plain.isEmpty)
    }

    func test_patternWithNoMatchingAuditRule_getsPlainRec() {
        // reboundLow has no cross-ref rule, so it stays as a plain pattern rec
        let pattern = makePattern(category: .reboundLow, eventCount: 4)
        let report = makeAuditReport(findings: [watchFinding(.maxIOB, message: "IOB low")])
        let recs = TIRRecommendationEngine.recommend(patterns: [pattern], auditReport: report)
        // reboundLow → plain pattern rec (no cross-ref rule for it)
        let plainRecs = recs.filter { $0.source == .pattern }
        XCTAssertEqual(plainRecs.count, 1)
        XCTAssertEqual(plainRecs[0].category, .reboundLow)
        // maxIOB → audit-only (no constraintLimited pattern to pair with)
        let auditOnly = recs.filter { $0.source == .settingsAudit }
        XCTAssertEqual(auditOnly.count, 1)
    }

    func test_emptyReport_producesOnlyPatternRecs() {
        let pattern = makePattern(category: .reboundHigh, eventCount: 3)
        let report = makeAuditReport(findings: [])
        let recs = TIRRecommendationEngine.recommend(patterns: [pattern], auditReport: report)
        XCTAssertEqual(recs.count, 1)
        XCTAssertEqual(recs[0].source, .pattern)
    }

    func test_crossRef_depth_isAlwaysSpecific() {
        let pattern = makePattern(category: .persistentElevation, eventCount: 3)
        let report = makeAuditReport(findings: [watchFinding(.maxSMBBasalMinutes)])
        let recs = TIRRecommendationEngine.recommend(patterns: [pattern], auditReport: report)
        let crossRef = recs.first { $0.source == .crossReferenced }
        XCTAssertNotNil(crossRef)
        XCTAssertEqual(crossRef?.depth, .specific, "Cross-referenced recs should always be .specific depth")
    }

    func test_auditOnly_depth_isObservational() {
        let report = makeAuditReport(findings: [watchFinding(.maxIOB, message: "IOB low")])
        let recs = TIRRecommendationEngine.recommend(patterns: [], auditReport: report)
        let auditRec = recs.first { $0.source == .settingsAudit }
        XCTAssertNotNil(auditRec)
        XCTAssertEqual(auditRec?.depth, .observational, "Audit-only recs should be .observational depth")
    }

    // MARK: - WindowCoverage computed property tests

    func test_windowCoverage_expectedGlucoseCount() {
        let cov = WindowCoverage(
            windowDays: 7,
            analysisEnd: Date(),
            glucoseRecordCount: 1000,
            carbDataAvailable: true,
            pumpDataAvailable: true,
            caveats: []
        )
        XCTAssertEqual(cov.expectedGlucoseCount, 7 * 288)
    }

    func test_windowCoverage_glucoseCoverage_partial() {
        let expected = 14 * 288
        let cov = WindowCoverage(
            windowDays: 14,
            analysisEnd: Date(),
            glucoseRecordCount: expected / 2,
            carbDataAvailable: true,
            pumpDataAvailable: true,
            caveats: []
        )
        XCTAssertEqual(cov.glucoseCoverage, 0.5, accuracy: 0.001)
    }

    func test_windowCoverage_glucoseCoverage_cappedAtOne() {
        let cov = WindowCoverage(
            windowDays: 1,
            analysisEnd: Date(),
            glucoseRecordCount: 9999, // way more than 288
            carbDataAvailable: true,
            pumpDataAvailable: true,
            caveats: []
        )
        XCTAssertEqual(cov.glucoseCoverage, 1.0)
    }

    func test_windowCoverage_zeroDays_coverageIsZero() {
        let cov = WindowCoverage(
            windowDays: 0,
            analysisEnd: Date(),
            glucoseRecordCount: 100,
            carbDataAvailable: true,
            pumpDataAvailable: true,
            caveats: []
        )
        XCTAssertEqual(cov.expectedGlucoseCount, 0)
        XCTAssertEqual(cov.glucoseCoverage, 0.0)
    }

    // MARK: - TimeOfDayBuckets additional tests

    func test_timeOfDayBuckets_total() {
        let buckets = TimeOfDayBuckets(overnight: 2, morning: 3, afternoon: 5, evening: 1)
        XCTAssertEqual(buckets.total, 11)
    }

    func test_timeOfDayBuckets_allInOnePeriod() {
        let buckets = TimeOfDayBuckets(overnight: 0, morning: 10, afternoon: 0, evening: 0)
        XCTAssertEqual(buckets.dominantPeriod, "morning")
    }

    // MARK: - New low category recommendation tests

    func test_compressionLow_producesObservationalRecommendation() {
        let pattern = makePattern(category: .compressionLow, eventCount: 3)
        let recs = TIRRecommendationEngine.recommend(patterns: [pattern])
        XCTAssertEqual(recs.count, 1)
        XCTAssertEqual(recs[0].category, .compressionLow)
        XCTAssertEqual(recs[0].depth, .observational)
        XCTAssertEqual(recs[0].source, .pattern)
    }

    func test_overcorrectionLow_producesSpecificRecommendation() {
        let pattern = makePattern(category: .overcorrectionLow, eventCount: 3)
        let recs = TIRRecommendationEngine.recommend(patterns: [pattern])
        XCTAssertEqual(recs.count, 1)
        XCTAssertEqual(recs[0].depth, .specific)
    }

    func test_stackingLow_producesSpecificRecommendation() {
        let pattern = makePattern(category: .stackingLow, eventCount: 3)
        let recs = TIRRecommendationEngine.recommend(patterns: [pattern])
        XCTAssertEqual(recs.count, 1)
        XCTAssertEqual(recs[0].depth, .specific)
    }

    func test_activityRelatedLow_producesSpecificRecommendation() {
        let pattern = makePattern(category: .activityRelatedLow, eventCount: 3)
        let recs = TIRRecommendationEngine.recommend(patterns: [pattern])
        XCTAssertEqual(recs.count, 1)
        XCTAssertEqual(recs[0].depth, .specific)
    }

    func test_basalTooAggressive_producesObservationalRecommendation() {
        let pattern = makePattern(category: .basalTooAggressive, eventCount: 3)
        let recs = TIRRecommendationEngine.recommend(patterns: [pattern])
        XCTAssertEqual(recs.count, 1)
        XCTAssertEqual(recs[0].depth, .observational)
    }

    func test_overcorrectionLow_plus_sigmoidWatch_producesCrossRef() {
        let pattern = makePattern(category: .overcorrectionLow, eventCount: 3)
        let report = makeAuditReport(findings: [watchFinding(.sigmoidAutosens, message: "Sigmoid aggressive")])
        let recs = TIRRecommendationEngine.recommend(patterns: [pattern], auditReport: report)
        let crossRefs = recs.filter { $0.source == .crossReferenced }
        XCTAssertEqual(crossRefs.count, 1)
        XCTAssertEqual(crossRefs[0].category, .overcorrectionLow)
        XCTAssertTrue(crossRefs[0].detail.contains("Sigmoid aggressive"))
    }

    func test_stackingLow_plus_smbMinutesWatch_producesCrossRef() {
        let pattern = makePattern(category: .stackingLow, eventCount: 4)
        let report = makeAuditReport(findings: [watchFinding(.maxSMBBasalMinutes, message: "SMB cap high")])
        let recs = TIRRecommendationEngine.recommend(patterns: [pattern], auditReport: report)
        let crossRefs = recs.filter { $0.source == .crossReferenced }
        XCTAssertEqual(crossRefs.count, 1)
        XCTAssertEqual(crossRefs[0].category, .stackingLow)
    }

    func test_lowCategoryWithNoMatchingRule_getsPlainRec() {
        // compressionLow has no cross-ref rule
        let pattern = makePattern(category: .compressionLow, eventCount: 4)
        let report = makeAuditReport(findings: [watchFinding(.maxIOB)])
        let recs = TIRRecommendationEngine.recommend(patterns: [pattern], auditReport: report)
        let plainRecs = recs.filter { $0.source == .pattern }
        XCTAssertEqual(plainRecs.count, 1)
        XCTAssertEqual(plainRecs[0].category, .compressionLow)
    }
}
