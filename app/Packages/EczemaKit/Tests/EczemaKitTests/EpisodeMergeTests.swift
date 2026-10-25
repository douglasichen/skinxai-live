import Foundation
import Testing
@testable import EczemaKit

/// Watch → iPhone contract: episodes decoded from `transferUserInfo` are folded into the days.
@Suite struct EpisodeMergeTests {
    let cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "America/Los_Angeles")!; return c }()
    var now: Date { cal.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 23))! }

    func at(_ hour: Int, _ minute: Int, dayOffset: Int = 0) -> Date {
        let day = cal.date(byAdding: .day, value: dayOffset, to: cal.startOfDay(for: now))!
        return cal.date(byAdding: .minute, value: hour * 60 + minute, to: day)!
    }

    func episode(_ start: Date, seconds: Double, intense: Bool = false, label: EpisodeLabel? = nil, id: UUID = UUID()) -> ScratchEpisode {
        ScratchEpisode(id: id, start: start, end: start.addingTimeInterval(seconds), meanHz: 4, meanRMS: intense ? 0.4 : 0.2,
                       intense: intense, source: .live, label: label)
    }

    @Test func addsMinutesToTheHourAndCounts() {
        var d = DemoData.make(today: now, calendar: cal)
        let before = d.today!
        let added = EpisodeMerge.apply([episode(at(3, 10), seconds: 120, intense: true)], to: &d, calendar: cal)
        #expect(added == 1)
        #expect(abs(d.today!.scratchMinutesByHour[3] - before.scratchMinutesByHour[3] - 2) < 0.02)
        #expect(d.today!.episodeCount == before.episodeCount + 1)
        #expect(d.today!.intenseCount == before.intenseCount + 1)
        #expect(d.episodes.contains { cal.isDate($0.start, equalTo: at(3, 10), toGranularity: .second) })
    }

    @Test func splitsAcrossAnHour() {
        var d = DemoData.make(today: now, calendar: cal)
        let before = d.today!.scratchMinutesByHour
        EpisodeMerge.apply([episode(at(4, 59), seconds: 120)], to: &d, calendar: cal)
        #expect(abs(d.today!.scratchMinutesByHour[4] - before[4] - 1) < 0.02)
        #expect(abs(d.today!.scratchMinutesByHour[5] - before[5] - 1) < 0.02)
    }

    @Test func sameIdTwiceCountsOnce() {
        var d = DemoData.make(today: now, calendar: cal)
        let before = d.today!
        let e = episode(at(2, 0), seconds: 60)
        EpisodeMerge.apply([e], to: &d, calendar: cal)
        let again = EpisodeMerge.apply([e], to: &d, calendar: cal)
        #expect(again == 0)
        #expect(d.today!.episodeCount == before.episodeCount + 1)
        #expect(abs(d.today!.scratchMinutes - before.scratchMinutes - 1) < 0.02)
    }

    @Test func aLaterNoTakesItBackOut() {
        var d = DemoData.make(today: now, calendar: cal)
        let before = d.today!
        let id = UUID()
        EpisodeMerge.apply([episode(at(1, 30), seconds: 90, intense: true, id: id)], to: &d, calendar: cal)
        EpisodeMerge.apply([episode(at(1, 30), seconds: 90, intense: true, label: .rejected, id: id)], to: &d, calendar: cal)
        #expect(d.today!.episodeCount == before.episodeCount)
        #expect(d.today!.intenseCount == before.intenseCount)
        #expect(abs(d.today!.scratchMinutes - before.scratchMinutes) < 0.02)
        #expect(!d.episodes.contains { $0.id == id })
    }

    @Test func yesterdayLandsOnYesterday() {
        var d = DemoData.make(today: now, calendar: cal)
        let i = d.days.count - 2
        let before = d.days[i]
        EpisodeMerge.apply([episode(at(23, 0, dayOffset: -1), seconds: 60)], to: &d, calendar: cal)
        #expect(d.days[i].episodeCount == before.episodeCount + 1)
        #expect(d.today!.episodeCount == DemoData.make(today: now, calendar: cal).today!.episodeCount)
    }

    @Test func outsideTheWindowIsIgnored() {
        var d = DemoData.make(today: now, calendar: cal)
        let added = EpisodeMerge.apply([episode(at(3, 0, dayOffset: -40), seconds: 60)], to: &d, calendar: cal)
        #expect(added == 0)
    }

    @Test func contractPayloadRoundTrips() throws {
        // The watch sends JSONEncoder().encode([ScratchEpisode]) with default settings.
        let sent = [episode(at(3, 0), seconds: 75, intense: true, label: .confirmed)]
        let data = try JSONEncoder().encode(sent)
        let received = try JSONDecoder().decode([ScratchEpisode].self, from: data)
        #expect(received == sent)
    }
}
