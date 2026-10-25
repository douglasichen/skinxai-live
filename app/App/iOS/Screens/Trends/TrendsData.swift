import SwiftUI
import EczemaKit

/// Range of the Trends timeline: the last 7 nights, or every night there is ("All time"; more than 21
/// nights scroll sideways).
enum TrendsRange: String, CaseIterable, Identifiable, Hashable {
    case week, all
    var id: Self { self }
    var title: String { self == .week ? "7 nights" : "All time" }
    /// How many nights the chart shows (the last ones).
    var nights: Int { self == .week ? min(7, TrendsStory.nightCount) : TrendsStory.nightCount }
    /// Top bar subtitle: "Last 7 nights", "All time · 74 nights".
    var subtitle: String { self == .week ? "Last \(nights) nights" : "All time · \(nights) nights" }
    /// Whether night `night` is on the chart.
    func shows(_ night: Int) -> Bool {
        TrendsStory.nightIDs.contains(night) && night > StageStory.lastNightIndex - nights
    }
    /// The nights on the chart, oldest first.
    var ids: [Int] { Array(TrendsStory.nightIDs.suffix(nights)) }
}

/// Something on the timeline: a new skin-contact product he bought (on its order date: all the app can read
/// is the order, not when he used it), an exam week, the trip, a late workout.
struct TrendsEvent: Identifiable, Hashable {
    enum Kind: String, CaseIterable {
        case purchase, exams, trip, gym
    }

    let kind: Kind
    /// First and last night (a purchase: the night of its order date, both).
    let start: Int
    let end: Int
    /// "shampoo", "bodywash", "exams:-26", "trip:-47", "gym:7".
    let id: String
    let emoji: String
    /// The product's name without its size ("Summit Peak Mint Shampoo"); "Exams", "Trip", "Late gym".
    let name: String
    /// Where space is tight (the strip's chips): "Summit Peak Shampoo".
    let shortName: String
    /// A purchase: the order's full item name.
    var item: String? = nil

    /// A new thing he bought (pink on the timeline).
    var isProduct: Bool { kind == .purchase }

    /// How the timeline draws a new product: its key (launch arguments, ids), its picture and short name.
    /// Products without an entry still show, with a package and their own name.
    static let products: [String: (key: String, emoji: String, short: String)] = {
        typealias P = StageStory.Product
        return [
            P.coastlineSunscreen.item: ("sunscreen", "🌤", "Coastline Sunscreen"),
            P.summitShampoo.item: ("shampoo", "💧", "Summit Peak Shampoo"),
            P.alderPineDeodorant.item: ("deodorant", "🧴", "Alder & Pine Deodorant"),
            P.baylineHoodie.item: ("hoodie", "👕", "Bayline Hoodie"),
            P.lumenHandSoap.item: ("handsoap", "✋", "Lumen Hand Soap"),
            P.baylineTShirts.item: ("tshirts", "👕", "Bayline T-Shirts"),
            P.harborOatLotion.item: ("lotion", "🧴", "Harbor Oat Lotion"),
            P.brightwellLotion.item: ("brightwelllotion", "🧴", "Brightwell Lotion"),
            P.cloudrestPillow.item: ("pillow", "🛏", "Cloudrest Pillow"),
            P.northfieldSweater.item: ("sweater", "🧶", "Northfield Sweater"),
            P.freshMeadowDetergent.item: ("detergent", "🧺", "FreshMeadow Detergent"),
            P.darnToughSocks.item: ("socks", "🧦", "Darn Tough Socks"),
            P.brightwellBodyWash.item: ("bodywash", "🧴", "Brightwell Body Wash"),
        ]
    }()

    /// A new skin-contact order as a timeline event.
    static func purchase(_ o: StageStory.Order) -> TrendsEvent {
        let name = o.item.components(separatedBy: ",")[0]
        let look = products[o.item]
        let key = look?.key ?? name.lowercased().filter(\.isLetter)
        return TrendsEvent(kind: .purchase, start: o.night, end: o.night, id: key, emoji: look?.emoji ?? "📦",
                           name: name, shortName: look?.short ?? name, item: o.item)
    }

    /// The new things he bought that touch his skin (they list ingredients or a material), oldest first.
    static var purchases: [TrendsEvent] {
        StageStory.orders(calendar: TrendsStory.calendar).filter { !$0.boughtBefore && $0.skinContact }.map(purchase)
    }

