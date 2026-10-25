import Foundation
import Testing
@testable import EczemaKit

/// The key facts of the approved demo scenario (SCENARIO-MI.md): four flares, each starting the night after a
/// new product arrived; methylisothiazolinone (MI) is in every flare product and in nothing he tolerates.
/// Claude has to find this from the tools; the app never says it.
@Suite struct ScenarioMITests {
    let cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "America/Los_Angeles")!; return c }()
    /// Saturday, October 24, 2026, 3 PM in Berkeley (the first demo day).
    var now: Date { cal.date(from: DateComponents(year: 2026, month: 10, day: 24, hour: 15))! }
    var orders: [StageStory.Order] { StageStory.orders(now: now, calendar: cal) }

    static let mi = "Methylisothiazolinone"
    static func hasMI(_ o: StageStory.Order) -> Bool { o.ingredients?.contains(mi) == true }

    @Test func miIsInExactlyTheFourFlareProducts() {
        let withMI = orders.filter(Self.hasMI).map(\.item)
        // The four flare products, and the one exception: the Brightwell lotion (Sep 27), never opened, no flare.
        #expect(withMI == [StageStory.Product.summitShampoo.item, StageStory.Product.lumenHandSoap.item,
                           StageStory.Product.brightwellLotion.item,
                           StageStory.Product.freshMeadowDetergent.item, StageStory.bodyWashItem])
        // Each flare has one product with MI among its new things.
        for flare in StageHistory.flares {
            #expect(flare.items.filter { item in orders.contains { $0.item == item && Self.hasMI($0) } }.count == 1, "\(flare.nights)")
        }
        // Nothing tolerated has it (nor its sister preservative): the repeat purchases and every new thing
        // that didn't come before a flare.
        let flareItems = Set(StageHistory.flares.flatMap(\.items))
        for o in orders where !flareItems.contains(o.item) && o.item != StageStory.Product.brightwellLotion.item {
            #expect(!(o.ingredients ?? []).contains { $0.lowercased().contains("isothiazolinone") }, "\(o.item)")
        }
        #expect(orders.filter { $0.boughtBefore && $0.ingredients != nil }.allSatisfy { !Self.hasMI($0) })
    }

    @Test func theOtherSuspectsFailHonestly() throws {
        let item = { (name: String) in self.orders.last { $0.item == name } }
        // No fragrance in the "fragrance-free" body wash.
        #expect(!StageStory.bodyWashIngredients.contains { $0.lowercased().contains("fragrance") || $0.lowercased().contains("parfum") })
        #expect(StageStory.bodyWashItem.contains("Fragrance-Free"))
        // Fragrance and limonene in the deodorant he uses daily; fragrance, SLS and betaine in his usual shampoo.
        let deodorant = try #require(item(StageStory.Product.alderPineDeodorant.item)?.ingredients)
        #expect(deodorant.contains("Fragrance (Parfum)") && deodorant.contains("Limonene"))
        let shampoo = try #require(item(StageStory.Product.riverstoneShampoo.item)?.ingredients)
        #expect(["Fragrance (Parfum)", "Sodium Laureth Sulfate", "Cocamidopropyl Betaine"].allSatisfy(shampoo.contains))
        // SLS in his usual detergent and hand soap too.
        for name in [StageStory.Product.evercleanDetergent.item, StageStory.Product.willowHandSoap.item] {
            #expect(item(name)?.ingredients?.contains("Sodium Laureth Sulfate") == true, "\(name)")
            #expect(item(name)?.boughtBefore == true)
        }
        // Wool: the socks after flare 3 were fine.
        #expect(item(StageStory.Product.darnToughSocks.item)?.material?.contains("wool") == true)
        #expect((6...9).allSatisfy { !StageHistory.night($0).flare })
        // Stress: HRV dips 6–8 ms through the mid-September exam week, its last (calm) night too.
        for i in StageHistory.examWeek {
            let dip = StageStory.usualHrvMs - StageStory.hrv(i)
            #expect((4...14).contains(dip), "night \(i): \(dip) ms")
        }
        #expect(StageHistory.night(-23).minutes <= 13)
        // Travel: only the first flare.
        #expect(StageHistory.nights.filter(\.trip).map(\.id) == Array(-47...(-44)))
    }

    @Test func eachFlareStartsTheNightAfterItsOrder() throws {
        for flare in StageHistory.flares {
            for name in flare.items {
                let order = try #require(orders.first { $0.item == name })
                #expect(!order.boughtBefore, "\(name)")
                #expect(order.night == flare.nights.lowerBound - 1, "\(name)")
                let next = cal.date(byAdding: .day, value: 1, to: order.date)!
                #expect(cal.isDate(next, inSameDayAs: StageStory.nightDate(flare.nights.lowerBound, now: now, calendar: cal)), "\(name)")
            }
            // Above usual on every flare night, and not the night before.
            #expect(flare.nights.allSatisfy { StageHistory.night($0).minutes > StageStory.usual })
            #expect(StageHistory.night(flare.orderedNight).minutes <= StageStory.usual + 1)
        }
    }

    @Test func toolsReturnUpTo74Nights() throws {
        func count(_ name: String, _ key: String, _ args: [String: Any]) -> Int? {
            (StageStory.runTool(name: name, arguments: args, now: now, calendar: cal)[key] as? [Any])?.count
        }
        #expect(StageStory.toolMaxNights == 74)
        for n in [74, 120] {
            #expect(count("scratch_history", "nights", ["nights": n]) == 74)
            #expect(count("weather_history", "days", ["days": n]) == 74)
            #expect(count("sleep_history", "nights", ["nights": n]) == 74)
        }
        #expect(count("scratch_history", "nights", [:]) == 14)
        let scratch = try #require(StageStory.runTool(name: "scratch_history", arguments: ["nights": 74], now: now, calendar: cal)["nights"] as? [[String: Any]])
        #expect(scratch.first?["night_of"] as? String == "2026-08-11" && scratch.last?["night_of"] as? String == "2026-10-23")
        #expect(scratch.compactMap { $0["scratch_minutes"] as? Int } == StageHistory.nights.map(\.minutes))
        let sleep = try #require(StageStory.runTool(name: "sleep_history", arguments: ["nights": 74], now: now, calendar: cal)["nights"] as? [[String: Any]])
        #expect(sleep.compactMap { $0["hrv_ms"] as? Int } == StageHistory.nightIDs.map(StageStory.hrv))
        #expect(count("order_history", "orders", ["days": 120]) == 30)
    }

    /// With `ET_TOOLS_DUMP=<path>` in the environment, writes every data tool's full output for today =
    /// Saturday, Oct 24, 2026 to that file (for testing the chat server's MI prompt):
    /// `{"today": "...", "scratch_history": {...}, "order_history": {...}, ...}`.
    @Test func dumpsTheToolsForTheChatServer() throws {
        guard let path = ProcessInfo.processInfo.environment["ET_TOOLS_DUMP"], !path.isEmpty else { return }
        let calls: [(String, String)] = [("scratch_history", #"{"nights":74}"#), ("order_history", #"{"days":120}"#),
                                         ("weather_history", #"{"days":74}"#), ("calendar_events", #"{"days":120}"#),
                                         ("sleep_history", #"{"nights":74}"#)]
        var text = #"{"today":"\#(StageStory.todayLong(now: now, calendar: cal))""#
        for (name, args) in calls {
            text += #","\#(name)":"# + StageStory.runToolJSON(name: name, argumentsJSON: args, now: now, calendar: cal)
        }
        text += "}"
        #expect((try? JSONSerialization.jsonObject(with: Data(text.utf8))) is [String: Any])
        try text.write(toFile: path, atomically: true, encoding: .utf8)
    }
}
