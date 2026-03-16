import SwiftUI

struct TIRSummaryView: View {
    @ObservedObject var state: TIRAnalysis.StateModel

    private let supportedWindows = [7, 14, 30, 90]

    var body: some View {
        List {
            Section {
                Picker("Window", selection: $state.windowDays) {
                    ForEach(supportedWindows, id: \.self) { days in
                        Text("\(days) days").tag(days)
                    }
                }
                .pickerStyle(.segmented)

                if let result = state.analysisResult {
                    VStack(alignment: .leading, spacing: 8) {
                        coverageIndicator(result.readiness)
                        Text("Time in Range")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(result.rangeBreakdown.inRange, format: .percent.precision(.fractionLength(1)))
                            .font(.title2)
                            .fontWeight(.bold)
                        Text(
                            "Estimated impacted by patterns: \(result.totalTIRCost, format: .percent.precision(.fractionLength(1)))"
                        )
                        .font(.caption)
                        .foregroundColor(.secondary)
                        rangeBar(result.rangeBreakdown)
                        rangeLegend(result.rangeBreakdown)
                        Text(
                            "Last updated: \(result.analysisDate, format: .dateTime.day().month(.wide).year().hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))"
                        )
                        .font(.caption)
                        .foregroundColor(.secondary)
                        if let source = result.windowCoverage.caveats.first(where: { $0.hasPrefix("Data source:") }) {
                            Text(source)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                if let notice = state.analysisError {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text(notice)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Button {
                    state.triggerAnalysis()
                } label: {
                    HStack {
                        if state.isAnalyzing {
                            ProgressView().padding(.trailing, 6)
                        }
                        Text(state.isAnalyzing ? "Analyzing..." : "Run Analysis")
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .buttonStyle(.borderedProminent)
                .disabled(state.isAnalyzing)
            }

            if let result = state.analysisResult, !result.recommendations.isEmpty {
                Section("Patterns & Suggestions") {
                    ForEach(Array(result.recommendations.enumerated()), id: \.offset) { _, rec in
                        recommendationRow(rec, result: result)
                    }
                }
            }

            if let result = state.analysisResult {
                Section("High Patterns") {
                    breakdownRow(result: result, category: .reboundHigh)
                    breakdownRow(result: result, category: .persistentElevation)
                    breakdownRow(result: result, category: .risingWithoutCarbs)
                    breakdownRow(result: result, category: .constraintLimited)
                }

                Section("Low Patterns") {
                    breakdownRow(result: result, category: .compressionLow)
                    breakdownRow(result: result, category: .overcorrectionLow)
                    breakdownRow(result: result, category: .stackingLow)
                    breakdownRow(result: result, category: .activityRelatedLow)
                    breakdownRow(result: result, category: .reboundLow)
                    breakdownRow(result: result, category: .basalTooAggressive)
                    breakdownRow(result: result, category: .fallingWithoutActiveInsulin)
                    breakdownRow(result: result, category: .persistentLow)
                }

                Section("Data Quality") {
                    breakdownRow(result: result, category: .postConnectivityGap)
                }

                Section("Unclassified Outliers") {
                    let highOutlierCost = result.tirCost(for: .unclassifiedHigh)
                    let lowOutlierCost = result.tirCost(for: .unclassifiedLow)
                    let outlierEvents = result.events(for: .unclassifiedHigh) + result.events(for: .unclassifiedLow)

                    NavigationLink {
                        TIRCategoryDetailView(
                            title: "Unclassified Outliers",
                            events: outlierEvents.sorted { $0.start < $1.start }
                        )
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Unclassified Outliers")
                                Spacer()
                                Text(
                                    "High \(highOutlierCost, format: .percent.precision(.fractionLength(1))) • Low \(lowOutlierCost, format: .percent.precision(.fractionLength(1)))"
                                )
                                .font(.caption)
                                .foregroundColor(.secondary)
                            }
                            ProgressView(value: highOutlierCost + lowOutlierCost, total: max(result.totalTIRCost, 0.0001))
                            Text("\(outlierEvents.count) events")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .onChange(of: state.windowDays) { _ in
            state.triggerAnalysis()
        }
        .onAppear {
            if state.analysisResult == nil {
                state.triggerAnalysis()
            } else {
                state.refreshAuditReport()
            }
        }
    }

    @ViewBuilder private func coverageIndicator(_ readiness: TIRReadiness) -> some View {
        let available = readiness.fullDaysAvailable
        let required = readiness.requiredFullDays
        let fraction = required > 0 ? Double(available) / Double(required) : 1.0
        VStack(alignment: .leading, spacing: 4) {
            if required <= 14 {
                HStack(spacing: 3) {
                    ForEach(0 ..< required, id: \.self) { i in
                        Circle()
                            .fill(i < available ? Color.accentColor : Color.secondary.opacity(0.25))
                            .frame(width: 8, height: 8)
                    }
                }
            } else {
                ProgressView(value: fraction)
                    .frame(maxWidth: 160)
            }
            Text(coverageLabel(fraction: fraction, available: available, required: required))
                .font(.caption)
                .foregroundColor(fraction < 0.4 ? .orange : .secondary)
        }
    }

    private func coverageLabel(fraction: Double, available: Int, required: Int) -> String {
        let confidence: String
        if fraction >= 0.8 { confidence = "High confidence" } else if fraction >= 0.4 { confidence = "Medium confidence" } else { confidence = "Low confidence" }
        return "\(available)/\(required) days · \(confidence)"
    }

    @ViewBuilder private func breakdownRow(result: TIRAnalysisResult, category: TIREventCategory) -> some View {
        let pattern = result.pattern(for: category)
        NavigationLink {
            TIRCategoryDetailView(title: title(for: category), events: result.events(for: category))
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(title(for: category))
                    Spacer()
                    Text(result.tirCost(for: category), format: .percent.precision(.fractionLength(1)))
                        .foregroundColor(.secondary)
                }
                ProgressView(value: result.tirCost(for: category), total: max(result.totalTIRCost, 0.0001))
                Text(patternCaption(pattern))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 2)
        }
    }

    private func patternCaption(_ pattern: TIRCategoryPattern) -> String {
        let count = pattern.eventCount
        let base = "\(count) event\(count == 1 ? "" : "s")"
        if let period = pattern.timeOfDayBuckets.dominantPeriod {
            return "\(base) · mostly \(period)"
        }
        return base
    }

    @ViewBuilder private func rangeBar(_ range: TIRRangeBreakdown) -> some View {
        GeometryReader { proxy in
            HStack(spacing: 1) {
                Color.red.opacity(0.95).frame(width: proxy.size.width * range.veryLow)
                Color.orange.opacity(0.95).frame(width: proxy.size.width * range.low)
                Color.green.opacity(0.9).frame(width: proxy.size.width * range.inRange)
                Color.yellow.opacity(0.9).frame(width: proxy.size.width * range.high)
                Color.orange.opacity(0.7).frame(width: proxy.size.width * range.veryHigh)
            }
            .frame(height: 12)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .frame(height: 12)
    }

    @ViewBuilder private func rangeLegend(_ range: TIRRangeBreakdown) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(
                "Very Low \(range.veryLow, format: .percent.precision(.fractionLength(1))) • Low \(range.low, format: .percent.precision(.fractionLength(1)))"
            )
            .font(.caption)
            .foregroundColor(.secondary)
            Text(
                "In Range \(range.inRange, format: .percent.precision(.fractionLength(1))) • High \(range.high, format: .percent.precision(.fractionLength(1))) • Very High \(range.veryHigh, format: .percent.precision(.fractionLength(1)))"
            )
            .font(.caption)
            .foregroundColor(.secondary)
        }
    }

    @ViewBuilder private func recommendationRow(_ rec: TIRRecommendation, result: TIRAnalysisResult) -> some View {
        let icon: String = {
            switch rec.source {
            case .settingsAudit: return "gearshape.fill"
            case .crossReferenced: return "lightbulb.fill"
            case .pattern: return rec.depth == .specific ? "lightbulb.fill" : "info.circle"
            }
        }()
        let iconColor: Color = {
            switch rec.source {
            case .crossReferenced,
                 .settingsAudit: return .orange
            case .pattern: return rec.depth == .specific ? .orange : .secondary
            }
        }()

        NavigationLink {
            if let category = rec.category {
                TIRCategoryDetailView(title: title(for: category), events: result.events(for: category))
            } else if let audit = state.auditReport {
                TIRSettingsAuditView(report: audit)
            }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Image(systemName: icon)
                        .foregroundColor(iconColor)
                        .font(.subheadline)
                    if rec.source == .settingsAudit {
                        Text("Settings")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.12))
                            .cornerRadius(4)
                    } else if rec.source == .crossReferenced {
                        Text("Pattern + Settings")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.12))
                            .cornerRadius(4)
                    }
                }
                Text(rec.headline)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(rec.detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 2)
        }
    }

    private func title(for category: TIREventCategory) -> String {
        switch category {
        case .reboundHigh: "Rebound High"
        case .postConnectivityGap: "Post Connectivity Gap"
        case .constraintLimited: "Max Insulin Limit"
        case .risingWithoutCarbs: "Rising Without Carbs"
        case .persistentElevation: "Persistent Elevation"
        case .unclassifiedHigh: "Unclassified High"
        case .compressionLow: "Compression Low"
        case .overcorrectionLow: "Overcorrection Low"
        case .stackingLow: "Stacking Low"
        case .activityRelatedLow: "Activity-Related Low"
        case .reboundLow: "Rebound Low"
        case .basalTooAggressive: "Basal Too Aggressive"
        case .fallingWithoutActiveInsulin: "Falling Without Active Insulin"
        case .persistentLow: "Persistent Low"
        case .unclassifiedLow: "Unclassified Low"
        }
    }
}
