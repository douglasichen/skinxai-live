import Foundation
import Testing
@testable import EczemaKit

@Suite struct StageStoryTests {
    let cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "America/Los_Angeles")!; return c }()
    /// Saturday, October 24, 2026, 3 PM in Berkeley (the first demo day).
    var now: Date { cal.date(from: DateComponents(year: 2026, month: 10, day: 24, hour: 15))! }

    // MARK: Numbers

    @Test func numbers() {
        #expect(StageStory.nights == [9, 14, 11, 8, 15, 12, 10, 16, 13, 11, 17, 24, 29, 41])
        #expect(StageStory.episodes == [8, 11, 9, 7, 12, 10, 8, 12, 11, 9, 13, 16, 19, 23])
        #expect(StageStory.usual == 12)
        #expect(StageStory.nightCount == 14 && StageStory.lastNightIndex == 13)
        for count in [StageStory.episodes.count, StageStory.sleepHours.count, StageStory.wakeUps.count,
                      StageStory.humidity.count, StageStory.highF.count, StageStory.hrvMs.count] {
            #expect(count == 14)
        }
        #expect(StageStory.sleepHours == [7.4, 7.1, 6.2, 6.0, 6.4, 7.5, 7.3, 7.2, 7.6, 7.0, 6.9, 6.4, 5.6, 5.1])
        #expect(StageStory.wakeUps == [0, 1, 1, 1, 0, 0, 1, 0, 0, 1, 1, 1, 2, 2])
        #expect(StageStory.humidity == [52, 49, 55, 51, 47, 50, 53, 48, 51, 50, 49, 47, 46, 29])
        #expect(StageStory.highF == [64, 66, 63, 61, 65, 67, 66, 64, 63, 65, 66, 64, 63, 68])
        // HRV: usual 52, last night 38, falling over the last three nights.
        #expect(StageStory.usualHrvMs == 52 && StageStory.LastNight.hrvMs == 38)
        #expect(StageStory.hrvMs[10] > StageStory.hrvMs[11] && StageStory.hrvMs[11] > StageStory.hrvMs[12] && StageStory.hrvMs[12] > 38)
        // Dry air only on night 13; body wash from night 10; midterms nights 1–3.
        #expect(StageStory.humidity.indices.filter { StageStory.humidity[$0] < StageStory.dryBelowPercent } == [StageStory.dryAirNight])
        #expect(StageStory.dryAirNight == 13 && StageStory.bodyWashNight == 10 && StageStory.examNights == 1...3)
        #expect(StageStory.location == "Berkeley, CA" && StageStory.airQuality == 41 && StageStory.pollen == "low")
    }

    @Test func lastNight() {
        typealias L = StageStory.LastNight
        #expect(L.minutes == 41 && L.episodes == 23 && L.intense == 7 && L.wakeUps == 2)
        #expect(L.sleepHours == 5.1 && L.humidity == 29 && L.highF == 68)
        #expect(L.worst == "2–4 AM" && L.asleep == "11:04 PM" && L.awake == "6:52 AM")
        #expect(L.minutesPerHour == [1, 3, 6, 10, 11, 6, 3, 1])
        #expect(L.minutesPerHour.reduce(0, +) == L.minutes)
        #expect(L.hourLabels.count == L.minutesPerHour.count)
        // The worst stretch is 2–4 AM: the two biggest hours.
        let worst = L.minutesPerHour.indices.sorted { L.minutesPerHour[$0] > L.minutesPerHour[$1] }.prefix(2).sorted()
        #expect(worst.map { L.hourLabels[$0] } == ["2A", "3A"])
        // Fell asleep 11:04 PM on Friday, woke up 6:52 AM on Saturday (today).
        let asleep = cal.dateComponents([.month, .day, .hour, .minute], from: L.asleepDate(now: now, calendar: cal))
        let awake = cal.dateComponents([.month, .day, .hour, .minute], from: L.awakeDate(now: now, calendar: cal))
        #expect([asleep.month, asleep.day, asleep.hour, asleep.minute] == [10, 23, 23, 4])
        #expect([awake.month, awake.day, awake.hour, awake.minute] == [10, 24, 6, 52])
    }

    @Test func quarterHourBuckets() {
        let q = StageStory.LastNight.quarterHours
        #expect(q.count == 32)
        for (hour, minutes) in StageStory.LastNight.minutesPerHour.enumerated() {
            #expect(abs(q[hour * 4 ..< hour * 4 + 4].reduce(0, +) - Double(minutes)) < 1e-9)
        }
        #expect(abs(q.reduce(0, +) - 41) < 1e-9)
        #expect(q.allSatisfy { $0 >= 0 })
        // The prototype's drawNight() with rng(7), bit for bit (values printed by node).
        #expect(q[0] == 0.08870849282281994)
        #expect(q[5] == 2.109974264703858)
        #expect(q[19] == 3.713571258147694)
        #expect(q[30] == 0.5008481915636267)
        #expect(q.indices.filter { q[$0] == 0 } == [4, 7, 8, 22, 26, 28, 31])
        #expect(q.filter { $0 > 2.2 }.count == 8)
        // Deterministic, and any seed keeps every hour's total.
        #expect(StageStory.quarterHourSplit(StageStory.LastNight.minutesPerHour, seed: 7) == q)
        for seed: UInt32 in [1, 2, 99, 12_345] {
            let other = StageStory.quarterHourSplit(StageStory.LastNight.minutesPerHour, seed: seed)
            #expect(abs(other.reduce(0, +) - 41) < 1e-9)
        }
    }

    @Test func derivedNumbers() {
        #expect(StageStory.nights.indices.filter(StageStory.isFlare) == [11, 12, 13])
        #expect(!StageStory.isFlare(-1) && !StageStory.isFlare(14))
        #expect(StageStory.flareStreak == 3)
        #expect(String(format: "%.1f", StageStory.ratio(StageStory.lastNightIndex)) == "3.4")
        #expect(Int(StageStory.weekAverage.rounded()) == 22)
        #expect(abs(StageStory.weekAverage - 151.0 / 7) < 1e-12)
        #expect(abs(StageStory.previousWeekAverage - 79.0 / 7) < 1e-12)
        #expect(StageStory.weekChangePercent == 91)
    }

    // MARK: Dates

    @Test func datesAreRelativeToNow() {
        let iso = { (night: Int, at: Date, cal: Calendar) in StageStory.iso(StageStory.nightDate(night, now: at, calendar: cal), calendar: cal) }
        #expect(iso(13, now, cal) == "2026-10-23")
        #expect(iso(StageStory.bodyWashNight, now, cal) == "2026-10-20")
        #expect(iso(0, now, cal) == "2026-10-10")
        #expect(StageStory.nightDates(now: now, calendar: cal).map { StageStory.iso($0, calendar: cal) }.first == "2026-10-10")
        #expect(cal.component(.hour, from: StageStory.nightDate(5, now: now, calendar: cal)) == 12)
        // Just after midnight it is already the next day: last night is the night that just began.
        let afterMidnight = cal.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 0, minute: 30))!
        #expect(iso(13, afterMidnight, cal) == "2026-10-24")
        // The next demo day moves the whole story by one day.
        let sunday = cal.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 11))!
        #expect(iso(13, sunday, cal) == "2026-10-24" && iso(0, sunday, cal) == "2026-10-11")
        // The phone's time zone decides the day: 3 PM in Berkeley is already Sunday morning in Tokyo.
        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        #expect(iso(13, now, tokyo) == "2026-10-24")
        // A phone on another calendar system still gets Gregorian dates.
        var japanese = Calendar(identifier: .japanese)
        japanese.timeZone = cal.timeZone
        #expect(iso(13, now, japanese) == "2026-10-23")
        #expect(StageStory.todayLong(now: now, calendar: japanese) == "Saturday, October 24, 2026")
    }

    @Test func textHelpers() throws {
        let night = { StageStory.nightDate($0, now: now, calendar: cal) }
        #expect(StageStory.weekday(night(10), calendar: cal) == "Tuesday")
        #expect(StageStory.weekday(night(10), short: true, calendar: cal) == "Tue")
        #expect(StageStory.monthDay(night(13), calendar: cal) == "Oct 23")
        #expect(StageStory.month(night(0), calendar: cal) == "Oct")
        #expect(StageStory.month(night(0), short: false, calendar: cal) == "October")
        #expect(StageStory.monthDayRange(night(1), night(3), calendar: cal) == "Oct 11–13")
        let sep30 = try #require(StageStory.date(iso: "2026-09-30", calendar: cal))
        #expect(StageStory.monthDayRange(sep30, night(0), calendar: cal) == "Sep 30 – Oct 10")
        let today = StageStory.todayLong(now: now, calendar: cal)
        #expect(today == "Saturday, October 24, 2026")
        // The chat server only accepts this shape.
        let shape = try Regex(#"^[A-Za-z]+, [A-Za-z]+ \d{1,2}, \d{4}$"#)
        #expect(today.wholeMatch(of: shape) != nil)
        // ISO dates back to nights (Claude's marker_date).
        #expect(StageStory.night(iso: "2026-10-20", now: now, calendar: cal) == 10)
        #expect(StageStory.night(iso: "2026-10-11 to 2026-10-13", now: now, calendar: cal) == 1)
        #expect(StageStory.night(iso: "2026-10-24", now: now, calendar: cal) == nil)
        #expect(StageStory.night(iso: "2026-10-09", now: now, calendar: cal) == nil)
        #expect(StageStory.night(on: night(7), now: now, calendar: cal) == 7)
        #expect(StageStory.date(iso: "2026-02-31", calendar: cal) == nil)
        #expect(StageStory.date(iso: "last Tuesday", calendar: cal) == nil)
        #expect(StageStory.date(iso: "", calendar: cal) == nil)
    }

    // MARK: Orders and calendar

    @Test func orders() throws {
        let orders = StageStory.orders(now: now, calendar: cal)
        #expect(orders.count == 30)
        #expect(orders.map(\.date) == orders.map(\.date).sorted())
        #expect(orders.allSatisfy { StageHistory.nightIDs.contains($0.night) })
        #expect(orders.allSatisfy { cal.isDate($0.date, inSameDayAs: StageStory.nightDate($0.night, now: now, calendar: cal)) })
        // The body wash: new, ordered the day before the first night with it.
        let wash = try #require(orders.first { $0.item == StageStory.bodyWashItem })
        #expect(wash == StageStory.bodyWashOrder(now: now, calendar: cal))
        #expect(wash.item == "Brightwell Sensitive Fragrance-Free Body Wash, 18 fl oz" && !wash.boughtBefore)
        #expect(wash.ingredients == StageStory.bodyWashIngredients)
        #expect(StageStory.iso(wash.date, calendar: cal) == "2026-10-19")
        // New personal-care items: sunscreen, the travel shampoo, deodorant, lotion, the body wash.
        let fresh = orders.filter { $0.category == "personal care" && !$0.boughtBefore }
        #expect(fresh.map(\.item) == [StageStory.Product.coastlineSunscreen.item, StageStory.Product.summitShampoo.item,
                                       StageStory.Product.alderPineDeodorant.item, StageStory.Product.harborOatLotion.item,
                                       StageStory.Product.brightwellLotion.item, StageStory.bodyWashItem])
        // Two new things on Oct 5.
        let oct5 = orders.filter { StageStory.iso($0.date, calendar: cal) == "2026-10-05" }
        #expect(oct5.map(\.item) == [StageStory.Product.northfieldSweater.item, StageStory.Product.freshMeadowDetergent.item])
        #expect(oct5.map(\.category) == ["clothing", "household"] && oct5.allSatisfy { !$0.boughtBefore })
        #expect(oct5[0].material == "100% lambswool" && oct5[0].ingredients == nil)
        #expect(oct5[1].ingredients?.contains("Fragrance") == true && oct5[1].material == nil)
        // Every skin-contact product lists its ingredients or its material; the rest list neither.
        for o in orders where o.category == "clothing" { #expect(o.material != nil && o.ingredients == nil, "\(o.item)") }
        for o in orders where ["grocery", "school", "electronics"].contains(o.category) { #expect(!o.skinContact, "\(o.item)") }
        #expect(orders.filter(\.skinContact).count == 20)
        // His usual detergent, reordered every month (fictional brand, since it lists ingredients).
        #expect(orders.filter { $0.item.hasPrefix("Everclean Free & Clear") }.map { StageStory.iso($0.date, calendar: cal) }
                == ["2026-08-11", "2026-09-10", "2026-10-13"])
        #expect(!orders.contains { ["Tide", "CeraVe", "Method"].contains(where: $0.item.hasPrefix) })
        // The same in the tool's JSON, with the material.
        let tool = StageStory.runTool(name: "order_history", arguments: ["days": 120], now: now, calendar: cal)
        let list = try #require(tool["orders"] as? [[String: Any]])
        #expect(list.count == 30)
        let sweater = try #require(list.first { $0["item"] as? String == StageStory.Product.northfieldSweater.item })
        #expect(sweater["material"] as? String == "100% lambswool" && sweater["ingredients"] == nil)
        let washJSON = try #require(list.first { $0["item"] as? String == StageStory.bodyWashItem })
        #expect(washJSON["ingredients"] as? [String] == StageStory.bodyWashIngredients && washJSON["material"] == nil)
    }

    @Test func calendarEvents() throws {
        let events = StageStory.calendarEvents(now: now, calendar: cal)
        #expect(events.map(\.title) == ["Trip to Seattle (family)", "Exam week (CS 61B, Math 54 quizzes)",
                                        "Midterm exams (CS 61B, Math 54)", "Dentist", "Team project deadline", "CalHacks 13.0 (hackathon)"])
        let span = { (e: StageStory.Event) in [e.date, e.endDate ?? e.date].map { StageStory.iso($0, calendar: cal) } }
        #expect(span(events[0]) == ["2026-08-24", "2026-08-27"])
        #expect(span(events[1]) == ["2026-09-14", "2026-09-17"])
        #expect(span(events[2]) == ["2026-10-11", "2026-10-13"])
        #expect(events[2].note == "stressful week")
        #expect(StageStory.iso(events[5].date, calendar: cal) == "2026-10-25")
        // The tool: every event in the last N days (and the ones ahead).
        func titles(_ days: Int) throws -> [String] {
            let r = StageStory.runTool(name: "calendar_events", arguments: ["days": days], now: now, calendar: cal)
            return try #require(r["events"] as? [[String: Any]]).compactMap { $0["title"] as? String }
        }
        #expect(try titles(120).count == 6)
        #expect(try titles(74).count == 6)
        #expect(try titles(45) == Array(events.dropFirst().map(\.title)))
        #expect(try titles(14) == Array(events.suffix(4).map(\.title)))
        #expect(try titles(1) == ["CalHacks 13.0 (hackathon)"])
    }

    // MARK: Tools

    @Test func toolKeysAndShapes() throws {
        func run(_ name: String, _ args: [String: Any] = [:]) -> [String: Any] {
            StageStory.runTool(name: name, arguments: args, now: now, calendar: cal)
        }
        let scratch = run("scratch_history", ["nights": 14])
        #expect(Set(scratch.keys) == ["usual_minutes_per_night", "measured_by", "nights", "last_night_worst_hours"])
        #expect(scratch["usual_minutes_per_night"] as? Int == 12)
        #expect(scratch["measured_by"] as? String == "Apple Watch, every night")
        #expect(scratch["last_night_worst_hours"] as? String == "2–4 AM")
        let nights = try #require(scratch["nights"] as? [[String: Any]])
        #expect(nights.count == 14)
        #expect(nights.allSatisfy { Set($0.keys) == ["night_of", "weekday", "scratch_minutes", "scratch_episodes"] })
        #expect(nights.compactMap { $0["scratch_minutes"] as? Int } == StageStory.nights)
        #expect(nights.compactMap { $0["scratch_episodes"] as? Int } == StageStory.episodes)
        #expect(nights.last?["night_of"] as? String == "2026-10-23" && nights.last?["weekday"] as? String == "Friday")

        let orders = run("order_history", ["days": 120])
        #expect(Set(orders.keys) == ["source", "orders"])
        #expect(orders["source"] as? String == "Amazon order history")
        let list = try #require(orders["orders"] as? [[String: Any]])
        #expect(list.count == 30)
        for order in list {
            let keys = Set(order.keys)
            #expect(keys.isSuperset(of: ["date", "item", "category", "bought_before"]))
            #expect(keys.isSubset(of: ["date", "item", "category", "bought_before", "note", "ingredients", "material"]))
            #expect(!(keys.contains("ingredients") && keys.contains("material")))
            #expect(order["bought_before"] is Bool)
        }

        let weather = run("weather_history", ["days": 14])
        #expect(Set(weather.keys) == ["location", "days"])
        #expect(weather["location"] as? String == "Berkeley, CA")
        let days = try #require(weather["days"] as? [[String: Any]])
        #expect(days.count == 14)
        #expect(days.allSatisfy { Set($0.keys) == ["date", "humidity_percent", "high_f"] })
        #expect(days.compactMap { $0["humidity_percent"] as? Int } == StageStory.humidity)
        #expect(days.compactMap { $0["high_f"] as? Int } == StageStory.highF)

        let calendar = run("calendar_events", ["days": 30])
        #expect(Set(calendar.keys) == ["events"])
        let events = try #require(calendar["events"] as? [[String: Any]])
        #expect(events.count == 4)
        #expect(events.allSatisfy { Set($0.keys).isSuperset(of: ["date", "title"]) && Set($0.keys).isSubset(of: ["date", "title", "note"]) })
        #expect(events.first?["date"] as? String == "2026-10-11 to 2026-10-13")
        let all = try #require(run("calendar_events")["events"] as? [[String: Any]])
        #expect(all.first?["date"] as? String == "2026-08-24 to 2026-08-27")

        let sleep = run("sleep_history", ["nights": 14])
        #expect(Set(sleep.keys) == ["source", "usual_hrv_ms", "nights"])
        #expect(sleep["source"] as? String == "Apple Health")
        let sleepNights = try #require(sleep["nights"] as? [[String: Any]])
        #expect(sleepNights.allSatisfy { Set($0.keys) == ["night_of", "hours_asleep", "wake_ups", "hrv_ms"] })
        #expect(sleepNights.compactMap { $0["hours_asleep"] as? Double } == StageStory.sleepHours)
        #expect(sleepNights.compactMap { $0["wake_ups"] as? Int } == StageStory.wakeUps)
        #expect(sleepNights.compactMap { $0["hrv_ms"] as? Int } == StageStory.hrvMs)

        #expect(StageStory.dataTools == ["scratch_history", "order_history", "weather_history", "calendar_events", "sleep_history"])
        let unknown = run("show_timeline")
        #expect(unknown.count == 1 && unknown["error"] as? String == "There is no tool called show_timeline.")
    }

    /// The tool messages, byte for byte. The fixtures were recorded from this code for the MI scenario
    /// (SCENARIO-MI.md); since then the app's tools are the source of truth, not the web page's story.js.
    @Test func toolJSONIsPinned() {
        func json(_ name: String, _ args: String?) -> String {
            StageStory.runToolJSON(name: name, argumentsJSON: args, now: now, calendar: cal)
        }
        #expect(json("scratch_history", "{}") == Fixture.scratch14)
        #expect(json("scratch_history", #"{"nights": 3}"#) == Fixture.scratch3)
        #expect(json("order_history", "{}") == Fixture.orders120)
        #expect(json("order_history", #"{"days":30}"#) == Fixture.orders30)
        #expect(json("weather_history", #"{"days":14}"#) == Fixture.weather14)
        #expect(json("weather_history", #"{"days":2}"#) == Fixture.weather2)
        #expect(json("calendar_events", #"{"days":30}"#) == Fixture.calendar)
        #expect(json("sleep_history", #"{"nights":14}"#) == Fixture.sleep14)
        #expect(json("sleep_history", #"{"nights":4}"#) == Fixture.sleep4)
        // Further back, from the longer history: up to all 74 nights.
        #expect(json("scratch_history", #"{"nights":30}"#) == Fixture.scratch30)
        #expect(json("weather_history", #"{"days":30}"#) == Fixture.weather30)
        #expect(json("sleep_history", #"{"nights":30}"#) == Fixture.sleep30)
        #expect(json("scratch_history", #"{"nights":74}"#) == Fixture.scratch74)
        #expect(json("scratch_history", #"{"nights":90}"#) == Fixture.scratch74)
        #expect(json("weather_history", #"{"days":74}"#) == Fixture.weather74)
        #expect(json("sleep_history", #"{"nights":74}"#) == Fixture.sleep74)
        #expect(json("calendar_events", "{}") == Fixture.calendarAll)
        // Missing or malformed arguments mean the default (14), like story.js.
        #expect(json("scratch_history", nil) == Fixture.scratch14)
        #expect(json("scratch_history", "{nights: 3") == Fixture.scratch14)
        #expect(json("scratch_history", "[3]") == Fixture.scratch14)
        #expect(json("nope", "{}") == #"{"error":"There is no tool called nope."}"#)
    }

    @Test func argumentsAreClamped() {
        let cases: [(Any?, Int)] = [(nil, 14), (7, 7), ("3", 3), (" 5 ", 5), (0, 14), (20, 20), (30, 30), (74, 74), (99, 74), (-2, 1),
                                    (2.5, 3), (2.4, 2), ("abc", 14), ("", 14), (NSNull(), 14), (true, 1), (Double.infinity, 74)]
        for (value, expected) in cases {
            let args: [String: Any] = value.map { ["nights": $0] } ?? [:]
            let result = StageStory.runTool(name: "scratch_history", arguments: args, now: now, calendar: cal)
            #expect((result["nights"] as? [Any])?.count == expected, "nights: \(String(describing: value))")
        }
        // Numbers from a parsed tool call (NSNumber) work the same.
        #expect(StageStory.clampCount(NSNumber(value: 6), max: 14) == 6)
        #expect(StageStory.clampCount(NSNumber(value: 6.5), max: 14) == 7)
        #expect(StageStory.clampCount(500, max: 120) == 120)
        #expect(StageStory.clampCount(nil, max: 30, default: 14) == 14)
    }

    /// Older nights come from `StageHistory`; the last 14 stay the story's.
    @Test func thirtyNightsBack() throws {
        let scratch = StageStory.runTool(name: "scratch_history", arguments: ["nights": 30], now: now, calendar: cal)
        let nights = try #require(scratch["nights"] as? [[String: Any]])
        #expect(nights.count == 30)
        #expect(nights.first?["night_of"] as? String == "2026-09-24")
        #expect(nights.compactMap { $0["scratch_minutes"] as? Int } == (-16...13).map { StageHistory.night($0).minutes })
        #expect(Array(nights.suffix(14)).compactMap { $0["scratch_minutes"] as? Int } == StageStory.nights)
        // The third flare, Oct 6–9.
        let flare = nights.filter { ["2026-10-06", "2026-10-07", "2026-10-08", "2026-10-09"].contains($0["night_of"] as? String ?? "") }
        #expect(flare.compactMap { $0["scratch_minutes"] as? Int } == [19, 27, 31, 22])
        let sleep = StageStory.runTool(name: "sleep_history", arguments: ["nights": 30], now: now, calendar: cal)
        #expect((sleep["nights"] as? [[String: Any]])?.compactMap { $0["wake_ups"] as? Int } == (-16...13).map { StageHistory.night($0).wakeUps })
        let weather = StageStory.runTool(name: "weather_history", arguments: ["days": 30], now: now, calendar: cal)
        #expect((weather["days"] as? [[String: Any]])?.compactMap { $0["humidity_percent"] as? Int } == (-16...13).map { StageHistory.night($0).humidity })
    }

    @Test func jsonText() {
        #expect(StageJSON.string("a\"b\\c\nd\t\u{01}–°").text == "\"a\\\"b\\\\c\\nd\\t\\u0001–°\"")
        #expect(StageJSON.double(6.0).text == "6")
        #expect(StageJSON.double(7.4).text == "7.4")
        #expect(StageJSON.object([("b", .int(1)), ("a", .array([.bool(true), .bool(false)]))]).text == #"{"b":1,"a":[true,false]}"#)
    }
}

