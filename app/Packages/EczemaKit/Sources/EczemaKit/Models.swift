import Foundation

// MARK: - Exposures (the "suspects" a person can run into)

public enum ExposureKind: String, Codable, CaseIterable, Sendable, Hashable {
    case newProduct, detergent, dairy, nuts, seafood, gluten, alcohol, sweat, pet, pool, wool, stress, dryAir, travel, other

    public var label: String {
        switch self {
        case .newProduct: "New product"
        case .detergent: "New detergent"
        case .dairy: "Dairy"
        case .nuts: "Nuts"
        case .seafood: "Seafood"
        case .gluten: "Gluten"
        case .alcohol: "Alcohol"
        case .sweat: "Sweaty workout"
        case .pet: "Pet"
        case .pool: "Pool"
        case .wool: "Wool"
        case .stress: "Stress"
        case .dryAir: "Dry air"
        case .travel: "Travel"
        case .other: "Other"
        }
    }

    public var emoji: String {
        switch self {
        case .newProduct: "🧴"
        case .detergent: "🧺"
        case .dairy: "🥛"
        case .nuts: "🥜"
        case .seafood: "🍤"
        case .gluten: "🍞"
        case .alcohol: "🍷"
        case .sweat: "🏋️"
        case .pet: "🐶"
        case .pool: "🏊"
        case .wool: "🧶"
        case .stress: "📚"
        case .dryAir: "💧"
        case .travel: "✈️"
        case .other: "✳️"
        }
    }

    /// Kinds the user can tag by hand in the quick-tag sheet (the rest are detected automatically).
    public static let taggable: [ExposureKind] = [.newProduct, .detergent, .dairy, .nuts, .seafood, .gluten, .alcohol, .sweat, .pet, .pool, .wool, .stress]
}

public struct Exposure: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var kind: ExposureKind
    /// Short user-facing name, e.g. "Brightwell Ocean Breeze Body Wash".
    public var title: String
    /// Start of the day the exposure happened.
    public var day: Date
    /// true when it was detected automatically (weather, watch), false when tagged by the user.
    public var automatic: Bool
    public var note: String?

    public init(id: UUID = UUID(), kind: ExposureKind, title: String? = nil, day: Date, automatic: Bool = false, note: String? = nil) {
        self.id = id; self.kind = kind; self.title = title ?? kind.label; self.day = day; self.automatic = automatic; self.note = note
    }
}

// MARK: - Scratching

public enum EpisodeSource: String, Codable, Sendable, Hashable { case live, recorded, demo }
public enum EpisodeLabel: String, Codable, Sendable, Hashable { case confirmed, rejected }

/// One run of scratching detected by the watch.
public struct ScratchEpisode: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var start: Date
    public var end: Date
    /// Back-and-forth rate in Hz (Lilly 2023 uses this as scratch intensity).
    public var meanHz: Double
    /// Strength of wrist motion in g.
    public var meanRMS: Double
    public var intense: Bool
    public var source: EpisodeSource
    public var label: EpisodeLabel?

    public var duration: TimeInterval { end.timeIntervalSince(start) }

    public init(id: UUID = UUID(), start: Date, end: Date, meanHz: Double, meanRMS: Double, intense: Bool,
                source: EpisodeSource, label: EpisodeLabel? = nil) {
        self.id = id; self.start = start; self.end = end; self.meanHz = meanHz; self.meanRMS = meanRMS
        self.intense = intense; self.source = source; self.label = label
    }
}

// MARK: - Environment

public enum PollenLevel: String, Codable, Sendable, Hashable {
    case none, low, moderate, high, unknown
    public var label: String { self == .unknown ? "—" : rawValue.capitalized }
}

// MARK: - One day of data

public struct DayRecord: Codable, Identifiable, Hashable, Sendable {
    public var id: Date { day }
    /// Start of the day.
    public var day: Date
    /// Minutes of scratching in each hour, index 0 = midnight. Always 24 values.
    public var scratchMinutesByHour: [Double]
    public var episodeCount: Int
    public var intenseCount: Int
    /// Sleep of the night that ended this morning.
    public var sleepHours: Double
    public var wakeUps: Int
    public var hrvMs: Double
    public var restingHR: Double
    public var humidityPct: Double
    public var tempC: Double
    public var aqi: Int
    public var pollen: PollenLevel
    public var exposures: [Exposure]

    public var scratchMinutes: Double { scratchMinutesByHour.reduce(0, +) }
    /// Hour with the most scratching, nil when the day is calm.
    public var worstHour: Int? {
        guard let m = scratchMinutesByHour.max(), m > 0.5 else { return nil }
        return scratchMinutesByHour.firstIndex(of: m)
    }

    public init(day: Date, scratchMinutesByHour: [Double], episodeCount: Int, intenseCount: Int, sleepHours: Double,
                wakeUps: Int, hrvMs: Double, restingHR: Double, humidityPct: Double, tempC: Double, aqi: Int,
                pollen: PollenLevel, exposures: [Exposure]) {
        precondition(scratchMinutesByHour.count == 24, "24 hourly values")
        self.day = day; self.scratchMinutesByHour = scratchMinutesByHour; self.episodeCount = episodeCount
        self.intenseCount = intenseCount; self.sleepHours = sleepHours; self.wakeUps = wakeUps; self.hrvMs = hrvMs
        self.restingHR = restingHR; self.humidityPct = humidityPct; self.tempC = tempC; self.aqi = aqi
        self.pollen = pollen; self.exposures = exposures
    }
}

