import Foundation

/// Douglas's last 14 nights for the stage build: one source of truth for every number on screen and
/// for the data Claude's tools read. A port of the live page's `web/story.js` with the numbers of the
/// approved prototype (v5).
///
/// Night `i` (0 = oldest … 13 = last night) started on the evening of `nightDate(i)`: today at noon
/// minus (14 − i) days, so the story always ends last night. Dates are relative to `now`, on the
/// Gregorian calendar in the calendar's time zone (the phone's by default). Text helpers write English,
/// the app's language, whatever the phone's region is.
///
/// What happened: he ordered a body wash for the first time the day before night 10 (a "fragrance-free,
/// sensitive skin" one) and has used it since; his scratching climbed from that night on. Midterm exams on
/// nights 1–3 didn't move it, the only dry night (13) came after the rise began, and his laundry detergent is
/// the same fragrance-free one he has ordered every month for two years. It is his fourth flare: the three
/// before it, and what they have in common, are in `StageHistory` (the 60 nights before these 14).
public enum StageStory {

    // MARK: - Nights (index 0 = oldest … 13 = last night)

    /// Minutes of scratching per night, measured by the watch.
    public static let nights: [Int] = [9, 14, 11, 8, 15, 12, 10, 16, 13, 11, 17, 24, 29, 41]
    /// Scratching episodes per night.
    public static let episodes: [Int] = [8, 11, 9, 7, 12, 10, 8, 12, 11, 9, 13, 16, 19, 23]
    /// Hours asleep per night (Apple Health).
    public static let sleepHours: [Double] = [7.4, 7.1, 6.2, 6.0, 6.4, 7.5, 7.3, 7.2, 7.6, 7.0, 6.9, 6.4, 5.6, 5.1]
    /// Times he woke up per night.
    public static let wakeUps: [Int] = [0, 1, 1, 1, 0, 0, 1, 0, 0, 1, 1, 1, 2, 2]
    /// Outdoor humidity on the day each night started, percent.
    public static let humidity: [Int] = [52, 49, 55, 51, 47, 50, 53, 48, 51, 50, 49, 47, 46, 29]
    /// High temperature on that day, °F.
    public static let highF: [Int] = [64, 66, 63, 61, 65, 67, 66, 64, 63, 65, 66, 64, 63, 68]
    /// Heart-rate variability per night, ms. It drops over the last three nights.
    public static let hrvMs: [Int] = [53, 51, 52, 54, 50, 52, 53, 51, 52, 53, 51, 46, 42, 38]

    /// His usual minutes of scratching a night.
    public static let usual = 12
    /// His usual HRV, ms.
    public static let usualHrvMs = 52
    /// Nights in the story: 14.
    public static var nightCount: Int { nights.count }
    /// Index of last night: 13.
    public static var lastNightIndex: Int { nights.count - 1 }

    /// The first night with the new body wash. He ordered it the day before, his first body wash ever.
    public static let bodyWashNight = 10
    /// The only dry night (humidity 29%).
    public static let dryAirNight = 13
    /// Midterm exams.
    public static let examNights: ClosedRange<Int> = 1...3
    /// Humidity under this is "dry", percent.
    public static let dryBelowPercent = 35

    // MARK: - Around you (today)

    public static let location = "Berkeley, CA"
    /// US air quality index, and its word.
    public static let airQuality = 41
    public static let airQualityLabel = "good"
    public static let pollen = "low"

    // MARK: - Derived numbers

    /// A night above this × usual is a flare night (the orange bars): nights 11–13.
    public static let flareFactor = 1.5

    /// Is night `night` above 1.5 × usual? (False for an index outside the story.)
    public static func isFlare(_ night: Int) -> Bool {
        nights.indices.contains(night) && Double(nights[night]) > flareFactor * Double(usual)
    }

    /// Flare nights in a row, ending last night: 3 ("Up 3 nights in a row").
    public static var flareStreak: Int {
        var streak = 0
        for night in nights.indices.reversed() {
            guard isFlare(night) else { break }
            streak += 1
        }
        return streak
    }

    /// Night `night` ÷ usual. Last night: 41 / 12 ≈ 3.4 ("3.4× your usual").
    public static func ratio(_ night: Int) -> Double {
        Double(nights[night]) / Double(usual)
    }

    /// Mean minutes a night over the last 7 nights: 151 / 7 ≈ 21.6 (shown as 22).
    public static var weekAverage: Double { mean(nights.suffix(7)) }
    /// Mean minutes a night over the 7 nights before those: 79 / 7 ≈ 11.3.
    public static var previousWeekAverage: Double { mean(nights.dropLast(7).suffix(7)) }
    /// How much the last 7 nights went up from the 7 before, percent, rounded: 91 ("▲ up 91% from last week").
    public static var weekChangePercent: Int {
        Int((weekAverage / previousWeekAverage * 100 - 100).rounded())
    }

