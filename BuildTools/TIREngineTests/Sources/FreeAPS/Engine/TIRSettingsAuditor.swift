import Foundation

enum AuditSeverity: Equatable {
    case watch
    case ok
}

struct TIRSettingsAuditFinding {
    let severity: AuditSeverity
    let message: String
    let suggestion: String?
}

struct TIRSettingsAuditReport {
    let findings: [TIRSettingsAuditFinding]
}

enum TIRSettingsAuditor {
    static func audit(settings: FreeAPSSettings, preferences: Preferences) -> TIRSettingsAuditReport {
        var findings: [TIRSettingsAuditFinding] = []

        let autosensMax = NSDecimalNumber(decimal: preferences.autosensMax).doubleValue
        let adjustmentFactor = NSDecimalNumber(decimal: preferences.adjustmentFactor).doubleValue
        if preferences.sigmoid, autosensMax > 1.5 {
            findings.append(TIRSettingsAuditFinding(
                severity: .watch,
                message: String(
                    format: "Sigmoid is enabled with autosens max %.2f and AF %.2f. This can make dynamic sensitivity adjustments steeper at high BG.",
                    autosensMax,
                    adjustmentFactor
                ),
                suggestion: "If corrections feel too aggressive or variable, consider lowering autosens max toward 1.4-1.5."
            ))
        } else {
            findings.append(TIRSettingsAuditFinding(
                severity: .ok,
                message: String(
                    format: "Sigmoid/autosens combination looks conservative (sigmoid %@, autosens max %.2f).",
                    preferences.sigmoid ? "on" : "off",
                    autosensMax
                ),
                suggestion: nil
            ))
        }

        let maxDelta = NSDecimalNumber(decimal: preferences.maxDeltaBGthreshold).doubleValue
        if preferences.enableUAM, maxDelta < 0.25 {
            findings.append(TIRSettingsAuditFinding(
                severity: .watch,
                message: String(
                    format: "Max Delta-BG threshold is %.2f with UAM enabled. Lower values can suppress SMB response after CGM reconnection gaps.",
                    maxDelta
                ),
                suggestion: "Consider testing a threshold near 0.30 if post-gap highs are frequent."
            ))
        } else {
            findings.append(TIRSettingsAuditFinding(
                severity: .ok,
                message: String(
                    format: "Max Delta-BG threshold %.2f with UAM %@ does not indicate elevated post-gap suppression risk.",
                    maxDelta,
                    preferences.enableUAM ? "enabled" : "disabled"
                ),
                suggestion: nil
            ))
        }

        let maxIOB = NSDecimalNumber(decimal: preferences.maxIOB).doubleValue
        if maxIOB <= 0 {
            findings.append(TIRSettingsAuditFinding(
                severity: .watch,
                message: "Max IOB is set to 0U, which can strongly limit automated correction headroom.",
                suggestion: "If constraint-limited highs are common, consider a cautious Max IOB increase with close monitoring."
            ))
        } else if maxIOB < 2 {
            findings.append(TIRSettingsAuditFinding(
                severity: .watch,
                message: String(format: "Max IOB is %.1fU, which may be too restrictive for many correction scenarios.", maxIOB),
                suggestion: "Compare Max IOB to typical correction needs before adjusting."
            ))
        } else {
            findings.append(TIRSettingsAuditFinding(
                severity: .ok,
                message: String(format: "Max IOB (%.1fU) provides meaningful correction headroom.", maxIOB),
                suggestion: nil
            ))
        }

        let maxSmbMinutes = NSDecimalNumber(decimal: preferences.maxSMBBasalMinutes).doubleValue
        let minimumSmb = NSDecimalNumber(decimal: settings.minimumSMB).doubleValue
        if maxSmbMinutes <= 0 {
            findings.append(TIRSettingsAuditFinding(
                severity: .watch,
                message: "Max SMB Basal Minutes is 0, so SMB boluses are effectively disabled.",
                suggestion: "Set a non-zero SMB basal-minute cap if automated correction boluses are desired."
            ))
        } else if maxSmbMinutes > 60 {
            findings.append(TIRSettingsAuditFinding(
                severity: .watch,
                message: String(
                    format: "Max SMB Basal Minutes is %.0f with minimum SMB %.2fU, which may allow larger correction boluses than intended.",
                    maxSmbMinutes,
                    minimumSmb
                ),
                suggestion: "Verify this cap against your basal profile and correction tolerance."
            ))
        } else {
            findings.append(TIRSettingsAuditFinding(
                severity: .ok,
                message: String(
                    format: "Max SMB Basal Minutes (%.0f) and minimum SMB %.2fU are within a commonly used range.",
                    maxSmbMinutes,
                    minimumSmb
                ),
                suggestion: nil
            ))
        }

        return TIRSettingsAuditReport(findings: findings)
    }
}
