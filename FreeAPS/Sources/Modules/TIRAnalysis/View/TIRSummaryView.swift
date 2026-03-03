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

                Button {
                    state.triggerAnalysis()
                } label: {
                    HStack {
                        if state.isAnalyzing {
                            ProgressView().padding(.trailing, 6)
                        }
                        Text(state.isAnalyzing ? "Analyzing..." : "Run Analysis")
                            .fontWeight(.semibold)
                    }
                }
                .disabled(state.isAnalyzing)

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
                        Text("\(result.events.count) events • \(result.analysisDate, style: .date)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }

            if let caveat = state.coverageCaveat {
                Section {
                    Text(caveat)
                        .font(.footnote)
                        .foregroundColor(.orange)
                } header: {
                    Text("Coverage Caveat")
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
                    breakdownRow(result: result, category: .reboundLow)
                    breakdownRow(result: result, category: .persistentLow)
                    breakdownRow(result: result, category: .fallingWithoutActiveInsulin)
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

            if let result = state.analysisResult, !result.recommendations.isEmpty {
                Section("Patterns & Suggestions") {
                    ForEach(Array(result.recommendations.enumerated()), id: \.offset) { _, rec in
                        NavigationLink {
                            TIRCategoryDetailView(title: title(for: rec.category), events: result.events(for: rec.category))
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Image(systemName: rec.depth == .specific ? "lightbulb.fill" : "info.circle")
                                        .foregroundColor(rec.depth == .specific ? .orange : .secondary)
                                        .font(.caption)
                                    Text(rec.headline)
                                        .fontWeight(.semibold)
                                }
                                Text(rec.detail)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }

            if let audit = state.auditReport {
                Section {
                    NavigationLink {
                        TIRSettingsAuditView(report: audit)
                    } label: {
                        HStack {
                            Text("Settings Audit")
                            Spacer()
                            Text("\(audit.findings.count) findings")
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
        if fraction >= 0.8 { confidence = "High confidence" }
        else if fraction >= 0.4 { confidence = "Medium confidence" }
        else { confidence = "Low confidence" }
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

    private func title(for category: TIREventCategory) -> String {
        switch category {
        case .reboundHigh: "Rebound High"
        case .postConnectivityGap: "Post Connectivity Gap"
        case .constraintLimited: "Max Insulin Limit"
        case .risingWithoutCarbs: "Rising Without Carbs"
        case .persistentElevation: "Persistent Elevation"
        case .unclassifiedHigh: "Unclassified High"
        case .reboundLow: "Rebound Low"
        case .persistentLow: "Persistent Low"
        case .fallingWithoutActiveInsulin: "Falling Without Active Insulin"
        case .unclassifiedLow: "Unclassified Low"
        }
    }
}
