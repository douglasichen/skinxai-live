import Foundation
import HealthKit

/// Reads sleep, HRV, resting heart rate and workouts from Apple Health. Read-only, optional:
/// without access (or on a device without Health) every value is simply missing.
@MainActor
final class HealthReader {
    struct Day: Equatable {
        var sleepHours: Double?
        var wakeUps: Int?
        var hrvMs: Double?
        var restingHR: Double?
        var workoutMinutes: Double = 0
    }

    private let store = HKHealthStore()

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    static let readTypes: Set<HKObjectType> = [
        HKCategoryType(.sleepAnalysis),
        HKQuantityType(.heartRateVariabilitySDNN),
        HKQuantityType(.restingHeartRate),
        HKObjectType.workoutType(),
    ]

    /// true once the user has answered the Health sheet (Health never tells apps what was allowed).
    func wasAsked() async -> Bool {
        guard Self.isAvailable else { return false }
        let status = try? await store.statusForAuthorizationRequest(toShare: [], read: Self.readTypes)
        return status == .unnecessary
    }

    /// true when Health returns at least one sample of a type we read (last 30 days). Health
    /// hides denied data as "no data", so this is the only honest sign that reading works.
    func returnsSamples(now: Date = Date()) async -> Bool {
        guard Self.isAvailable else { return false }
        let predicate = HKQuery.predicateForSamples(withStart: now.addingTimeInterval(-30 * 86_400), end: now)
        let types: [HKSampleType] = [HKCategoryType(.sleepAnalysis), HKQuantityType(.heartRateVariabilitySDNN),
                                     HKQuantityType(.restingHeartRate), HKObjectType.workoutType()]
        for type in types {
            let query = HKSampleQueryDescriptor(predicates: [.sample(type: type, predicate: predicate)],
                                                sortDescriptors: [], limit: 1)
            if let found = try? await query.result(for: store), !found.isEmpty { return true }
        }
        return false
    }

    func requestAccess() async {
        guard Self.isAvailable else { return }
        try? await store.requestAuthorization(toShare: [], read: Self.readTypes)
    }

    /// One summary per day for the `count` days ending today (keys = start of day).
    func days(_ count: Int, now: Date = Date(), calendar: Calendar = .current) async -> [Date: Day] {
        guard Self.isAvailable, count > 0 else { return [:] }
        let today = calendar.startOfDay(for: now)
        guard let first = calendar.date(byAdding: .day, value: -(count - 1), to: today),
              let nightStart = calendar.date(byAdding: .hour, value: -6, to: first) else { return [:] }
        var out: [Date: Day] = [:]
        for i in 0..<count {
            if let d = calendar.date(byAdding: .day, value: i, to: first) { out[d] = Day() }
        }

        // Sleep: the night that ended on the morning of each day (18:00 the evening before → noon).
        let sleep = (try? await HKSampleQueryDescriptor(
            predicates: [.categorySample(type: HKCategoryType(.sleepAnalysis),
                                         predicate: HKQuery.predicateForSamples(withStart: nightStart, end: now))],
            sortDescriptors: [SortDescriptor(\.startDate)]).result(for: store)) ?? []
        for day in out.keys {
            guard let from = calendar.date(byAdding: .hour, value: -6, to: day),
                  let to = calendar.date(byAdding: .hour, value: 12, to: day) else { continue }
            let night = sleep.filter { $0.endDate > from && $0.startDate < to }
            let summary = Self.summarize(night: night)
            out[day]?.sleepHours = summary.hours
            out[day]?.wakeUps = summary.wakeUps
        }

        // HRV and resting heart rate: daily averages.
        let window = HKQuery.predicateForSamples(withStart: first, end: now)
        let hrv = await dailyAverages(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), from: first, predicate: window, calendar: calendar)
        let rhr = await dailyAverages(.restingHeartRate, unit: .count().unitDivided(by: .minute()), from: first, predicate: window, calendar: calendar)
        for (day, v) in hrv { out[day]?.hrvMs = v.rounded() }
        for (day, v) in rhr { out[day]?.restingHR = v.rounded() }

        // Workouts (≥ 20 min of sweat counts as an exposure).
        let workouts = (try? await HKSampleQueryDescriptor(
            predicates: [.workout(window)], sortDescriptors: []).result(for: store)) ?? []
        for w in workouts {
            let day = calendar.startOfDay(for: w.startDate)
            out[day]?.workoutMinutes += w.duration / 60
        }
        return out
    }

    private func dailyAverages(_ id: HKQuantityTypeIdentifier, unit: HKUnit, from start: Date, predicate: NSPredicate,
                               calendar: Calendar) async -> [Date: Double] {
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: HKQuantityType(id), predicate: predicate),
            options: .discreteAverage, anchorDate: start, intervalComponents: DateComponents(day: 1))
        guard let collection = try? await descriptor.result(for: store) else { return [:] }
        var out: [Date: Double] = [:]
        collection.enumerateStatistics(from: start, to: Date()) { stats, _ in
            if let q = stats.averageQuantity() { out[calendar.startOfDay(for: stats.startDate)] = q.doubleValue(for: unit) }
        }
        return out
    }

    /// Hours asleep (overlapping samples from several sources merged) and wake-ups during the night.
    static func summarize(night samples: [HKCategorySample]) -> (hours: Double?, wakeUps: Int?) {
        let asleepValues: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue,
        ]
        let asleep = samples.filter { asleepValues.contains($0.value) }
            .map { ($0.startDate, $0.endDate) }
            .sorted { $0.0 < $1.0 }
        guard !asleep.isEmpty else { return (nil, nil) }
        var merged: [(Date, Date)] = []
        for s in asleep {
            if let last = merged.last, s.0 <= last.1 { merged[merged.count - 1].1 = max(last.1, s.1) } else { merged.append(s) }
        }
        let seconds = merged.reduce(0) { $0 + $1.1.timeIntervalSince($1.0) }
        let firstSleep = merged.first!.0, lastSleep = merged.last!.1
        let awake = samples.filter {
            $0.value == HKCategoryValueSleepAnalysis.awake.rawValue && $0.startDate > firstSleep && $0.endDate < lastSleep
                && $0.endDate.timeIntervalSince($0.startDate) >= 60
        }.count
        // Sources without "awake" samples: count gaps of 5+ minutes between sleep stretches.
        let gaps = zip(merged, merged.dropFirst()).filter { $1.0.timeIntervalSince($0.1) >= 300 }.count
        return ((seconds / 3600 * 10).rounded() / 10, max(awake, gaps))
    }
}