    // MARK: - Last night

    /// Last night (night 13) in detail.
    public enum LastNight {
        /// Minutes of scratching: 41.
        public static var minutes: Int { StageStory.nights[StageStory.lastNightIndex] }
        /// Scratching episodes: 23.
        public static var episodes: Int { StageStory.episodes[StageStory.lastNightIndex] }
        /// Intense episodes among them: 7.
        public static let intense = 7
        /// Times he woke up: 2.
        public static var wakeUps: Int { StageStory.wakeUps[StageStory.lastNightIndex] }
        /// Hours asleep: 5.1.
        public static var sleepHours: Double { StageStory.sleepHours[StageStory.lastNightIndex] }
        /// HRV: 38 ms (usual 52).
        public static var hrvMs: Int { StageStory.hrvMs[StageStory.lastNightIndex] }
        /// Humidity: 29% (dry).
        public static var humidity: Int { StageStory.humidity[StageStory.lastNightIndex] }
        /// High temperature: 68 °F.
        public static var highF: Int { StageStory.highF[StageStory.lastNightIndex] }
        /// The worst stretch of the night.
        public static let worst = "2–4 AM"
        /// When he fell asleep and woke up, as clock text.
        public static let asleep = "11:04 PM"
        public static let awake = "6:52 AM"
        /// The clock hour of `minutesPerHour[0]`: 11 PM.
        public static let firstHour = 23
        /// Minutes of scratching per clock hour, 11 PM … 6 AM. They add up to 41.
        public static let minutesPerHour: [Int] = [1, 3, 6, 10, 11, 6, 3, 1]
        /// Labels of those hours.
        public static let hourLabels: [String] = ["11P", "12A", "1A", "2A", "3A", "4A", "5A", "6A"]
        /// 32 quarter-hour buckets from 11:00 PM to 7:00 AM, minutes each: the prototype's split (four
        /// seeded random weights per hour, a weight under 0.18 becomes 0, each hour keeps its total).
        /// Always the same numbers; they add up to 41.
        public static let quarterHours: [Double] = StageStory.quarterHourSplit(minutesPerHour, seed: 7)

        /// 11:04 PM on the evening of night 13: when he fell asleep.
        public static func asleepDate(now: Date = Date(), calendar: Calendar = .current) -> Date {
            let cal = StageStory.gregorian(calendar)
            return StageStory.time(23, 4, on: StageStory.nightDate(StageStory.lastNightIndex, now: now, calendar: cal), cal)
        }

        /// 6:52 AM the morning after (today): when he woke up.
        public static func awakeDate(now: Date = Date(), calendar: Calendar = .current) -> Date {
            let cal = StageStory.gregorian(calendar)
            let evening = StageStory.nightDate(StageStory.lastNightIndex, now: now, calendar: cal)
            let morning = cal.date(byAdding: .day, value: 1, to: evening) ?? evening
            return StageStory.time(6, 52, on: morning, cal)
        }
    }

    // MARK: - Dates

    /// Noon on the day night `night` started (it started that evening). Night 13 = yesterday,
    /// night 0 = 14 days ago.
    public static func nightDate(_ night: Int, now: Date = Date(), calendar: Calendar = .current) -> Date {
        let cal = gregorian(calendar)
        let today = noon(now, cal)
        guard let day = cal.date(byAdding: .day, value: night - nights.count, to: today) else { return today }
        return noon(day, cal)
    }

    /// The 14 night dates, oldest first.
    public static func nightDates(now: Date = Date(), calendar: Calendar = .current) -> [Date] {
        nights.indices.map { nightDate($0, now: now, calendar: calendar) }
    }

    /// The night that started on the calendar day of `date`, if it is one of the 14.
    public static func night(on date: Date, now: Date = Date(), calendar: Calendar = .current) -> Int? {
        let cal = gregorian(calendar)
        return nights.indices.first { cal.isDate(nightDate($0, now: now, calendar: cal), inSameDayAs: date) }
    }

    /// The night of a "YYYY-MM-DD" date (e.g. Claude's `marker_date`), if it is one of the 14.
    public static func night(iso: String, now: Date = Date(), calendar: Calendar = .current) -> Int? {
        date(iso: iso, calendar: calendar).flatMap { night(on: $0, now: now, calendar: calendar) }
    }

    // MARK: - Text (English, whatever the phone's region)

