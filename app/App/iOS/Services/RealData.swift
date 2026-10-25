import Foundation
import EczemaKit

/// What real mode keeps on the phone (Application Support/EczemaTwin, never leaves the device).
struct RealSaved: Codable, Equatable {
    /// Exposures the user tagged (quick-tag sheet) while in real mode.
    var tags: [Exposure] = []
    var caseFile: CaseFile?
    var experiment: Experiment?
    /// Last Open-Meteo report (offline fallback).
    var environment: EnvironmentReport?
    /// Last Health summaries, keyed by start of day.
    var health: [HealthEntry] = []

    struct HealthEntry: Codable, Equatable {
        var day: Date
        var sleepHours: Double?
        var wakeUps: Int?
        var hrvMs: Double?
        var restingHR: Double?
        var workoutMinutes: Double
    }
}

enum RealStore {
    private static var folder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent("EczemaTwin", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    private static var episodesURL: URL { folder.appendingPathComponent("episodes.json") }
    private static var savedURL: URL { folder.appendingPathComponent("real.json") }

    /// Every episode received from the watch (30 days kept).
    static func loadEpisodes() -> [ScratchEpisode] {
        guard let data = try? Data(contentsOf: episodesURL) else { return [] }
        return (try? JSONDecoder().decode([ScratchEpisode].self, from: data)) ?? []
    }

    /// Adds or replaces (same id) episodes and returns the full list.
    @discardableResult
    static func storeEpisodes(_ incoming: [ScratchEpisode], now: Date = Date()) -> [ScratchEpisode] {
        var all = loadEpisodes()
        for e in incoming {
            if let i = all.firstIndex(where: { $0.id == e.id }) { all[i] = e } else { all.append(e) }
        }
        let cutoff = now.addingTimeInterval(-30 * 86_400)
        all = all.filter { $0.start > cutoff }.sorted { $0.start < $1.start }
        if let data = try? JSONEncoder().encode(all) { try? data.write(to: episodesURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]) }
        return all
    }

    static func loadSaved() -> RealSaved {
        guard let data = try? Data(contentsOf: savedURL) else { return RealSaved() }
        return (try? JSONDecoder().decode(RealSaved.self, from: data)) ?? RealSaved()
    }

    static func save(_ saved: RealSaved) {
        if let data = try? JSONEncoder().encode(saved) { try? data.write(to: savedURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]) }
    }
}

/// Builds the real-mode dataset: the last 14 days from the watch (scratching), Apple Health
/// (sleep, HRV, resting HR, workouts), Open-Meteo (humidity, temperature, AQI, pollen) and the
/// user's tags. A value nobody measured stays 0 (pollen `.unknown`).
enum RealDataBuilder {
    static let windowDays = 14

    static func build(now: Date = Date(), calendar: Calendar = .current,
                      episodes: [ScratchEpisode], saved: RealSaved) -> TwinDataset {
        let today = calendar.startOfDay(for: now)
        var days: [DayRecord] = []
        for i in 0..<windowDays {
            guard let day = calendar.date(byAdding: .day, value: i - (windowDays - 1), to: today) else { continue }
            let health = saved.health.first { calendar.isDate($0.day, inSameDayAs: day) }
            let isToday = calendar.isDate(day, inSameDayAs: today)
            let env: EnvironmentReading? = {
                guard let report = saved.environment else { return nil }
                if isToday, calendar.isDate(report.fetchedAt, inSameDayAs: today) { return report.current }
                return report.day(day, calendar: calendar)
            }()
            var exposures = saved.tags.filter { calendar.isDate($0.day, inSameDayAs: day) }
            if let env, env.humidityPct != nil, env.isDry {
                exposures.append(Exposure(id: stableID(.dryAir, day), kind: .dryAir, title: "Dry air", day: day, automatic: true,
                                          note: "Outdoor humidity \(Int(env.humidityPct ?? 0))%"))
            }
            if let minutes = health?.workoutMinutes, minutes >= 20 {
                exposures.append(Exposure(id: stableID(.sweat, day), kind: .sweat, title: "Sweaty workout", day: day, automatic: true,
                                          note: "\(Int(minutes)) min workout in Apple Health"))
            }
            days.append(DayRecord(
                day: day,
                scratchMinutesByHour: Array(repeating: 0, count: 24),
                episodeCount: 0,
                intenseCount: 0,
                sleepHours: health?.sleepHours ?? 0,
                wakeUps: health?.wakeUps ?? 0,
                hrvMs: health?.hrvMs ?? 0,
                restingHR: health?.restingHR ?? 0,
                humidityPct: env?.humidityPct ?? 0,
                tempC: env?.tempC ?? 0,
                aqi: env?.aqi ?? 0,
                pollen: env?.pollen ?? .unknown,
                exposures: exposures))
        }

        var dataset = TwinDataset(days: days, episodes: [], baselineMinutesPerDay: priorBaseline,
                                  caseFile: saved.caseFile, experiment: nil, isDemo: false)
        EpisodeMerge.apply(episodes.filter { $0.label != .rejected }, to: &dataset, calendar: calendar)
        dataset.experiment = evaluated(saved.experiment, days: dataset.days, calendar: calendar)

        // Lists show the last few days, like the demo.
        if let cutoff = calendar.date(byAdding: .day, value: -2, to: today) {
            dataset.episodes = dataset.episodes.filter { $0.start >= cutoff }
        }
        dataset.baselineMinutesPerDay = baseline(dataset.days)
        return dataset
    }

    /// Same id for the same automatic exposure on every rebuild (no list churn).
    static func stableID(_ kind: ExposureKind, _ day: Date) -> UUID {
        let k = ExposureKind.allCases.firstIndex(of: kind) ?? 0
        let t = UInt64(max(0, day.timeIntervalSince1970))
        return UUID(uuidString: String(format: "ECA70000-%04X-4000-8000-%012llX", k, t)) ?? UUID()
    }

    /// "Your usual": median of full days the watch tracked; until there are 3 of those, the calm
    /// median of the demo story is the starting guess.
    static func baseline(_ days: [DayRecord]) -> Double {
        let tracked = days.dropLast().filter { $0.episodeCount > 0 }.map(\.scratchMinutes).sorted()
        guard tracked.count >= 3 else { return priorBaseline }
        let mid = tracked.count / 2
        let median = tracked.count % 2 == 0 ? (tracked[mid - 1] + tracked[mid]) / 2 : tracked[mid]
        return max(1, median)
    }

    static var priorBaseline: Double {
        let calm = DemoData.flareMinutes.prefix(DemoData.flareStartDay).sorted()
        let mid = calm.count / 2
        return calm.count % 2 == 0 ? (calm[mid - 1] + calm[mid]) / 2 : calm[mid]
    }

    /// A finished test gets its verdict (same rule as the demo: 40% less scratching = confirmed).
    static func evaluated(_ experiment: Experiment?, days: [DayRecord], calendar: Calendar) -> Experiment? {
        guard var e = experiment, e.status == .running else { return experiment }
        let start = calendar.startOfDay(for: e.startDay)
        // Judge after the last full test day.
        let during = days.filter { $0.day >= start }
        guard during.count > e.plan.lengthDays else { return e }
        let judged = during.prefix(e.plan.lengthDays)
        let avg = judged.map(\.scratchMinutes).reduce(0, +) / Double(max(1, judged.count))
        e.status = avg < e.baselineMinutesPerDay * 0.6 ? .confirmed : .notConfirmed
        return e
    }
}
