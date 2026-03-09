import Foundation

/// Pure static engine — no side effects, no external dependencies.
/// Filters patterns to those with ≥3 events and maps each to a category-appropriate recommendation.
/// When an audit report is provided, cross-references pattern evidence with settings findings.
enum TIRRecommendationEngine {
    static let recurrenceThreshold = 3

    // MARK: - Public API

    /// Backward-compatible entry point (no audit cross-referencing).
    static func recommend(patterns: [TIRCategoryPattern]) -> [TIRRecommendation] {
        recommend(patterns: patterns, auditReport: nil)
    }

    /// Full entry point with optional audit cross-referencing.
    static func recommend(
        patterns: [TIRCategoryPattern],
        auditReport: TIRSettingsAuditReport?
    ) -> [TIRRecommendation] {
        let patternRecs = patterns
            .filter { $0.eventCount >= recurrenceThreshold }
            .compactMap { recommendation(for: $0) }

        guard let report = auditReport else { return patternRecs }

        // Cross-referenced recommendations supersede plain pattern recs for the same category.
        let crossRecs = crossReferencedRecommendations(patterns: patterns, report: report)
        let crossRefCategories = Set(crossRecs.compactMap(\.category))
        let filteredPatternRecs = patternRecs.filter { rec in
            guard let cat = rec.category else { return true }
            return !crossRefCategories.contains(cat)
        }

        // Standalone audit recommendations for .watch findings not consumed by cross-refs.
        let auditRecs = auditOnlyRecommendations(from: report, patterns: patterns)

        return filteredPatternRecs + crossRecs + auditRecs
    }