    /// "2026-10-20": the tools' date format, in the calendar's time zone.
    public static func iso(_ date: Date, calendar: Calendar = .current) -> String {
        let c = gregorian(calendar).dateComponents([.year, .month, .day], from: date)
        return "\(padded(c.year ?? 0, 4))-\(padded(c.month ?? 0, 2))-\(padded(c.day ?? 0, 2))"
    }

    /// Noon on the day of "2026-10-20" (on the first day of "2026-10-11 to 2026-10-13"), or nil if the
    /// text doesn't start with a real date.
    public static func date(iso text: String, calendar: Calendar = .current) -> Date? {
        let cal = gregorian(calendar)
        let parts = text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(10).split(separator: "-")
        guard parts.count == 3, parts[0].count == 4,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              let date = cal.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) else { return nil }
        let back = cal.dateComponents([.year, .month, .day], from: date)   // no "February 31"
        return back.year == year && back.month == month && back.day == day ? date : nil
    }

    /// "Tuesday", or "Tue" when `short`.
    public static func weekday(_ date: Date, short: Bool = false, calendar: Calendar = .current) -> String {
        let index = gregorian(calendar).component(.weekday, from: date) - 1
        let name = weekdayNames[min(max(index, 0), 6)]
        return short ? String(name.prefix(3)) : name
    }

    /// "Oct", or "October" when not `short`.
    public static func month(_ date: Date, short: Bool = true, calendar: Calendar = .current) -> String {
        let index = gregorian(calendar).component(.month, from: date) - 1
        let name = monthNames[min(max(index, 0), 11)]
        return short ? String(name.prefix(3)) : name
    }

    /// "Oct 20".
    public static func monthDay(_ date: Date, calendar: Calendar = .current) -> String {
        "\(month(date, calendar: calendar)) \(gregorian(calendar).component(.day, from: date))"
    }

    /// "Oct 11–13" (the midterms), or "Oct 30 – Nov 2" across two months.
    public static func monthDayRange(_ start: Date, _ end: Date, calendar: Calendar = .current) -> String {
        let cal = gregorian(calendar)
        if cal.component(.month, from: start) == cal.component(.month, from: end) {
            return "\(monthDay(start, calendar: cal))–\(cal.component(.day, from: end))"
        }
        return "\(monthDay(start, calendar: cal)) – \(monthDay(end, calendar: cal))"
    }

    /// "Saturday, October 24, 2026": the `today` the chat server expects.
    public static func todayLong(now: Date = Date(), calendar: Calendar = .current) -> String {
        let cal = gregorian(calendar)
        let c = cal.dateComponents([.year, .day], from: now)
        return "\(weekday(now, calendar: cal)), \(month(now, short: false, calendar: cal)) \(c.day ?? 1), \(c.year ?? 2026)"
    }

    // MARK: - Orders (Amazon)

    /// Something he can order: its name, category and what its label says. Skin-contact products have
    /// an ingredient list (liquids, creams) or a material (clothing, the pillow); the rest have neither.
    public struct Product: Sendable, Hashable {
        public let item: String
        public let category: String
        /// The ingredients, in label order.
        public let ingredients: [String]?
        /// What it is made of ("100% lambswool").
        public let material: String?

        public init(item: String, category: String, ingredients: [String]? = nil, material: String? = nil) {
            self.item = item
            self.category = category
            self.ingredients = ingredients
            self.material = material
        }

        /// It touches his skin: it has an ingredient list or a material.
        public var skinContact: Bool { ingredients != nil || material != nil }
    }

    /// One online order.
    public struct Order: Sendable, Hashable {
        /// Noon on the order day.
        public let date: Date
        /// The night that started on the order day (−60 … 13).
        public let night: Int
        public let item: String
        public let category: String
        /// He had bought this before (a repeat purchase).
        public let boughtBefore: Bool
        public let note: String?
        /// The ingredient list, when the product has one.
        public let ingredients: [String]?
        /// The material, for clothing and the pillow.
        public let material: String?

        /// It touches his skin: it has an ingredient list or a material.
        public var skinContact: Bool { ingredients != nil || material != nil }
    }

    /// The body wash's item name.
    public static var bodyWashItem: String { Product.brightwellBodyWash.item }
    /// The body wash's ingredients, in label order (no fragrance).
    public static var bodyWashIngredients: [String] { Product.brightwellBodyWash.ingredients ?? [] }

    /// His 29 orders of the last ~11 weeks (nights −60 … 12), oldest first: repeat purchases he has used for
    /// years, the new products of the four flares (see `StageHistory.flares`) and new things that changed
    /// nothing (sunscreen, deodorant, lotion, a pillow, a hoodie, T-shirts, socks).
    public static func orders(now: Date = Date(), calendar: Calendar = .current) -> [Order] {
        let cal = gregorian(calendar)
        func o(_ night: Int, _ product: Product, before: Bool, note: String? = nil) -> Order {
            order(night, product, before: before, note: note, now: now, cal)
        }
        func o(_ night: Int, _ item: String, _ category: String, before: Bool, note: String? = nil) -> Order {
            o(night, Product(item: item, category: category), before: before, note: note)
        }
        typealias P = Product
        let monthly = "fragrance-free; same product every month for 2 years", washed = "washed before wearing"
        let coffee = "Peet's Major Dickason's Coffee Beans, 2 lb", bars = "RXBAR Protein Bars, 12 count"
        return [
            o(-60, P.evercleanDetergent, before: true, note: monthly),
            o(-58, P.riverstoneShampoo, before: true, note: "repeat purchase, every ~6 weeks"),
            o(-56, P.coastlineSunscreen, before: false, note: "for sunny days"),
            o(-52, coffee, "grocery", before: true),
            o(-47, P.summitShampoo, before: false, note: "travel size"),
            o(-45, P.dermacalmCream, before: true, note: "fragrance-free; repeat purchase, uses daily"),
            o(-40, "Five Star Spiral Notebooks, 5 pack", "school", before: true),
            o(-38, P.alderPineDeodorant, before: false, note: "uses daily"),
            o(-35, P.baylineHoodie, before: false, note: washed),
            o(-33, "Colgate Total Toothpaste, 2 pack", "personal care", before: true),
            o(-30, P.evercleanDetergent, before: true, note: monthly),
            o(-28, P.lumenHandSoap, before: false),
            o(-24, "Anker USB-C Charging Cable, 6 ft", "electronics", before: false),
            o(-21, P.baylineTShirts, before: false, note: washed),
            o(-20, bars, "grocery", before: true),
            o(-18, P.harborOatLotion, before: false, note: "uses daily"),
            o(-16, P.riverstoneShampoo, before: true, note: "repeat purchase, every ~6 weeks"),
            o(-15, P.willowHandSoap, before: true, note: "unscented; repeat purchase"),
            o(-13, P.brightwellLotion, before: false),
            o(-9, P.cloudrestPillow, before: false),
            o(-8, "Duracell AAA Batteries, 8 pack", "school", before: true),
            o(-5, P.northfieldSweater, before: false, note: "first wool sweater"),
            o(-5, P.freshMeadowDetergent, before: false, note: "trial size"),
            o(2, coffee, "grocery", before: true),
            o(3, P.evercleanDetergent, before: true, note: monthly),
            o(5, P.darnToughSocks, before: false, note: washed),
            o(7, "Nissin Top Ramen, 24 pack", "grocery", before: true),
            bodyWashOrder(now: now, calendar: cal),
            o(11, "Philips LED Desk Lamp Bulb", "household", before: true),
            o(12, bars, "grocery", before: true),
        ]
    }

    /// The body wash: ordered the day before night 10, the first body wash he ever ordered.
    public static func bodyWashOrder(now: Date = Date(), calendar: Calendar = .current) -> Order {
        order(bodyWashNight - 1, Product.brightwellBodyWash, before: false,
              note: "first time ordering any body wash; delivered next day", now: now, gregorian(calendar))
    }

    // MARK: - Calendar

    /// One calendar event.
    public struct Event: Sendable, Hashable {
        /// Noon on its (first) day.
        public let date: Date
        /// Noon on its last day, for an event over several days (the midterms).
        public let endDate: Date?
        public let title: String
        public let note: String?
    }

    /// His calendar, oldest first: the family trip (nights −47 … −44), the mid-September exam week
    /// (−26 … −23), the midterms (nights 1–3), the dentist, a project deadline, and the hackathon tomorrow.
    public static func calendarEvents(now: Date = Date(), calendar: Calendar = .current) -> [Event] {
        let cal = gregorian(calendar)
        let night = { (i: Int) in nightDate(i, now: now, calendar: cal) }
        let tomorrow = noon(cal.date(byAdding: .day, value: 1, to: now) ?? now, cal)
        return [
            Event(date: night(StageHistory.tripNights.lowerBound), endDate: night(StageHistory.tripNights.upperBound),
                  title: "Trip to Seattle (family)", note: nil),
            Event(date: night(StageHistory.examWeek.lowerBound), endDate: night(StageHistory.examWeek.upperBound),
                  title: "Exam week (CS 61B, Math 54 quizzes)", note: nil),
            Event(date: night(examNights.lowerBound), endDate: night(examNights.upperBound),
                  title: "Midterm exams (CS 61B, Math 54)", note: "stressful week"),
            Event(date: night(6), endDate: nil, title: "Dentist", note: nil),
            Event(date: night(9), endDate: nil, title: "Team project deadline", note: nil),
            Event(date: tomorrow, endDate: nil, title: "CalHacks 13.0 (hackathon)", note: nil),
        ]
    }

    // MARK: - Claude's data tools

    /// The data tools the app runs for Claude, named as the chat server names them. The other tools
    /// (`show_timeline`, `show_product`, `ask_user`, `show_conclusion`) are drawn by the chat.
    public static let dataTools: [String] = ["scratch_history", "order_history", "weather_history", "calendar_events", "sleep_history"]

    /// Runs a data tool with the model's arguments (`nights` or `days`, clamped like story.js: missing,
    /// 0 or not a number means the default). Scratching, weather and sleep go back up to 74 nights (14 by
    /// default); nights before the story's 14 come from `StageHistory`. Orders go back up to 120 days (all by
    /// default), calendar events too (events that end in the window, and the ones still ahead). The keys and
    /// shapes are story.js's, plus `material` on clothing orders,
    /// with dates as "YYYY-MM-DD" in the calendar's time zone. An unknown name returns
    /// `["error": "There is no tool called <name>."]`.
    public static func runTool(name: String, arguments: [String: Any] = [:], now: Date = Date(),
                               calendar: Calendar = .current) -> [String: Any] {
        toolResult(name, arguments, now: now, calendar: calendar).foundationObject as? [String: Any] ?? [:]
    }

    /// `runTool` for a tool call as the model sent it: `argumentsJSON` is the call's `function.arguments`
    /// text (missing or malformed means no arguments). Returns the JSON text for the tool message, with
    /// the keys in story.js's order.
    public static func runToolJSON(name: String, argumentsJSON: String?, now: Date = Date(),
                                   calendar: Calendar = .current) -> String {
        toolResult(name, arguments(fromJSON: argumentsJSON), now: now, calendar: calendar).text
    }

    /// How far back the scratching, weather and sleep tools go: 74 nights (all of `StageHistory`).
    public static let toolMaxNights = 74
    /// How far back the order and calendar tools go: 120 days.
    public static let toolMaxDays = 120

    // MARK: - Internals

    /// Heart-rate variability on night `i`, ms (lower = more stress): `hrvMs` for the last 14 nights;
    /// before them his usual with small deterministic night-to-night noise, a dip on the flare nights (poor
    /// sleep), a 6–8 ms dip through the mid-September exam week (stress; its last night too, when his
    /// scratching was back to normal) and after short nights. Trends draws the same numbers.
    public static func hrv(_ i: Int) -> Int {
        if i >= 0 { return hrvMs[min(i, hrvMs.count - 1)] }
        let flareDip: [Int: Int] = [-46: 3, -45: 6, -44: 7, -43: 4,              // flare 1
                                    -27: 3, -26: 7, -25: 8, -24: 7, -23: 6,      // flare 2 and the exam week
                                    -4: 4, -3: 7, -2: 8, -1: 5]                  // flare 3
        let noise = ((i * 37 + 1_000_003) % 7) - 3
        let short = StageHistory.night(i).sleepHours < StageHistory.shortSleepBelow ? 3 : 0
        return usualHrvMs + noise - (flareDip[i] ?? 0) - short
    }

    /// Night `i`'s numbers for the tools: the story's own for 0 … 13, `StageHistory`'s before.
    private static func toolNight(_ i: Int) -> (minutes: Int, episodes: Int, humidity: Int, highF: Int, sleep: Double, wakes: Int) {
        if i >= 0 { return (nights[i], episodes[i], humidity[i], highF[i], sleepHours[i], wakeUps[i]) }
        let n = StageHistory.night(i)
        return (n.minutes, n.episodes, n.humidity, n.highF, n.sleepHours, n.wakeUps)
    }

    static func toolResult(_ name: String, _ args: [String: Any], now: Date, calendar: Calendar) -> StageJSON {
        let cal = gregorian(calendar)
        let day = { (i: Int) in iso(nightDate(i, now: now, calendar: cal), calendar: cal) }
        switch name {
        case "scratch_history":
            let from = nights.count - clampCount(args["nights"], max: toolMaxNights, default: nights.count)
            let list = (from..<nights.count).map { i -> StageJSON in
                .object([("night_of", .string(day(i))),
                         ("weekday", .string(weekday(nightDate(i, now: now, calendar: cal), calendar: cal))),
                         ("scratch_minutes", .int(toolNight(i).minutes)),
                         ("scratch_episodes", .int(toolNight(i).episodes))])
            }
            return .object([("usual_minutes_per_night", .int(usual)),
                            ("measured_by", .string("Apple Watch, every night")),
                            ("nights", .array(list)),
                            ("last_night_worst_hours", .string(LastNight.worst))])
        case "order_history":
            let since = windowStart(args["days"], now: now, cal)
            let list = orders(now: now, calendar: cal).filter { $0.date >= since }.map { $0.json(cal) }
            return .object([("source", .string("Amazon order history")), ("orders", .array(list))])
        case "weather_history":
            let from = nights.count - clampCount(args["days"], max: toolMaxNights, default: nights.count)
            let list = (from..<nights.count).map { i -> StageJSON in
                .object([("date", .string(day(i))), ("humidity_percent", .int(toolNight(i).humidity)), ("high_f", .int(toolNight(i).highF))])
            }
            return .object([("location", .string(location)), ("days", .array(list))])
        case "calendar_events":
            let since = windowStart(args["days"], now: now, cal)
            let list = calendarEvents(now: now, calendar: cal).filter { ($0.endDate ?? $0.date) >= since }.map { $0.json(cal) }
            return .object([("events", .array(list))])
        case "sleep_history":
            let from = nights.count - clampCount(args["nights"], max: toolMaxNights, default: nights.count)
            let list = (from..<nights.count).map { i -> StageJSON in
                .object([("night_of", .string(day(i))), ("hours_asleep", .double(toolNight(i).sleep)), ("wake_ups", .int(toolNight(i).wakes)),
                         ("hrv_ms", .int(hrv(i)))])
            }
            return .object([("source", .string("Apple Health")), ("usual_hrv_ms", .int(usualHrvMs)), ("nights", .array(list))])
        default:
            return .object([("error", .string("There is no tool called \(name)."))])
        }
    }

    /// The start of the last `days` days, today included (up to `toolMaxDays`; all of them by default).
    private static func windowStart(_ days: Any?, now: Date, _ cal: Calendar) -> Date {
        let days = clampCount(days, max: toolMaxDays)
        return cal.date(byAdding: .day, value: 1 - days, to: cal.startOfDay(for: now)) ?? now
    }

    /// story.js's `clampN`: `Math.max(1, Math.min(max, Math.round(+n || dflt)))` (`dflt` = max unless given).
    static func clampCount(_ value: Any?, max: Int, default fallback: Int? = nil) -> Int {
        let x = jsNumber(value)
        let n = x.isNaN || x == 0 ? Double(fallback ?? max) : x
        let rounded = (n + 0.5).rounded(.down)   // Math.round
        return Int(Swift.max(1, Swift.min(Double(max), rounded)))
    }

    /// JavaScript's unary plus on a JSON value: numbers, numeric text and booleans; anything else is NaN.
    static func jsNumber(_ value: Any?) -> Double {
        switch value {
        case let v as Int: return Double(v)
        case let v as Double: return v
        case let v as NSNumber: return v.doubleValue
        case let v as Bool: return v ? 1 : 0
        case let v as String:
            let text = v.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? 0 : Double(text) ?? .nan
        default: return .nan
        }
    }

    /// The arguments object of a tool call (malformed or not an object: none).
    static func arguments(fromJSON text: String?) -> [String: Any] {
        guard let data = text?.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else { return [:] }
        return object as? [String: Any] ?? [:]
    }

    /// Splits minutes per hour into quarter hours like the prototype's `drawNight()`: four weights per
    /// hour from `rng(seed)` (an LCG), a weight under 0.18 becomes 0, normalized so each hour keeps its
    /// total. Bit for bit the same numbers as the prototype.
    static func quarterHourSplit(_ minutesPerHour: [Int], seed: UInt32) -> [Double] {
        var state = seed
        func next() -> Double {
            state = state &* 1_664_525 &+ 1_013_904_223
            return Double(state) / 4_294_967_296
        }
        var buckets: [Double] = []
        for minutes in minutesPerHour {
            var weights = (0..<4).map { _ in next() }.map { $0 < 0.18 ? 0 : $0 }
            if weights.reduce(0, +) == 0 { weights = [1, 1, 1, 1] }   // never with seed 7; keeps the hour's total
            let sum = weights.reduce(0, +)
            buckets += weights.map { Double(minutes) * $0 / sum }
        }
        return buckets
    }

    /// The Gregorian calendar in `calendar`'s time zone (the tools' dates are Gregorian on every phone).
    static func gregorian(_ calendar: Calendar) -> Calendar {
        guard calendar.identifier != .gregorian else { return calendar }
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        return gregorian
    }

    static func noon(_ date: Date, _ cal: Calendar) -> Date {
        time(12, 0, on: date, cal)
    }

    static func time(_ hour: Int, _ minute: Int, on date: Date, _ cal: Calendar) -> Date {
        var c = cal.dateComponents([.year, .month, .day], from: date)
        c.hour = hour
        c.minute = minute
        return cal.date(from: c) ?? date
    }

    /// An order on the day night `night` started.
    private static func order(_ night: Int, _ product: Product, before: Bool, note: String?, now: Date, _ cal: Calendar) -> Order {
        Order(date: nightDate(night, now: now, calendar: cal), night: night, item: product.item, category: product.category,
              boughtBefore: before, note: note, ingredients: product.ingredients, material: product.material)
    }

    private static func mean<C: Collection>(_ values: C) -> Double where C.Element == Int {
        values.isEmpty ? 0 : Double(values.reduce(0, +)) / Double(values.count)
    }

    private static func padded(_ number: Int, _ width: Int) -> String {
        let text = String(number)
        return String(repeating: "0", count: max(0, width - text.count)) + text
    }

    private static let weekdayNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    private static let monthNames = ["January", "February", "March", "April", "May", "June", "July", "August",
                                     "September", "October", "November", "December"]
}

