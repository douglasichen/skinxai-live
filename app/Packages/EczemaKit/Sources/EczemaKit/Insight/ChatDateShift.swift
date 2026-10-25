import Foundation

/// Moves the dates in a saved conversation by whole days, so a conversation saved on one day replays on another
/// as if it had happened that day. The story's nights always count back from today (`StageStory`), so the same
/// conversation one day later talks about dates one day later: 2026-10-20 becomes 2026-10-21, "Tue Oct 20" becomes
/// "Wed Oct 21", "Oct 11–13" becomes "Oct 12–14", "the 19th" becomes "the 20th", "Saturday" becomes "Sunday".
///
/// Only what reads as a date moves: ISO dates, a month name with a day ("Oct 20", "October 20, 2026"), "the 19th"
/// near the day the text was written (not "the 3rd night"), and full weekday names. Everything else stays as it was.
enum ChatDateShift {
    /// `text` with every date moved by `days`. `reference` is when the text was written: it gives the year of
    /// "Oct 20" and the month of "the 19th".
    static func shift(_ text: String, by days: Int, reference: Date, calendar: Calendar) -> String {
        guard days != 0, !text.isEmpty else { return text }
        let cal = StageStory.gregorian(calendar)
        let ns = text as NSString
        var out = ""
        var cursor = 0
        for match in pattern.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let range = match.range
            out += ns.substring(with: NSRange(location: cursor, length: range.location - cursor))
            let found = Found(match: match, text: ns)
            out += replacement(found, days: days, reference: reference, cal: cal) ?? ns.substring(with: range)
            cursor = range.location + range.length
        }
        out += ns.substring(from: cursor)
        return out
    }

    // MARK: - Private

    private static let weekdays = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    private static let months = ["January", "February", "March", "April", "May", "June", "July", "August", "September",
                                 "October", "November", "December"]

    private static let pattern: NSRegularExpression = {
        let weekday = "Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday"
        let shortWeekday = "Mon|Tues|Tue|Wed|Thurs|Thur|Thu|Fri|Sat|Sun"
        let month = "January|February|March|April|May|June|July|August|September|October|November|December"
            + "|Jan|Feb|Mar|Apr|Jun|Jul|Aug|Sept|Sep|Oct|Nov|Dec"
        let ord = "st|nd|rd|th"
        let source = [
            // 2026-10-20
            #"(?<iso>\b\d{4}-\d{2}-\d{2}\b)"#,
            // [Tue ]Oct 20[th][–22][, 2026]
            #"(?<md>\b(?:(?<wd>\#(weekday)|\#(shortWeekday))(?<wsep>,?\s))?(?<mon>\#(month))(?<msep>\.?\s)(?<day>\d{1,2})(?<ord>\#(ord))?"#
                + #"(?:(?<sep>\s?[–-]\s?)(?<end>\d{1,2})(?<endord>\#(ord))?)?(?:(?<ysep>,\s)(?<year>\d{4}))?\b)"#,
            // the 19th (not "the 3rd night")
            #"(?<ordinal>\b(?<the>[Tt]he\s)(?<oday>\d{1,2})(?:\#(ord))\b(?!\s(?:night|nights|time|times|day|days|week|weeks|episode|episodes|question|place|one|of\s(?:those|these|them))\b))"#,
            // Saturday
            #"(?<weekday>\b(?:\#(weekday))\b)"#,
        ].joined(separator: "|")
        return try! NSRegularExpression(pattern: source)
    }()

    /// One match, read by group name.
    private struct Found {
        let match: NSTextCheckingResult
        let text: NSString

        subscript(_ name: String) -> String? {
            let range = match.range(withName: name)
            return range.location == NSNotFound ? nil : text.substring(with: range)
        }
    }

    private static func replacement(_ m: Found, days: Int, reference: Date, cal: Calendar) -> String? {
        if let iso = m["iso"] {
            guard let date = StageStory.date(iso: iso, calendar: cal) else { return nil }
            return StageStory.iso(moved(date, days, cal), calendar: cal)
        }
        if m["md"] != nil { return monthDay(m, days: days, reference: reference, cal: cal) }
        if m["ordinal"] != nil, let the = m["the"], let day = m["oday"].flatMap(Int.init) {
            guard let date = nearest(day: day, to: reference, cal: cal) else { return nil }
            let new = cal.component(.day, from: moved(date, days, cal))
            return "\(the)\(new)\(suffix(new))"
        }
        if let name = m["weekday"], let k = weekdays.firstIndex(of: name) {
            return weekdays[((k + days) % 7 + 7) % 7]
        }
        return nil
    }

    /// "Tue Oct 20", "October 11–13", "Oct 30, 2026": the date (and a range's end) moved, in the same style.
    private static func monthDay(_ m: Found, days: Int, reference: Date, cal: Calendar) -> String? {
        guard let token = m["mon"], let msep = m["msep"], let day = m["day"].flatMap(Int.init),
              let month = monthNumber(token) else { return nil }
        let short = !months.contains(token)          // "Oct", "Sept" (not "June")
        let year = m["year"].flatMap(Int.init) ?? inferredYear(month: month, day: day, reference: reference, cal: cal)
        guard let date = valid(year, month, day, cal) else { return nil }
        let new = moved(date, days, cal)
        let newMonth = cal.component(.month, from: new), newDay = cal.component(.day, from: new)

        var out = ""
        if let wd = m["wd"], let wsep = m["wsep"] {
            let name = weekdays[cal.component(.weekday, from: new) - 1]
            out += (wd.count > 5 ? name : String(name.prefix(3))) + wsep
        }
        out += (newMonth == month ? token : monthName(newMonth, short: short)) + msep
        out += "\(newDay)" + (m["ord"] != nil ? suffix(newDay) : "")
        if let sep = m["sep"], let endText = m["end"] {
            if let end = Int(endText), end > day, let endDate = valid(year, month, end, cal) {
                let newEnd = moved(endDate, days, cal)
                let endMonth = cal.component(.month, from: newEnd), endDay = cal.component(.day, from: newEnd)
                out += sep + (endMonth != newMonth ? monthName(endMonth, short: short) + " " : "")
                out += "\(endDay)" + (m["endord"] != nil ? suffix(endDay) : "")
            } else {
                out += sep + endText + (m["endord"] ?? "")      // "Oct 20 - 3 nights later": not a range
            }
        }
        if let ysep = m["ysep"], m["year"] != nil { out += ysep + "\(cal.component(.year, from: new))" }
        return out
    }

    private static func moved(_ date: Date, _ days: Int, _ cal: Calendar) -> Date {
        cal.date(byAdding: .day, value: days, to: date) ?? date
    }

    /// Noon on that day, if it exists ("Feb 30" doesn't).
    private static func valid(_ year: Int, _ month: Int, _ day: Int, _ cal: Calendar) -> Date? {
        guard (1...31).contains(day), let date = cal.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) else { return nil }
        let back = cal.dateComponents([.year, .month, .day], from: date)
        return back.year == year && back.month == month && back.day == day ? date : nil
    }

    /// The year that puts "Oct 20" closest to when the text was written.
    private static func inferredYear(month: Int, day: Int, reference: Date, cal: Calendar) -> Int {
        let year = cal.component(.year, from: reference)
        return [year, year - 1, year + 1].min { a, b in
            distance(valid(a, month, day, cal), reference) < distance(valid(b, month, day, cal), reference)
        } ?? year
    }

    /// "the 19th": that day in the month of `reference`, the month before or the month after, whichever is
    /// closest, if it is within three weeks (the story's two weeks of nights, and a little after).
    private static func nearest(day: Int, to reference: Date, cal: Calendar) -> Date? {
        let c = cal.dateComponents([.year, .month], from: reference)
        guard let year = c.year, let month = c.month else { return nil }
        let candidates = [-1, 0, 1].compactMap { offset -> Date? in
            var m = month + offset, y = year
            if m < 1 { m += 12; y -= 1 }
            if m > 12 { m -= 12; y += 1 }
            return valid(y, m, day, cal)
        }
        guard let best = candidates.min(by: { distance($0, reference) < distance($1, reference) }),
              distance(best, reference) <= 21 * 86_400 else { return nil }
        return best
    }

    private static func distance(_ date: Date?, _ reference: Date) -> TimeInterval {
        date.map { abs($0.timeIntervalSince(reference)) } ?? .infinity
    }

    private static func monthNumber(_ token: String) -> Int? {
        let key = token.prefix(3)
        return months.firstIndex { $0.hasPrefix(key) }.map { $0 + 1 }
    }

    private static func monthName(_ month: Int, short: Bool) -> String {
        let name = months[min(max(month - 1, 0), 11)]
        return short ? String(name.prefix(3)) : name
    }

    /// 1st, 2nd, 3rd, 4th … 11th, 12th, 13th … 21st, 22nd, 23rd … 31st.
    private static func suffix(_ day: Int) -> String {
        if (11...13).contains(day % 100) { return "th" }
        switch day % 10 {
        case 1: return "st"
        case 2: return "nd"
        case 3: return "rd"
        default: return "th"
        }
    }
}

extension ChatTranscript {
    /// The same conversation moved to the day of `now`: its start and every date in it (Claude's words, the tool
    /// calls' arguments, the saved tool results) move by the days in between. A conversation saved yesterday then
    /// replays with today's dates, the same ones Today and Trends show.
    public func moved(toDayOf now: Date, calendar: Calendar = .current) -> ChatTranscript {
        let cal = StageStory.gregorian(calendar)
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: startedAt), to: cal.startOfDay(for: now)).day ?? 0
        guard days != 0 else { return self }
        let reference = startedAt
        func move(_ text: String) -> String { ChatDateShift.shift(text, by: days, reference: reference, calendar: cal) }
        var copy = self
        copy.startedAt = cal.date(byAdding: .day, value: days, to: startedAt) ?? startedAt
        copy.messages = messages.map { message in
            var m = message
            m.content = move(m.content)
            m.toolCalls = m.toolCalls.map { ChatToolCall(id: $0.id, name: $0.name, arguments: move($0.arguments)) }
            return m
        }
        return copy
    }
}
