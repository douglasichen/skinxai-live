import Foundation
import Testing
@testable import EczemaKit

/// The demo story's "today" always holds last night's flare, whatever the hour (night rehearsals).
@Suite struct StoryRevealTests {
    let cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "America/Los_Angeles")!; return c }()
    func at(_ hour: Int, _ minute: Int = 30) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: hour, minute: minute))!
    }

    @Test func revealHourNeverBeforeSeven() {
        #expect(DemoData.storyRevealHour(at: at(0), calendar: cal) == 7)
        #expect(DemoData.storyRevealHour(at: at(2), calendar: cal) == 7)
        #expect(DemoData.storyRevealHour(at: at(7), calendar: cal) == 7)
        #expect(DemoData.storyRevealHour(at: at(15), calendar: cal) == 15)
        #expect(DemoData.storyRevealHour(at: at(23, 59), calendar: cal) == 23)
    }

    @Test func nightRehearsalShowsTheFlare() {
        for hour in [0, 1, 2, 6] {
            let now = at(hour)
            let d = DemoData.make(today: now, revealThroughHour: DemoData.storyRevealHour(at: now, calendar: cal), calendar: cal)
            let today = d.today!
            #expect(today.worstHour.map { (1...4).contains($0) } == true)
            #expect(today.scratchMinutes > 25, "a flare night, not a calm day (hour \(hour))")
            #expect(d.todayRatio > 2)
            #expect(today.scratchMinutesByHour[8...].allSatisfy { $0 == 0 }, "nothing after 7 am yet")
            // Same night as a morning launch.
            let morning = DemoData.make(today: at(7), calendar: cal)
            #expect(today.scratchMinutesByHour == morning.today!.scratchMinutesByHour)
        }
    }

    @Test func defaultStillCutsAtTheCurrentHour() {
        // Without the parameter nothing changes (the watch and old call sites).
        let d = DemoData.make(today: at(0), calendar: cal)
        #expect(d.today!.scratchMinutesByHour[1...].allSatisfy { $0 == 0 })
        let later = DemoData.make(today: at(17), revealThroughHour: DemoData.storyRevealHour(at: at(17), calendar: cal), calendar: cal)
        #expect(later.days.map(\.scratchMinutesByHour) == DemoData.make(today: at(17), calendar: cal).days.map(\.scratchMinutesByHour))
    }
}
