import Combine
import Foundation
import SwiftUI
import Swinject

// Track 2: StateModel with @Published engine results and on-demand analysis trigger.
// Track 5 will add UI-binding properties and navigation hooks.

extension TIRAnalysis {
    final class StateModel: BaseStateModel<Provider> {
        // MARK: - Published state

        /// The most recent analysis result. nil until triggerAnalysis() completes.
        @Published var analysisResult: TIRAnalysisResult? = nil

        /// True while an analysis run is in progress.
        @Published var isAnalyzing: Bool = false

        /// Analysis window in days. Supported values: 7, 14, 30.
        @Published var windowDays: Int = 14

        /// First caveat from the most recent result's WindowCoverage, if any.
        /// Used by Track 5 UI to surface data-quality warnings.
        @Published var coverageCaveat: String? = nil

        /// Static settings-risk audit report (Track 4).
        @Published var auditReport: TIRSettingsAuditReport? = nil

        // MARK: - Actions

        /// Runs analysis on demand. Concurrent calls are silently ignored.
        /// Updates `analysisResult` and `isAnalyzing` on the main actor when done.
        func triggerAnalysis() {
            guard !isAnalyzing else { return }
            isAnalyzing = true
            coverageCaveat = nil
            refreshAuditReport()
            let days = windowDays
            Task {
                let result = await provider.runAnalysis(windowDays: days)
                await MainActor.run {
                    self.analysisResult = result
                    self.coverageCaveat = result.windowCoverage.caveats.first
                    self.isAnalyzing = false
                }
            }
        }

        // MARK: - BaseStateModel

        override func subscribe() {
            // On-demand analysis; static settings audit can be shown immediately.
            refreshAuditReport()
        }

        func refreshAuditReport() {
            auditReport = TIRSettingsAuditor.audit(
                settings: settingsManager.settings,
                preferences: settingsManager.preferences
            )
        }
    }
}
