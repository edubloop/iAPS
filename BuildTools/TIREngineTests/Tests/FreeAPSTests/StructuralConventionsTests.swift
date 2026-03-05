import Foundation
import XCTest

final class StructuralConventionsTests: XCTestCase {
    private var repoRoot: URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0 ..< 5 {
            url.deleteLastPathComponent()
        }
        return url
    }

    private func swiftFiles(under relativeDir: String) throws -> [URL] {
        let root = repoRoot.appendingPathComponent(relativeDir, isDirectory: true)
        let keys: [URLResourceKey] = [.isRegularFileKey]
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys)
        var files: [URL] = []

        while case let fileURL as URL = enumerator?.nextObject() {
            guard fileURL.pathExtension == "swift" else { continue }
            let values = try fileURL.resourceValues(forKeys: Set(keys))
            if values.isRegularFile == true {
                files.append(fileURL)
            }
        }

        return files
    }

    private func relativePath(_ url: URL) -> String {
        let rootPath = repoRoot.path.hasSuffix("/") ? repoRoot.path : repoRoot.path + "/"
        return url.path.replacingOccurrences(of: rootPath, with: "")
    }

    func test_secondsPerDayLiteralsScopedToAllowlist() throws {
        let allowlist: Set<String> = [
            "FreeAPS/Sources/APS/APSManager.swift",
            "FreeAPS/Sources/APS/CGM/CGMType.swift",
            "FreeAPS/Sources/APS/KnownPlugins.swift",
            "FreeAPS/Sources/APS/Storage/CoreDataStorage.swift",
            "FreeAPS/Sources/Modules/Dynamic/DynamicStateModel.swift",
            "FreeAPS/Sources/Modules/Home/View/Header/CurrentGlucoseView.swift",
            "FreeAPS/Sources/Modules/Stat/View/StatsView.swift",
            "FreeAPS/Sources/Modules/TIRAnalysis/Engine/TIRModels.swift",
            "FreeAPS/Sources/Modules/TIRAnalysis/TIRAnalysisProvider.swift",
            "FreeAPS/Sources/Views/ViewModifiers.swift"
        ]

        let files = try swiftFiles(under: "FreeAPS/Sources")
        var violations: [String] = []

        for file in files {
            let path = relativePath(file)
            let content = try String(contentsOf: file, encoding: .utf8)
            let containsLiteral = content.contains("8.64E4") || content.contains("86400")
            if containsLiteral, !allowlist.contains(path) {
                violations.append(path)
            }
        }

        XCTAssertTrue(
            violations.isEmpty,
            "Found new day-in-seconds literals outside allowlist: \(violations.sorted())"
        )
    }

    func test_nightscoutProfileEndpointLiteralScopedToAllowlist() throws {
        let endpointLiteral = "/api/v1/profile.json"
        let allowlist: Set<String> = [
            "FreeAPS/Sources/Modules/NightscoutConfig/NightscoutConfigStateModel.swift",
            "FreeAPS/Sources/Services/Network/NightscoutAPI.swift"
        ]

        let files = try swiftFiles(under: "FreeAPS/Sources")
        var violations: [String] = []

        for file in files {
            let path = relativePath(file)
            let content = try String(contentsOf: file, encoding: .utf8)
            if content.contains(endpointLiteral), !allowlist.contains(path) {
                violations.append(path)
            }
        }

        XCTAssertTrue(
            violations.isEmpty,
            "Found duplicated Nightscout profile endpoint literal outside allowlist: \(violations.sorted())"
        )
    }

    func test_deepLinkSchemesScopedToKnownFiles() throws {
        let markers = [
            "dexcomgcgm://",
            "dexcomg6://",
            "dexcomg7://",
            "xdripswift://",
            "libredirect://",
            "freeaps-x://libre-transmitter"
        ]

        let allowlist: Set<String> = [
            "FreeAPS/Sources/APS/CGM/AppGroupCGM/AppGroupSource.swift",
            "FreeAPS/Sources/APS/CGM/CGMType.swift",
            "FreeAPS/Sources/APS/KnownPlugins.swift"
        ]

        let files = try swiftFiles(under: "FreeAPS/Sources")
        var violations: [String] = []

        for file in files {
            let path = relativePath(file)
            let content = try String(contentsOf: file, encoding: .utf8)
            let hasMarker = markers.contains { content.contains($0) }
            if hasMarker, !allowlist.contains(path) {
                violations.append(path)
            }
        }

        XCTAssertTrue(
            violations.isEmpty,
            "Found deep-link scheme literals outside allowed mapping files: \(violations.sorted())"
        )
    }
}