    /// Every event, oldest first. Purchases sit on their order date only.
    static var all: [TrendsEvent] {
        var list = purchases
        list += TrendsStory.runs(\.exams).map {
            TrendsEvent(kind: .exams, start: $0.lowerBound, end: $0.upperBound, id: "exams:\($0.lowerBound)", emoji: "📚",
                        name: "Exams", shortName: "Exams")
        }
        list += TrendsStory.runs(\.trip).map {
            TrendsEvent(kind: .trip, start: $0.lowerBound, end: $0.upperBound, id: "trip:\($0.lowerBound)", emoji: "✈",
                        name: "Trip", shortName: "Trip")
        }
        list += StageHistory.nights.filter(\.gym).map {
            TrendsEvent(kind: .gym, start: $0.id, end: $0.id, id: "gym:\($0.id)", emoji: "🏋️", name: "Late gym", shortName: "Late gym")
        }
        return list.sorted { $0.start < $1.start }
    }

    /// The event with id `id` ("shampoo", "bodywash", "exams:1", "gym:7"; also plain "exams" = the midterms,
    /// "trip" and "gym" = the last workout, for launch arguments).
    static func find(_ id: String) -> TrendsEvent? {
        let list = all
        if let e = list.first(where: { $0.id == id }) { return e }
        switch id {
        case "exams": return list.last { $0.kind == .exams }
        case "trip": return list.last { $0.kind == .trip }
        case "gym": return list.last { $0.kind == .gym }
        case "wash", "bodyWash": return list.first { $0.id == "bodywash" }
        default: return nil
        }
    }

    /// The events on night `i`.
    static func on(_ i: Int) -> [TrendsEvent] { all.filter { ($0.start...$0.end).contains(i) } }
}

/// The overlay drawn over the scratch bars: one factor at a time, on its own axis at the right.
enum TrendsOverlay: String, CaseIterable, Identifiable, Hashable {
    case none, sleep, humidity, temp, stress
    var id: Self { self }

    /// Chip title: "None", "Sleep", "Humidity", "Temp", "Stress".
    var title: String {
        switch self {
        case .none: return "None"
        case .sleep: return "Sleep"
        case .humidity: return "Humidity"
        case .temp: return "Temp"
        case .stress: return "Stress"
        }
    }

    /// The right axis' title: "SLEEP · HOURS", "OUTDOOR HUMIDITY · %", "DAY HIGH · °F", "HRV · MS".
    var axisTitle: String {
        switch self {
        case .none: return ""
        case .sleep: return "SLEEP · HOURS"
        case .humidity: return "OUTDOOR HUMIDITY · %"
        case .temp: return "DAY HIGH · °F"
        case .stress: return "STRESS · HRV MS"
        }
    }

    /// The right axis, bottom to top: six gridlines shared with the minutes (0 … 50).
    var domain: ClosedRange<Double> {
        switch self {
        case .none: return 0...1
        case .sleep: return 4...9
        case .humidity: return 0...100
        case .temp: return 50...100
        case .stress: return 20...70
        }
    }

    /// The night's value.
    func value(_ i: Int) -> Double? {
        let n = TrendsStory.night(i)
        switch self {
        case .none: return nil
        case .sleep: return n.sleepHours
        case .humidity: return Double(n.humidity)
        case .temp: return Double(n.highF)
        case .stress: return Double(TrendsStory.hrv(i))
        }
    }

    /// "6.9 h", "49%", "66°F", "51 ms".
    func text(_ v: Double) -> String {
        switch self {
        case .none: return ""
        case .sleep: return String(format: "%.1f h", v)
        case .humidity: return "\(Int(v.rounded()))%"
        case .temp: return "\(Int(v.rounded()))°F"
        case .stress: return "\(Int(v.rounded())) ms"
        }
    }

    /// An axis label: "9h", "100%", "90°", "60".
    func tick(_ v: Double) -> String {
        let n = Int(v.rounded())
        switch self {
        case .none: return ""
        case .sleep: return "\(n)h"
        case .humidity: return "\(n)%"
        case .temp: return "\(n)°"
        case .stress: return "\(n)"
        }
    }

    var chart: OverlayBarChart.Overlay? {
        guard self != .none else { return nil }
        let steps = TrendsStory.gridSteps
        let d = domain
        let ticks = (0...steps).map { tick(d.lowerBound + (d.upperBound - d.lowerBound) * Double($0) / Double(steps)) }
        return .init(id: rawValue, title: axisTitle, domain: d, ticks: ticks)
    }
}

