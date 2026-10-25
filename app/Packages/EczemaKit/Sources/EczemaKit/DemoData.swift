import Foundation

/// Deterministic demo data: Douglas's story.
///
/// Story (day 1 = 13 days ago, day 14 = today):
/// - Days 1–6 calm, about 11 minutes of scratching a day.
/// - Day 5: he starts a new scented body wash (Brightwell Ocean Breeze Body Wash).
/// - Day 6: indoor air turns dry (humidity under 30%) and stays dry.
/// - Day 7 on: flare. Scratching roughly triples, mostly at night (2–4 a.m.), sleep drops, HRV drops.
/// - Days 11–12: exam stress and short sleep (they come after the flare started).
/// - Day 14 (today): 47 minutes, worst night so far. Claude's case file is ready.
///
/// `experimentDay` (1...10) extends the story: the user paused the body wash the day after the
/// case file, and today is that day of the 10-day test. Scratching falls back toward normal
/// although the air stays dry, which points at the body wash.
public enum DemoData {
    public static let flareMinutes: [Double] = [11, 13, 10, 12, 13, 11, 24, 38, 31, 36, 38, 29, 31, 47]
    public static let experimentMinutes: [Double] = [35, 28, 22, 19, 16, 14, 12, 11, 10, 10]
    public static let bodyWashDay = 4        // index of day 5
    public static let dryAirDay = 5          // index of day 6
    public static let flareStartDay = 6      // index of day 7
    public static let examDays: Set<Int> = [10, 11]
    public static let gymDays: Set<Int> = [1, 3, 8, 12, 15, 18, 21]
    public static let dairyDays: Set<Int> = [2, 7, 13, 16, 20]

    /// Hour the demo story reveals "today" through: the current hour, but never earlier than 7 am,
    /// so today always holds last night's flare (1–5 am) even during a night rehearsal.
    /// Pass it as `revealThroughHour`; real data never uses it.
    public static func storyRevealHour(at now: Date = Date(), calendar: Calendar = .current) -> Int {
        max(calendar.component(.hour, from: now), 7)
    }

    /// - Parameter revealThroughHour: last hour of today that has data (`nil` = the hour of `today`).
    public static func make(today: Date = Date(), experimentDay: Int? = nil, revealThroughHour: Int? = nil,
                            calendar: Calendar = .current) -> TwinDataset {
        let extra = max(0, min(experimentDay ?? 0, experimentMinutes.count))
        let minutes = flareMinutes + experimentMinutes.prefix(extra)
        let n = minutes.count
        let todayStart = calendar.startOfDay(for: today)
        func dayDate(_ i: Int) -> Date { calendar.date(byAdding: .day, value: i - (n - 1), to: todayStart)! }
        var rng = SplitMix64(seed: 0xEC2E_3A71)

        var days: [DayRecord] = []
        var episodes: [ScratchEpisode] = []
        for i in 0..<n {
            let date = dayDate(i)
            let total = minutes[i]
            let flare = total > 20
            let inExperiment = i >= flareMinutes.count
            let usingWash = i >= bodyWashDay && !inExperiment
            let dry = i >= dryAirDay
            let exam = examDays.contains(i)

            // Hourly split: night-heavy, more so during a flare.
            var w = [Double](repeating: 0, count: 24)
            for h in 0..<24 {
                let night: Double = (h >= 1 && h <= 4) ? (flare ? 9 : 4) : (h == 0 || h == 5) ? (flare ? 3.5 : 2) : 0
                let evening: Double = (h >= 20 && h <= 23) ? (flare ? 2.2 : 2.0) : 0
                let afternoon: Double = (h >= 13 && h <= 17) ? 0.9 : 0
                w[h] = night + evening + afternoon + 0.25 + rng.next() * 0.6
            }
            let sum = w.reduce(0, +)
            var hourly = w.map { ($0 / sum * total * 10).rounded() / 10 }
            // Hours after "now" on today are empty (scratching hasn't happened yet).
            if i == n - 1 {
                let nowHour = revealThroughHour ?? calendar.component(.hour, from: today)
                for h in 0..<24 where h > nowHour { hourly[h] = 0 }
            }

            // Episodes from the hourly minutes.
            var dayEpisodes: [ScratchEpisode] = []
            for h in 0..<24 where hourly[h] > 0.05 {
                var left = hourly[h] * 60
                var t = date.addingTimeInterval(Double(h) * 3600 + rng.next() * 300)
                while left > 5 {
                    let len = min(left, 20 + rng.next() * 100)
                    let intenseChance = flare ? 0.18 : 0.05
                    let intense = rng.next() < intenseChance
                    let rms = intense ? 0.36 + rng.next() * 0.3 : 0.12 + rng.next() * 0.2
                    dayEpisodes.append(ScratchEpisode(start: t, end: t.addingTimeInterval(len), meanHz: 2.8 + rng.next() * 2.8,
                                                      meanRMS: rms, intense: intense, source: .demo))
                    left -= len
                    t = t.addingTimeInterval(len + 30 + rng.next() * (3600 / max(1, hourly[h])))
                }
            }

            var exposures: [Exposure] = []
            if usingWash {
                exposures.append(Exposure(kind: .newProduct, title: "Brightwell Ocean Breeze Body Wash", day: date, automatic: false,
                                          note: i == bodyWashDay ? "Started today" : nil))
            }
            if dry { exposures.append(Exposure(kind: .dryAir, title: "Dry air", day: date, automatic: true)) }
            if exam { exposures.append(Exposure(kind: .stress, title: "Exam stress", day: date)) }
            if gymDays.contains(i) { exposures.append(Exposure(kind: .sweat, title: "Sweaty workout", day: date, automatic: true)) }
            if dairyDays.contains(i) { exposures.append(Exposure(kind: .dairy, title: "Dairy", day: date)) }

            let severity = min(1, max(0, (total - 11) / 36))         // 0 calm ... 1 worst
            days.append(DayRecord(
                day: date,
                scratchMinutesByHour: hourly,
                episodeCount: dayEpisodes.count,
                intenseCount: dayEpisodes.filter(\.intense).count,
                sleepHours: ((7.3 - severity * 2.1 - (exam ? 0.9 : 0) + (rng.next() - 0.5) * 0.4) * 10).rounded() / 10,
                wakeUps: Int((1 + severity * 5.5 + rng.next() * 1.4).rounded()),
                hrvMs: ((49 - severity * 16 - (exam ? 5 : 0) + (rng.next() - 0.5) * 4)).rounded(),
                restingHR: (58 + severity * 7 + (exam ? 2 : 0) + (rng.next() - 0.5) * 2).rounded(),
                humidityPct: (dry ? 27 + rng.next() * 4 : 52 + rng.next() * 8).rounded(),
                tempC: ((dry ? 10 + rng.next() * 2.5 : 14 + rng.next() * 2.5) * 10).rounded() / 10,
                aqi: Int(24 + rng.next() * 22),
                pollen: i % 4 == 0 ? .moderate : .low,
                exposures: exposures))
            if i >= n - 3 { episodes += dayEpisodes }
        }

        let calm = Array(minutes.prefix(flareStartDay)).sorted()
        let baseline = (calm[calm.count / 2 - 1] + calm[calm.count / 2]) / 2

        let caseFile = demoCaseFile(created: dayDate(flareMinutes.count - 1), windowStart: dayDate(0),
                                    washDay: dayDate(bodyWashDay), dryDay: dayDate(dryAirDay),
                                    flareDay: dayDate(flareStartDay), examDay: dayDate(examDays.min()!))
        var experiment: Experiment?
        if extra > 0, let plan = caseFile.nextExperiment {
            let flareSlice = flareMinutes[flareStartDay...]
            let before = flareSlice.reduce(0, +) / Double(flareSlice.count)
            let sofar = experimentMinutes.prefix(extra)
            let after = sofar.reduce(0, +) / Double(sofar.count)
            var status = ExperimentStatus.running
            if extra >= plan.lengthDays { status = after < before * 0.6 ? .confirmed : .notConfirmed }
            experiment = Experiment(plan: plan, startDay: dayDate(flareMinutes.count), baselineMinutesPerDay: before, status: status)
        }
        return TwinDataset(days: days, episodes: episodes.sorted { $0.start < $1.start }, baselineMinutesPerDay: baseline,
                           caseFile: caseFile, experiment: experiment, isDemo: true)
    }

