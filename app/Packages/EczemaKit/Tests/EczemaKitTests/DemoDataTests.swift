import Foundation
import Testing
@testable import EczemaKit

@Suite struct DemoDataTests {
    let cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "America/Los_Angeles")!; return c }()
    let now: Date = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return c.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 23))! }()

    @Test func flareStory() {
        let d = DemoData.make(today: now, calendar: cal)
        #expect(d.days.count == 14)
        #expect(d.days.allSatisfy { $0.scratchMinutesByHour.count == 24 })
        #expect(abs(d.today!.scratchMinutes - 47) < 1.5)
        #expect(d.todayRatio > 3.5)
        #expect(d.caseFile?.suspects.first?.kind == .newProduct)
        #expect(d.experiment == nil)
        #expect(d.today!.worstHour.map { (1...4).contains($0) } == true)
        #expect(d.days[DemoData.bodyWashDay].exposures.contains { $0.kind == .newProduct })
        #expect(!d.days[DemoData.bodyWashDay - 1].exposures.contains { $0.kind == .newProduct })
        #expect(d.days.last!.intenseCount > 0)
    }

    @Test func experimentStory() {
        let d = DemoData.make(today: now, experimentDay: 6, calendar: cal)
        #expect(d.days.count == 20)
        #expect(d.experiment?.status == .running)
        #expect(d.experimentDays(calendar: cal).count == 6)
        #expect(!d.today!.exposures.contains { $0.kind == .newProduct })
        let done = DemoData.make(today: now, experimentDay: 10, calendar: cal)
        #expect(done.experiment?.status == .confirmed)
    }

    @Test func deterministic() {
        #expect(DemoData.make(today: now, calendar: cal).days.map(\.scratchMinutesByHour) == DemoData.make(today: now, calendar: cal).days.map(\.scratchMinutesByHour))
    }
}
