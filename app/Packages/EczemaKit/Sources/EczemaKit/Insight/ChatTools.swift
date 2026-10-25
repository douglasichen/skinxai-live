import Foundation

/// Claude's tools as the app sees them: the five data tools it runs with `StageStory`, the three display tools
/// it draws as cards, and `ask_user`, which waits for Douglas.
public enum ChatTools {
    public enum Kind: Sendable, Equatable {
        /// Runs locally; the result goes back as JSON.
        case data
        /// Drawn as a card; answered `{"shown": true}`.
        case display
        /// A question for Douglas; answered with his answer.
        case question
        /// Not a tool the app knows; answered with an error.
        case unknown
    }

    public static let timeline = "show_timeline"
    public static let product = "show_product"
    public static let conclusion = "show_conclusion"
    public static let question = "ask_user"

    public static func kind(of name: String) -> Kind {
        if StageStory.dataTools.contains(name) { return .data }
        if [timeline, product, conclusion].contains(name) { return .display }
        if name == question { return .question }
        return .unknown
    }

    /// The result of a display tool.
    public static let shownResult = #"{"shown":true}"#

    /// The result of `ask_user`: `{"answer": "<what Douglas said>"}`.
    public static func answerResult(_ answer: String) -> String { ChatWire.json(["answer": answer]) }

    /// The answer inside an `ask_user` result (for a replay).
    public static func answer(fromResult content: String) -> String? {
        (ChatWire.object(fromJSON: content)["answer"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The result for a tool the app doesn't know.
    public static func unknownResult(_ name: String) -> String { ChatWire.json(["error": "There is no tool called \(name)."]) }

    // MARK: - Rows of the tool card

    /// One row of the tool card: an icon tile and a human name ("Scratch history · 14 nights").
    public struct Row: Hashable, Sendable {
        public var icon: String
        public var title: String
    }

    /// What a row says while its tool runs.
    public static let reading = "Reading…"

    /// The row for a data tool call, from its arguments (known before the tool runs).
    public static func row(name: String, argumentsJSON: String) -> Row {
        let args = ChatWire.object(fromJSON: argumentsJSON)
        switch name {
        case "scratch_history":
            let n = StageStory.clampCount(args["nights"], max: StageStory.toolMaxNights, default: StageStory.nightCount)
            return Row(icon: "⌚", title: "Scratch history · \(count(n, "night"))")
        case "order_history":
            return Row(icon: "📦", title: "Amazon orders · \(count(StageStory.clampCount(args["days"], max: 120), "day"))")
        case "weather_history":
            let city = StageStory.location.split(separator: ",").first.map(String.init) ?? StageStory.location
            return Row(icon: "🌤\u{FE0F}", title: "Weather · \(city)")
        case "calendar_events":
            return Row(icon: "📅", title: "Calendar")
        case "sleep_history":
            return Row(icon: "🛏\u{FE0F}", title: "Sleep · Apple Health")
        default:
            let words = name.split(separator: "_").joined(separator: " ")
            return Row(icon: "🔎", title: words.prefix(1).uppercased() + words.dropFirst())
        }
    }

    /// One plain line about a data tool's result, computed from the result (chat.js `SUMMARY`, in the app's
    /// words): "Up 3 nights in a row · last night 41 min (usual 12)".
    public static func summary(name: String, resultJSON: String, calendar: Calendar = .current) -> String {
        let r = ChatWire.object(fromJSON: resultJSON)
        if r["error"] != nil { return "Couldn't read this data" }
        switch name {
        case "scratch_history":
            let minutes = list(r["nights"]).compactMap { int($0["scratch_minutes"]) }
            guard let last = minutes.last else { return "No nights yet" }
            let usual = int(r["usual_minutes_per_night"]) ?? StageStory.usual
            let streak = minutes.reversed().prefix { Double($0) > StageStory.flareFactor * Double(usual) }.count
            return streak >= 2 ? "Up \(streak) nights in a row · last night \(last) min (usual \(usual))"
                               : "Last night \(last) min · usual \(usual)"
        case "order_history":
            let orders = list(r["orders"])
            guard !orders.isEmpty else { return "No orders in that time" }
            let fresh = orders.filter { ($0["category"] as? String) == "personal care" && bool($0["bought_before"]) == false }.count
            return "\(count(orders.count, "order")) · \(count(fresh, "personal-care item")) you never bought before"
        case "weather_history":
            let humidity = list(r["days"]).compactMap { int($0["humidity_percent"]) }
            guard let last = humidity.last, let lo = humidity.min(), let hi = humidity.max() else { return "No weather in that time" }
            let usual = humidity.filter { $0 >= StageStory.dryBelowPercent }
            if last < StageStory.dryBelowPercent, let ulo = usual.min(), let uhi = usual.max() {
                return "Humidity \(range(ulo, uhi))% most days · \(last)% last night"
            }
            return "Humidity \(range(lo, hi))% · \(last)% last night"
        case "calendar_events":
            let events = list(r["events"])
            guard let event = events.first(where: { $0["note"] is String }) ?? events.first,
                  let title = event["title"] as? String else { return "Nothing on your calendar" }
            let name = title.replacingOccurrences(of: #"\s*\(.*?\)"#, with: "", options: .regularExpression)
            let when = (event["date"] as? String).map { span($0, calendar: calendar) } ?? ""
            let note = (event["note"] as? String).map { " · \($0)" } ?? ""
            return "\(name)\(when.isEmpty ? "" : " \(when)")\(note)"
        case "sleep_history":
            guard let last = list(r["nights"]).last, let hours = double(last["hours_asleep"]) else { return "No nights yet" }
            let wakes = int(last["wake_ups"]) ?? 0
            return "\(decimal(hours)) h last night · woke up \(wakes)×"
        default:
            return "Done"
        }
    }

    // MARK: - Helpers

    /// "1 night", "14 nights".
    static func count(_ n: Int, _ word: String) -> String { "\(n) \(word)\(n == 1 ? "" : "s")" }

    static func range(_ lo: Int, _ hi: Int) -> String { lo == hi ? "\(lo)" : "\(lo)–\(hi)" }

    /// "5.1", "6".
    static func decimal(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }

    /// "2026-10-11 to 2026-10-13" → "Oct 11–13"; "2026-10-16" → "Oct 16".
    static func span(_ text: String, calendar: Calendar) -> String {
        let parts = text.components(separatedBy: " to ")
        guard let start = StageStory.date(iso: parts[0], calendar: calendar) else { return text }
        if parts.count > 1, let end = StageStory.date(iso: parts[1], calendar: calendar) {
            return StageStory.monthDayRange(start, end, calendar: calendar)
        }
        return StageStory.monthDay(start, calendar: calendar)
    }

    static func list(_ value: Any?) -> [[String: Any]] { value as? [[String: Any]] ?? [] }

    static func int(_ value: Any?) -> Int? {
        switch value {
        case let v as Int: return v
        case let v as Double: return Int(v.rounded())
        case let v as NSNumber: return v.intValue
        case let v as String: return Int(v)
        default: return nil
        }
    }

    static func double(_ value: Any?) -> Double? {
        switch value {
        case let v as Double: return v
        case let v as Int: return Double(v)
        case let v as NSNumber: return v.doubleValue
        case let v as String: return Double(v)
        default: return nil
        }
    }

    static func bool(_ value: Any?) -> Bool? {
        switch value {
        case let v as Bool: return v
        case let v as NSNumber: return v.boolValue
        default: return nil
        }
    }
}
