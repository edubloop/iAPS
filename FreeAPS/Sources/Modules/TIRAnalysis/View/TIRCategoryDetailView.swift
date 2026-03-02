import SwiftUI

struct TIRCategoryDetailView: View {
    let title: String
    let events: [TIREvent]

    var body: some View {
        List {
            if events.isEmpty {
                Text("No events found in this category for the selected window.")
                    .foregroundColor(.secondary)
            } else {
                ForEach(events) { event in
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Duration")
                                Spacer()
                                Text("\(event.durationMinutes) min")
                                    .foregroundColor(.secondary)
                            }
                            HStack {
                                Text("Peak")
                                Spacer()
                                Text("\(event.peakSeverity) mg/dL")
                                    .foregroundColor(.secondary)
                            }
                            HStack {
                                Text("Confidence")
                                Spacer()
                                Text(event.confidence.rawValue.capitalized)
                                    .foregroundColor(.secondary)
                            }
                            if !event.contributingFactors.isEmpty {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Contributing Factors")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    ForEach(Array(event.contributingFactors.enumerated()), id: \.offset) { _, factor in
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(factor.factor)
                                                .font(.subheadline)
                                                .fontWeight(.semibold)
                                            Text(factor.evidence)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                            if let suggestion = factor.suggestion {
                                                Text(suggestion)
                                                    .font(.caption)
                                                    .foregroundColor(factor.actionable ? .orange : .secondary)
                                            }
                                        }
                                        .padding(8)
                                        .background(Color(.secondarySystemBackground))
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                    }
                                }
                            }
                        }
                    } header: {
                        Text(event.start, style: .time) + Text(" - ") + Text(event.end, style: .time)
                    }
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
