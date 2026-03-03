import Combine
import Foundation
import Swinject

// Track 2: Full data-layer implementation.
// Fetches glucose + carbs via HealthKit (multi-day), pump history from file
// storage (24 h limit), then calls TIRAnalysisEngine.analyze(_:).

extension TIRAnalysis {
    final class Provider: BaseProvider, TIRAnalysisProvider {
        @Injected() var pumpHistoryStorage: PumpHistoryStorage!
        @Injected() var settingsManager: SettingsManager!
        @Injected() var nightscoutManager: NightscoutManager!

        private let hkReader = TIRHealthKitReader()
        private enum TIRDataSource: String {
            case nightscout
            case healthkit

            var title: String {
                switch self {
                case .nightscout: "Nightscout"
                case .healthkit: "HealthKit"
                }
            }
        }

        // MARK: - TIRAnalysisProvider

        func runAnalysis(windowDays: Int) async -> TIRAnalysisResult {
            let now = Date()
            let windowEnd = now
            let windowStart = windowEnd.addingTimeInterval(TimeInterval(-windowDays) * 86400)

            // 1. Build configuration from live settings.
            let settings = settingsManager.settings
            let preferences = settingsManager.preferences
            let configuration = TIRAnalysisConfiguration.make(
                highMgdL: NSDecimalNumber(decimal: settings.high).doubleValue,
                lowMgdL: NSDecimalNumber(decimal: settings.low).doubleValue,
                maxIOB: NSDecimalNumber(decimal: preferences.maxIOB).doubleValue,
                units: settings.units,
                windowDays: windowDays,
                windowEnd: windowEnd
            )

            if settings.tirSimulationEnabled {
                let scenario = TIRSimulationScenario(rawValue: settings.tirSimulationScenario) ?? .mixedRealistic
                let simInput = buildSimulationInput(
                    scenario: scenario,
                    windowStart: windowStart,
                    windowEnd: windowEnd,
                    baseConfiguration: configuration
                )
                let highEvents = TIRAnalysisEngine.analyze(simInput)
                let lowEvents = buildLowPatternEvents(
                    glucose: simInput.glucose,
                    configuration: configuration,
                    carbEntries: simInput.carbEntries,
                    iobHistory: simInput.iobHistory,
                    pumpHistory: simInput.pumpHistory
                )
                let events = (highEvents + lowEvents).sorted { $0.start < $1.start }
                let coverage = buildCoverage(
                    glucose: simInput.glucose,
                    carbEntries: simInput.carbEntries,
                    pumpHistory: simInput.pumpHistory ?? [],
                    windowDays: windowDays,
                    windowEnd: windowEnd,
                    extraCaveats: ["Simulator mode active: \(scenario.title) scenario"]
                )
                let readiness = TIRReadiness.sufficient(
                    windowDays: windowDays,
                    glucoseCoverage: coverage.glucoseCoverage
                )

                debug(.service, "TIR simulation complete: \(events.count) events, scenario \(scenario.rawValue)")
                return TIRAnalysisResult(
                    events: events,
                    windowCoverage: coverage,
                    analysisDate: now,
                    rangeBreakdown: buildRangeBreakdown(glucose: simInput.glucose),
                    readiness: readiness
                )
            }

            let source = TIRDataSource(rawValue: settings.tirDataSource) ?? .nightscout

            let glucose: [BloodGlucose]
            let carbEntries: [CarbsEntry]?
            var sourceCaveats: [String] = ["Data source: \(source.title)"]

            switch source {
            case .healthkit:
                glucose = await hkReader.fetchGlucose(from: windowStart, to: windowEnd)
                let hkCarbs = await hkReader.fetchCarbs(from: windowStart, to: windowEnd)
                carbEntries = hkCarbs.isEmpty ? nil : hkCarbs
            case .nightscout:
                if !settings.nightscoutFetchEnabled {
                    sourceCaveats.append("Nightscout fetching is disabled in Nightscout Config.")
                    glucose = []
                    carbEntries = nil
                } else {
                    glucose = await fetchNightscoutGlucose(from: windowStart, to: windowEnd)
                    let nsCarbs = await fetchNightscoutCarbs(from: windowStart, to: windowEnd)
                    carbEntries = nsCarbs.isEmpty ? nil : nsCarbs

                    if !settings.isUploadEnabled {
                        sourceCaveats.append(
                            "Nightscout upload is disabled. Ensure another source is writing recent glucose/carb data."
                        )
                    }
                }
            }

            // 4. Fetch recent pump history from file storage (24 h retention limit).
            //    Used for PERSISTENT_ELEVATION (SMB detection) within the recent window.
            let recentPump = pumpHistoryStorage.recent().filter {
                $0.timestamp.addingTimeInterval(24 * 3600) > now
            }

            let readiness = buildReadiness(
                glucose: glucose,
                windowStart: windowStart,
                windowEnd: windowEnd,
                windowDays: windowDays
            )

            // 5. Run engine. IOB history unavailable in iAPS (no rolling store).
            let input = TIRAnalysisInput(
                glucose: glucose,
                carbEntries: carbEntries,
                pumpHistory: recentPump.isEmpty ? nil : recentPump,
                iobHistory: nil, // CONSTRAINT_LIMITED skipped; no rolling IOB history.
                configuration: configuration
            )
            let highEvents = TIRAnalysisEngine.analyze(input)
            let lowEvents = buildLowPatternEvents(
                glucose: glucose,
                configuration: configuration,
                carbEntries: carbEntries,
                iobHistory: nil,
                pumpHistory: recentPump.isEmpty ? nil : recentPump
            )
            let events = (highEvents + lowEvents).sorted { $0.start < $1.start }

            // 6. Compute window coverage + caveats.
            let coverage = buildCoverage(
                glucose: glucose,
                carbEntries: carbEntries,
                pumpHistory: recentPump,
                windowDays: windowDays,
                windowEnd: windowEnd,
                extraCaveats: sourceCaveats + (readiness.message.map { [$0] } ?? []),
                source: source
            )

            // 7. Build per-category patterns and derive recommendations.
            let partialResult = TIRAnalysisResult(
                events: events,
                windowCoverage: coverage,
                analysisDate: now,
                rangeBreakdown: buildRangeBreakdown(glucose: glucose),
                readiness: readiness,
                recommendations: []
            )
            let patterns = TIREventCategory.allCases.map { partialResult.pattern(for: $0) }
            let recommendations = TIRRecommendationEngine.recommend(patterns: patterns)

            debug(.service, "TIR analysis complete: \(events.count) events, coverage \(Int(coverage.glucoseCoverage * 100))%, \(recommendations.count) recommendations")
            return TIRAnalysisResult(
                events: events,
                windowCoverage: coverage,
                analysisDate: now,
                rangeBreakdown: buildRangeBreakdown(glucose: glucose),
                readiness: readiness,
                recommendations: recommendations
            )
        }

