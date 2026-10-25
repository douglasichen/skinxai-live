import Foundation
import Testing
@testable import EczemaKit

@Suite struct StageHistoryTests {
    let cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "America/Los_Angeles")!; return c }()
    /// Saturday, October 24, 2026, 3 PM in Berkeley (the first demo day).
    var now: Date { cal.date(from: DateComponents(year: 2026, month: 10, day: 24, hour: 15))! }

    @Test func shape() {
        #expect(StageHistory.count == 74 && StageHistory.nights.count == 74)
        #expect(StageHistory.nights.first?.id == -60 && StageHistory.nights.last?.id == 13)
        #expect(StageHistory.nights.map(\.id) == Array(-60...13))
        for array in [StageHistory.earlierMinutes.count, StageHistory.earlierEpisodes.count, StageHistory.earlierHumidity.count,
                      StageHistory.earlierHighF.count, StageHistory.earlierSleep.count, StageHistory.earlierWakeUps.count] {
            #expect(array == 60)
        }
        // Dates: the oldest night is Tue Aug 11, last night Fri Oct 23.
        #expect(StageStory.iso(StageStory.nightDate(-60, now: now, calendar: cal), calendar: cal) == "2026-08-11")
        #expect(StageStory.iso(StageStory.nightDate(13, now: now, calendar: cal), calendar: cal) == "2026-10-23")
    }

    @Test func lastFourteenAreTheStory() {
        let last = Array(StageHistory.nights.suffix(14))
        #expect(last.map(\.id) == Array(0...13))
        #expect(last.map(\.minutes) == StageStory.nights)
        #expect(last.map(\.episodes) == StageStory.episodes)
        #expect(last.map(\.humidity) == StageStory.humidity)
        #expect(last.map(\.highF) == StageStory.highF)
        #expect(last.map(\.sleepHours) == StageStory.sleepHours)
        #expect(last.map(\.wakeUps) == StageStory.wakeUps)
        #expect(last.filter(\.exams).map(\.id) == Array(StageStory.examNights))
        #expect(last.filter(\.dry).map(\.id) == [StageStory.dryAirNight])
        #expect(!last.contains { $0.trip })
        // The story itself is untouched.
        #expect(StageStory.nights == [9, 14, 11, 8, 15, 12, 10, 16, 13, 11, 17, 24, 29, 41])
        #expect(StageHistory.flares.last?.nights == StageStory.bodyWashNight...13)
    }

    @Test func earlierNightsTellHonestStories() {
        let earlier = StageHistory.nights.prefix(60)
        // Three earlier flares, with the scenario's minutes.
        let minutes = { (r: ClosedRange<Int>) in r.map { StageHistory.night($0).minutes } }
        #expect(minutes(-46...(-43)) == [18, 24, 26, 17])
        #expect(minutes(-27...(-24)) == [17, 22, 25, 19])
        #expect(minutes(-4...(-1)) == [19, 27, 31, 22])
        #expect(StageHistory.night(-23).minutes == 13, "the last exam night is back to normal")
        // Every night above 1.5× usual is in one of the four flares.
        #expect(StageHistory.nights.filter(\.flare).allSatisfy { StageHistory.inFlare($0.id) })
        // Usual ~12 with noise outside them.
        let typical = StageHistory.typicalNights
        #expect(typical.count == 58)
        #expect(abs(StageHistory.typicalAverage - 12) < 0.5)
        #expect(typical.map(\.minutes).min()! >= 8 && typical.map(\.minutes).max()! <= 16)
        // Calm dry days outside the flares; the dry spell around the hand soap.
        let dry = typical.filter(\.dry)
        #expect(dry.count >= 7)
        #expect(dry.allSatisfy { $0.minutes <= 13 })
        #expect([-28, -27, -26].map { StageHistory.night($0).humidity } == [31, 29, 30])
        // The exam week, the trip, a few new clothes.
        #expect(earlier.filter(\.exams).map(\.id) == [-26, -25, -24, -23])
        #expect(earlier.filter(\.trip).map(\.id) == [-47, -46, -45, -44])
        #expect(StageHistory.clothes.count == 3 && earlier.filter(\.newClothes).count == 6)
        #expect(!earlier.filter(\.newClothes).contains { StageHistory.inFlare($0.id) })
        // The socks are StageStory's order on night 5, worn from night 6.
        #expect(StageHistory.clothes.last?.firstNight == 6)
        #expect(StageStory.orders(now: now, calendar: cal).contains { $0.item.hasPrefix("Darn Tough Merino Wool Socks") })
    }

    @Test func theFlaresDates() {
        let iso = { (i: Int) in StageStory.iso(StageStory.nightDate(i, now: now, calendar: cal), calendar: cal) }
        #expect(StageHistory.flares.map { iso($0.nights.lowerBound) } == ["2026-08-25", "2026-09-13", "2026-10-06", "2026-10-20"])
        #expect(StageHistory.flares.map { iso($0.nights.upperBound) } == ["2026-08-28", "2026-09-16", "2026-10-09", "2026-10-23"])
        #expect(StageHistory.flares.map { iso($0.orderedNight) } == ["2026-08-24", "2026-09-12", "2026-10-05", "2026-10-19"])
        // ISO dates back to nights, across all 74.
        #expect(StageHistory.night(iso: "2026-08-11", now: now, calendar: cal) == -60)
        #expect(StageHistory.night(iso: "2026-10-05", now: now, calendar: cal) == -5)
        #expect(StageHistory.night(iso: "2026-10-23", now: now, calendar: cal) == 13)
        #expect(StageHistory.night(iso: "2026-08-10", now: now, calendar: cal) == nil)
        #expect(StageHistory.night(iso: "2026-10-24", now: now, calendar: cal) == nil)
        #expect(StageHistory.night(iso: "soon", now: now, calendar: cal) == nil)
    }

    @Test func comparisons() {
        // Late gym nights: a little higher.
        let gym = StageHistory.compare(\.gym)
        #expect(gym.withNights == 14 && gym.withoutNights == 60)
        #expect((1...4).contains(gym.roundedDifference))
        // Outside the flares, dry air and short sleep don't move it.
        let typical = StageHistory.typicalNights
        let dryIn = typical.filter(\.dry), dryOut = typical.filter { !$0.dry }
        #expect(abs(mean(dryIn.map(\.minutes)) - mean(dryOut.map(\.minutes))) < 1.5)
        let short = typical.filter { StageHistory.afterShortSleep($0.id) }
        #expect(!short.isEmpty && abs(mean(short.map(\.minutes)) - StageHistory.typicalAverage) < 1.5)
        // The midterms were calm.
        #expect(StageStory.examNights.allSatisfy { !StageHistory.night($0).flare })
    }

    @Test func noWeekdayPattern() {
        // The same groups on either demo day.
        for day in [24, 25] {
            let at = cal.date(from: DateComponents(year: 2026, month: 10, day: day, hour: 15))!
            let averages = StageHistory.weekdayAverages(now: at, calendar: cal)
            #expect(averages.count == 7)
            #expect(averages.allSatisfy { abs($0 - Double(StageStory.usual)) <= 2 })
        }
    }

    @Test func weatherIsNotLinked() {
        // Outside the flares, humidity and temperature don't move the minutes.
        let before = StageHistory.typicalNights
        #expect(abs(correlation(before.map { Double($0.humidity) }, before.map { Double($0.minutes) })) < 0.25)
        #expect(abs(correlation(before.map { Double($0.highF) }, before.map { Double($0.minutes) })) < 0.25)
    }

    @Test func lastNightSleep() {
        typealias S = StageHistory.LastNightSleep
        #expect(S.segments.first?.start == 0 && S.segments.last?.end == S.length)
        for (a, b) in zip(S.segments, S.segments.dropFirst()) {
            #expect(a.end == b.start && a.stage != b.stage)
        }
        #expect(S.segments.allSatisfy { $0.minutes > 0 })
        #expect(S.minutesAsleep == Int((StageStory.LastNight.sleepHours * 60).rounded()))
        #expect(S.wakeUps.count == StageStory.LastNight.wakeUps)
        #expect(S.wakeUps.count == 2 && S.wakeUpsAfterScratching == 2)
        #expect(S.length == 7 * 60 + 48)   // 11:04 PM → 6:52 AM
    }

    private func mean(_ values: [Int]) -> Double { Double(values.reduce(0, +)) / Double(max(values.count, 1)) }

    private func correlation(_ x: [Double], _ y: [Double]) -> Double {
        let mx = x.reduce(0, +) / Double(x.count), my = y.reduce(0, +) / Double(y.count)
        let cov = zip(x, y).map { ($0 - mx) * ($1 - my) }.reduce(0, +)
        let vx = x.map { ($0 - mx) * ($0 - mx) }.reduce(0, +), vy = y.map { ($0 - my) * ($0 - my) }.reduce(0, +)
        return cov / (vx * vy).squareRoot()
    }
}
