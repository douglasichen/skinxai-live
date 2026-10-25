import Foundation

/// Douglas's longer history for the Trends tab and Claude's tools: 60 nights before `StageStory`'s 14, so 74
/// nights that end last night. The last 14 are `StageStory`'s nights exactly (same minutes, humidity,
/// temperature, sleep, midterms, dry night). Claude's tools read up to all 74 (`StageStory.runTool`).
///
/// Nights are numbered like `StageStory`'s: 0 = the oldest of the 14 … 13 = last night; the earlier
/// nights are −60 … −1 (night −60 started 74 days before today). `StageStory.nightDate(_:)` gives every
/// night's date, negative ones included. With today = Sat Oct 24: night n is Oct 10 + n (−60 = Tue Aug 11).
///
/// The story (SCENARIO-MI.md; the app shows only the raw data, Claude has to find this itself): his usual is
/// about 12 minutes a night with ordinary noise, and he had four short flares, each starting the night after
/// a different new product arrived. All four products contain the preservative methylisothiazolinone (MI);
/// nothing he tolerates does (`flares`):
/// 1. nights −46 … −43 (Aug 25–28: 18, 24, 26, 17 min): the Summit Peak travel shampoo, bought Aug 24 for
///    the family trip to Seattle (Aug 24–27). The travel size ran out and the flare ended;
/// 2. nights −27 … −24 (Sep 13–16: 17, 22, 25, 19): the Lumen hand soap, bought Sep 12. It overlaps the
///    mid-September exam week (−26 … −23) and a dry spell; the last exam night (−23) is back to 13. He
///    stopped using the soap (only asking can tell);
/// 3. nights −4 … −1 (Oct 6–9: 19, 27, 31, 22): the wool sweater and the FreshMeadow detergent trial size,
///    both bought Oct 5. The trial size lasted four loads; he kept wearing the sweater (only asking can tell);
/// 4. nights 10 … 13 (Oct 20–23, now): the Brightwell "fragrance-free, sensitive" body wash, bought Oct 19.
///
/// What fails as an explanation, honestly in the data: fragrance (not in #4; tolerated daily in his deodorant
/// and his usual shampoo), sodium laureth sulfate and cocamidopropyl betaine (in his usual shampoo, hand soap
/// and detergent), wool (the socks were fine, the sweater was worn after #3 ended), stress (the midterms
/// and the last exam night were calm; HRV dips through the whole exam week), dry air (dry days elsewhere were
/// calm), travel (#1 only). Also: late gym nights are 2–3 minutes higher (a weak link), other new things
/// (sunscreen, deodorant, lotion, pillow, hoodie, T-shirts, socks) didn't move it, no weekday pattern.
public enum StageHistory {

    // MARK: - Nights

    /// One night.
    public struct Night: Sendable, Hashable, Identifiable {
        /// The night's number (−60 … 13; 13 = last night).
        public let id: Int
        /// Minutes of scratching.
        public let minutes: Int
        public let episodes: Int
        /// Outdoor humidity that day, percent.
        public let humidity: Int
        /// High temperature that day, °F.
        public let highF: Int
        /// Hours asleep.
        public let sleepHours: Double
        public let wakeUps: Int
        /// An exam week (mid-September, the midterms).
        public let exams: Bool
        /// Away on the family trip (calendar).
        public let trip: Bool
        /// A late workout (sweat) that evening.
        public let gym: Bool
        /// The first nights with newly bought clothes (washed before wearing).
        public let newClothes: Bool

        /// Humidity under 35%.
        public var dry: Bool { humidity < StageStory.dryBelowPercent }
        /// Above 1.5 × usual.
        public var flare: Bool { Double(minutes) > StageStory.flareFactor * Double(StageStory.usual) }
    }

    /// Nights before `StageStory`'s 14: 60.
    public static let earlierCount = 60
    /// The oldest night's number: −60.
    public static var firstNight: Int { -earlierCount }
    /// Every night's number, oldest first: −60 … 13.
    public static var nightIDs: ClosedRange<Int> { firstNight...StageStory.lastNightIndex }
    /// 74.
    public static var count: Int { nightIDs.count }

    /// Every night, oldest first (74; the last 14 are `StageStory`'s).
    public static let nights: [Night] = nightIDs.map(makeNight)