// MARK: - Products

extension StageStory.Product {
    // The four flares' new products. Every one lists methylisothiazolinone (MI); nothing he tolerates does.

    public static let summitShampoo = Self(item: "Summit Peak Mint Shampoo, travel size 3 fl oz", category: "personal care",
        ingredients: ["Water", "Sodium Laureth Sulfate", "Cocamidopropyl Betaine", "Fragrance (Parfum)", "Menthol",
                      "Sodium Chloride", "Methylchloroisothiazolinone", "Methylisothiazolinone", "Citric Acid"])
    public static let lumenHandSoap = Self(item: "Lumen Citrus Foaming Hand Soap", category: "household",
        ingredients: ["Water", "Sodium Laureth Sulfate", "Glycerin", "Fragrance (Parfum)", "Limonene",
                      "Methylisothiazolinone", "Tetrasodium EDTA"])
    public static let freshMeadowDetergent = Self(item: "FreshMeadow Spring Bloom Detergent, trial size", category: "household",
        ingredients: ["Water", "Sodium Laureth Sulfate", "Alcohol Ethoxylate", "Sodium Citrate", "Fragrance",
                      "Methylisothiazolinone", "Colorant"])
    public static let northfieldSweater = Self(item: "Northfield Lambswool Crewneck Sweater", category: "clothing",
        material: "100% lambswool")
    /// "Fragrance-free, for sensitive skin": he picked it to be safe. No fragrance.
    public static let brightwellBodyWash = Self(item: "Brightwell Sensitive Fragrance-Free Body Wash, 18 fl oz",
        category: "personal care",
        ingredients: ["Water", "Sodium Laureth Sulfate", "Cocamidopropyl Betaine", "Glycerin", "Sodium Chloride",
                      "Methylisothiazolinone", "Citric Acid"])

