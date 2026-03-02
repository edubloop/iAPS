import SwiftUI

struct TIRSettingsAuditView: View {
    let report: TIRSettingsAuditReport

    var body: some View {
        List {
            Section {
                Text(summaryText)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            ForEach(Array(report.findings.enumerated()), id: \.offset) { _, finding in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: finding.severity == .watch ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                            .foregroundColor(finding.severity == .watch ? .orange : .green)
                        Text(finding.severity == .watch ? "Needs attention" : "Looks good")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.secondary)
                    }

                    Text("What we see")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(finding.message)
                        .font(.subheadline)

                    Text("Why it matters")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(whyItMatters(for: finding))
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if let suggestion = finding.suggestion {
                        Text("What to try")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(suggestion)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("Settings Audit")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var summaryText: String {
        let warnings = report.findings.filter { $0.severity == .watch }.count
        if warnings == 0 {
            return "Current configuration looks stable for this analysis window."
        }
        return "\(warnings) setting\(warnings == 1 ? "" : "s") may need attention before changing insulin behavior."
    }

    private func whyItMatters(for finding: TIRSettingsAuditFinding) -> String {
        if finding.severity == .watch {
            return "This setting may be contributing to recurring high/low patterns or inconsistent corrections."
        }
        return "This setting is unlikely to be a major contributor to current TIR patterns."
    }
}
