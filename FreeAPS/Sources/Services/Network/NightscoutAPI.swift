import Combine
import CommonCrypto
import Foundation
import JavaScriptCore
import Swinject

class NightscoutAPI {
    init(url: URL, secret: String? = nil) {
        self.url = url
        self.secret = secret?.nonEmpty
    }

    enum Config {
        static let entriesPath = "/api/v1/entries/sgv.json"
        static let uploadEntriesPath = "/api/v1/entries.json"
        static let treatmentsPath = "/api/v1/treatments.json"
        static let statusPath = "/api/v1/devicestatus.json"
        static let profilePath = "/api/v1/profile.json"
        static let sharePath = "/upload.php"
        static let versionPath = "/vcheck.php"
        static let retryCount = 2
        static let timeout: TimeInterval = 60
    }

    enum Error: LocalizedError {
        case badStatusCode
        case missingURL
    }

    let url: URL
    let secret: String?

    private let service = NetworkService()

    @Injected() private var settingsManager: SettingsManager!

    // MARK: - Request builder

    /// Builds a `URLRequest` from components.
    /// Returns `nil` only if `URLComponents` cannot produce a valid URL
    /// (e.g. the host or path is malformed).
    private func makeRequest(
        baseURL: URL? = nil,
        path: String,
        queryItems: [URLQueryItem]? = nil,
        method: String = "GET",
        constrainedNetwork: Bool = false,
        addSecret: Bool = true
    ) -> URLRequest? {
        let base = baseURL ?? url
        var components = URLComponents()
        components.scheme = base.scheme
        components.host = base.host
        components.port = base.port
        components.path = path
        if let items = queryItems, !items.isEmpty {
            components.queryItems = items
        }
        guard let builtURL = components.url else { return nil }
        var request = URLRequest(url: builtURL)
        request.allowsConstrainedNetworkAccess = constrainedNetwork
        request.timeoutInterval = Config.timeout
        request.httpMethod = method
        if addSecret, let secret = secret {
            request.addValue(secret.sha1(), forHTTPHeaderField: "api-secret")
        }
        return request
    }

    private func missingURLPublisher<T>() -> AnyPublisher<T, Swift.Error> {
        Fail(error: NightscoutAPI.Error.missingURL).eraseToAnyPublisher()
    }
}

extension NightscoutAPI {
    func checkConnection() -> AnyPublisher<Void, Swift.Error> {
        struct Check: Codable, Equatable {
            var eventType = "Note"
            var enteredBy = "iAPS"
            var notes = "iAPS connected"
        }
        let check = Check()
        var request = URLRequest(url: url.appendingPathComponent(Config.treatmentsPath))

        if let secret = secret {
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpMethod = "POST"
            request.addValue(secret.sha1(), forHTTPHeaderField: "api-secret")
            request.httpBody = try? JSONCoding.encoder.encode(check)
        } else {
            request.httpMethod = "GET"
        }

        return service.run(request)
            .map { _ in () }
            .eraseToAnyPublisher()
    }

