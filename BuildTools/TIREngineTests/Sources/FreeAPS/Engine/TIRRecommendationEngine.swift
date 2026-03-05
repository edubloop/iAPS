import Foundation

/// Pure static engine — no side effects, no external dependencies.
/// Filters patterns to those with ≥3 events and maps each to a category-appropriate recommendation.
enum TIRRecommendationEngine {
    static let recurrenceThreshold = 3

    static func recommend(patterns: [TIRCategoryPattern]) -> [TIRRecommendation] {
        patterns
            .filter { $0.eventCount >= recurrenceThreshold }
            .compactMap { recommendation(for: $0) }
    }

    // MARK: - Private

    private static func recommendation(for pattern: TIRCategoryPattern) -> TIRRecommendation? {
        let period = pattern.timeOfDayBuckets.dominantPeriod.map { " in the \($0)" } ?? ""
        switch pattern.category {
        case .postConnectivityGap:
            return TIRRecommendation(
                category: pattern.category,
                headline: "Recurring CGM connectivity gaps",
                detail: "CGM reconnection gaps are recurring\(period). Check sensor placement and phone proximity during these periods.",
                depth: .specific
            )
        case .reboundHigh:
            return TIRRecommendation(
                category: pattern.category,
                headline: "Recurring rebound highs after lows",
                detail: "Recurring rebounds suggest over-treatment of lows. Consider smaller fast-acting amounts or a 15-min recheck before re-treating.",
                depth: .specific
            )
        case .risingWithoutCarbs:
            return TIRRecommendation(
                category: pattern.category,
                headline: "Unexplained rises\(period)",
                detail: "Recurring unexplained rises\(period) may reflect ISF being too conservative for that time of day. Review ISF profile for this window.",
                depth: .observational
            )
        case .constraintLimited:
            return TIRRecommendation(
                category: pattern.category,
                headline: "Max IOB ceiling limiting corrections",
                detail: "Max IOB ceiling appears to be limiting corrections during these events. Review Max IOB setting in context of your typical correction needs.",
                depth: .observational
            )
        case .persistentElevation:
            return TIRRecommendation(
                category: pattern.category,
                headline: "Recurring persistent elevations",
                detail: "Persistent elevations are recurring. Root causes vary — review basal rates, ISF, and carb absorption timing for this period.",
                depth: .observational
            )
        case .reboundLow:
            return TIRRecommendation(
                category: pattern.category,
                headline: "Recurring lows following highs",
                detail: "Recurring lows following highs suggest correction dosing is too aggressive. Review correction sensitivity and post-correction monitoring.",
                depth: .specific
            )
        case .persistentLow:
            return TIRRecommendation(
                category: pattern.category,
                headline: "Sustained lows recurring\(period)",
                detail: "Sustained lows recurring\(period) may reflect excess basal. Review basal profile for this time window.",
                depth: .observational
            )
        case .fallingWithoutActiveInsulin:
            return TIRRecommendation(
                category: pattern.category,
                headline: "Recurring unexplained falls",
                detail: "Recurring unexplained falls — consider activity, absorption variability, or basal overdelivery\(period).",
                depth: .observational
            )
        case .unclassifiedHigh,
             .unclassifiedLow:
            return nil
        }
    }
}