/// The tools at Saturday, October 24, 2026, 3 PM, TZ=America/Los_Angeles (recorded from this code for the MI
/// scenario).
private enum Fixture {
    static let scratch14 = #"{"usual_minutes_per_night":12,"measured_by":"Apple Watch, every night","nights":[{"night_of":"2026-10-10","weekday":"Saturday","scratch_minutes":9,"scratch_episodes":8},{"night_of":"2026-10-11","weekday":"Sunday","scratch_minutes":14,"scratch_episodes":11},{"night_of":"2026-10-12","weekday":"Monday","scratch_minutes":11,"scratch_episodes":9},{"night_of":"2026-10-13","weekday":"Tuesday","scratch_minutes":8,"scratch_episodes":7},{"night_of":"2026-10-14","weekday":"Wednesday","scratch_minutes":15,"scratch_episodes":12},{"night_of":"2026-10-15","weekday":"Thursday","scratch_minutes":12,"scratch_episodes":10},{"night_of":"2026-10-16","weekday":"Friday","scratch_minutes":10,"scratch_episodes":8},{"night_of":"2026-10-17","weekday":"Saturday","scratch_minutes":16,"scratch_episodes":12},{"night_of":"2026-10-18","weekday":"Sunday","scratch_minutes":13,"scratch_episodes":11},{"night_of":"2026-10-19","weekday":"Monday","scratch_minutes":11,"scratch_episodes":9},{"night_of":"2026-10-20","weekday":"Tuesday","scratch_minutes":17,"scratch_episodes":13},{"night_of":"2026-10-21","weekday":"Wednesday","scratch_minutes":24,"scratch_episodes":16},{"night_of":"2026-10-22","weekday":"Thursday","scratch_minutes":29,"scratch_episodes":19},{"night_of":"2026-10-23","weekday":"Friday","scratch_minutes":41,"scratch_episodes":23}],"last_night_worst_hours":"2–4 AM"}"#
    static let scratch3 = #"{"usual_minutes_per_night":12,"measured_by":"Apple Watch, every night","nights":[{"night_of":"2026-10-21","weekday":"Wednesday","scratch_minutes":24,"scratch_episodes":16},{"night_of":"2026-10-22","weekday":"Thursday","scratch_minutes":29,"scratch_episodes":19},{"night_of":"2026-10-23","weekday":"Friday","scratch_minutes":41,"scratch_episodes":23}],"last_night_worst_hours":"2–4 AM"}"#
    static let scratch30 = #"{"usual_minutes_per_night":12,"measured_by":"Apple Watch, every night","nights":[{"night_of":"2026-09-24","weekday":"Thursday","scratch_minutes":10,"scratch_episodes":8},{"night_of":"2026-09-25","weekday":"Friday","scratch_minutes":9,"scratch_episodes":8},{"night_of":"2026-09-26","weekday":"Saturday","scratch_minutes":12,"scratch_episodes":11},{"night_of":"2026-09-27","weekday":"Sunday","scratch_minutes":10,"scratch_episodes":8},{"night_of":"2026-09-28","weekday":"Monday","scratch_minutes":16,"scratch_episodes":12},{"night_of":"2026-09-29","weekday":"Tuesday","scratch_minutes":12,"scratch_episodes":10},{"night_of":"2026-09-30","weekday":"Wednesday","scratch_minutes":10,"scratch_episodes":9},{"night_of":"2026-10-01","weekday":"Thursday","scratch_minutes":13,"scratch_episodes":10},{"night_of":"2026-10-02","weekday":"Friday","scratch_minutes":11,"scratch_episodes":10},{"night_of":"2026-10-03","weekday":"Saturday","scratch_minutes":11,"scratch_episodes":9},{"night_of":"2026-10-04","weekday":"Sunday","scratch_minutes":14,"scratch_episodes":11},{"night_of":"2026-10-05","weekday":"Monday","scratch_minutes":10,"scratch_episodes":7},{"night_of":"2026-10-06","weekday":"Tuesday","scratch_minutes":19,"scratch_episodes":14},{"night_of":"2026-10-07","weekday":"Wednesday","scratch_minutes":27,"scratch_episodes":18},{"night_of":"2026-10-08","weekday":"Thursday","scratch_minutes":31,"scratch_episodes":20},{"night_of":"2026-10-09","weekday":"Friday","scratch_minutes":22,"scratch_episodes":15},{"night_of":"2026-10-10","weekday":"Saturday","scratch_minutes":9,"scratch_episodes":8},{"night_of":"2026-10-11","weekday":"Sunday","scratch_minutes":14,"scratch_episodes":11},{"night_of":"2026-10-12","weekday":"Monday","scratch_minutes":11,"scratch_episodes":9},{"night_of":"2026-10-13","weekday":"Tuesday","scratch_minutes":8,"scratch_episodes":7},{"night_of":"2026-10-14","weekday":"Wednesday","scratch_minutes":15,"scratch_episodes":12},{"night_of":"2026-10-15","weekday":"Thursday","scratch_minutes":12,"scratch_episodes":10},{"night_of":"2026-10-16","weekday":"Friday","scratch_minutes":10,"scratch_episodes":8},{"night_of":"2026-10-17","weekday":"Saturday","scratch_minutes":16,"scratch_episodes":12},{"night_of":"2026-10-18","weekday":"Sunday","scratch_minutes":13,"scratch_episodes":11},{"night_of":"2026-10-19","weekday":"Monday","scratch_minutes":11,"scratch_episodes":9},{"night_of":"2026-10-20","weekday":"Tuesday","scratch_minutes":17,"scratch_episodes":13},{"night_of":"2026-10-21","weekday":"Wednesday","scratch_minutes":24,"scratch_episodes":16},{"night_of":"2026-10-22","weekday":"Thursday","scratch_minutes":29,"scratch_episodes":19},{"night_of":"2026-10-23","weekday":"Friday","scratch_minutes":41,"scratch_episodes":23}],"last_night_worst_hours":"2–4 AM"}"#
    static let scratch74 = #"{"usual_minutes_per_night":12,"measured_by":"Apple Watch, every night","nights":[{"night_of":"2026-08-11","weekday":"Tuesday","scratch_minutes":14,"scratch_episodes":12},{"night_of":"2026-08-12","weekday":"Wednesday","scratch_minutes":12,"scratch_episodes":9},{"night_of":"2026-08-13","weekday":"Thursday","scratch_minutes":15,"scratch_episodes":11},{"night_of":"2026-08-14","weekday":"Friday","scratch_minutes":10,"scratch_episodes":9},{"night_of":"2026-08-15","weekday":"Saturday","scratch_minutes":14,"scratch_episodes":11},{"night_of":"2026-08-16","weekday":"Sunday","scratch_minutes":14,"scratch_episodes":12},{"night_of":"2026-08-17","weekday":"Monday","scratch_minutes":12,"scratch_episodes":10},{"night_of":"2026-08-18","weekday":"Tuesday","scratch_minutes":15,"scratch_episodes":12},{"night_of":"2026-08-19","weekday":"Wednesday","scratch_minutes":12,"scratch_episodes":10},{"night_of":"2026-08-20","weekday":"Thursday","scratch_minutes":10,"scratch_episodes":8},{"night_of":"2026-08-21","weekday":"Friday","scratch_minutes":9,"scratch_episodes":7},{"night_of":"2026-08-22","weekday":"Saturday","scratch_minutes":14,"scratch_episodes":11},{"night_of":"2026-08-23","weekday":"Sunday","scratch_minutes":12,"scratch_episodes":11},{"night_of":"2026-08-24","weekday":"Monday","scratch_minutes":10,"scratch_episodes":7},{"night_of":"2026-08-25","weekday":"Tuesday","scratch_minutes":18,"scratch_episodes":13},{"night_of":"2026-08-26","weekday":"Wednesday","scratch_minutes":24,"scratch_episodes":16},{"night_of":"2026-08-27","weekday":"Thursday","scratch_minutes":26,"scratch_episodes":18},{"night_of":"2026-08-28","weekday":"Friday","scratch_minutes":17,"scratch_episodes":12},{"night_of":"2026-08-29","weekday":"Saturday","scratch_minutes":14,"scratch_episodes":11},{"night_of":"2026-08-30","weekday":"Sunday","scratch_minutes":14,"scratch_episodes":11},{"night_of":"2026-08-31","weekday":"Monday","scratch_minutes":14,"scratch_episodes":11},{"night_of":"2026-09-01","weekday":"Tuesday","scratch_minutes":13,"scratch_episodes":10},{"night_of":"2026-09-02","weekday":"Wednesday","scratch_minutes":12,"scratch_episodes":10},{"night_of":"2026-09-03","weekday":"Thursday","scratch_minutes":13,"scratch_episodes":10},{"night_of":"2026-09-04","weekday":"Friday","scratch_minutes":14,"scratch_episodes":11},{"night_of":"2026-09-05","weekday":"Saturday","scratch_minutes":11,"scratch_episodes":10},{"night_of":"2026-09-06","weekday":"Sunday","scratch_minutes":13,"scratch_episodes":10},{"night_of":"2026-09-07","weekday":"Monday","scratch_minutes":10,"scratch_episodes":7},{"night_of":"2026-09-08","weekday":"Tuesday","scratch_minutes":14,"scratch_episodes":11},{"night_of":"2026-09-09","weekday":"Wednesday","scratch_minutes":10,"scratch_episodes":9},{"night_of":"2026-09-10","weekday":"Thursday","scratch_minutes":13,"scratch_episodes":9},{"night_of":"2026-09-11","weekday":"Friday","scratch_minutes":11,"scratch_episodes":10},{"night_of":"2026-09-12","weekday":"Saturday","scratch_minutes":11,"scratch_episodes":9},{"night_of":"2026-09-13","weekday":"Sunday","scratch_minutes":17,"scratch_episodes":12},{"night_of":"2026-09-14","weekday":"Monday","scratch_minutes":22,"scratch_episodes":15},{"night_of":"2026-09-15","weekday":"Tuesday","scratch_minutes":25,"scratch_episodes":17},{"night_of":"2026-09-16","weekday":"Wednesday","scratch_minutes":19,"scratch_episodes":14},{"night_of":"2026-09-17","weekday":"Thursday","scratch_minutes":13,"scratch_episodes":10},{"night_of":"2026-09-18","weekday":"Friday","scratch_minutes":12,"scratch_episodes":11},{"night_of":"2026-09-19","weekday":"Saturday","scratch_minutes":15,"scratch_episodes":12},{"night_of":"2026-09-20","weekday":"Sunday","scratch_minutes":12,"scratch_episodes":11},{"night_of":"2026-09-21","weekday":"Monday","scratch_minutes":11,"scratch_episodes":10},{"night_of":"2026-09-22","weekday":"Tuesday","scratch_minutes":12,"scratch_episodes":10},{"night_of":"2026-09-23","weekday":"Wednesday","scratch_minutes":13,"scratch_episodes":10},{"night_of":"2026-09-24","weekday":"Thursday","scratch_minutes":10,"scratch_episodes":8},{"night_of":"2026-09-25","weekday":"Friday","scratch_minutes":9,"scratch_episodes":8},{"night_of":"2026-09-26","weekday":"Saturday","scratch_minutes":12,"scratch_episodes":11},{"night_of":"2026-09-27","weekday":"Sunday","scratch_minutes":10,"scratch_episodes":8},{"night_of":"2026-09-28","weekday":"Monday","scratch_minutes":16,"scratch_episodes":12},{"night_of":"2026-09-29","weekday":"Tuesday","scratch_minutes":12,"scratch_episodes":10},{"night_of":"2026-09-30","weekday":"Wednesday","scratch_minutes":10,"scratch_episodes":9},{"night_of":"2026-10-01","weekday":"Thursday","scratch_minutes":13,"scratch_episodes":10},{"night_of":"2026-10-02","weekday":"Friday","scratch_minutes":11,"scratch_episodes":10},{"night_of":"2026-10-03","weekday":"Saturday","scratch_minutes":11,"scratch_episodes":9},{"night_of":"2026-10-04","weekday":"Sunday","scratch_minutes":14,"scratch_episodes":11},{"night_of":"2026-10-05","weekday":"Monday","scratch_minutes":10,"scratch_episodes":7},{"night_of":"2026-10-06","weekday":"Tuesday","scratch_minutes":19,"scratch_episodes":14},{"night_of":"2026-10-07","weekday":"Wednesday","scratch_minutes":27,"scratch_episodes":18},{"night_of":"2026-10-08","weekday":"Thursday","scratch_minutes":31,"scratch_episodes":20},{"night_of":"2026-10-09","weekday":"Friday","scratch_minutes":22,"scratch_episodes":15},{"night_of":"2026-10-10","weekday":"Saturday","scratch_minutes":9,"scratch_episodes":8},{"night_of":"2026-10-11","weekday":"Sunday","scratch_minutes":14,"scratch_episodes":11},{"night_of":"2026-10-12","weekday":"Monday","scratch_minutes":11,"scratch_episodes":9},{"night_of":"2026-10-13","weekday":"Tuesday","scratch_minutes":8,"scratch_episodes":7},{"night_of":"2026-10-14","weekday":"Wednesday","scratch_minutes":15,"scratch_episodes":12},{"night_of":"2026-10-15","weekday":"Thursday","scratch_minutes":12,"scratch_episodes":10},{"night_of":"2026-10-16","weekday":"Friday","scratch_minutes":10,"scratch_episodes":8},{"night_of":"2026-10-17","weekday":"Saturday","scratch_minutes":16,"scratch_episodes":12},{"night_of":"2026-10-18","weekday":"Sunday","scratch_minutes":13,"scratch_episodes":11},{"night_of":"2026-10-19","weekday":"Monday","scratch_minutes":11,"scratch_episodes":9},{"night_of":"2026-10-20","weekday":"Tuesday","scratch_minutes":17,"scratch_episodes":13},{"night_of":"2026-10-21","weekday":"Wednesday","scratch_minutes":24,"scratch_episodes":16},{"night_of":"2026-10-22","weekday":"Thursday","scratch_minutes":29,"scratch_episodes":19},{"night_of":"2026-10-23","weekday":"Friday","scratch_minutes":41,"scratch_episodes":23}],"last_night_worst_hours":"2–4 AM"}"#
    static let orders120 = #"{"source":"Amazon order history","orders":[{"date":"2026-08-11","item":"Everclean Free & Clear Liquid Detergent, 92 loads","category":"household","bought_before":true,"note":"fragrance-free; same product every month for 2 years","ingredients":["Water","Sodium Laureth Sulfate","Alcohol Ethoxylate","Sodium Citrate","Sodium Benzoate","Enzymes"]},{"date":"2026-08-13","item":"Riverstone Daily Shampoo, 16 fl oz","category":"personal care","bought_before":true,"note":"repeat purchase, every ~6 weeks","ingredients":["Water","Sodium Laureth Sulfate","Cocamidopropyl Betaine","Glycerin","Fragrance (Parfum)","Sodium Benzoate","Citric Acid"]},{"date":"2026-08-15","item":"Coastline Mineral Sunscreen SPF 30","category":"personal care","bought_before":false,"note":"for sunny days","ingredients":["Zinc Oxide","Water","Caprylic/Capric Triglyceride","Glycerin","Phenoxyethanol","Tocopherol"]},{"date":"2026-08-19","item":"Peet's Major Dickason's Coffee Beans, 2 lb","category":"grocery","bought_before":true},{"date":"2026-08-24","item":"Summit Peak Mint Shampoo, travel size 3 fl oz","category":"personal care","bought_before":false,"note":"travel size","ingredients":["Water","Sodium Laureth Sulfate","Cocamidopropyl Betaine","Fragrance (Parfum)","Menthol","Sodium Chloride","Methylchloroisothiazolinone","Methylisothiazolinone","Citric Acid"]},{"date":"2026-08-26","item":"Dermacalm Ceramide Cream, 16 oz","category":"personal care","bought_before":true,"note":"fragrance-free; repeat purchase, uses daily","ingredients":["Water","Glycerin","Ceramide NP","Cetearyl Alcohol","Petrolatum","Phenoxyethanol"]},{"date":"2026-08-31","item":"Five Star Spiral Notebooks, 5 pack","category":"school","bought_before":true},{"date":"2026-09-02","item":"Alder & Pine Cedar Deodorant","category":"personal care","bought_before":false,"note":"uses daily","ingredients":["Propylene Glycol","Water","Sodium Stearate","Fragrance (Parfum)","Linalool","Limonene","Sodium Benzoate"]},{"date":"2026-09-05","item":"Bayline Cotton Pullover Hoodie","category":"clothing","bought_before":false,"note":"washed before wearing","material":"80% cotton, 20% polyester"},{"date":"2026-09-07","item":"Colgate Total Toothpaste, 2 pack","category":"personal care","bought_before":true},{"date":"2026-09-10","item":"Everclean Free & Clear Liquid Detergent, 92 loads","category":"household","bought_before":true,"note":"fragrance-free; same product every month for 2 years","ingredients":["Water","Sodium Laureth Sulfate","Alcohol Ethoxylate","Sodium Citrate","Sodium Benzoate","Enzymes"]},{"date":"2026-09-12","item":"Lumen Citrus Foaming Hand Soap","category":"household","bought_before":false,"ingredients":["Water","Sodium Laureth Sulfate","Glycerin","Fragrance (Parfum)","Limonene","Methylisothiazolinone","Tetrasodium EDTA"]},{"date":"2026-09-16","item":"Anker USB-C Charging Cable, 6 ft","category":"electronics","bought_before":false},{"date":"2026-09-19","item":"Bayline Crew T-Shirts, 3 pack","category":"clothing","bought_before":false,"note":"washed before wearing","material":"100% cotton"},{"date":"2026-09-20","item":"RXBAR Protein Bars, 12 count","category":"grocery","bought_before":true},{"date":"2026-09-22","item":"Harbor Oat Daily Lotion","category":"personal care","bought_before":false,"note":"uses daily","ingredients":["Water","Glycerin","Colloidal Oatmeal","Cetearyl Alcohol","Dimethicone","Phenoxyethanol","Sodium Benzoate"]},{"date":"2026-09-24","item":"Riverstone Daily Shampoo, 16 fl oz","category":"personal care","bought_before":true,"note":"repeat purchase, every ~6 weeks","ingredients":["Water","Sodium Laureth Sulfate","Cocamidopropyl Betaine","Glycerin","Fragrance (Parfum)","Sodium Benzoate","Citric Acid"]},{"date":"2026-09-25","item":"Willow Unscented Hand Soap Refill","category":"household","bought_before":true,"note":"unscented; repeat purchase","ingredients":["Water","Sodium Laureth Sulfate","Glycerin","Cocamidopropyl Betaine","Sodium Benzoate","Citric Acid"]},{"date":"2026-09-27","item":"Brightwell Daily Moisturizing Lotion, 12 fl oz","category":"personal care","bought_before":false,"ingredients":["Water","Glycerin","Cetearyl Alcohol","Dimethicone","Fragrance (Parfum)","Methylisothiazolinone","Carbomer"]},{"date":"2026-10-01","item":"Cloudrest Memory Foam Pillow","category":"household","bought_before":false,"material":"polyurethane foam, polyester cover"},{"date":"2026-10-02","item":"Duracell AAA Batteries, 8 pack","category":"school","bought_before":true},{"date":"2026-10-05","item":"Northfield Lambswool Crewneck Sweater","category":"clothing","bought_before":false,"note":"first wool sweater","material":"100% lambswool"},{"date":"2026-10-05","item":"FreshMeadow Spring Bloom Detergent, trial size","category":"household","bought_before":false,"note":"trial size","ingredients":["Water","Sodium Laureth Sulfate","Alcohol Ethoxylate","Sodium Citrate","Fragrance","Methylisothiazolinone","Colorant"]},{"date":"2026-10-12","item":"Peet's Major Dickason's Coffee Beans, 2 lb","category":"grocery","bought_before":true},{"date":"2026-10-13","item":"Everclean Free & Clear Liquid Detergent, 92 loads","category":"household","bought_before":true,"note":"fragrance-free; same product every month for 2 years","ingredients":["Water","Sodium Laureth Sulfate","Alcohol Ethoxylate","Sodium Citrate","Sodium Benzoate","Enzymes"]},{"date":"2026-10-15","item":"Darn Tough Merino Wool Socks, 3 pairs","category":"clothing","bought_before":false,"note":"washed before wearing","material":"54% merino wool, 43% nylon, 3% spandex"},{"date":"2026-10-17","item":"Nissin Top Ramen, 24 pack","category":"grocery","bought_before":true},{"date":"2026-10-19","item":"Brightwell Sensitive Fragrance-Free Body Wash, 18 fl oz","category":"personal care","bought_before":false,"note":"first time ordering any body wash; delivered next day","ingredients":["Water","Sodium Laureth Sulfate","Cocamidopropyl Betaine","Glycerin","Sodium Chloride","Methylisothiazolinone","Citric Acid"]},{"date":"2026-10-21","item":"Philips LED Desk Lamp Bulb","category":"household","bought_before":true},{"date":"2026-10-22","item":"RXBAR Protein Bars, 12 count","category":"grocery","bought_before":true}]}"#
    static let orders30 = #"{"source":"Amazon order history","orders":[{"date":"2026-09-25","item":"Willow Unscented Hand Soap Refill","category":"household","bought_before":true,"note":"unscented; repeat purchase","ingredients":["Water","Sodium Laureth Sulfate","Glycerin","Cocamidopropyl Betaine","Sodium Benzoate","Citric Acid"]},{"date":"2026-09-27","item":"Brightwell Daily Moisturizing Lotion, 12 fl oz","category":"personal care","bought_before":false,"ingredients":["Water","Glycerin","Cetearyl Alcohol","Dimethicone","Fragrance (Parfum)","Methylisothiazolinone","Carbomer"]},{"date":"2026-10-01","item":"Cloudrest Memory Foam Pillow","category":"household","bought_before":false,"material":"polyurethane foam, polyester cover"},{"date":"2026-10-02","item":"Duracell AAA Batteries, 8 pack","category":"school","bought_before":true},{"date":"2026-10-05","item":"Northfield Lambswool Crewneck Sweater","category":"clothing","bought_before":false,"note":"first wool sweater","material":"100% lambswool"},{"date":"2026-10-05","item":"FreshMeadow Spring Bloom Detergent, trial size","category":"household","bought_before":false,"note":"trial size","ingredients":["Water","Sodium Laureth Sulfate","Alcohol Ethoxylate","Sodium Citrate","Fragrance","Methylisothiazolinone","Colorant"]},{"date":"2026-10-12","item":"Peet's Major Dickason's Coffee Beans, 2 lb","category":"grocery","bought_before":true},{"date":"2026-10-13","item":"Everclean Free & Clear Liquid Detergent, 92 loads","category":"household","bought_before":true,"note":"fragrance-free; same product every month for 2 years","ingredients":["Water","Sodium Laureth Sulfate","Alcohol Ethoxylate","Sodium Citrate","Sodium Benzoate","Enzymes"]},{"date":"2026-10-15","item":"Darn Tough Merino Wool Socks, 3 pairs","category":"clothing","bought_before":false,"note":"washed before wearing","material":"54% merino wool, 43% nylon, 3% spandex"},{"date":"2026-10-17","item":"Nissin Top Ramen, 24 pack","category":"grocery","bought_before":true},{"date":"2026-10-19","item":"Brightwell Sensitive Fragrance-Free Body Wash, 18 fl oz","category":"personal care","bought_before":false,"note":"first time ordering any body wash; delivered next day","ingredients":["Water","Sodium Laureth Sulfate","Cocamidopropyl Betaine","Glycerin","Sodium Chloride","Methylisothiazolinone","Citric Acid"]},{"date":"2026-10-21","item":"Philips LED Desk Lamp Bulb","category":"household","bought_before":true},{"date":"2026-10-22","item":"RXBAR Protein Bars, 12 count","category":"grocery","bought_before":true}]}"#
    static let weather14 = #"{"location":"Berkeley, CA","days":[{"date":"2026-10-10","humidity_percent":52,"high_f":64},{"date":"2026-10-11","humidity_percent":49,"high_f":66},{"date":"2026-10-12","humidity_percent":55,"high_f":63},{"date":"2026-10-13","humidity_percent":51,"high_f":61},{"date":"2026-10-14","humidity_percent":47,"high_f":65},{"date":"2026-10-15","humidity_percent":50,"high_f":67},{"date":"2026-10-16","humidity_percent":53,"high_f":66},{"date":"2026-10-17","humidity_percent":48,"high_f":64},{"date":"2026-10-18","humidity_percent":51,"high_f":63},{"date":"2026-10-19","humidity_percent":50,"high_f":65},{"date":"2026-10-20","humidity_percent":49,"high_f":66},{"date":"2026-10-21","humidity_percent":47,"high_f":64},{"date":"2026-10-22","humidity_percent":46,"high_f":63},{"date":"2026-10-23","humidity_percent":29,"high_f":68}]}"#
    static let weather2 = #"{"location":"Berkeley, CA","days":[{"date":"2026-10-22","humidity_percent":46,"high_f":63},{"date":"2026-10-23","humidity_percent":29,"high_f":68}]}"#
    static let weather30 = #"{"location":"Berkeley, CA","days":[{"date":"2026-09-24","humidity_percent":28,"high_f":81},{"date":"2026-09-25","humidity_percent":60,"high_f":67},{"date":"2026-09-26","humidity_percent":53,"high_f":76},{"date":"2026-09-27","humidity_percent":49,"high_f":74},{"date":"2026-09-28","humidity_percent":63,"high_f":73},{"date":"2026-09-29","humidity_percent":50,"high_f":67},{"date":"2026-09-30","humidity_percent":68,"high_f":75},{"date":"2026-10-01","humidity_percent":29,"high_f":74},{"date":"2026-10-02","humidity_percent":49,"high_f":69},{"date":"2026-10-03","humidity_percent":58,"high_f":67},{"date":"2026-10-04","humidity_percent":51,"high_f":67},{"date":"2026-10-05","humidity_percent":71,"high_f":68},{"date":"2026-10-06","humidity_percent":61,"high_f":71},{"date":"2026-10-07","humidity_percent":61,"high_f":70},{"date":"2026-10-08","humidity_percent":70,"high_f":64},{"date":"2026-10-09","humidity_percent":48,"high_f":64},{"date":"2026-10-10","humidity_percent":52,"high_f":64},{"date":"2026-10-11","humidity_percent":49,"high_f":66},{"date":"2026-10-12","humidity_percent":55,"high_f":63},{"date":"2026-10-13","humidity_percent":51,"high_f":61},{"date":"2026-10-14","humidity_percent":47,"high_f":65},{"date":"2026-10-15","humidity_percent":50,"high_f":67},{"date":"2026-10-16","humidity_percent":53,"high_f":66},{"date":"2026-10-17","humidity_percent":48,"high_f":64},{"date":"2026-10-18","humidity_percent":51,"high_f":63},{"date":"2026-10-19","humidity_percent":50,"high_f":65},{"date":"2026-10-20","humidity_percent":49,"high_f":66},{"date":"2026-10-21","humidity_percent":47,"high_f":64},{"date":"2026-10-22","humidity_percent":46,"high_f":63},{"date":"2026-10-23","humidity_percent":29,"high_f":68}]}"#
    static let weather74 = #"{"location":"Berkeley, CA","days":[{"date":"2026-08-11","humidity_percent":63,"high_f":71},{"date":"2026-08-12","humidity_percent":68,"high_f":70},{"date":"2026-08-13","humidity_percent":55,"high_f":74},{"date":"2026-08-14","humidity_percent":62,"high_f":70},{"date":"2026-08-15","humidity_percent":52,"high_f":69},{"date":"2026-08-16","humidity_percent":68,"high_f":68},{"date":"2026-08-17","humidity_percent":48,"high_f":69},{"date":"2026-08-18","humidity_percent":68,"high_f":70},{"date":"2026-08-19","humidity_percent":30,"high_f":77},{"date":"2026-08-20","humidity_percent":66,"high_f":70},{"date":"2026-08-21","humidity_percent":44,"high_f":72},{"date":"2026-08-22","humidity_percent":46,"high_f":72},{"date":"2026-08-23","humidity_percent":46,"high_f":71},{"date":"2026-08-24","humidity_percent":31,"high_f":81},{"date":"2026-08-25","humidity_percent":52,"high_f":67},{"date":"2026-08-26","humidity_percent":71,"high_f":73},{"date":"2026-08-27","humidity_percent":56,"high_f":76},{"date":"2026-08-28","humidity_percent":66,"high_f":69},{"date":"2026-08-29","humidity_percent":68,"high_f":70},{"date":"2026-08-30","humidity_percent":60,"high_f":72},{"date":"2026-08-31","humidity_percent":47,"high_f":76},{"date":"2026-09-01","humidity_percent":45,"high_f":71},{"date":"2026-09-02","humidity_percent":31,"high_f":90},{"date":"2026-09-03","humidity_percent":30,"high_f":91},{"date":"2026-09-04","humidity_percent":53,"high_f":87},{"date":"2026-09-05","humidity_percent":59,"high_f":67},{"date":"2026-09-06","humidity_percent":45,"high_f":68},{"date":"2026-09-07","humidity_percent":58,"high_f":75},{"date":"2026-09-08","humidity_percent":64,"high_f":65},{"date":"2026-09-09","humidity_percent":48,"high_f":76},{"date":"2026-09-10","humidity_percent":47,"high_f":67},{"date":"2026-09-11","humidity_percent":32,"high_f":76},{"date":"2026-09-12","humidity_percent":31,"high_f":76},{"date":"2026-09-13","humidity_percent":29,"high_f":72},{"date":"2026-09-14","humidity_percent":30,"high_f":71},{"date":"2026-09-15","humidity_percent":71,"high_f":70},{"date":"2026-09-16","humidity_percent":60,"high_f":77},{"date":"2026-09-17","humidity_percent":69,"high_f":77},{"date":"2026-09-18","humidity_percent":55,"high_f":73},{"date":"2026-09-19","humidity_percent":52,"high_f":77},{"date":"2026-09-20","humidity_percent":64,"high_f":67},{"date":"2026-09-21","humidity_percent":61,"high_f":77},{"date":"2026-09-22","humidity_percent":53,"high_f":78},{"date":"2026-09-23","humidity_percent":52,"high_f":75},{"date":"2026-09-24","humidity_percent":28,"high_f":81},{"date":"2026-09-25","humidity_percent":60,"high_f":67},{"date":"2026-09-26","humidity_percent":53,"high_f":76},{"date":"2026-09-27","humidity_percent":49,"high_f":74},{"date":"2026-09-28","humidity_percent":63,"high_f":73},{"date":"2026-09-29","humidity_percent":50,"high_f":67},{"date":"2026-09-30","humidity_percent":68,"high_f":75},{"date":"2026-10-01","humidity_percent":29,"high_f":74},{"date":"2026-10-02","humidity_percent":49,"high_f":69},{"date":"2026-10-03","humidity_percent":58,"high_f":67},{"date":"2026-10-04","humidity_percent":51,"high_f":67},{"date":"2026-10-05","humidity_percent":71,"high_f":68},{"date":"2026-10-06","humidity_percent":61,"high_f":71},{"date":"2026-10-07","humidity_percent":61,"high_f":70},{"date":"2026-10-08","humidity_percent":70,"high_f":64},{"date":"2026-10-09","humidity_percent":48,"high_f":64},{"date":"2026-10-10","humidity_percent":52,"high_f":64},{"date":"2026-10-11","humidity_percent":49,"high_f":66},{"date":"2026-10-12","humidity_percent":55,"high_f":63},{"date":"2026-10-13","humidity_percent":51,"high_f":61},{"date":"2026-10-14","humidity_percent":47,"high_f":65},{"date":"2026-10-15","humidity_percent":50,"high_f":67},{"date":"2026-10-16","humidity_percent":53,"high_f":66},{"date":"2026-10-17","humidity_percent":48,"high_f":64},{"date":"2026-10-18","humidity_percent":51,"high_f":63},{"date":"2026-10-19","humidity_percent":50,"high_f":65},{"date":"2026-10-20","humidity_percent":49,"high_f":66},{"date":"2026-10-21","humidity_percent":47,"high_f":64},{"date":"2026-10-22","humidity_percent":46,"high_f":63},{"date":"2026-10-23","humidity_percent":29,"high_f":68}]}"#
    static let calendar = #"{"events":[{"date":"2026-10-11 to 2026-10-13","title":"Midterm exams (CS 61B, Math 54)","note":"stressful week"},{"date":"2026-10-16","title":"Dentist"},{"date":"2026-10-19","title":"Team project deadline"},{"date":"2026-10-25","title":"CalHacks 13.0 (hackathon)"}]}"#
    static let calendarAll = #"{"events":[{"date":"2026-08-24 to 2026-08-27","title":"Trip to Seattle (family)"},{"date":"2026-09-14 to 2026-09-17","title":"Exam week (CS 61B, Math 54 quizzes)"},{"date":"2026-10-11 to 2026-10-13","title":"Midterm exams (CS 61B, Math 54)","note":"stressful week"},{"date":"2026-10-16","title":"Dentist"},{"date":"2026-10-19","title":"Team project deadline"},{"date":"2026-10-25","title":"CalHacks 13.0 (hackathon)"}]}"#
    static let sleep14 = #"{"source":"Apple Health","usual_hrv_ms":52,"nights":[{"night_of":"2026-10-10","hours_asleep":7.4,"wake_ups":0,"hrv_ms":53},{"night_of":"2026-10-11","hours_asleep":7.1,"wake_ups":1,"hrv_ms":51},{"night_of":"2026-10-12","hours_asleep":6.2,"wake_ups":1,"hrv_ms":52},{"night_of":"2026-10-13","hours_asleep":6,"wake_ups":1,"hrv_ms":54},{"night_of":"2026-10-14","hours_asleep":6.4,"wake_ups":0,"hrv_ms":50},{"night_of":"2026-10-15","hours_asleep":7.5,"wake_ups":0,"hrv_ms":52},{"night_of":"2026-10-16","hours_asleep":7.3,"wake_ups":1,"hrv_ms":53},{"night_of":"2026-10-17","hours_asleep":7.2,"wake_ups":0,"hrv_ms":51},{"night_of":"2026-10-18","hours_asleep":7.6,"wake_ups":0,"hrv_ms":52},{"night_of":"2026-10-19","hours_asleep":7,"wake_ups":1,"hrv_ms":53},{"night_of":"2026-10-20","hours_asleep":6.9,"wake_ups":1,"hrv_ms":51},{"night_of":"2026-10-21","hours_asleep":6.4,"wake_ups":1,"hrv_ms":46},{"night_of":"2026-10-22","hours_asleep":5.6,"wake_ups":2,"hrv_ms":42},{"night_of":"2026-10-23","hours_asleep":5.1,"wake_ups":2,"hrv_ms":38}]}"#
    static let sleep4 = #"{"source":"Apple Health","usual_hrv_ms":52,"nights":[{"night_of":"2026-10-20","hours_asleep":6.9,"wake_ups":1,"hrv_ms":51},{"night_of":"2026-10-21","hours_asleep":6.4,"wake_ups":1,"hrv_ms":46},{"night_of":"2026-10-22","hours_asleep":5.6,"wake_ups":2,"hrv_ms":42},{"night_of":"2026-10-23","hours_asleep":5.1,"wake_ups":2,"hrv_ms":38}]}"#
    static let sleep30 = #"{"source":"Apple Health","usual_hrv_ms":52,"nights":[{"night_of":"2026-09-24","hours_asleep":7.9,"wake_ups":0,"hrv_ms":49},{"night_of":"2026-09-25","hours_asleep":6.9,"wake_ups":0,"hrv_ms":51},{"night_of":"2026-09-26","hours_asleep":5.5,"wake_ups":1,"hrv_ms":50},{"night_of":"2026-09-27","hours_asleep":7.6,"wake_ups":1,"hrv_ms":55},{"night_of":"2026-09-28","hours_asleep":7.6,"wake_ups":0,"hrv_ms":50},{"night_of":"2026-09-29","hours_asleep":7.4,"wake_ups":0,"hrv_ms":52},{"night_of":"2026-09-30","hours_asleep":6.9,"wake_ups":0,"hrv_ms":54},{"night_of":"2026-10-01","hours_asleep":7.8,"wake_ups":0,"hrv_ms":49},{"night_of":"2026-10-02","hours_asleep":6.9,"wake_ups":0,"hrv_ms":51},{"night_of":"2026-10-03","hours_asleep":7.2,"wake_ups":0,"hrv_ms":53},{"night_of":"2026-10-04","hours_asleep":6.7,"wake_ups":1,"hrv_ms":55},{"night_of":"2026-10-05","hours_asleep":7.7,"wake_ups":0,"hrv_ms":50},{"night_of":"2026-10-06","hours_asleep":6.8,"wake_ups":1,"hrv_ms":48},{"night_of":"2026-10-07","hours_asleep":6.6,"wake_ups":2,"hrv_ms":47},{"night_of":"2026-10-08","hours_asleep":6.6,"wake_ups":2,"hrv_ms":41},{"night_of":"2026-10-09","hours_asleep":6.9,"wake_ups":1,"hrv_ms":46},{"night_of":"2026-10-10","hours_asleep":7.4,"wake_ups":0,"hrv_ms":53},{"night_of":"2026-10-11","hours_asleep":7.1,"wake_ups":1,"hrv_ms":51},{"night_of":"2026-10-12","hours_asleep":6.2,"wake_ups":1,"hrv_ms":52},{"night_of":"2026-10-13","hours_asleep":6,"wake_ups":1,"hrv_ms":54},{"night_of":"2026-10-14","hours_asleep":6.4,"wake_ups":0,"hrv_ms":50},{"night_of":"2026-10-15","hours_asleep":7.5,"wake_ups":0,"hrv_ms":52},{"night_of":"2026-10-16","hours_asleep":7.3,"wake_ups":1,"hrv_ms":53},{"night_of":"2026-10-17","hours_asleep":7.2,"wake_ups":0,"hrv_ms":51},{"night_of":"2026-10-18","hours_asleep":7.6,"wake_ups":0,"hrv_ms":52},{"night_of":"2026-10-19","hours_asleep":7,"wake_ups":1,"hrv_ms":53},{"night_of":"2026-10-20","hours_asleep":6.9,"wake_ups":1,"hrv_ms":51},{"night_of":"2026-10-21","hours_asleep":6.4,"wake_ups":1,"hrv_ms":46},{"night_of":"2026-10-22","hours_asleep":5.6,"wake_ups":2,"hrv_ms":42},{"night_of":"2026-10-23","hours_asleep":5.1,"wake_ups":2,"hrv_ms":38}]}"#
    static let sleep74 = #"{"source":"Apple Health","usual_hrv_ms":52,"nights":[{"night_of":"2026-08-11","hours_asleep":7.6,"wake_ups":0,"hrv_ms":52},{"night_of":"2026-08-12","hours_asleep":7.5,"wake_ups":0,"hrv_ms":54},{"night_of":"2026-08-13","hours_asleep":7.7,"wake_ups":1,"hrv_ms":49},{"night_of":"2026-08-14","hours_asleep":6.7,"wake_ups":0,"hrv_ms":51},{"night_of":"2026-08-15","hours_asleep":7.8,"wake_ups":1,"hrv_ms":53},{"night_of":"2026-08-16","hours_asleep":5.5,"wake_ups":1,"hrv_ms":52},{"night_of":"2026-08-17","hours_asleep":6.7,"wake_ups":0,"hrv_ms":50},{"night_of":"2026-08-18","hours_asleep":7.9,"wake_ups":0,"hrv_ms":52},{"night_of":"2026-08-19","hours_asleep":7.3,"wake_ups":0,"hrv_ms":54},{"night_of":"2026-08-20","hours_asleep":7.9,"wake_ups":1,"hrv_ms":49},{"night_of":"2026-08-21","hours_asleep":7.2,"wake_ups":0,"hrv_ms":51},{"night_of":"2026-08-22","hours_asleep":7.1,"wake_ups":0,"hrv_ms":53},{"night_of":"2026-08-23","hours_asleep":7.1,"wake_ups":0,"hrv_ms":55},{"night_of":"2026-08-24","hours_asleep":7.3,"wake_ups":0,"hrv_ms":50},{"night_of":"2026-08-25","hours_asleep":6.9,"wake_ups":1,"hrv_ms":49},{"night_of":"2026-08-26","hours_asleep":6.7,"wake_ups":1,"hrv_ms":48},{"night_of":"2026-08-27","hours_asleep":6.6,"wake_ups":2,"hrv_ms":42},{"night_of":"2026-08-28","hours_asleep":7,"wake_ups":1,"hrv_ms":47},{"night_of":"2026-08-29","hours_asleep":7.8,"wake_ups":1,"hrv_ms":53},{"night_of":"2026-08-30","hours_asleep":7.8,"wake_ups":0,"hrv_ms":55},{"night_of":"2026-08-31","hours_asleep":7.6,"wake_ups":0,"hrv_ms":50},{"night_of":"2026-09-01","hours_asleep":7.8,"wake_ups":0,"hrv_ms":52},{"night_of":"2026-09-02","hours_asleep":7.4,"wake_ups":0,"hrv_ms":54},{"night_of":"2026-09-03","hours_asleep":7.4,"wake_ups":0,"hrv_ms":49},{"night_of":"2026-09-04","hours_asleep":7.7,"wake_ups":0,"hrv_ms":51},{"night_of":"2026-09-05","hours_asleep":7.6,"wake_ups":0,"hrv_ms":53},{"night_of":"2026-09-06","hours_asleep":7.6,"wake_ups":0,"hrv_ms":55},{"night_of":"2026-09-07","hours_asleep":5.8,"wake_ups":1,"hrv_ms":47},{"night_of":"2026-09-08","hours_asleep":7.7,"wake_ups":0,"hrv_ms":52},{"night_of":"2026-09-09","hours_asleep":7.4,"wake_ups":0,"hrv_ms":54},{"night_of":"2026-09-10","hours_asleep":7.2,"wake_ups":0,"hrv_ms":49},{"night_of":"2026-09-11","hours_asleep":7.2,"wake_ups":0,"hrv_ms":51},{"night_of":"2026-09-12","hours_asleep":7.6,"wake_ups":1,"hrv_ms":53},{"night_of":"2026-09-13","hours_asleep":6.9,"wake_ups":1,"hrv_ms":52},{"night_of":"2026-09-14","hours_asleep":6.6,"wake_ups":1,"hrv_ms":43},{"night_of":"2026-09-15","hours_asleep":6.5,"wake_ups":2,"hrv_ms":44},{"night_of":"2026-09-16","hours_asleep":6.8,"wake_ups":1,"hrv_ms":47},{"night_of":"2026-09-17","hours_asleep":6.7,"wake_ups":0,"hrv_ms":43},{"night_of":"2026-09-18","hours_asleep":7.5,"wake_ups":0,"hrv_ms":51},{"night_of":"2026-09-19","hours_asleep":7.9,"wake_ups":0,"hrv_ms":53},{"night_of":"2026-09-20","hours_asleep":7.4,"wake_ups":0,"hrv_ms":55},{"night_of":"2026-09-21","hours_asleep":7,"wake_ups":0,"hrv_ms":50},{"night_of":"2026-09-22","hours_asleep":7.3,"wake_ups":0,"hrv_ms":52},{"night_of":"2026-09-23","hours_asleep":7.1,"wake_ups":1,"hrv_ms":54},{"night_of":"2026-09-24","hours_asleep":7.9,"wake_ups":0,"hrv_ms":49},{"night_of":"2026-09-25","hours_asleep":6.9,"wake_ups":0,"hrv_ms":51},{"night_of":"2026-09-26","hours_asleep":5.5,"wake_ups":1,"hrv_ms":50},{"night_of":"2026-09-27","hours_asleep":7.6,"wake_ups":1,"hrv_ms":55},{"night_of":"2026-09-28","hours_asleep":7.6,"wake_ups":0,"hrv_ms":50},{"night_of":"2026-09-29","hours_asleep":7.4,"wake_ups":0,"hrv_ms":52},{"night_of":"2026-09-30","hours_asleep":6.9,"wake_ups":0,"hrv_ms":54},{"night_of":"2026-10-01","hours_asleep":7.8,"wake_ups":0,"hrv_ms":49},{"night_of":"2026-10-02","hours_asleep":6.9,"wake_ups":0,"hrv_ms":51},{"night_of":"2026-10-03","hours_asleep":7.2,"wake_ups":0,"hrv_ms":53},{"night_of":"2026-10-04","hours_asleep":6.7,"wake_ups":1,"hrv_ms":55},{"night_of":"2026-10-05","hours_asleep":7.7,"wake_ups":0,"hrv_ms":50},{"night_of":"2026-10-06","hours_asleep":6.8,"wake_ups":1,"hrv_ms":48},{"night_of":"2026-10-07","hours_asleep":6.6,"wake_ups":2,"hrv_ms":47},{"night_of":"2026-10-08","hours_asleep":6.6,"wake_ups":2,"hrv_ms":41},{"night_of":"2026-10-09","hours_asleep":6.9,"wake_ups":1,"hrv_ms":46},{"night_of":"2026-10-10","hours_asleep":7.4,"wake_ups":0,"hrv_ms":53},{"night_of":"2026-10-11","hours_asleep":7.1,"wake_ups":1,"hrv_ms":51},{"night_of":"2026-10-12","hours_asleep":6.2,"wake_ups":1,"hrv_ms":52},{"night_of":"2026-10-13","hours_asleep":6,"wake_ups":1,"hrv_ms":54},{"night_of":"2026-10-14","hours_asleep":6.4,"wake_ups":0,"hrv_ms":50},{"night_of":"2026-10-15","hours_asleep":7.5,"wake_ups":0,"hrv_ms":52},{"night_of":"2026-10-16","hours_asleep":7.3,"wake_ups":1,"hrv_ms":53},{"night_of":"2026-10-17","hours_asleep":7.2,"wake_ups":0,"hrv_ms":51},{"night_of":"2026-10-18","hours_asleep":7.6,"wake_ups":0,"hrv_ms":52},{"night_of":"2026-10-19","hours_asleep":7,"wake_ups":1,"hrv_ms":53},{"night_of":"2026-10-20","hours_asleep":6.9,"wake_ups":1,"hrv_ms":51},{"night_of":"2026-10-21","hours_asleep":6.4,"wake_ups":1,"hrv_ms":46},{"night_of":"2026-10-22","hours_asleep":5.6,"wake_ups":2,"hrv_ms":42},{"night_of":"2026-10-23","hours_asleep":5.1,"wake_ups":2,"hrv_ms":38}]}"#
}
