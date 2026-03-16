import Foundation

struct Oref2_variables: JSON, Equatable {
    var average_total_data: Decimal
    var weightedAverage: Decimal
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
    var smbIsAlwaysOff: Bool
    var start: Decimal
    var end: Decimal
    var smbMinutes: Decimal
    var uamMinutes: Decimal
}

extension Oref2_variables {
    private enum CodingKeys: String, CodingKey {
        case average_total_data
        case weightedAverage
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
        case smbIsAlwaysOff
        case start
        case end
        case smbMinutes
        case uamMinutes
    }
}