        // MARK: - Private

        private func buildCoverage(
            glucose: [BloodGlucose],
            carbEntries: [CarbsEntry]?,
            pumpHistory: [PumpHistoryEvent],
            windowDays: Int,
            windowEnd: Date,
            extraCaveats: [String] = [],
            source: TIRDataSource = .healthkit
        ) -> WindowCoverage {
            let actualCount = glucose.count
            let expectedCount = windowDays * 288
            let ratio = expectedCount > 0 ? Double(actualCount) / Double(expectedCount) : 0.0

            var caveats: [String] = []

            if actualCount == 0 {
                caveats.append(
                    "No glucose data found from \(source.title) for the \(windowDays)-day window. " +
                        "Run with simulator mode or verify \(source.title) connectivity and data permissions."
                )
            } else if ratio < 0.8 {
                let pct = Int((ratio * 100).rounded())
                caveats.append(
                    "Glucose coverage is \(pct)% of expected (\(actualCount)/\(expectedCount) readings). " +
                        "Some events may be missed or misclassified."
                )
            }

            if carbEntries == nil {
                caveats.append(
                    "Carb data unavailable from \(source.title). " +
                        "RISING_WITHOUT_CARBS events are reported with .low confidence."
                )
            }

            if pumpHistory.isEmpty {
                caveats.append(
                    "No recent pump history available. " +
                        "PERSISTENT_ELEVATION SMB factor detail is limited."
                )
            }

            caveats = extraCaveats + caveats

            return WindowCoverage(
                windowDays: windowDays,
                analysisEnd: windowEnd,
                glucoseRecordCount: actualCount,
                carbDataAvailable: carbEntries != nil,
                pumpDataAvailable: !pumpHistory.isEmpty,
                caveats: caveats
            )
        }

