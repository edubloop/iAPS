import Foundation
import Swinject

// Track 2: Full data-layer implementation.
// Fetches glucose + carbs via HealthKit (multi-day), pump history from file
// storage (24 h limit), then calls TIRAnalysisEngine.analyze(_:).

extension TIRAnalysis {
    final class Provider: BaseProvider, TIRAnalysisProvider {
        @Injected() var pumpHistoryStorage: PumpHistoryStorage!
        @Injected() var settingsManager: SettingsManager!

        private let hkReader = TIRHealthKitReader()

        // MARK: - TIRAnalysisProvider

        func runAnalysis(windowDays: Int) async -> TIRAnalysisResult {
            let now = Date()
            let windowEnd = now
            let windowStart = windowEnd.addingTimeInterval(TimeInterval(-windowDays) * 86_400)

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

            // 2. Fetch glucose from HealthKit — primary source for multi-day windows.
            //    File storage (GlucoseStorage) only retains 24 hours.
            let glucose = await hkReader.fetchGlucose(from: windowStart, to: windowEnd)

            // 3. Fetch carbs from HealthKit. Returns [] if permission not granted;
            //    treat as nil so EventClassifier degrades RISING_WITHOUT_CARBS to .low.
            let hkCarbs = await hkReader.fetchCarbs(from: windowStart, to: windowEnd)
            let carbEntries: [CarbsEntry]? = hkCarbs.isEmpty ? nil : hkCarbs

            // 4. Fetch recent pump history from file storage (24 h retention limit).
            //    Used for PERSISTENT_ELEVATION (SMB detection) within the recent window.
            let recentPump = pumpHistoryStorage.recent().filter {
                $0.timestamp.addingTimeInterval(24 * 3_600) > now
            }

            // 5. Run engine. IOB history unavailable in iAPS (no rolling store).
            let input = TIRAnalysisInput(
                glucose: glucose,
                carbEntries: carbEntries,
                pumpHistory: recentPump.isEmpty ? nil : recentPump,
                iobHistory: nil, // CONSTRAINT_LIMITED skipped; no rolling IOB history.
                configuration: configuration
            )
            let events = TIRAnalysisEngine.analyze(input)

            // 6. Compute window coverage + caveats.
            let coverage = buildCoverage(
                glucose: glucose,
                carbEntries: carbEntries,
                pumpHistory: recentPump,
                windowDays: windowDays,
                windowEnd: windowEnd
            )

            debug(.service, "TIR analysis complete: \(events.count) events, coverage \(Int(coverage.glucoseCoverage * 100))%")
            return TIRAnalysisResult(events: events, windowCoverage: coverage, analysisDate: now)
        }

        // MARK: - Private

        private func buildCoverage(
            glucose: [BloodGlucose],
            carbEntries: [CarbsEntry]?,
            pumpHistory: [PumpHistoryEvent],
            windowDays: Int,
            windowEnd: Date
        ) -> WindowCoverage {
            let actualCount = glucose.count
            let expectedCount = windowDays * 288
            let ratio = expectedCount > 0 ? Double(actualCount) / Double(expectedCount) : 0.0

            var caveats: [String] = []

            if actualCount == 0 {
                caveats.append(
                    "No glucose data found in HealthKit for the \(windowDays)-day window. " +
                        "Verify Apple Health access is enabled and your CGM app writes to Apple Health."
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
                    "Carb data unavailable from HealthKit. " +
                        "RISING_WITHOUT_CARBS events are reported with .low confidence."
                )
            }

            if pumpHistory.isEmpty {
                caveats.append(
                    "No recent pump history available. " +
                        "PERSISTENT_ELEVATION SMB factor detail is limited."
                )
            }

            return WindowCoverage(
                windowDays: windowDays,
                analysisEnd: windowEnd,
                glucoseRecordCount: actualCount,
                carbDataAvailable: carbEntries != nil,
                pumpDataAvailable: !pumpHistory.isEmpty,
                caveats: caveats
            )
        }
    }
}
