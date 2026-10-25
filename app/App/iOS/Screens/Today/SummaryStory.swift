import SwiftUI
import EczemaKit

/// Dates shared by Summary and Trends: Gregorian in the phone's time zone, like `StageStory`'s helpers.
enum TodayStory {
    /// The Gregorian calendar in the phone's time zone (`StageStory` dates are Gregorian everywhere).
    static var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        return cal
    }

    /// "SAT · OCT 24" (the top bar).
    static func topBarDate(_ now: Date = Date()) -> String {
        "\(StageStory.weekday(now, short: true, calendar: calendar)) · \(StageStory.monthDay(now, calendar: calendar))".uppercased()
    }
}

/// What the Summary tab says, all from `StageStory` (the same numbers Claude's tools read).
///
/// `last` is the night the page treats as last night. The app always uses night 13 (the flare). The
/// debug launch argument `-summaryState normal` reads the same story as of night 9, a calm night
/// (11 min, your usual 12; no flare in the three nights before), to show the calm page.
struct SummaryStory {
    enum Status { case flare, normal }

    /// Index of "last night" in `StageStory`'s arrays.
    let last: Int
    let now: Date

    init(last: Int = StageStory.lastNightIndex, now: Date = Date()) {
        self.last = min(max(last, 6), StageStory.lastNightIndex)
        self.now = now
    }

    /// The page at launch: the stage story, or the calm page with `-summaryState normal` (debug).
    static func current(now: Date = Date()) -> SummaryStory {
        #if DEBUG
        if UserDefaults.standard.string(forKey: "summaryState") == "normal" {
            return SummaryStory(last: 9, now: now)
        }
        #endif
        return SummaryStory(now: now)
    }

    private var calendar: Calendar { TodayStory.calendar }
    var usual: Int { StageStory.usual }

    // MARK: Status

    /// Minutes of scratching last night (41).
    var minutes: Int { StageStory.nights[last] }
    /// Last night ÷ your usual (3.4).
    var ratio: Double { Double(minutes) / Double(usual) }
    /// "3.4×" (one decimal under 10×).
    var ratioText: String { ratio >= 10 ? "\(Int(ratio.rounded()))×" : String(format: "%.1f×", ratio) }

    /// The last three nights, oldest first.
    var recent: ClosedRange<Int> { (last - 2)...last }
    /// Nights in the last three above 1.5 × your usual.
    var flareNights: Int { recent.filter(StageStory.isFlare).count }
    /// A flare: any of the last three nights above 1.5 × your usual.
    var status: Status { flareNights > 0 ? .flare : .normal }

    /// Flare nights in a row, ending last night (3).
    var streak: Int {
        var n = 0
        for i in stride(from: last, through: 0, by: -1) {
            guard StageStory.isFlare(i) else { break }
            n += 1
        }
        return n
    }

    /// "Flare-up" / "Normal": the one-word answer.
    var title: String { status == .flare ? "Flare-up" : "Normal" }

    /// "3 nights above your usual" / "Last night was about your usual".
    var detail: String {
        switch status {
        case .flare:
            if flareNights == 1 {
                return StageStory.isFlare(last) ? "Last night was well above your usual" : "1 night above your usual"
            }
            return "\(flareNights) nights above your usual"
        case .normal:
            return minutes <= usual ? "Last night was within your usual" : "Last night was about your usual"
        }
    }

    /// "Flare-up: 3 nights above your usual" (VoiceOver).
    var headline: String { "\(title): \(detail)" }

    // MARK: Last 7 nights

    /// The seven nights on the mini chart, oldest first.
    var week: ClosedRange<Int> { (last - 6)...last }

    /// The evening night `i` started, so that `last` is always yesterday.
    func date(_ i: Int) -> Date {
        StageStory.nightDate(i + (StageStory.lastNightIndex - last), now: now, calendar: calendar)
    }

    /// "FRI"
    func weekday(_ i: Int) -> String { StageStory.weekday(date(i), short: true, calendar: calendar).uppercased() }

