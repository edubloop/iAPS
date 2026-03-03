import SwiftUI

struct TIRCategoryDetailView: View {
    let title: String
    let events: [TIREvent]

    private var timeOfDayBuckets: TimeOfDayBuckets {
        let calendar = Calendar.current
        var overnight = 0, morning = 0, afternoon = 0, evening = 0
        for event in events {
            switch calendar.component(.hour, from: event.start) {
            case 0 ..< 6: overnight += 1
            case 6 ..< 12: morning += 1
            case 12 ..< 18: afternoon += 1
            default: evening += 1
            }
        }
        return TimeOfDayBuckets(overnight: overnight, morning: morning, afternoon: afternoon, evening: evening)
    }

    var body: some View {
        List {
            if events.isEmpty {
                Text("No events found in this category for the selected window.")
                    .foregroundColor(.secondary)
            } else {
                let buckets = timeOfDayBuckets
                if buckets.total > 0 {
                    Section("Time of Day") {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(
                                [
                                    ("Overnight (0–6)", buckets.overnight),
                                    ("Morning (6–12)", buckets.morning),
                                    ("Afternoon (12–18)", buckets.afternoon),
                                    ("Evening (18–24)", buckets.evening)
                                ],
                                id: \.0
                            ) { label, count in
                                HStack(spacing: 8) {
                                    Text(label)
                                        .font(.caption)
                                        .frame(width: 130, alignment: .leading)
                                    ProgressView(value: Double(count), total: Double(max(buckets.total, 1)))
                                    Text("\(count)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .frame(width: 20, alignment: .trailing)
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }

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
