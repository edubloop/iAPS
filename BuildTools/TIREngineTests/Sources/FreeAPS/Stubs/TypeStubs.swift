// TypeStubs.swift — minimal reproductions of the iAPS types used by the TIR engine.
// These are kept 1:1 with the real definitions so the engine + test files compile unchanged.

import Foundation

// MARK: - JSON protocol (stub)
// In the real app this is a Codable+Hashable typealias via SwiftyJSON.
// For testing, Codable suffices.
public typealias JSON = Codable

// MARK: - GlucoseUnits

public enum GlucoseUnits: String, Codable, Equatable {
    case mgdL = "mg/dL"
    case mmolL = "mmol/L"
    public static let exchangeRate: Decimal = 0.0555
}

// MARK: - BloodGlucose

public struct BloodGlucose: Codable, Identifiable, Hashable {
    public var _id: String
    public var id: String { _id }
    public var sgv: Int?
    public let date: Decimal
    public let dateString: Date
    public let noise: Int?
    public var glucose: Int?

    public init(
        _id: String = UUID().uuidString,
        sgv: Int? = nil,
        date: Decimal,
        dateString: Date,
        noise: Int? = nil,
        glucose: Int? = nil
    ) {
        self._id = _id
        self.sgv = sgv
        self.date = date
        self.dateString = dateString
        self.noise = noise
        self.glucose = glucose
    }

    public var isStateValid: Bool { sgv ?? 0 >= 39 && noise ?? 1 != 4 }

    public static func == (lhs: BloodGlucose, rhs: BloodGlucose) -> Bool {
        lhs.dateString == rhs.dateString
    }
    public func hash(into hasher: inout Hasher) { hasher.combine(dateString) }
}

// MARK: - CarbsEntry

public struct CarbsEntry: Codable, Equatable, Hashable {
    public let id: String?
    public var createdAt: Date
    public let actualDate: Date?
    public var carbs: Decimal
    public let fat: Decimal?
    public let protein: Decimal?
    public let note: String?
    public let enteredBy: String?
    public let isFPU: Bool?

    public init(
        id: String?,
        createdAt: Date,
        actualDate: Date?,
        carbs: Decimal,
        fat: Decimal? = nil,
        protein: Decimal? = nil,
        note: String? = nil,
        enteredBy: String? = nil,
        isFPU: Bool? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.actualDate = actualDate
        self.carbs = carbs
        self.fat = fat
        self.protein = protein
        self.note = note
        self.enteredBy = enteredBy
        self.isFPU = isFPU
    }

    public static func == (lhs: CarbsEntry, rhs: CarbsEntry) -> Bool { lhs.createdAt == rhs.createdAt }
    public func hash(into hasher: inout Hasher) { hasher.combine(createdAt) }
}

// MARK: - EventType + PumpHistoryEvent

public enum EventType: String, Codable {
    case bolus          = "Bolus"
    case smb            = "SMB"
    case tempBasal      = "TempBasal"
    case pumpSuspend    = "PumpSuspend"
    case pumpResume     = "PumpResume"
    // (others omitted — engine only checks .smb)
}

public struct PumpHistoryEvent: Codable, Equatable {
    public let id: String
    public let type: EventType
    public let timestamp: Date
    public let amount: Decimal?
    public let isSMB: Bool?

    public init(
        id: String,
        type: EventType,
        timestamp: Date,
        amount: Decimal? = nil,
        isSMB: Bool? = nil
    ) {
        self.id = id
        self.type = type
        self.timestamp = timestamp
        self.amount = amount
        self.isSMB = isSMB
    }
}

// MARK: - IOBTick0

public struct IOBTick0: Codable, Equatable {
    public let time: Date
    public let iob: Decimal
    public let activity: Decimal

    public init(time: Date, iob: Decimal, activity: Decimal) {
        self.time = time
        self.iob = iob
        self.activity = activity
    }
}