        private func buildRangeBreakdown(glucose: [BloodGlucose]) -> TIRRangeBreakdown {
            let valid = glucose.filter { $0.isStateValid }
            guard !valid.isEmpty else { return .empty }

            let total = Double(valid.count)
            let veryLow = Double(valid.filter { ThresholdCrossingDetector.sgvValue($0) < 54 }.count) / total
            let low = Double(valid.filter {
                let v = ThresholdCrossingDetector.sgvValue($0)
                return v >= 54 && v < 70
            }.count) / total
            let inRange = Double(valid.filter {
                let v = ThresholdCrossingDetector.sgvValue($0)
                return v >= 70 && v <= 180
            }.count) / total
            let high = Double(valid.filter {
                let v = ThresholdCrossingDetector.sgvValue($0)
                return v > 180 && v <= 250
            }.count) / total
            let veryHigh = Double(valid.filter { ThresholdCrossingDetector.sgvValue($0) > 250 }.count) / total

            return TIRRangeBreakdown(
                veryLow: veryLow,
                low: low,
                inRange: inRange,
                high: high,
                veryHigh: veryHigh
            )
        }

        private func buildReadiness(
            glucose: [BloodGlucose],
            windowStart: Date,
            windowEnd: Date,
            windowDays: Int
        ) -> TIRReadiness {
            let valid = glucose
                .filter { $0.isStateValid }
                .filter { $0.dateString >= windowStart && $0.dateString <= windowEnd }

            let expectedCount = max(windowDays * 288, 1)
            let glucoseCoverage = min(1.0, Double(valid.count) / Double(expectedCount))

            let minRecordsPerFullDay = Int(288 * 70 / 100)
            let calendar = Calendar.current
            var countsByDay: [Date: Int] = [:]
            for reading in valid {
                let day = calendar.startOfDay(for: reading.dateString)
                countsByDay[day, default: 0] += 1
            }

            let fullDays = min(windowDays, countsByDay.values.filter { $0 >= minRecordsPerFullDay }.count)
            let daysLeft = max(0, windowDays - fullDays)
            let isSufficient = daysLeft == 0
            let message: String? = isSufficient
                ? nil
                : "Need \(daysLeft) more full \(daysLeft == 1 ? "day" : "days") for \(windowDays)-day insights (\(fullDays)/\(windowDays) full days available)."

            return TIRReadiness(
                windowDays: windowDays,
                fullDaysAvailable: fullDays,
                requiredFullDays: windowDays,
                daysLeft: daysLeft,
                glucoseCoverage: glucoseCoverage,
                isSufficient: isSufficient,
                message: message
            )
        }

        private func fetchNightscoutGlucose(from start: Date, to end: Date) async -> [BloodGlucose] {
            for await glucose in nightscoutManager.fetchGlucose(since: start, progress: nil).values {
                return glucose
                    .filter { $0.dateString >= start && $0.dateString <= end }
                    .sorted { $0.dateString < $1.dateString }
            }
            return []
        }

        private func fetchNightscoutCarbs(from start: Date, to end: Date) async -> [CarbsEntry] {
            for await carbs in nightscoutManager.fetchCarbs().values {
                return carbs
                    .filter {
                        let d = $0.actualDate ?? $0.createdAt
                        return d >= start && d <= end
                    }
                    .sorted { ($0.actualDate ?? $0.createdAt) < ($1.actualDate ?? $1.createdAt) }
            }
            return []
        }

