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
            .postConnectivityGap, .reboundHigh, .risingWithoutCarbs,
            .constraintLimited, .persistentElevation, .reboundLow,
            .persistentLow, .fallingWithoutActiveInsulin
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
}