/// The selected night, as the strip under the chart lists it.
struct TrendsNight: Equatable {
    struct Metric: Equatable, Identifiable {
        var id: String { label }
        /// "SLEEP"
        let label: String
        /// "6.9"
        let value: String
        /// "h"
        let unit: String
    }

    let id: Int
    /// "LAST NIGHT · FRI OCT 23", "TUE OCT 20"
    let eyebrow: String
    let minutes: Int
    let metrics: [Metric]
    /// The new things bought that day.
    let purchases: [TrendsEvent]
}

/// What the Trends tab shows, all from `StageStory` and its longer history `StageHistory`.
///
/// Nights are numbered like `StageStory`'s (0 = oldest of the 14 … 13 = last night). The 60 nights of
/// `StageHistory` before them have negative numbers (−60 … −1); "All time" shows all 74.
enum TrendsStory {
    static var calendar: Calendar { TodayStory.calendar }

    // MARK: Nights

    static var nightIDs: ClosedRange<Int> { StageHistory.nightIDs }
    static var nightCount: Int { nightIDs.count }

    static func night(_ i: Int) -> StageHistory.Night { StageHistory.night(i) }

    /// Heart-rate variability on night `i`, ms (`StageStory.hrv`, the numbers Claude's sleep tool reads).
    static func hrv(_ i: Int) -> Int { StageStory.hrv(i) }

    /// The runs of nights with `flag`, oldest first (the exam weeks: mid-September and the midterms; the trip).
    static func runs(_ flag: KeyPath<StageHistory.Night, Bool>) -> [ClosedRange<Int>] {
        var runs: [ClosedRange<Int>] = []
        for n in StageHistory.nights where n[keyPath: flag] {
            if let last = runs.last, last.upperBound == n.id - 1 {
                runs[runs.count - 1] = last.lowerBound...n.id
            } else {
                runs.append(n.id...n.id)
            }
        }
        return runs
    }

    // MARK: Chart

    /// Minutes at the top gridline (the worst night is 41) and the steps under it.
    static let scaleTop: Double = 50
    static let gridSteps = 5

    static func nights(_ range: TrendsRange, overlay: TrendsOverlay, now: Date = Date()) -> [OverlayBarChart.Night] {
        let cal = calendar
        return range.ids.map { i in
            let n = night(i)
            let date = StageStory.nightDate(i, now: now, calendar: cal)
            return OverlayBarChart.Night(
                id: i, minutes: Double(n.minutes), hot: n.flare,
                day: "\(cal.component(.day, from: date))",
                month: StageStory.month(date, calendar: cal).uppercased(),
                startsMonth: cal.component(.day, from: date) == 1,
                isLast: i == StageStory.lastNightIndex,
                overlay: overlay.value(i),
                accessibility: accessibility(i, date: date))
        }
    }

    /// The exam weeks and the trip on the chart's nights (clipped to the range), as light labelled bands.
    static func bands(_ range: TrendsRange) -> [OverlayBarChart.Band] {
        guard let first = range.ids.first, let last = range.ids.last else { return [] }
        let all = runs(\.exams).map { ($0, "exams", "EXAMS", "📚") } + runs(\.trip).map { ($0, "trip", "TRIP", "✈") }
        return all.compactMap { run, key, label, emoji in
            guard run.upperBound >= first, run.lowerBound <= last else { return nil }
            return .init(id: "\(key):\(run.lowerBound)", start: max(run.lowerBound, first), end: min(run.upperBound, last),
                         label: label, emoji: emoji)
        }
    }

    /// The new products on the chart's nights; things bought the same day (the sweater and the detergent, Oct 5)
    /// side by side, in order.
    static func markers(_ range: TrendsRange) -> [OverlayBarChart.Marker] {
        let shown = TrendsEvent.purchases.filter { range.shows($0.start) }
        return shown.map { e in
            .init(id: e.id, night: e.start, row: shown.filter { $0.start == e.start }.firstIndex(of: e) ?? 0, emoji: e.emoji,
                  fill: Twin.Palette.pink, accessibility: "\(e.name), bought \(dayText(night: e.start)). Opens details.")
        }
    }

    // MARK: The selected night

