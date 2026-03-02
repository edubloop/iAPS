import Foundation

// MARK: - TIREventCategory

/// The classification of a high-glucose event for Phase 1A decomposition.
/// Priority order matches EventClassifier strict precedence.
enum TIREventCategory: String, Codable, CaseIterable {
    case reboundHigh = "REBOUND_HIGH"
    case postConnectivityGap = "POST_CONNECTIVITY_GAP"
    case constraintLimited = "CONSTRAINT_LIMITED"
    case risingWithoutCarbs = "RISING_WITHOUT_CARBS"
    case persistentElevation = "PERSISTENT_ELEVATION"
    case unclassifiedHigh = "UNCLASSIFIED_HIGH"
    // Deferred to Track 2+: POST_MEAL_SPIKE and subcategories, LOW events
}

// MARK: - TIREventConfidence

enum TIREventConfidence: String, Codable {
    case high
    case medium
    case low
}

// MARK: - TIRContributingFactor

/// Defined now so TIREvent is fully Codable.
/// Populated when classifier evidence is available.
struct TIRContributingFactor: Codable {
    let factor: String
    let evidence: String
    let actionable: Bool
    let suggestion: String?
}

// MARK: - TIREvent

/// Canonical output type of the engine. Matches the Track 0 JSON contract
/// in `.context/TIR-Phase1A-Track0.md`.
struct TIREvent: Codable, Identifiable {
    /// Stable deterministic ID: "evt_\(yyyyMMddTHHmmZ)_\(zeroPaddedOrdinal)"
    let id: String
    let start: Date
    let end: Date
    /// Always "high" in Track 1; LOW events deferred.
    let type: String
    /// Peak CGM reading in mg/dL (always mg/dL internally regardless of display units).
    let peakSeverity: Int
    let durationMinutes: Int
    /// Fraction of the analysis window this event consumed: durationMinutes / windowMinutes.
    let tirCost: Double
    let category: TIREventCategory
    let confidence: TIREventConfidence
    /// Populated by EventClassifier when supporting evidence is available.
    let contributingFactors: [TIRContributingFactor]

    enum CodingKeys: String, CodingKey {
        case id
        case start
        case end
        case type
        case peakSeverity = "peak_severity"
        case durationMinutes = "duration_minutes"
        case tirCost = "tir_cost"
        case category
        case confidence
        case contributingFactors = "contributing_factors"
    }
}

// MARK: - GlucoseSegment (internal; not serialized)

/// A contiguous run of BloodGlucose readings above the high threshold
/// after 15-minute consolidation. Intermediate type used only within
/// ThresholdCrossingDetector and EventClassifier.
struct GlucoseSegment {
    /// Chronological, state-valid readings that make up this high event
    /// (including any bridging in-range readings absorbed during consolidation).
    let readings: [BloodGlucose]
    let start: Date
    let end: Date
    /// Maximum sgv value (mg/dL) across all readings.
    let peakSgv: Int

    var durationMinutes: Int {
        Int(end.timeIntervalSince(start) / 60.0)
    }
}

// MARK: - TIRAnalysisConfiguration

/// Plain value type — no DI coupling, no UIKit/SwiftUI imports.
/// The caller (Provider in Track 2, or test harness) constructs and passes this in.
struct TIRAnalysisConfiguration {
    /// Upper in-range threshold in mg/dL.
    /// Note: FreeAPSSettings.high is stored in mg/dL regardless of display units.
    let highThresholdMgdL: Double

    /// Lower in-range threshold in mg/dL.
    let lowThresholdMgdL: Double

    /// Preferences.maxIOB as a Double. Used for CONSTRAINT_LIMITED bucket checks.
    let maxIOB: Double

    let windowStart: Date
    let windowEnd: Date

    /// Display units — carried for reference; the engine operates in mg/dL internally.
    let units: GlucoseUnits

    /// Convenience factory from live settings.
    /// Called by the Provider (Track 2) and test helpers.
    /// FreeAPSSettings.high / .low are always stored in mg/dL.
    static func make(
        highMgdL: Double,
        lowMgdL: Double,
        maxIOB: Double,
        units: GlucoseUnits = .mmolL,
        windowDays: Int = 14,
        windowEnd: Date = Date()
    ) -> TIRAnalysisConfiguration {
        TIRAnalysisConfiguration(
            highThresholdMgdL: highMgdL,
            lowThresholdMgdL: lowMgdL,
            maxIOB: maxIOB,
            windowStart: windowEnd.addingTimeInterval(TimeInterval(-windowDays * 86400)),
            windowEnd: windowEnd,
            units: units
        )
    }
}

// MARK: - TIRAnalysisInput

/// All data the engine accepts. Glucose is required; everything else is optional
/// so the engine degrades confidence gracefully when data is unavailable.
struct TIRAnalysisInput {
    /// Required. Must be chronologically sorted ascending by dateString.
    let glucose: [BloodGlucose]

    /// Optional carb entries for the analysis window.
    /// From HealthKit in Track 2.
    let carbEntries: [CarbsEntry]?

    /// Optional pump history for the analysis window.
    /// From PumpHistoryStorage.recent() in Track 2 (24 h retention limit).
    let pumpHistory: [PumpHistoryEvent]?

    /// Optional IOB history ticks.
    /// No rolling IOB history exists in iAPS; always nil in Track 2.
    /// CONSTRAINT_LIMITED classification skipped when nil.
    let iobHistory: [IOBTick0]?

    let configuration: TIRAnalysisConfiguration
}

// MARK: - WindowCoverage

/// Data availability report for the analysis window.
/// Matches the canonical model in `.context/TIR-Phase1A-Track0.md`.
struct WindowCoverage: Codable {
    let windowDays: Int
    let analysisEnd: Date
    /// Number of blood glucose readings found in the window.
    let glucoseRecordCount: Int
    /// True if at least one carb entry was found in the window.
    let carbDataAvailable: Bool
    /// True if any pump history was available (file storage, 24 h window).
    let pumpDataAvailable: Bool
    /// Human-readable caveats for display and confidence downgrade explanations.
    let caveats: [String]

    /// Expected glucose record count for a fully-covered window (288 readings/day).
    var expectedGlucoseCount: Int { windowDays * 288 }

    /// Fraction of expected readings present. Capped at 1.0.
    var glucoseCoverage: Double {
        expectedGlucoseCount > 0
            ? min(1.0, Double(glucoseRecordCount) / Double(expectedGlucoseCount))
            : 0.0
    }

    enum CodingKeys: String, CodingKey {
        case windowDays = "window_days"
        case analysisEnd = "analysis_end"
        case glucoseRecordCount = "glucose_record_count"
        case carbDataAvailable = "carb_data_available"
        case pumpDataAvailable = "pump_data_available"
        case caveats
    }
}

// MARK: - TIRAnalysisResult

/// Top-level output of a complete TIR analysis run.
/// Wraps the classified event list with window coverage metadata.
struct TIRAnalysisResult {
    let events: [TIREvent]
    let windowCoverage: WindowCoverage
    let analysisDate: Date

    /// Sum of tirCost across all events.
    var totalTIRCost: Double {
        events.map(\.tirCost).reduce(0, +)
    }

    func events(for category: TIREventCategory) -> [TIREvent] {
        events.filter { $0.category == category }
    }

    func tirCost(for category: TIREventCategory) -> Double {
        events(for: category).map(\.tirCost).reduce(0, +)
    }
}