    /// Night `i` (−60 … 13; clamped).
    public static func night(_ i: Int) -> Night {
        nights[min(max(i, firstNight), StageStory.lastNightIndex) - firstNight]
    }

    /// The night (−60 … 13) that started on the day of a "YYYY-MM-DD" date (e.g. Claude's marker date), if
    /// it is one of the 74.
    public static func night(iso text: String, now: Date = Date(), calendar: Calendar = .current) -> Int? {
        let cal = StageStory.gregorian(calendar)
        guard let date = StageStory.date(iso: text, calendar: cal) else { return nil }
        let last = StageStory.nightDate(StageStory.lastNightIndex, now: now, calendar: cal)
        guard let days = cal.dateComponents([.day], from: cal.startOfDay(for: last), to: cal.startOfDay(for: date)).day else { return nil }
        let i = StageStory.lastNightIndex + days
        return nightIDs.contains(i) ? i : nil
    }

    // MARK: - The four flares

    /// A flare and the new product(s) that arrived the day before it started.
    public struct Flare: Sendable, Hashable {
        /// Its nights.
        public let nights: ClosedRange<Int>
        /// The new products (order items), all ordered on the day of night `nights.lowerBound − 1`.
        public let items: [String]
        /// The night of the order day.
        public var orderedNight: Int { nights.lowerBound - 1 }
    }

    /// The four flares, oldest first. Every one of their products lists methylisothiazolinone.
    public static let flares: [Flare] = [
        Flare(nights: -46...(-43), items: [StageStory.Product.summitShampoo.item]),
        Flare(nights: -27...(-24), items: [StageStory.Product.lumenHandSoap.item]),
        Flare(nights: -4...(-1), items: [StageStory.Product.northfieldSweater.item, StageStory.Product.freshMeadowDetergent.item]),
        Flare(nights: StageStory.bodyWashNight...StageStory.lastNightIndex, items: [StageStory.bodyWashItem]),
    ]

    /// Is night `i` one of the four flares' nights?
    public static func inFlare(_ i: Int) -> Bool { flares.contains { $0.nights.contains(i) } }

    /// The nights outside the four flares (58). His usual.
    public static var typicalNights: [Night] { nights.filter { !inFlare($0.id) } }

    /// The night after a short one (under `shortSleepBelow` hours the night before).
    public static func afterShortSleep(_ i: Int) -> Bool {
        i > firstNight && night(i - 1).sleepHours < shortSleepBelow
    }
    /// Sleep under this many hours is a short night.
    public static let shortSleepBelow = 6.5

    /// Clothes he bought for the first time (`StageStory.orders`), and the night he first wore them: each
    /// was washed before wearing.
    public static let clothes: [(item: String, firstNight: Int)] = [
        (StageStory.Product.baylineHoodie.item, -33),
        (StageStory.Product.baylineTShirts.item, -19),
        (StageStory.Product.darnToughSocks.item, 6),
    ]

    // MARK: - Nights with and without

    /// Average minutes on the nights with something against the nights without it, over all 74 nights.
    public struct Comparison: Sendable, Hashable {
        public let withMinutes: Double
        public let withoutMinutes: Double
        public let withNights: Int
        public let withoutNights: Int
        /// with − without, minutes.
        public var difference: Double { withMinutes - withoutMinutes }
        /// Rounded difference, e.g. +3.
        public var roundedDifference: Int { Int(difference.rounded()) }
    }

    /// The 74 nights split by `applies`.
    public static func compare(_ applies: (Night) -> Bool) -> Comparison {
        let with = nights.filter(applies)
        let without = nights.filter { !applies($0) }
        return Comparison(withMinutes: mean(with.map(\.minutes)), withoutMinutes: mean(without.map(\.minutes)),
                          withNights: with.count, withoutNights: without.count)
    }

    // MARK: - Weekdays

    /// Average minutes per weekday, Monday first, over the nights outside the four flares (58 nights).
    /// Night dates are relative to `now`, but the groups are the same whatever the day.
    public static func weekdayAverages(now: Date = Date(), calendar: Calendar = .current) -> [Double] {
        let cal = StageStory.gregorian(calendar)
        var groups = Array(repeating: [Int](), count: 7)
        for n in typicalNights {
            let weekday = cal.component(.weekday, from: StageStory.nightDate(n.id, now: now, calendar: cal))   // 1 = Sunday
            groups[(weekday + 5) % 7].append(n.minutes)
        }
        return groups.map(mean)
    }