    // MARK: - Pattern-based (existing logic)

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
        case .compressionLow:
            return TIRRecommendation(
                category: pattern.category,
                headline: "Suspected compression lows\(period)",
                detail: "Short-lived lows with rapid recovery suggest CGM compression artifacts. These are likely not true lows — verify with fingerstick if concerned.",
                depth: .observational
            )
        case .overcorrectionLow:
            return TIRRecommendation(
                category: pattern.category,
                headline: "Lows following corrections\(period)",
                detail: "Recurring lows following manual boluses or corrections suggest the correction dose may be too aggressive. Review ISF and correction factor.",
                depth: .specific
            )
        case .stackingLow:
            return TIRRecommendation(
                category: pattern.category,
                headline: "Lows from insulin stacking\(period)",
                detail: "Multiple insulin deliveries in rapid succession preceded these lows. Review SMB frequency settings and consider increasing the interval between doses.",
                depth: .specific
            )
        case .activityRelatedLow:
            return TIRRecommendation(
                category: pattern.category,
                headline: "Activity-related lows\(period)",
                detail: "These lows correlated with exercise or activity periods. Consider pre-exercise carbs, reduced basal, or an exercise override profile.",
                depth: .specific
            )
        case .reboundLow:
            return TIRRecommendation(
                category: pattern.category,
                headline: "Recurring lows following highs\(period)",
                detail: "Recurring lows following highs suggest correction dosing is too aggressive. Review correction sensitivity and post-correction monitoring.",
                depth: .specific
            )
        case .basalTooAggressive:
            return TIRRecommendation(
                category: pattern.category,
                headline: "Lows without insulin or food triggers\(period)",
                detail: "Recurring lows without recent boluses or carbs suggest the basal rate may be too high for this time period. Consider reviewing basal profile.",
                depth: .observational
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
                headline: "Recurring unexplained falls\(period)",
                detail: "Recurring unexplained falls — consider activity, absorption variability, or basal overdelivery\(period).",
                depth: .observational
            )
        case .unclassifiedHigh,
             .unclassifiedLow:
            return nil
        }
    }

    // MARK: - Cross-referencing (Part B)

    /// Mapping of pattern categories to the audit checks they correlate with.
    private static let crossReferenceRules: [(TIREventCategory, AuditCheckID)] = [
        // High categories
        (.constraintLimited, .maxIOB),
        (.risingWithoutCarbs, .sigmoidAutosens),
        (.reboundHigh, .sigmoidAutosens),
        (.persistentElevation, .maxSMBBasalMinutes),
        (.postConnectivityGap, .maxDeltaUAM),
        // Low categories
        (.overcorrectionLow, .sigmoidAutosens), // aggressive ISF → overcorrection
        (.stackingLow, .maxSMBBasalMinutes) // SMB delivery settings → stacking
    ]

    private static func crossReferencedRecommendations(
        patterns: [TIRCategoryPattern],
        report: TIRSettingsAuditReport
    ) -> [TIRRecommendation] {
        let findingsByCheck = Dictionary(
            report.findings.map { ($0.checkID, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        return crossReferenceRules.compactMap { category, checkID in
            guard let pattern = patterns.first(where: { $0.category == category }),
                  pattern.eventCount >= recurrenceThreshold,
                  let finding = findingsByCheck[checkID],
                  finding.severity == .watch
            else { return nil }

            return crossReferencedRecommendation(
                category: category,
                pattern: pattern,
                finding: finding
            )
        }
    }

    private static func crossReferencedRecommendation(
        category: TIREventCategory,
        pattern: TIRCategoryPattern,
        finding: TIRSettingsAuditFinding
    ) -> TIRRecommendation {
        let period = pattern.timeOfDayBuckets.dominantPeriod.map { " in the \($0)" } ?? ""
        let headline: String
        let detail: String

        switch (category, finding.checkID) {
        case (.constraintLimited, .maxIOB):
            headline = "Max IOB ceiling is limiting corrections"
            detail =
                "The system hit the Max IOB limit \(pattern.eventCount) times over \(pattern.recurrenceDays) days\(period). \(finding.message)"

        case (.risingWithoutCarbs, .sigmoidAutosens):
            headline = "Unexplained rises may relate to sensitivity settings"
            detail =
                "Recurring unexplained rises (\(pattern.eventCount) events\(period)) coincide with aggressive sensitivity settings. \(finding.message)"

        case (.reboundHigh, .sigmoidAutosens):
            headline = "Rebound highs may be worsened by correction settings"
            detail =
                "Recurring rebound highs (\(pattern.eventCount) events\(period)) may be amplified by dynamic sensitivity. \(finding.message)"

        case (.persistentElevation, .maxSMBBasalMinutes):
            headline = "Persistent highs may relate to SMB delivery limits"
            detail = "Persistent elevations recurred \(pattern.eventCount) times\(period). \(finding.message)"

        case (.postConnectivityGap, .maxDeltaUAM):
            headline = "Post-gap highs may be worsened by SMB suppression"
            detail = "CGM reconnection gaps led to \(pattern.eventCount) high events\(period). \(finding.message)"

        case (.overcorrectionLow, .sigmoidAutosens):
            headline = "Overcorrection lows may relate to aggressive sensitivity"
            detail =
                "Recurring overcorrection lows (\(pattern.eventCount) events\(period)) may be amplified by dynamic sensitivity settings. \(finding.message)"

        case (.stackingLow, .maxSMBBasalMinutes):
            headline = "Insulin stacking lows may relate to SMB delivery limits"
            detail =
                "Insulin stacking preceded \(pattern.eventCount) lows\(period). \(finding.message)"

        default:
            headline = "Settings context for \(category.rawValue)"
            detail = finding.message
        }

        return TIRRecommendation(
            category: category,
            headline: headline,
            detail: detail,
            depth: .specific,
            source: .crossReferenced
        )
    }

    // MARK: - Audit-only recommendations (Part A)

    private static func auditOnlyRecommendations(
        from report: TIRSettingsAuditReport,
        patterns: [TIRCategoryPattern]
    ) -> [TIRRecommendation] {
        // Determine which audit checks are already consumed by cross-references.
        let activeCrossRefs = Set(
            crossReferenceRules
                .filter { rule in patterns.contains { $0.category == rule.0 && $0.eventCount >= recurrenceThreshold } }
                .map(\.1)
        )

        return report.findings
            .filter { $0.severity == .watch && !activeCrossRefs.contains($0.checkID) }
            .map { finding in
                TIRRecommendation(
                    category: nil,
                    headline: "Settings: \(auditHeadline(for: finding.checkID))",
                    detail: finding.message + (finding.suggestion.map { " \($0)" } ?? ""),
                    depth: .observational,
                    source: .settingsAudit
                )
            }
    }

    private static func auditHeadline(for checkID: AuditCheckID) -> String {
        switch checkID {
        case .sigmoidAutosens: return "Sigmoid/autosens may need attention"
        case .maxDeltaUAM: return "Delta-BG threshold may suppress SMB"
        case .maxIOB: return "Max IOB may be limiting corrections"
        case .maxSMBBasalMinutes: return "SMB delivery minutes may need review"
        }
    }
}