        private func buildLowPatternEvents(
            glucose: [BloodGlucose],
            configuration: TIRAnalysisConfiguration,
            carbEntries: [CarbsEntry]?,
            iobHistory: [IOBTick0]?,
            pumpHistory: [PumpHistoryEvent]?
        ) -> [TIREvent] {
            let sorted = glucose
                .filter { $0.isStateValid }
                .filter { $0.dateString >= configuration.windowStart && $0.dateString <= configuration.windowEnd }
                .sorted { $0.dateString < $1.dateString }

            guard sorted.count > 1 else { return [] }

            var segments: [[BloodGlucose]] = []
            var current: [BloodGlucose] = []

            for reading in sorted {
                let value = ThresholdCrossingDetector.sgvValue(reading)
                if value < Int(configuration.lowThresholdMgdL.rounded()) {
                    if let prev = current.last,
                       reading.dateString.timeIntervalSince(prev.dateString) > 15 * 60
                    {
                        segments.append(current)
                        current = []
                    }
                    current.append(reading)
                } else if !current.isEmpty {
                    segments.append(current)
                    current = []
                }
            }
            if !current.isEmpty {
                segments.append(current)
            }

            let windowMinutes = max(configuration.windowEnd.timeIntervalSince(configuration.windowStart) / 60, 1)

            var ordinalsByMinute: [String: Int] = [:]
            var events: [TIREvent] = []

            for segment in segments where segment.count >= 2 {
                guard let start = segment.first?.dateString, let end = segment.last?.dateString else { continue }
                let durationMinutes = Int(end.timeIntervalSince(start) / 60)
                guard durationMinutes >= 10 else { continue }

                let nadir = segment.map { ThresholdCrossingDetector.sgvValue($0) }.min() ?? 0
                let category = lowCategory(
                    start: start,
                    end: end,
                    nadir: nadir,
                    configuration: configuration,
                    carbEntries: carbEntries,
                    iobHistory: iobHistory,
                    pumpHistory: pumpHistory,
                    allGlucose: sorted
                )
                let confidence: TIREventConfidence = nadir < 54 ? .high : .medium
                let factors = lowFactors(category: category, nadir: nadir, durationMinutes: durationMinutes)

                let minuteKey = TIRAnalysisEngine.stableMinuteKey(from: start)
                let ordinal = (ordinalsByMinute[minuteKey] ?? 0) + 1
                ordinalsByMinute[minuteKey] = ordinal

                events.append(TIREvent(
                    id: "evt_low_\(minuteKey)_\(String(format: "%03d", ordinal))",
                    start: start,
                    end: end,
                    type: "low",
                    peakSeverity: nadir,
                    durationMinutes: durationMinutes,
                    tirCost: Double(durationMinutes) / windowMinutes,
                    category: category,
                    confidence: confidence,
                    contributingFactors: factors
                ))
            }

            return events
        }

        private func lowCategory(
            start: Date,
            end: Date,
            nadir: Int,
            configuration: TIRAnalysisConfiguration,
            carbEntries: [CarbsEntry]?,
            iobHistory: [IOBTick0]?,
            pumpHistory: [PumpHistoryEvent]?,
            allGlucose: [BloodGlucose]
        ) -> TIREventCategory {
            let lookbackStart = start.addingTimeInterval(-90 * 60)
            let hadRecentHigh = allGlucose.contains {
                $0.dateString >= lookbackStart &&
                    $0.dateString < start &&
                    ThresholdCrossingDetector.sgvValue($0) > Int(configuration.highThresholdMgdL)
            }
            if hadRecentHigh { return .reboundLow }

            if end.timeIntervalSince(start) >= 45 * 60 { return .persistentLow }

            let recentIOB = iobHistory?.filter { $0.time >= start.addingTimeInterval(-60 * 60) && $0.time <= start }
            let maxRecentIOB = recentIOB?.map { NSDecimalNumber(decimal: $0.iob).doubleValue }.max() ?? 0
            let recentInsulinAction = (pumpHistory ?? []).contains {
                $0.timestamp >= start.addingTimeInterval(-75 * 60) &&
                    $0.timestamp <= start &&
                    ($0.type == .smb || $0.type == .bolus || $0.isSMB == true)
            }
            let recentCarbs = (carbEntries ?? []).contains {
                let d = $0.actualDate ?? $0.createdAt
                return d >= start.addingTimeInterval(-2 * 60 * 60) && d <= start
            }
            if maxRecentIOB < 0.3, !recentInsulinAction, !recentCarbs, nadir >= 54 {
                return .fallingWithoutActiveInsulin
            }

            return .unclassifiedLow
        }