// MARK: - Insight ("case file")

public enum Confidence: String, Codable, Sendable, Hashable, CaseIterable {
    case low, lowMedium, medium, high
    public var label: String {
        switch self { case .low: "Low"; case .lowMedium: "Low–Medium"; case .medium: "Medium"; case .high: "High" }
    }
    /// 0...1, used for the confidence bar.
    public var score: Double {
        switch self { case .low: 0.18; case .lowMedium: 0.38; case .medium: 0.62; case .high: 0.86 }
    }
}

public struct Suspect: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var kind: ExposureKind?
    public var title: String
    public var confidence: Confidence
    /// e.g. "about 2 days"
    public var lag: String
    public var evidence: String
    /// When the suspect started and when the flare followed (for the evidence timeline).
    public var startedOn: Date?
    public var flareOn: Date?

    public init(id: UUID = UUID(), kind: ExposureKind?, title: String, confidence: Confidence, lag: String,
                evidence: String, startedOn: Date? = nil, flareOn: Date? = nil) {
        self.id = id; self.kind = kind; self.title = title; self.confidence = confidence; self.lag = lag
        self.evidence = evidence; self.startedOn = startedOn; self.flareOn = flareOn
    }
}

public struct ExperimentPlan: Codable, Hashable, Sendable {
    /// e.g. "Pause the Brightwell body wash"
    public var title: String
    /// One plain sentence telling the user what to do.
    public var instruction: String
    public var trigger: ExposureKind?
    public var lengthDays: Int

    public init(title: String, instruction: String, trigger: ExposureKind?, lengthDays: Int) {
        self.title = title; self.instruction = instruction; self.trigger = trigger; self.lengthDays = lengthDays
    }
}

public struct CaseFile: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var number: Int
    public var createdAt: Date
    public var windowStart: Date
    public var windowEnd: Date
    public var patternFound: Bool
    /// 2–4 plain sentences.
    public var summary: String
    /// Ranked, most likely first.
    public var suspects: [Suspect]
    public var cannotSeparate: [String]
    public var nextExperiment: ExperimentPlan?
    public var redFlags: [String]
    /// "claude-sonnet-5-5 (live)" or "bundled demo analysis".
    public var producedBy: String

    public init(id: UUID = UUID(), number: Int, createdAt: Date, windowStart: Date, windowEnd: Date, patternFound: Bool,
                summary: String, suspects: [Suspect], cannotSeparate: [String], nextExperiment: ExperimentPlan?,
                redFlags: [String], producedBy: String) {
        self.id = id; self.number = number; self.createdAt = createdAt; self.windowStart = windowStart
        self.windowEnd = windowEnd; self.patternFound = patternFound; self.summary = summary; self.suspects = suspects
        self.cannotSeparate = cannotSeparate; self.nextExperiment = nextExperiment; self.redFlags = redFlags
        self.producedBy = producedBy
    }
}

// MARK: - Experiments

public enum ExperimentStatus: String, Codable, Sendable, Hashable { case running, confirmed, notConfirmed, stopped }

public struct Experiment: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var plan: ExperimentPlan
    public var startDay: Date
    /// Average scratch minutes per day in the days before the experiment.
    public var baselineMinutesPerDay: Double
    public var status: ExperimentStatus

    public init(id: UUID = UUID(), plan: ExperimentPlan, startDay: Date, baselineMinutesPerDay: Double, status: ExperimentStatus = .running) {
        self.id = id; self.plan = plan; self.startDay = startDay; self.baselineMinutesPerDay = baselineMinutesPerDay; self.status = status
    }
}

// MARK: - Everything the app shows

public struct TwinDataset: Codable, Hashable, Sendable {
    /// Oldest first. The last element is "today".
    public var days: [DayRecord]
    /// Episodes of the last few days (used for lists and the watch).
    public var episodes: [ScratchEpisode]
    /// The user's normal scratch minutes per day (median of calm days).
    public var baselineMinutesPerDay: Double
    public var caseFile: CaseFile?
    public var experiment: Experiment?
    public var isDemo: Bool

    public init(days: [DayRecord], episodes: [ScratchEpisode], baselineMinutesPerDay: Double, caseFile: CaseFile?,
                experiment: Experiment?, isDemo: Bool) {
        self.days = days; self.episodes = episodes; self.baselineMinutesPerDay = baselineMinutesPerDay
        self.caseFile = caseFile; self.experiment = experiment; self.isDemo = isDemo
    }

    public var today: DayRecord? { days.last }
    /// Today's minutes divided by the usual (1.0 = normal).
    public var todayRatio: Double {
        guard let t = today, baselineMinutesPerDay > 0 else { return 1 }
        return t.scratchMinutes / baselineMinutesPerDay
    }
    public func day(_ date: Date, calendar: Calendar = .current) -> DayRecord? {
        days.first { calendar.isDate($0.day, inSameDayAs: date) }
    }
    /// Days of the running experiment so far (today included), oldest first.
    public func experimentDays(calendar: Calendar = .current) -> [DayRecord] {
        guard let e = experiment else { return [] }
        return days.filter { $0.day >= calendar.startOfDay(for: e.startDay) }
    }
}
