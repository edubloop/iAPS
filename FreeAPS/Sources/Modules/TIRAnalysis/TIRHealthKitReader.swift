import Foundation
import HealthKit

/// Read-only HealthKit data fetcher for TIR Analysis (Track 2).
///
/// Isolated from the app's write-focused `BaseHealthKitManager` — creates its own
/// `HKHealthStore` instance. This is safe: iOS uses a shared underlying database, so
/// all `HKHealthStore` instances on the same device access the same data.
///
/// All methods return `[]` gracefully when HealthKit is unavailable, when the
/// required sample type doesn't exist on the current device, or when the query
/// fails for any reason (permission denied is silently treated as no data).
struct TIRHealthKitReader {
    private let store = HKHealthStore()
    private static let bgUnit = HKUnit(from: "mg/dL")
    private static let carbUnit = HKUnit.gram()

    // MARK: - Blood Glucose

    /// Fetch blood glucose samples from HealthKit within [start, end).
    /// Converts `HKQuantitySample` → `BloodGlucose` using mg/dL as the canonical unit.
    /// Results are sorted chronologically ascending.
    func fetchGlucose(from start: Date, to end: Date) async -> [BloodGlucose] {
        guard HKHealthStore.isHealthDataAvailable(),
              let sampleType = HKQuantityType.quantityType(forIdentifier: .bloodGlucose)
        else { return [] }

        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sampleType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, results, error in
                if let error = error {
                    debug(.service, "TIRHealthKitReader: BG query error — \(error.localizedDescription)")
                    continuation.resume(returning: [])
                    return
                }
                let glucose = ((results as? [HKQuantitySample]) ?? [])
                    .compactMap(TIRHealthKitReader.bloodGlucose(from:))
                debug(.service, "TIRHealthKitReader: fetched \(glucose.count) BG samples")
                continuation.resume(returning: glucose)
            }
            store.execute(query)
        }
    }

    // MARK: - Dietary Carbohydrates

    /// Fetch dietary carbohydrate samples from HealthKit within [start, end).
    /// Returns `[]` if permission was not granted or no carb data is present.
    /// The caller should treat an empty result as `carbEntries: nil` (confidence degraded).
    func fetchCarbs(from start: Date, to end: Date) async -> [CarbsEntry] {
        guard HKHealthStore.isHealthDataAvailable(),
              let sampleType = HKQuantityType.quantityType(forIdentifier: .dietaryCarbohydrates)
        else { return [] }

        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sampleType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, results, error in
                if let error = error {
                    debug(.service, "TIRHealthKitReader: carbs query error — \(error.localizedDescription)")
                    continuation.resume(returning: [])
                    return
                }
                let carbs = ((results as? [HKQuantitySample]) ?? [])
                    .compactMap(TIRHealthKitReader.carbsEntry(from:))
                debug(.service, "TIRHealthKitReader: fetched \(carbs.count) carb samples")
                continuation.resume(returning: carbs)
            }
            store.execute(query)
        }
    }

    // MARK: - Workouts

    /// Fetch workout samples from HealthKit within [start, end).
    /// Returns `ExerciseEvent` array for `ACTIVITY_RELATED_LOW` classification.
    func fetchWorkouts(from start: Date, to end: Date) async -> [ExerciseEvent] {
        guard HKHealthStore.isHealthDataAvailable() else { return [] }

        let workoutType = HKObjectType.workoutType()
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: workoutType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, results, error in
                if let error = error {
                    debug(.service, "TIRHealthKitReader: workout query error — \(error.localizedDescription)")
                    continuation.resume(returning: [])
                    return
                }
                let workouts = ((results as? [HKWorkout]) ?? []).map { workout in
                    ExerciseEvent(
                        start: workout.startDate,
                        end: workout.endDate,
                        source: .healthkit,
                        notes: workout.workoutActivityType.commonName
                    )
                }
                debug(.service, "TIRHealthKitReader: fetched \(workouts.count) workouts")
                continuation.resume(returning: workouts)
            }
            store.execute(query)
        }
    }

    // MARK: - Conversion Helpers

    private static func bloodGlucose(from sample: HKQuantitySample) -> BloodGlucose? {
        let mgdl = sample.quantity.doubleValue(for: bgUnit)
        guard mgdl > 0 else { return nil }
        let sgv = Int(mgdl.rounded())
        let ts = sample.startDate
        return BloodGlucose(
            _id: sample.uuid.uuidString,
            sgv: sgv,
            date: Decimal(ts.timeIntervalSince1970 * 1000), // ms since epoch (Nightscout convention)
            dateString: ts,
            glucose: sgv
            // noise: nil → isStateValid = (sgv >= 39 && 1 != 4) = true for valid readings
        )
    }

    private static func carbsEntry(from sample: HKQuantitySample) -> CarbsEntry? {
        let grams = sample.quantity.doubleValue(for: carbUnit)
        guard grams > 0 else { return nil }
        return CarbsEntry(
            id: sample.uuid.uuidString,
            createdAt: sample.startDate,
            actualDate: sample.startDate,
            carbs: Decimal(grams),
            fat: nil,
            protein: nil,
            note: nil,
            enteredBy: CarbsEntry.appleHealth,
            isFPU: false
        )
    }
}

// MARK: - HKWorkoutActivityType helpers

extension HKWorkoutActivityType {
    /// Human-readable name for common workout types.
    var commonName: String {
        switch self {
        case .running: return "Running"
        case .cycling: return "Cycling"
        case .walking: return "Walking"
        case .swimming: return "Swimming"
        case .hiking: return "Hiking"
        case .yoga: return "Yoga"
        case .functionalStrengthTraining,
             .traditionalStrengthTraining: return "Strength Training"
        case .crossTraining: return "Cross Training"
        case .elliptical: return "Elliptical"
        case .rowing: return "Rowing"
        case .dance: return "Dance"
        case .coreTraining: return "Core Training"
        case .highIntensityIntervalTraining: return "HIIT"
        default: return "Workout"
        }
    }
}