    // New products that changed nothing.

    /// Has MI too, but no flare followed: he never opened it (only asking can tell). The one exception
    /// Claude has to ask about.
    public static let brightwellLotion = Self(item: "Brightwell Daily Moisturizing Lotion, 12 fl oz", category: "personal care",
        ingredients: ["Water", "Glycerin", "Cetearyl Alcohol", "Dimethicone", "Fragrance (Parfum)",
                      "Methylisothiazolinone", "Carbomer"])

    public static let coastlineSunscreen = Self(item: "Coastline Mineral Sunscreen SPF 30", category: "personal care",
        ingredients: ["Zinc Oxide", "Water", "Caprylic/Capric Triglyceride", "Glycerin", "Phenoxyethanol", "Tocopherol"])
    /// Fragrance and limonene, tolerated daily.
    public static let alderPineDeodorant = Self(item: "Alder & Pine Cedar Deodorant", category: "personal care",
        ingredients: ["Propylene Glycol", "Water", "Sodium Stearate", "Fragrance (Parfum)", "Linalool", "Limonene",
                      "Sodium Benzoate"])
    public static let harborOatLotion = Self(item: "Harbor Oat Daily Lotion", category: "personal care",
        ingredients: ["Water", "Glycerin", "Colloidal Oatmeal", "Cetearyl Alcohol", "Dimethicone", "Phenoxyethanol",
                      "Sodium Benzoate"])
    public static let cloudrestPillow = Self(item: "Cloudrest Memory Foam Pillow", category: "household",
        material: "polyurethane foam, polyester cover")
    public static let baylineHoodie = Self(item: "Bayline Cotton Pullover Hoodie", category: "clothing",
        material: "80% cotton, 20% polyester")
    public static let baylineTShirts = Self(item: "Bayline Crew T-Shirts, 3 pack", category: "clothing",
        material: "100% cotton")
    public static let darnToughSocks = Self(item: "Darn Tough Merino Wool Socks, 3 pairs", category: "clothing",
        material: "54% merino wool, 43% nylon, 3% spandex")