        private func lowFactors(
            category: TIREventCategory,
            nadir: Int,
            durationMinutes: Int
        ) -> [TIRContributingFactor] {
            switch category {
            case .reboundLow:
                return [
                    TIRContributingFactor(
                        factor: "Recent high before low",
                        evidence: "Low followed a recent high/correction window",
                        actionable: true,
                        suggestion: "Review correction intensity and timing to reduce rebound lows"
                    )
                ]
            case .persistentLow:
                return [
                    TIRContributingFactor(
                        factor: "Sustained low duration",
                        evidence: "Low range persisted for \(durationMinutes) minutes (nadir \(nadir) mg/dL)",
                        actionable: true,
                        suggestion: "Review basal profile and correction strategy around this period"
                    )
                ]
            case .fallingWithoutActiveInsulin:
                return [
                    TIRContributingFactor(
                        factor: "Drop without active insulin",
                        evidence: "No recent active insulin signal detected before this low",
                        actionable: true,
                        suggestion: "Consider basal, activity, or meal-timing contributors"
                    )
                ]
            default:
                return []
            }
        }

        private enum TIRSimulationScenario: String {
            case mixedRealistic = "mixed_realistic"
            case reboundHeavy = "rebound_heavy"
            case postGapHeavy = "post_gap_heavy"
            case constraintLimited = "constraint_limited"

            var title: String {
                switch self {
                case .mixedRealistic: "Mixed realistic"
                case .reboundHeavy: "Rebound-focused"
                case .postGapHeavy: "Post-gap focused"
                case .constraintLimited: "Constraint-limited"
                }
            }
        }

        private func buildSimulationInput(
            scenario: TIRSimulationScenario,
            windowStart: Date,
            windowEnd: Date,
            baseConfiguration: TIRAnalysisConfiguration
        ) -> TIRAnalysisInput {
            let safeMaxIOB = max(baseConfiguration.maxIOB, 3)
            let configuration = TIRAnalysisConfiguration(
                highThresholdMgdL: baseConfiguration.highThresholdMgdL,
                lowThresholdMgdL: baseConfiguration.lowThresholdMgdL,
                maxIOB: safeMaxIOB,
                windowStart: baseConfiguration.windowStart,
                windowEnd: baseConfiguration.windowEnd,
                units: baseConfiguration.units
            )

            var gapIntervals: [DateInterval] = []
            let lows: [DateInterval]
            let highs: [DateInterval]
            let carbs: [CarbsEntry]
            var pumpEvents: [PumpHistoryEvent] = []
            var iobTicks: [IOBTick0] = []

            switch scenario {
            case .reboundHeavy:
                lows = [
                    interval(31.0, 30.2, from: windowEnd),
                    interval(12.8, 12.1, from: windowEnd),
                    interval(5.8, 5.1, from: windowEnd)
                ]
                highs = [
                    interval(30, 29, from: windowEnd),
                    interval(12, 11.2, from: windowEnd),
                    interval(5, 4.2, from: windowEnd)
                ]
                carbs = [
                    carb(hoursBeforeEnd: 6.5, grams: 24, windowEnd: windowEnd)
                ]
            case .postGapHeavy:
                lows = []
                highs = [
                    interval(30, 28.8, from: windowEnd),
                    interval(13, 11.8, from: windowEnd),
                    interval(6, 4.8, from: windowEnd)
                ]
                carbs = []
                gapIntervals = [
                    interval(30.6, 30.1, from: windowEnd),
                    interval(13.6, 13.1, from: windowEnd),
                    interval(6.6, 6.1, from: windowEnd)
                ]
            case .constraintLimited:
                lows = []
                highs = [
                    interval(26, 22.5, from: windowEnd),
                    interval(13, 10.5, from: windowEnd),
                    interval(6, 3.5, from: windowEnd)
                ]
                carbs = []
                iobTicks = iobTicksNearCeiling(for: highs, maxIOB: safeMaxIOB)
            case .mixedRealistic:
                lows = [interval(45.8, 45.2, from: windowEnd)]
                highs = [
                    interval(45, 44, from: windowEnd), // rebound
                    interval(34, 32.8, from: windowEnd), // post-gap
                    interval(22, 19, from: windowEnd), // constraint-limited
                    interval(12, 8.5, from: windowEnd), // rising w/o carbs
                    interval(7, 3, from: windowEnd) // persistent elevation
                ]
                gapIntervals = [interval(34.6, 34.1, from: windowEnd)]
                carbs = [
                    carb(hoursBeforeEnd: 43.2, grams: 18, windowEnd: windowEnd),
                    carb(hoursBeforeEnd: 20.5, grams: 22, windowEnd: windowEnd)
                ]
                iobTicks = iobTicksNearCeiling(for: [interval(22, 19, from: windowEnd)], maxIOB: safeMaxIOB)
                pumpEvents = smbEvents(for: [interval(7, 3, from: windowEnd)], windowEnd: windowEnd)
            }

            if scenario == .constraintLimited {
                pumpEvents = smbEvents(for: [interval(7, 3, from: windowEnd)], windowEnd: windowEnd)
            }

            let glucose = simulatedGlucose(
                windowStart: windowStart,
                windowEnd: windowEnd,
                highs: highs,
                lows: lows,
                gaps: gapIntervals,
                highThreshold: configuration.highThresholdMgdL
            )

            return TIRAnalysisInput(
                glucose: glucose,
                carbEntries: carbs.isEmpty ? nil : carbs,
                pumpHistory: pumpEvents.isEmpty ? nil : pumpEvents,
                iobHistory: iobTicks.isEmpty ? nil : iobTicks,
                configuration: configuration
            )
        }

