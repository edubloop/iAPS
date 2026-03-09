import Foundation

enum CGMType: String, JSON, CaseIterable, Identifiable {
    var id: String { rawValue }

    case nightscout
    case xdrip
    case dexcomG5
    case dexcomG6
    case dexcomG7
    case simulator
    case libreTransmitter
    case glucoseDirect
    case enlite

    var displayName: String {
        switch self {
        case .nightscout:
            return "Nightscout"
        case .xdrip:
            return "xDrip4iOS"
        case .glucoseDirect:
            return "Glucose Direct"
        case .dexcomG5:
            return "Dexcom G5"
        case .dexcomG6:
            return "Dexcom G6"
        case .dexcomG7:
            return "Dexcom G7"
        case .simulator:
            return NSLocalizedString("Glucose Simulator", comment: "Glucose Simulator CGM type")
        case .libreTransmitter:
            return NSLocalizedString("Libre Transmitter", comment: "Libre Transmitter type")
        case .enlite:
            return "Medtronic Enlite"
        }
    }

    var appURL: URL? {
        switch self {
        case .enlite,
             .nightscout:
            return nil
        case .xdrip:
            return CGMExternalAppURLs.xdripApp
        case .glucoseDirect:
            return CGMExternalAppURLs.glucoseDirectApp
        case .dexcomG5:
            return CGMExternalAppURLs.dexcomG5App
        case .dexcomG6:
            return CGMExternalAppURLs.dexcomG6App
        case .dexcomG7:
            return CGMExternalAppURLs.dexcomG7App
        case .simulator:
            return nil
        case .libreTransmitter:
            return CGMExternalAppURLs.libreTransmitterApp
        }
    }

    var externalLink: URL? {
        switch self {
        case .xdrip:
            return CGMExternalAppURLs.xdripExternalLink
        case .glucoseDirect:
            return CGMExternalAppURLs.glucoseDirectExternalLink
        default: return nil
        }
    }

    var subtitle: String {
        switch self {
        case .nightscout:
            return NSLocalizedString("Online or internal server", comment: "Online or internal server")
        case .xdrip:
            return NSLocalizedString(
                "Using shared app group with external CGM app xDrip4iOS",
                comment: "Shared app group xDrip4iOS"
            )
        case .dexcomG5:
            return NSLocalizedString("Native G5 app", comment: "Native G5 app")
        case .dexcomG6:
            return NSLocalizedString("Dexcom G6 app", comment: "Dexcom G6 app")
        case .dexcomG7:
            return NSLocalizedString("Dexcom G7 app", comment: "Dexcom G76 app")
        case .simulator:
            return NSLocalizedString("Simple simulator", comment: "Simple simulator")
        case .libreTransmitter:
            return NSLocalizedString(
                "Direct connection with Libre 1 transmitters or European Libre 2 sensors",
                comment: "Direct connection with Libre 1 transmitters or European Libre 2 sensors"
            )
        case .glucoseDirect:
            return NSLocalizedString(
                "Using shared app group with external CGM app GlucoseDirect",
                comment: "Shared app group GlucoseDirect"
            )
        case .enlite:
            return NSLocalizedString("Minilink transmitter", comment: "Minilink transmitter")
        }
    }

    var expiration: TimeInterval {
        let secondsOfDay = CGMConstants.secondsPerDay
        switch self {
        case .dexcomG6:
            return 10 * secondsOfDay
        case .dexcomG7:
            return 10.5 * secondsOfDay
        case .libreTransmitter:
            return 14.5 * secondsOfDay
        case .enlite:
            return 6 * secondsOfDay
        default:
            return 10 * secondsOfDay
        }
    }
}

enum CGMExternalAppURLs {
    static let xdripApp = URL(string: "xdripswift://")!
    static let glucoseDirectApp = URL(string: "libredirect://")!
    static let dexcomG5App = URL(string: "dexcomgcgm://")!
    static let dexcomG6App = URL(string: "dexcomg6://")!
    static let dexcomG7App = URL(string: "dexcomg7://")!
    static let libreTransmitterApp = URL(string: "freeaps-x://libre-transmitter")!

    static let xdripExternalLink = URL(string: "https://github.com/JohanDegraeve/xdripswift")!
    static let glucoseDirectExternalLink = URL(string: "https://github.com/creepymonster/GlucoseDirectApp")!
}

enum CGMConstants {
    static let secondsPerDay: TimeInterval = 24 * 60 * 60
}

enum GlucoseDataError: Error {
    case noData
    case unreliableData
}

// temporary - convert from CGMType to pluginIdentifier
extension CGMType {
    var pluginIdentifier: String? {
        switch self {
        case .nightscout: return "NightscoutRemoteCGM"
        case .dexcomG5: return "DexcomG5CGMManager" // or whatever the actual identifier is
        case .dexcomG6: return "DexcomG6CGMManager"
        case .dexcomG7: return "G7CGMManager"
        case .simulator: return "MockCGMManager"
        case .libreTransmitter: return "LibreTransmitterManager"
        case .glucoseDirect: return "GlucoseDirectCGM" // if available
        case .xdrip: return "xDripCGM" // if available
        case .enlite: return "EnliteCGM" // if available
        }
    }

    static func from(pluginIdentifier: String) -> CGMType? {
        CGMType.allCases.first { $0.pluginIdentifier == pluginIdentifier }
    }
}