    // Repeat purchases he has used for years (no MI).

    public static let evercleanDetergent = Self(item: "Everclean Free & Clear Liquid Detergent, 92 loads", category: "household",
        ingredients: ["Water", "Sodium Laureth Sulfate", "Alcohol Ethoxylate", "Sodium Citrate", "Sodium Benzoate", "Enzymes"])
    /// Sodium laureth sulfate, cocamidopropyl betaine and fragrance, tolerated daily.
    public static let riverstoneShampoo = Self(item: "Riverstone Daily Shampoo, 16 fl oz", category: "personal care",
        ingredients: ["Water", "Sodium Laureth Sulfate", "Cocamidopropyl Betaine", "Glycerin", "Fragrance (Parfum)",
                      "Sodium Benzoate", "Citric Acid"])
    public static let dermacalmCream = Self(item: "Dermacalm Ceramide Cream, 16 oz", category: "personal care",
        ingredients: ["Water", "Glycerin", "Ceramide NP", "Cetearyl Alcohol", "Petrolatum", "Phenoxyethanol"])
    public static let willowHandSoap = Self(item: "Willow Unscented Hand Soap Refill", category: "household",
        ingredients: ["Water", "Sodium Laureth Sulfate", "Glycerin", "Cocamidopropyl Betaine", "Sodium Benzoate", "Citric Acid"])
}