        private func simulatedGlucose(
            windowStart: Date,
            windowEnd: Date,
            highs: [DateInterval],
            lows: [DateInterval],
            gaps: [DateInterval],
            highThreshold: Double
        ) -> [BloodGlucose] {
            var points: [BloodGlucose] = []
            var timestamp = windowStart
            var index = 0

            while timestamp <= windowEnd {
                if gaps.contains(where: { $0.contains(timestamp) }) {
                    timestamp = timestamp.addingTimeInterval(300)
                    continue
                }

                let base = 110 + (index % 5)
                var value = base
                if lows.contains(where: { $0.contains(timestamp) }) {
                    value = 64
                }
                if highs.contains(where: { $0.contains(timestamp) }) {
                    value = Int(max(highThreshold + 25, 178))
                }

                points.append(BloodGlucose(
                    _id: "sim_\(index)",
                    sgv: value,
                    date: Decimal(timestamp.timeIntervalSince1970 * 1000),
                    dateString: timestamp,
                    glucose: value
                ))
                timestamp = timestamp.addingTimeInterval(300)
                index += 1
            }

            return points
        }

        private func smbEvents(for windows: [DateInterval], windowEnd: Date) -> [PumpHistoryEvent] {
            var events: [PumpHistoryEvent] = []
            var index = 0
            for window in windows {
                var t = window.start.addingTimeInterval(20 * 60)
                while t <= window.end {
                    events.append(PumpHistoryEvent(
                        id: "sim_smb_\(index)",
                        type: .smb,
                        timestamp: t,
                        amount: 0.35,
                        isSMB: true
                    ))
                    t = t.addingTimeInterval(20 * 60)
                    index += 1
                }
            }
            if events.isEmpty {
                events.append(PumpHistoryEvent(
                    id: "sim_smb_default",
                    type: .smb,
                    timestamp: windowEnd.addingTimeInterval(-90 * 60),
                    amount: 0.35,
                    isSMB: true
                ))
            }
            return events
        }

        private func iobTicksNearCeiling(for windows: [DateInterval], maxIOB: Double) -> [IOBTick0] {
            var ticks: [IOBTick0] = []
            for window in windows {
                var t = window.start
                while t <= window.end {
                    ticks.append(IOBTick0(
                        time: t,
                        iob: Decimal(maxIOB * 0.98),
                        activity: 0.03
                    ))
                    t = t.addingTimeInterval(5 * 60)
                }
            }
            return ticks
        }

        private func interval(_ hoursBeforeEndStart: Double, _ hoursBeforeEndEnd: Double, from windowEnd: Date) -> DateInterval {
            let start = windowEnd.addingTimeInterval(-hoursBeforeEndStart * 3600)
            let end = windowEnd.addingTimeInterval(-hoursBeforeEndEnd * 3600)
            return DateInterval(start: min(start, end), end: max(start, end))
        }

        private func carb(hoursBeforeEnd: Double, grams: Decimal, windowEnd: Date) -> CarbsEntry {
            let date = windowEnd.addingTimeInterval(-hoursBeforeEnd * 3600)
            return CarbsEntry(
                id: "sim_carb_\(Int(hoursBeforeEnd * 10))",
                createdAt: date,
                actualDate: date,
                carbs: grams,
                fat: nil,
                protein: nil,
                note: "Simulator meal",
                enteredBy: CarbsEntry.manual,
                isFPU: false
            )
        }
    }
}
