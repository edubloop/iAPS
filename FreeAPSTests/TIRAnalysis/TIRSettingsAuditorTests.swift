@testable import FreeAPS
import XCTest

final class TIRSettingsAuditorTests: XCTestCase {
    // MARK: - Smoke

    /// Ensures the auditor always produces at least one finding per check.
    /// Using >= so adding new checks in the future doesn't break this test.
    func test_auditAlwaysReturnsAtLeastFourFindings() {
        let report = TIRSettingsAuditor.audit(settings: FreeAPSSettings(), preferences: Preferences())
        XCTAssertGreaterThanOrEqual(report.findings.count, 4)
    }

    // MARK: - Check 1: Sigmoid / autosens

    func test_sigmoidHighAutosens_isWatch() {
        var prefs = Preferences()
        prefs.sigmoid = true
        prefs.autosensMax = 1.6
        let report = TIRSettingsAuditor.audit(settings: FreeAPSSettings(), preferences: prefs)
        XCTAssertTrue(
            report.findings.contains { $0.severity == .watch && $0.message.contains("Sigmoid is enabled") },
            "Expected .watch for sigmoid=true && autosensMax > 1.5"
        )
    }

    func test_sigmoidDefaultValues_isOk() {
        // sigmoid=false, autosensMax=1.2 — both safe
        let report = TIRSettingsAuditor.audit(settings: FreeAPSSettings(), preferences: Preferences())
        XCTAssertTrue(
            report.findings.contains { $0.severity == .ok && $0.message.contains("looks conservative") },
            "Expected .ok for default sigmoid/autosens settings"
        )
    }

    // MARK: - Check 2: UAM + maxDeltaBGthreshold

    func test_uamLowDelta_isWatch() {
        var prefs = Preferences()
        prefs.enableUAM = true
        prefs.maxDeltaBGthreshold = 0.2
        let report = TIRSettingsAuditor.audit(settings: FreeAPSSettings(), preferences: prefs)
        XCTAssertTrue(
            report.findings.contains { $0.severity == .watch && $0.message.contains("Delta-BG threshold") },
            "Expected .watch for UAM + maxDeltaBGthreshold < 0.25"
        )
    }

    func test_uamDefaultValues_isOk() {
        // enableUAM=false, maxDeltaBGthreshold=0.3 — both safe
        let report = TIRSettingsAuditor.audit(settings: FreeAPSSettings(), preferences: Preferences())
        XCTAssertTrue(
            report.findings.contains { $0.severity == .ok && $0.message.contains("does not indicate elevated post-gap") },
            "Expected .ok for default UAM/delta settings"
        )
    }

    // MARK: - Check 3: Max IOB

    func test_zeroMaxIOB_isWatch() {
        var prefs = Preferences()
        prefs.maxIOB = 0
        let report = TIRSettingsAuditor.audit(settings: FreeAPSSettings(), preferences: prefs)
        XCTAssertTrue(
            report.findings.contains { $0.severity == .watch && $0.message.contains("Max IOB is set to 0U") },
            "Expected .watch for maxIOB == 0"
        )
    }

    func test_lowNonZeroMaxIOB_isWatch() {
        var prefs = Preferences()
        prefs.maxIOB = 1.5
        let report = TIRSettingsAuditor.audit(settings: FreeAPSSettings(), preferences: prefs)
        XCTAssertTrue(
            report.findings.contains { $0.severity == .watch && $0.message.contains("1.5U") },
            "Expected .watch for 0 < maxIOB < 2"
        )
    }

    func test_adequateMaxIOB_isOk() {
        var prefs = Preferences()
        prefs.maxIOB = 3.0
        let report = TIRSettingsAuditor.audit(settings: FreeAPSSettings(), preferences: prefs)
        XCTAssertTrue(
            report.findings.contains { $0.severity == .ok && $0.message.contains("correction headroom") },
            "Expected .ok for maxIOB >= 2"
        )
    }

    // MARK: - Check 4: Max SMB Basal Minutes

    func test_zeroSMBMinutes_isWatch() {
        var prefs = Preferences()
        prefs.maxSMBBasalMinutes = 0
        let report = TIRSettingsAuditor.audit(settings: FreeAPSSettings(), preferences: prefs)
        XCTAssertTrue(
            report.findings.contains { $0.severity == .watch && $0.message.contains("effectively disabled") },
            "Expected .watch for maxSMBBasalMinutes == 0"
        )
    }

    func test_excessiveSMBMinutes_isWatch() {
        var prefs = Preferences()
        prefs.maxSMBBasalMinutes = 90
        let report = TIRSettingsAuditor.audit(settings: FreeAPSSettings(), preferences: prefs)
        XCTAssertTrue(
            report.findings.contains { $0.severity == .watch && $0.message.contains("Max SMB Basal Minutes is 90") },
            "Expected .watch for maxSMBBasalMinutes > 60"
        )
    }

    func test_reasonableSMBMinutes_isOk() {
        var prefs = Preferences()
        prefs.maxSMBBasalMinutes = 30
        let report = TIRSettingsAuditor.audit(settings: FreeAPSSettings(), preferences: prefs)
        XCTAssertTrue(
            report.findings.contains { $0.severity == .ok && $0.message.contains("Max SMB Basal Minutes") },
            "Expected .ok for maxSMBBasalMinutes in safe range (1–60)"
        )
    }
}