    static func detail(_ i: Int, now: Date = Date()) -> TrendsNight {
        let i = min(max(i, nightIDs.lowerBound), nightIDs.upperBound)
        let n = night(i)
        let date = StageStory.nightDate(i, now: now, calendar: calendar)
        let day = dayText(date).uppercased()
        return TrendsNight(
            id: i,
            eyebrow: i == StageStory.lastNightIndex ? "LAST NIGHT · \(day)" : day,
            minutes: n.minutes,
            metrics: [
                .init(label: "Scratch", value: "\(n.minutes)", unit: "min"),
                .init(label: "Sleep", value: String(format: "%.1f", n.sleepHours), unit: "h"),
                .init(label: "Humidity", value: "\(n.humidity)", unit: "%"),
                .init(label: "Temp", value: "\(n.highF)", unit: "°F"),
                .init(label: "HRV", value: "\(hrv(i))", unit: "ms"),
            ],
            purchases: TrendsEvent.on(i).filter(\.isProduct))
    }

    /// "Tue Oct 20"
    static func dayText(_ date: Date) -> String {
        "\(StageStory.weekday(date, short: true, calendar: calendar)) \(StageStory.monthDay(date, calendar: calendar))"
    }

    /// "Tue Oct 20" for night `i`.
    static func dayText(night i: Int, now: Date = Date()) -> String {
        dayText(StageStory.nightDate(i, now: now, calendar: calendar))
    }

    /// "Monday, Oct 19: 11 minutes. Slept 7.0 hours, humidity 50%, high 65°F, HRV 53 ms. Bought Brightwell
    /// Sensitive Fragrance-Free Body Wash."
    private static func accessibility(_ i: Int, date: Date) -> String {
        let n = night(i)
        var text = "\(StageStory.weekday(date, calendar: calendar)), \(StageStory.monthDay(date, calendar: calendar)): "
            + "\(n.minutes) minutes"
        if i == StageStory.lastNightIndex { text = "Last night, " + text }
        text += n.flare ? ", above your usual." : "."
        text += String(format: " Slept %.1f hours, humidity %d%%, high %d°F, HRV %d ms.", n.sleepHours, n.humidity, n.highF, hrv(i))
        for e in TrendsEvent.on(i) { text += e.isProduct ? " Bought \(e.name)." : " \(e.name)." }
        return text
    }
}

// MARK: - Launch arguments (debug builds: screenshots)

enum TrendsLaunch {
    private static func string(_ key: String) -> String? {
        #if DEBUG
        return UserDefaults.standard.string(forKey: key)
        #else
        return nil
        #endif
    }

    /// `-trendsSelect -2`: selects that night after the entrance (read from the raw arguments: a
    /// negative number would look like a flag to `UserDefaults`).
    static var select: Int? {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        guard let k = args.firstIndex(of: "-trendsSelect"), args.indices.contains(k + 1) else { return nil }
        return Int(args[k + 1])
        #else
        return nil
        #endif
    }
    /// `-trendsEvent shampoo|bodywash|sweater|…|exams|trip|gym`: opens that event's sheet.
    static var event: String? { string("trendsEvent") }
    /// `-trendsOverlay sleep|humidity|temp|stress`: the overlay drawn over the bars at launch.
    static var overlay: TrendsOverlay? {
        string("trendsOverlay").flatMap { TrendsOverlay(rawValue: $0 == "hrv" ? "stress" : $0) }
    }
}

// MARK: - After a purchase

/// How scratching went right after he bought a new item, from what the app can read (the order date
/// and the nightly minutes; not when he used it): the average of the 4 nights after the order date
/// against his usual 12 min, and the other new things bought that day (they share those nights).
struct TrendsPurchase {
    /// Nights after the order date that are compared.
    static let nightsAfter = 4

    let event: TrendsEvent
    /// The night of the order date.
    let bought: Int
    /// The nights compared (up to 4, ending at last night at the latest).
    let nights: ClosedRange<Int>
    /// Average minutes on those nights.
    let afterMinutes: Double
    let usual: Int
    /// Other new things bought the same day.
    let sameDay: [TrendsEvent]

    init?(_ e: TrendsEvent) {
        guard e.isProduct, e.start < StageStory.lastNightIndex else { return nil }
        event = e
        bought = e.start
        nights = (bought + 1)...min(bought + Self.nightsAfter, StageStory.lastNightIndex)
        afterMinutes = Double(nights.map { StageHistory.night($0).minutes }.reduce(0, +)) / Double(nights.count)
        usual = StageStory.usual
        sameDay = TrendsEvent.purchases.filter { $0.id != e.id && $0.start == e.start }
    }

    /// after − usual, rounded.
    var difference: Int { Int((afterMinutes - Double(usual)).rounded()) }

    /// The average is over 1.5 × usual: drawn orange, like the chart's bars over that line.
    var overFlareLine: Bool { afterMinutes > StageStory.flareFactor * Double(usual) }
}