    /// "Rising for 3 nights:" + "17 → 24 → 29 → 41 min".
    var trend: (lead: String, values: String) {
        if streak >= 2 {
            let run = Array(StageStory.nights[(last - streak)...last])
            let rising = zip(run, run.dropFirst()).allSatisfy { $0 < $1 }
            let lead = rising ? "Rising for \(streak) nights:" : "Above your usual \(streak) nights:"
            return (lead, run.map(String.init).joined(separator: " → ") + " min")
        }
        if status == .flare {
            return ("Up last night:", "\(StageStory.nights[last - 1]) → \(minutes) min")
        }
        let r = recent.map { String(StageStory.nights[$0]) }.joined(separator: " → ")
        return ("Steady:", "\(r) min, around your usual")
    }

    // MARK: Possible triggers (flare only)

    struct Trigger: Identifiable {
        let id: String
        let emoji: String
        let fill: Color
        let title: String
        /// "Bought Mon Oct 19"
        let detail: String
        /// "1 DAY BEFORE", "LAST NIGHT", "EARLIER"
        let when: String
        /// Before the rise and long gone: shown last, greyed.
        let earlier: Bool
    }

    /// The first night of the rise (the first flare night in the streak): 11.
    var riseNight: Int { last - max(streak, 1) + 1 }

    /// New things bought this many days before the rise (or during it) are listed.
    static let purchaseLead = 4

    /// What changed shortly before (or during) the rise, as plain facts: the new skin-contact things he bought
    /// (the Brightwell body wash), dry air; the midterms last, greyed, because they came well before it.
    var triggers: [Trigger] {
        guard status == .flare else { return [] }
        var list: [Trigger] = []
        let shift = StageStory.lastNightIndex - last
        for e in TrendsEvent.purchases {
            let night = e.start - shift   // on this page's nights (`last` is always yesterday)
            guard (riseNight - Self.purchaseLead)...last ~= night else { continue }
            list.append(Trigger(id: e.id, emoji: e.emoji, fill: Twin.Palette.pink, title: e.name,
                                detail: "Bought \(dayText(night))", when: relative(night), earlier: false))
        }
        let dry = StageStory.dryAirNight
        if dry <= last {
            list.append(Trigger(id: "dry", emoji: "💧", fill: Twin.Palette.orange, title: "Dry air",
                                detail: "Humidity \(StageStory.humidity[dry])% on \(dayText(dry))",
                                when: relative(dry), earlier: false))
        }
        let exams = StageStory.examNights
        if exams.upperBound <= last {
            let text = StageStory.monthDayRange(date(exams.lowerBound), date(exams.upperBound), calendar: calendar)
            list.append(Trigger(id: "exams", emoji: "📚", fill: Twin.Palette.paper, title: "Midterm exams",
                                detail: text, when: "EARLIER", earlier: true))
        }
        return list
    }

    /// Where night `i` sits against the rise: "1 DAY BEFORE", "LAST NIGHT", "DURING".
    private func relative(_ i: Int) -> String {
        if i == last { return "LAST NIGHT" }
        let before = riseNight - i
        if before > 0 { return before == 1 ? "1 DAY BEFORE" : "\(before) DAYS BEFORE" }
        return before == 0 ? "SAME NIGHT" : "DURING"
    }

    /// "Tue Oct 20"
    func dayText(_ i: Int) -> String {
        let d = date(i)
        return "\(StageStory.weekday(d, short: true, calendar: calendar)) \(StageStory.monthDay(d, calendar: calendar))"
    }

    // MARK: Factors (last night)

    struct Factor: Identifiable {
        enum Level { case bad, good, fine }
        let id: String
        let symbol: String
        let word: String
        let value: String
        let unit: String
        let status: String
        let level: Level
        let accessibility: String
    }

    /// Your usual sleep: the median of the story's nights before the new body wash.
    static var usualSleep: Double {
        let before = StageStory.sleepHours.prefix(StageStory.bodyWashNight).sorted()
        guard !before.isEmpty else { return 7 }
        let m = before.count / 2
        return before.count % 2 == 0 ? (before[m - 1] + before[m]) / 2 : before[m]
    }