    /// The analysis Claude gave for this story (shape matches the live API output).
    public static func demoCaseFile(created: Date, windowStart: Date, washDay: Date, dryDay: Date, flareDay: Date, examDay: Date) -> CaseFile {
        let df = DateFormatter(); df.dateFormat = "MMM d"
        return CaseFile(
            number: 3, createdAt: created, windowStart: windowStart, windowEnd: created, patternFound: true,
            summary: "Your scratching nearly tripled from \(df.string(from: flareDay)). The most likely cause is the new Brightwell Ocean Breeze Body Wash you started two days before. I'm fairly sure, not fully: the air also turned very dry that same week, so a short test will tell them apart.",
            suspects: [
                Suspect(kind: .newProduct, title: "Brightwell Ocean Breeze Body Wash", confidence: .medium, lag: "about 2 days",
                        evidence: "Scratching rose about 2 days after you started it and stayed high every day you used it. That delay fits how skin reacts to a new product (48–72 hours).",
                        startedOn: washDay, flareOn: flareDay),
                Suspect(kind: .dryAir, title: "Dry air", confidence: .lowMedium, lag: "0–1 day",
                        evidence: "Indoor humidity fell below 30% the next day and stayed low. Dry air weakens the skin barrier, so it may be adding to the flare.",
                        startedOn: dryDay, flareOn: flareDay),
                Suspect(kind: .stress, title: "Exam stress & short sleep", confidence: .low, lag: "0–1 day",
                        evidence: "Exams came after the flare had already started. Short sleep probably made it worse, not started it.",
                        startedOn: examDay, flareOn: nil),
            ],
            cannotSeparate: ["The Brightwell body wash and the dry air started one day apart, so this log can't fully separate them yet."],
            nextExperiment: ExperimentPlan(title: "Pause the Brightwell body wash",
                                           instruction: "Go back to your old wash for 10 days. Keep food, gym and room humidity the same.",
                                           trigger: .newProduct, lengthDays: 10),
            redFlags: [],
            producedBy: "Claude · bundled demo analysis")
    }
}

/// Small deterministic RNG so the demo looks the same on every launch.
public struct SplitMix64 {
    private var state: UInt64
    public init(seed: UInt64) { state = seed }
    /// 0..<1
    public mutating func next() -> Double {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z = z ^ (z >> 31)
        return Double(z >> 11) / Double(1 << 53)
    }
}
