import Foundation

struct DynamicVariables: JSON, Codable {
    var average_total_data: Decimal
    var weightedAverage: Decimal
    var weigthPercentage: Decimal
    var past2hoursAverage: Decimal
    var date: Date
    var isEnabled: Bool
    var presetActive: Bool
    var overridePercentage: Decimal
    var useOverride: Bool
    var duration: Decimal
    var unlimited: Bool
    var hbt: Decimal
    var overrideTarget: Decimal
    var smbIsOff: Bool
    var advancedSettings: Bool
    var isfAndCr: Bool
    var isf: Bool
    var cr: Bool
    var basal: Bool
    var smbIsAlwaysOff: Bool
    var start: Decimal
    var end: Decimal
    var smbMinutes: Decimal
    var uamMinutes: Decimal
    var maxIOB: Decimal
    var overrideMaxIOB: Bool
    var preset: String
    var autoISFoverrides: AutoISFsettings
    var aisfOverridden: Bool
}

extension DynamicVariables {
    private enum CodingKeys: String, CodingKey {
        case average_total_data
        case weightedAverage
        case weigthPercentage
        case past2hoursAverage
        case date
        case isEnabled
        case presetActive
        case overridePercentage
        case useOverride
        case duration
        case unlimited
        case hbt
        case overrideTarget
        case smbIsOff
        case advancedSettings
        case isfAndCr
        case isf
        case cr
        case basal
        case smbIsAlwaysOff
        case start
        case end
        case smbMinutes
        case uamMinutes
        case maxIOB
        case overrideMaxIOB
        case preset
        case autoISFoverrides
        case aisfOverridden
    }
}

// TDD
struct Basal {
    var amount: Decimal
    var noneComputed: Date?
    var nonComputedAmount: Decimal
    var time: Date?
    var duration: Double?
}

struct SkippedBasals {
    var amount: Decimal
    var time: Date?
    var duration: Double?
}

struct Reduce {
    var amount: Decimal?
}