// MARK: - Tool JSON

extension StageStory.Order {
    /// story.js's order object: date, item, category, bought_before, then note, ingredients and material when
    /// present.
    func json(_ cal: Calendar) -> StageJSON {
        var fields: [(String, StageJSON)] = [("date", .string(StageStory.iso(date, calendar: cal))),
                                             ("item", .string(item)),
                                             ("category", .string(category)),
                                             ("bought_before", .bool(boughtBefore))]
        if let note { fields.append(("note", .string(note))) }
        if let ingredients { fields.append(("ingredients", .array(ingredients.map { .string($0) }))) }
        if let material { fields.append(("material", .string(material))) }
        return .object(fields)
    }
}

extension StageStory.Event {
    /// story.js's event object: date ("a to b" for several days), title, then note when present.
    func json(_ cal: Calendar) -> StageJSON {
        let first = StageStory.iso(date, calendar: cal)
        let when = endDate.map { "\(first) to \(StageStory.iso($0, calendar: cal))" } ?? first
        var fields: [(String, StageJSON)] = [("date", .string(when)), ("title", .string(title))]
        if let note { fields.append(("note", .string(note))) }
        return .object(fields)
    }
}

/// JSON whose objects keep their key order, so a tool result reads exactly like story.js's
/// `JSON.stringify` output.
indirect enum StageJSON {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([StageJSON])
    case object([(String, StageJSON)])

    /// Plain Foundation values: `[String: Any]`, `[Any]`, `String`, `Int`, `Double`, `Bool`.
    var foundationObject: Any {
        switch self {
        case .string(let value): return value
        case .int(let value): return value
        case .double(let value): return value
        case .bool(let value): return value
        case .array(let values): return values.map(\.foundationObject)
        case .object(let fields):
            return Dictionary(fields.map { ($0.0, $0.1.foundationObject) }, uniquingKeysWith: { _, last in last })
        }
    }

    /// Compact JSON text, like `JSON.stringify`.
    var text: String {
        var out = ""
        write(to: &out)
        return out
    }

    private func write(to out: inout String) {
        switch self {
        case .string(let value): Self.quote(value, into: &out)
        case .int(let value): out += String(value)
        case .double(let value):
            if !value.isFinite { out += "null" }
            else if value == value.rounded(), abs(value) < 1e15 { out += String(Int(value)) }   // 6.0 → 6
            else { out += "\(value)" }
        case .bool(let value): out += value ? "true" : "false"
        case .array(let values):
            out += "["
            for (k, value) in values.enumerated() {
                if k > 0 { out += "," }
                value.write(to: &out)
            }
            out += "]"
        case .object(let fields):
            out += "{"
            for (k, field) in fields.enumerated() {
                if k > 0 { out += "," }
                Self.quote(field.0, into: &out)
                out += ":"
                field.1.write(to: &out)
            }
            out += "}"
        }
    }

    private static func quote(_ text: String, into out: inout String) {
        out += "\""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            default:
                if scalar.value < 0x20 {
                    let hex = String(scalar.value, radix: 16)
                    out += "\\u" + String(repeating: "0", count: 4 - hex.count) + hex
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        out += "\""
    }
}