    /// Sleep, stress (HRV), humidity, air quality, pollen, temperature. The ones off your usual first.
    var factors: [Factor] {
        let sleep = StageStory.sleepHours[last]
        let lowSleep = sleep < Self.usualSleep - 0.5
        let wake = StageStory.wakeUps[last]
        let hrv = StageStory.hrvMs[last]
        let lowHrv = Double(hrv) < Double(StageStory.usualHrvMs) * 0.9
        let humidity = StageStory.humidity[last]
        let dry = humidity < StageStory.dryBelowPercent
        let temp = StageStory.highF[last]
        let list = [
            Factor(id: "sleep", symbol: "bed.double.fill", word: "Sleep", value: String(format: "%.1f", sleep), unit: "h",
                   status: lowSleep ? "low" : "normal", level: lowSleep ? .bad : .good,
                   accessibility: String(format: "Sleep: %.1f hours, woke up %d times, ", sleep, wake)
                       + (lowSleep ? "shorter than usual." : "about usual.")),
            Factor(id: "stress", symbol: "waveform.path.ecg", word: "Stress", value: "\(hrv)", unit: "ms HRV",
                   status: lowHrv ? "high" : "normal", level: lowHrv ? .bad : .good,
                   accessibility: "Stress: heart rate variability \(hrv) milliseconds, your usual \(StageStory.usualHrvMs). "
                       + (lowHrv ? "Stress is high." : "Normal.")),
            Factor(id: "humidity", symbol: "drop.fill", word: "Humidity", value: "\(humidity)", unit: "%",
                   status: dry ? "dry" : "normal", level: dry ? .bad : .good,
                   accessibility: "Humidity \(humidity) percent, " + (dry ? "dry." : "normal.")),
            Factor(id: "air", symbol: "aqi.medium", word: "Air quality", value: "\(StageStory.airQuality)", unit: "AQI",
                   status: StageStory.airQualityLabel, level: StageStory.airQuality <= 50 ? .good : .bad,
                   accessibility: "Air quality \(StageStory.airQuality), \(StageStory.airQualityLabel)."),
            Factor(id: "pollen", symbol: "leaf.fill", word: "Pollen", value: StageStory.pollen.capitalized, unit: "",
                   status: StageStory.pollen == "low" ? "good" : StageStory.pollen,
                   level: StageStory.pollen == "low" ? .good : .bad,
                   accessibility: "Pollen \(StageStory.pollen)."),
            Factor(id: "temp", symbol: "thermometer.medium", word: "Temp", value: "\(temp)", unit: "°F",
                   status: "mild", level: .fine, accessibility: "High of \(temp) degrees Fahrenheit, mild."),
        ]
        // Stable sort: what's off your usual comes first.
        return list.filter { $0.level == .bad } + list.filter { $0.level != .bad }
    }

    // MARK: Last night detail

    /// The quarter-hour detail exists for night 13 only.
    var hasNightDetail: Bool { last == StageStory.lastNightIndex }
}

// MARK: - Launch arguments (debug builds: screenshots and recordings)

enum TodayTrendsLaunch {
    /// `-scrollTo bottom`: scroll the tab to its end after the entrance. `-scrollTo <id>` scrolls a
    /// section with that id to the top. (Anchoring the end marker at the top makes the scroll view
    /// stop at its last offset, with the content clear of the tab bar.)
    static func scrollForScreenshot(_ proxy: ScrollViewProxy, bottomID: String) {
        #if DEBUG
        guard let target = UserDefaults.standard.string(forKey: "scrollTo") else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            withAnimation(Twin.Motion.slide) {
                proxy.scrollTo(target == "bottom" ? bottomID : target, anchor: .top)
            }
        }
        #endif
    }

    /// `-trendsRange week|twoWeeks|all`: the Trends range at launch.
    static var trendsRange: TrendsRange? {
        #if DEBUG
        return UserDefaults.standard.string(forKey: "trendsRange").flatMap(TrendsRange.init(rawValue:))
        #else
        return nil
        #endif
    }

    /// `-trendsSelect 5`: Trends selects that night (0 = oldest … 13 = last night) after its entrance,
    /// as if it had been tapped.
    static var trendsSelect: Int? {
        #if DEBUG
        return UserDefaults.standard.string(forKey: "trendsSelect").flatMap(Int.init)
        #else
        return nil
        #endif
    }

    /// `-trendsTour 1`: a scripted walk through the Trends chart (screen recordings).
    static var trendsTour: Bool {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: "trendsTour")
        #else
        return false
        #endif
    }
}

extension View {
    /// Calls `action` when the calendar day changes (midnight, a time zone or clock change) or the app
    /// comes back to the front, so "last night" and the dates follow the clock while the app stays open.
    func onNewDay(_ action: @escaping () -> Void) -> some View {
        self
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged).receive(on: RunLoop.main)) { _ in action() }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in action() }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in action() }
    }
}