    /// Mean minutes a night outside the four flares (≈ 12, his usual).
    public static var typicalAverage: Double { mean(typicalNights.map(\.minutes)) }

    // MARK: - Last night's sleep

    /// Last night's sleep stages (Apple Health style) from 11:04 PM to 6:52 AM, made to agree with
    /// `StageStory`: 5.1 h asleep, woke up twice, each time right after a scratching bout in
    /// `StageStory.LastNight.quarterHours`.
    public enum LastNightSleep {
        public enum Stage: String, CaseIterable, Sendable {
            case awake, rem, core, deep
        }

        /// A stretch of one stage, in minutes after 11:04 PM.
        public struct Segment: Sendable, Hashable {
            public let stage: Stage
            public let start: Int
            public let end: Int
            public var minutes: Int { end - start }
        }

        /// 11:04 PM … 6:52 AM: 468 minutes.
        public static let length = 468
        /// 11:04 PM is 4 minutes after the first quarter hour (11:00 PM).
        public static let offsetIntoFirstQuarter = 4

        /// The stages, in order, covering 0 … 468 without gaps.
        public static let segments: [Segment] = {
            let plan: [(Stage, Int)] = [
                (.core, 14), (.deep, 52), (.core, 70), (.rem, 82), (.core, 104), (.deep, 130), (.core, 150),
                (.rem, 170), (.core, 211),
                (.awake, 301),                                   // 2:35–4:05 AM, after the 2:30 bout
                (.core, 320), (.deep, 332), (.core, 346),
                (.awake, 418),                                   // 4:50–6:02 AM, after the 4:45 bout
                (.core, 440), (.rem, 468),
            ]
            var start = 0
            return plan.map { stage, end in
                defer { start = end }
                return Segment(stage: stage, start: start, end: end)
            }
        }()

        /// Minutes asleep (every stage but awake): 306 = 5.1 h.
        public static var minutesAsleep: Int { segments.filter { $0.stage != .awake }.map(\.minutes).reduce(0, +) }

        /// The wake-ups: the awake stretches (2).
        public static var wakeUps: [Segment] { segments.filter { $0.stage == .awake } }

        /// The quarter hour (0 … 31 from 11:00 PM) that minute `t` after 11:04 PM falls in.
        public static func quarter(at t: Int) -> Int {
            min(max((t + offsetIntoFirstQuarter) / 15, 0), StageStory.LastNight.quarterHours.count - 1)
        }

        /// He scratched (at least a minute) in the quarter hour just before waking up.
        public static func followsScratching(_ wake: Segment) -> Bool {
            StageStory.LastNight.quarterHours[quarter(at: wake.start - 5)] >= 1
        }

        /// Wake-ups that came right after a scratching bout (2 of 2).
        public static var wakeUpsAfterScratching: Int { wakeUps.filter(followsScratching).count }
    }

    // MARK: - Data