    /// fetch glucose with [ date >= sinceDate AND date < untilDate ]
    func fetchLastGlucose(sinceDate: Date? = nil, untilDate: Date? = nil) -> AnyPublisher<[BloodGlucose], Swift.Error> {
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "count", value: "500"),
            // "date descending" should be the default sorting, but we're specifying it explicitly just in case
            URLQueryItem(name: "sort$desc", value: "dateString")
        ]
        if let date = sinceDate {
            queryItems.append(URLQueryItem(
                name: "find[dateString][$gte]",
                value: Formatter.iso8601withFractionalSeconds.string(from: date)
            ))
        }
        if let date = untilDate {
            queryItems.append(URLQueryItem(
                name: "find[dateString][$lt]",
                value: Formatter.iso8601withFractionalSeconds.string(from: date)
            ))
        }
        guard let request = makeRequest(
            path: Config.entriesPath,
            queryItems: queryItems,
            constrainedNetwork: true
        ) else { return missingURLPublisher() }

        return service.run(request)
            .retry(Config.retryCount)
            .decode(type: [BloodGlucose].self, decoder: JSONCoding.decoder)
            .catch { error -> AnyPublisher<[BloodGlucose], Swift.Error> in
                warning(.nightscout, "Glucose fetching error: \(error.localizedDescription)")
                return Just([]).setFailureType(to: Swift.Error.self).eraseToAnyPublisher()
            }
            .compactMap { glucose in
                glucose
                    .map {
                        var reading = $0
                        reading.glucose = $0.sgv
                        return reading
                    }
            }
            .eraseToAnyPublisher()
    }

    func fetchCarbs(sinceDate: Date? = nil) -> AnyPublisher<[CarbsEntry], Swift.Error> {
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "find[carbs][$exists]", value: "true"),
            URLQueryItem(
                name: "find[enteredBy][$ne]",
                value: CarbsEntry.manual.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
            ),
            URLQueryItem(
                name: "find[enteredBy][$ne]",
                value: CarbsEntry.watch.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
            ),
            URLQueryItem(
                name: "find[enteredBy][$ne]",
                value: CarbsEntry.shortcut.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
            ),
            URLQueryItem(
                name: "find[enteredBy][$ne]",
                value: NigtscoutTreatment.local.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
            ),
            URLQueryItem(
                name: "find[enteredBy][$ne]",
                value: NigtscoutTreatment.trio.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
            )
        ]
        if let date = sinceDate {
            queryItems.append(URLQueryItem(
                name: "find[created_at][$gt]",
                value: Formatter.iso8601withFractionalSeconds.string(from: date)
            ))
        }
        guard let request = makeRequest(path: Config.treatmentsPath, queryItems: queryItems) else {
            return missingURLPublisher()
        }

        return service.run(request)
            .retry(Config.retryCount)
            .decode(type: [CarbsEntry].self, decoder: JSONCoding.decoder)
            .catch { error -> AnyPublisher<[CarbsEntry], Swift.Error> in
                warning(.nightscout, "Carbs fetching error: \(error.localizedDescription)")
                return Just([]).setFailureType(to: Swift.Error.self).eraseToAnyPublisher()
            }
            .eraseToAnyPublisher()
    }

    func deleteCarbs(_ date: Date) -> AnyPublisher<Void, Swift.Error> {
        let queryItems: [URLQueryItem] = [
            URLQueryItem(name: "find[carbs][$exists]", value: "true"),
            URLQueryItem(
                name: "find[creation_date][$eq]",
                value: Formatter.iso8601withFractionalSeconds.string(from: date)
            )
        ]
        guard let request = makeRequest(path: Config.treatmentsPath, queryItems: queryItems, method: "DELETE") else {
            return missingURLPublisher()
        }

        return service.run(request)
            .retry(Config.retryCount)
            .map { _ in () }
            .eraseToAnyPublisher()
    }

    func deleteManualGlucose(at date: Date) -> AnyPublisher<Void, Swift.Error> {
        let queryItems: [URLQueryItem] = [
            URLQueryItem(name: "find[glucose][$exists]", value: "true"),
            URLQueryItem(
                name: "find[created_at][$eq]",
                value: Formatter.iso8601withFractionalSeconds.string(from: date)
            )
        ]
        guard let request = makeRequest(path: Config.treatmentsPath, queryItems: queryItems, method: "DELETE") else {
            return missingURLPublisher()
        }

        return service.run(request)
            .retry(Config.retryCount)
            .map { _ in () }
            .eraseToAnyPublisher()
    }

    func deleteInsulin(at date: Date) -> AnyPublisher<Void, Swift.Error> {
        let queryItems: [URLQueryItem] = [
            URLQueryItem(name: "find[bolus][$exists]", value: "true"),
            URLQueryItem(
                name: "find[created_at][$eq]",
                value: Formatter.iso8601withFractionalSeconds.string(from: date)
            )
        ]
        guard let request = makeRequest(path: Config.treatmentsPath, queryItems: queryItems, method: "DELETE") else {
            return missingURLPublisher()
        }

        return service.run(request)
            .retry(Config.retryCount)
            .map { _ in () }
            .eraseToAnyPublisher()
    }

    /// Fetch treatment records from Nightscout within [sinceDate, untilDate).
    /// Used by TIR analysis to get full insulin/exercise history beyond local 24h pump retention.
    /// - Parameter count: Maximum number of records to fetch (default 500).
    func fetchTreatments(
        sinceDate: Date,
        untilDate: Date? = nil,
        count: Int = 500
    ) -> AnyPublisher<[NigtscoutTreatment], Swift.Error> {
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "count", value: "\(count)"),
            URLQueryItem(
                name: "find[created_at][$gte]",
                value: Formatter.iso8601withFractionalSeconds.string(from: sinceDate)
            )
        ]
        if let until = untilDate {
            queryItems.append(URLQueryItem(
                name: "find[created_at][$lt]",
                value: Formatter.iso8601withFractionalSeconds.string(from: until)
            ))
        }
        guard let request = makeRequest(path: Config.treatmentsPath, queryItems: queryItems, constrainedNetwork: true) else {
            return missingURLPublisher()
        }

        return service.run(request)
            .retry(Config.retryCount)
            .decode(type: [NigtscoutTreatment].self, decoder: JSONCoding.decoder)
            .eraseToAnyPublisher()
    }

    func fetchTempTargets(sinceDate: Date? = nil) -> AnyPublisher<[TempTarget], Swift.Error> {
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "find[eventType]", value: "Temporary+Target"),
            URLQueryItem(
                name: "find[enteredBy][$ne]",
                value: TempTarget.manual.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
            ),
            URLQueryItem(
                name: "find[enteredBy][$ne]",
                value: NigtscoutTreatment.local.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
            ),
            URLQueryItem(name: "find[duration][$exists]", value: "true")
        ]
        if let date = sinceDate {
            queryItems.append(URLQueryItem(
                name: "find[created_at][$gt]",
                value: Formatter.iso8601withFractionalSeconds.string(from: date)
            ))
        }
        guard let request = makeRequest(path: Config.treatmentsPath, queryItems: queryItems) else {
            return missingURLPublisher()
        }

        return service.run(request)
            .retry(Config.retryCount)
            .decode(type: [TempTarget].self, decoder: JSONCoding.decoder)
            .catch { error -> AnyPublisher<[TempTarget], Swift.Error> in
                warning(.nightscout, "TempTarget fetching error: \(error.localizedDescription)")
                return Just([]).setFailureType(to: Swift.Error.self).eraseToAnyPublisher()
            }
            .eraseToAnyPublisher()
    }

    func fetchAnnouncement(sinceDate: Date? = nil) -> AnyPublisher<[Announcement], Swift.Error> {
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "find[eventType]", value: "Announcement"),
            URLQueryItem(
                name: "find[enteredBy]",
                value: Announcement.remote.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
            )
        ]
        if let date = sinceDate {
            queryItems.append(URLQueryItem(
                name: "find[created_at][$gte]",
                value: Formatter.iso8601withFractionalSeconds.string(from: date)
            ))
        }
        guard let request = makeRequest(path: Config.treatmentsPath, queryItems: queryItems) else {
            return missingURLPublisher()
        }

        return service.run(request)
            .retry(Config.retryCount)
            .decode(type: [Announcement].self, decoder: JSONCoding.decoder)
            .eraseToAnyPublisher()
    }

    func deleteAnnouncements() -> AnyPublisher<Void, Swift.Error> {
        let queryItems: [URLQueryItem] = [
            URLQueryItem(name: "find[eventType]", value: "Announcement"),
            URLQueryItem(
                name: "find[created_at][$gte]",
                value: Formatter.iso8601withFractionalSeconds.string(from: Date.now)
            )
        ]
        guard let request = makeRequest(path: Config.treatmentsPath, queryItems: queryItems, method: "DELETE") else {
            return missingURLPublisher()
        }

        return service.run(request)
            .retry(Config.retryCount)
            .map { _ in () }
            .eraseToAnyPublisher()
    }

    func deleteNSoverride() -> AnyPublisher<Void, Swift.Error> {
        let queryItems: [URLQueryItem] = [
            URLQueryItem(name: "find[eventType]", value: "Exercise"),
            URLQueryItem(name: "count", value: "1"), // Delete latest
            URLQueryItem(name: "find[enteredBy]", value: "iAPS") // Don't delete entries created in NS
        ]
        guard let request = makeRequest(path: Config.treatmentsPath, queryItems: queryItems, method: "DELETE") else {
            return missingURLPublisher()
        }

        return service.run(request)
            .retry(Config.retryCount)
            .map { _ in () }
            .eraseToAnyPublisher()
    }

    func deleteOverride(at date: Date) -> AnyPublisher<Void, Swift.Error> {
        let queryItems: [URLQueryItem] = [
            URLQueryItem(name: "find[Exercise][$exists]", value: "true"),
            URLQueryItem(
                name: "find[created_at][$eq]",
                value: Formatter.iso8601withFractionalSeconds.string(from: date)
            )
        ]
        guard let request = makeRequest(path: Config.treatmentsPath, queryItems: queryItems, method: "DELETE") else {
            return missingURLPublisher()
        }

        return service.run(request)
            .retry(Config.retryCount)
            .map { _ in () }
            .eraseToAnyPublisher()
    }

    // Dev work. Delete all exercise events
    func deleteAllNSoverrrides() -> AnyPublisher<Void, Swift.Error> {
        let queryItems: [URLQueryItem] = [
            URLQueryItem(name: "find[eventType]", value: "Exercise")
        ]
        guard let request = makeRequest(path: Config.treatmentsPath, queryItems: queryItems, method: "DELETE") else {
            return missingURLPublisher()
        }

        return service.run(request)
            .retry(Config.retryCount)
            .map { _ in () }
            .eraseToAnyPublisher()
    }

    func uploadTreatments(_ treatments: [NigtscoutTreatment]) -> AnyPublisher<Void, Swift.Error> {
        guard var request = makeRequest(path: Config.treatmentsPath, method: "POST") else {
            return missingURLPublisher()
        }
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONCoding.encoder.encode(treatments)

        return service.run(request)
            .retry(Config.retryCount)
            .map { _ in () }
            .eraseToAnyPublisher()
    }

    func uploadEcercises(_ override: [NigtscoutExercise]) -> AnyPublisher<Void, Swift.Error> {
        guard var request = makeRequest(path: Config.treatmentsPath, method: "POST") else {
            return missingURLPublisher()
        }
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONCoding.encoder.encode(override)

        return service.run(request)
            .retry(Config.retryCount)
            .map { _ in () }
            .eraseToAnyPublisher()
    }

    func uploadGlucose(_ glucose: [BloodGlucose]) -> AnyPublisher<Void, Swift.Error> {
        guard var request = makeRequest(path: Config.uploadEntriesPath, method: "POST") else {
            return missingURLPublisher()
        }
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        debug(.nightscout, "NS Client: uploading \(glucose.count) glucose entries")
        request.httpBody = try? JSONCoding.encoder.encode(glucose)

        return service.run(request)
            .retry(Config.retryCount)
            .map { _ in () }
            .eraseToAnyPublisher()
    }

    func uploadStats(_ stats: NightscoutStatistics) -> AnyPublisher<Void, Swift.Error> {
        let statURL = IAPSconfig.statURL
        guard var request = makeRequest(baseURL: statURL, path: Config.sharePath, method: "POST", addSecret: false) else {
            return missingURLPublisher()
        }
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONCoding.encoder.encode(stats)

        return service.run(request)
            .retry(Config.retryCount)
            .map { _ in () }
            .eraseToAnyPublisher()
    }

    func fetchVersion() -> AnyPublisher<Version, Swift.Error> {
        let statURL = IAPSconfig.statURL
        guard let request = makeRequest(
            baseURL: statURL,
            path: Config.versionPath,
            constrainedNetwork: true,
            addSecret: false
        ) else { return missingURLPublisher() }

        return service.run(request)
            .retry(Config.retryCount)
            .decode(type: Version.self, decoder: JSONCoding.decoder)
            .catch { error -> AnyPublisher<Version, Swift.Error> in
                warning(.nightscout, "Version fetching error: \(error.localizedDescription) \(request)")
                return Just(Version(main: "", dev: "")).setFailureType(to: Swift.Error.self).eraseToAnyPublisher()
            }
            .eraseToAnyPublisher()
    }

    func uploadStatus(_ status: NightscoutStatus) -> AnyPublisher<Void, Swift.Error> {
        guard var request = makeRequest(path: Config.statusPath, method: "POST") else {
            return missingURLPublisher()
        }
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONCoding.encoder.encode(status)

        return service.run(request)
            .retry(Config.retryCount)
            .map { _ in () }
            .eraseToAnyPublisher()
    }

    func uploadPrefs(_ prefs: NightscoutPreferences) -> AnyPublisher<Void, Swift.Error> {
        let statURL = IAPSconfig.statURL
        guard var request = makeRequest(baseURL: statURL, path: Config.sharePath, method: "POST", addSecret: false) else {
            return missingURLPublisher()
        }
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONCoding.encoder.encode(prefs)

        return service.run(request)
            .retry(Config.retryCount)
            .map { _ in () }
            .eraseToAnyPublisher()
    }

    func uploadSettings(_ settings: NightscoutSettings) -> AnyPublisher<Void, Swift.Error> {
        let statURL = IAPSconfig.statURL
        guard var request = makeRequest(baseURL: statURL, path: Config.sharePath, method: "POST", addSecret: false) else {
            return missingURLPublisher()
        }
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONCoding.encoder.encode(settings)

        return service.run(request)
            .retry(Config.retryCount)
            .map { _ in () }
            .eraseToAnyPublisher()
    }

    func uploadProfile(_ profile: NightscoutProfileStore) -> AnyPublisher<Void, Swift.Error> {
        guard var request = makeRequest(path: Config.profilePath, method: "POST") else {
            return missingURLPublisher()
        }
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONCoding.encoder.encode(profile)

        return service.run(request)
            .retry(Config.retryCount)
            .map { _ in () }
            .eraseToAnyPublisher()
    }

    func uploadSettingsToDatabase(_ profile: NightscoutProfileStore) -> AnyPublisher<Void, Swift.Error> {
        let statURL = IAPSconfig.statURL
        guard var request = makeRequest(baseURL: statURL, path: Config.sharePath, method: "POST", addSecret: false) else {
            return missingURLPublisher()
        }
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONCoding.encoder.encode(profile)

        return service.run(request)
            .retry(Config.retryCount)
            .map { _ in () }
            .eraseToAnyPublisher()
    }

    func uploadPreferences(_ preferences: Preferences) -> AnyPublisher<Void, Swift.Error> {
        guard var request = makeRequest(path: Config.profilePath, method: "POST") else {
            return missingURLPublisher()
        }
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONCoding.encoder.encode(preferences)

        return service.run(request)
            .retry(Config.retryCount)
            .map { _ in () }
            .eraseToAnyPublisher()
    }
}

private extension String {
    func sha1() -> String {
        let data = Data(utf8)
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_SHA1($0.baseAddress, CC_LONG(data.count), &digest)
        }
        let hexBytes = digest.map { String(format: "%02hhx", $0) }
        return hexBytes.joined()
    }
}