    // Nights −60 … −1 (Tue Aug 11 … Fri Oct 9 when today is Sat Oct 24). Flares at −46 … −43, −27 … −24 and
    // −4 … −1 (indices 14–17, 33–36, 56–59).
    static let earlierMinutes: [Int] = [14, 12, 15, 10, 14, 14, 12, 15, 12, 10, 9, 14, 12, 10, 18, 24, 26, 17, 14, 14,
                                        14, 13, 12, 13, 14, 11, 13, 10, 14, 10, 13, 11, 11, 17, 22, 25, 19, 13, 12, 15,
                                        12, 11, 12, 13, 10, 9, 12, 10, 16, 12, 10, 13, 11, 11, 14, 10, 19, 27, 31, 22]
    static let earlierEpisodes: [Int] = [12, 9, 11, 9, 11, 12, 10, 12, 10, 8, 7, 11, 11, 7, 13, 16, 18, 12, 11, 11,
                                         11, 10, 10, 10, 11, 10, 10, 7, 11, 9, 9, 10, 9, 12, 15, 17, 14, 10, 11, 12,
                                         11, 10, 10, 10, 8, 8, 11, 8, 12, 10, 9, 10, 10, 9, 11, 7, 14, 18, 20, 15]
    /// A dry spell −29 … −26 (Sep 11–14) around the hand soap; other dry days are calm.
    static let earlierHumidity: [Int] = [63, 68, 55, 62, 52, 68, 48, 68, 30, 66, 44, 46, 46, 31, 52, 71, 56, 66, 68, 60,
                                         47, 45, 31, 30, 53, 59, 45, 58, 64, 48, 47, 32, 31, 29, 30, 71, 60, 69, 55, 52,
                                         64, 61, 53, 52, 28, 60, 53, 49, 63, 50, 68, 29, 49, 58, 51, 71, 61, 61, 70, 48]
    static let earlierHighF: [Int] = [71, 70, 74, 70, 69, 68, 69, 70, 77, 70, 72, 72, 71, 81, 67, 73, 76, 69, 70, 72,
                                      76, 71, 90, 91, 87, 67, 68, 75, 65, 76, 67, 76, 76, 72, 71, 70, 77, 77, 73, 77,
                                      67, 77, 78, 75, 81, 67, 76, 74, 73, 67, 75, 74, 69, 67, 67, 68, 71, 70, 64, 64]
    static let earlierSleep: [Double] = [7.6, 7.5, 7.7, 6.7, 7.8, 5.5, 6.7, 7.9, 7.3, 7.9, 7.2, 7.1, 7.1, 7.3, 6.9, 6.7, 6.6, 7.0, 7.8, 7.8,
                                         7.6, 7.8, 7.4, 7.4, 7.7, 7.6, 7.6, 5.8, 7.7, 7.4, 7.2, 7.2, 7.6, 6.9, 6.6, 6.5, 6.8, 6.7, 7.5, 7.9,
                                         7.4, 7.0, 7.3, 7.1, 7.9, 6.9, 5.5, 7.6, 7.6, 7.4, 6.9, 7.8, 6.9, 7.2, 6.7, 7.7, 6.8, 6.6, 6.6, 6.9]
    static let earlierWakeUps: [Int] = [0, 0, 1, 0, 1, 1, 0, 0, 0, 1, 0, 0, 0, 0, 1, 1, 2, 1, 1, 0,
                                        0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 1, 1, 2, 1, 0, 0, 0,
                                        0, 0, 0, 1, 0, 0, 1, 1, 0, 0, 0, 0, 0, 0, 1, 0, 1, 2, 2, 1]
    /// The mid-September exam week (Mon–Thu, Sep 14–17), and the midterms.
    static let examWeek: ClosedRange<Int> = -26...(-23)
    static let examNights: Set<Int> = Set(examWeek).union(StageStory.examNights)
    /// The family trip to Seattle (Aug 24–27).
    static let tripNights: ClosedRange<Int> = -47...(-44)
    /// Late workouts, spread over the weekdays.
    static let gymNights: Set<Int> = [-58, -53, -49, -41, -40, -34, -30, -21, -17, -12, -6, -2, 4, 7]
    /// The first three nights in each new piece of clothing.
    static var clothesNights: Set<Int> {
        Set(clothes.flatMap { $0.firstNight...($0.firstNight + 2) })
    }

    private static func makeNight(_ i: Int) -> Night {
        let clothes = clothesNights
        if i >= 0 {
            return Night(id: i, minutes: StageStory.nights[i], episodes: StageStory.episodes[i],
                         humidity: StageStory.humidity[i], highF: StageStory.highF[i],
                         sleepHours: StageStory.sleepHours[i], wakeUps: StageStory.wakeUps[i],
                         exams: examNights.contains(i), trip: tripNights.contains(i),
                         gym: gymNights.contains(i), newClothes: clothes.contains(i))
        }
        let k = i + earlierCount
        return Night(id: i, minutes: earlierMinutes[k], episodes: earlierEpisodes[k],
                     humidity: earlierHumidity[k], highF: earlierHighF[k],
                     sleepHours: earlierSleep[k], wakeUps: earlierWakeUps[k],
                     exams: examNights.contains(i), trip: tripNights.contains(i),
                     gym: gymNights.contains(i), newClothes: clothes.contains(i))
    }

    private static func mean(_ values: [Int]) -> Double {
        values.isEmpty ? 0 : Double(values.reduce(0, +)) / Double(values.count)
    }
}
