import Foundation
import Testing
@testable import EczemaKit

/// Berkeley time (the stage, and the simulator the bundled conversation was recorded on).
private let cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "America/Los_Angeles")!; return c }()
private func day(_ d: Int, _ hour: Int = 15, month: Int = 10) -> Date {
    cal.date(from: DateComponents(year: 2026, month: month, day: d, hour: hour))!
}

private func object(_ text: String) -> NSDictionary {
    (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? NSDictionary ?? [:]
}

// MARK: - Moving dates

@Suite struct ChatDateShiftTests {
    func shift(_ text: String, _ days: Int = 1, from reference: Date = day(24)) -> String {
        ChatDateShift.shift(text, by: days, reference: reference, calendar: cal)
    }

    @Test func movesWhatReadsAsADate() {
        #expect(shift("the detergent you reordered on Oct 13 is the same") == "the detergent you reordered on Oct 14 is the same")
        #expect(shift("during midterms and the Oct 19 deadline") == "during midterms and the Oct 20 deadline")
        #expect(shift("It dropped to 29% on Oct 23.") == "It dropped to 29% on Oct 24.")
        #expect(shift("Midterm exams Oct 11–13 · stressful week") == "Midterm exams Oct 12–14 · stressful week")
        #expect(shift("You started it on Tue Oct 20.") == "You started it on Wed Oct 21.")
        #expect(shift("Since Tuesday, October 20, 2026, it rose.") == "Since Wednesday, October 21, 2026, it rose.")
        #expect(shift("first used on the 20th") == "first used on the 21st")
        #expect(shift(#"{"night_of":"2026-10-20","weekday":"Tuesday"}"#) == #"{"night_of":"2026-10-21","weekday":"Wednesday"}"#)
        #expect(shift(#"{"date":"2026-10-11 to 2026-10-13"}"#) == #"{"date":"2026-10-12 to 2026-10-14"}"#)
        #expect(shift("Today is Saturday.") == "Today is Sunday.")
    }

    @Test func acrossMonthsAndYears() {
        #expect(shift("Oct 31") == "Nov 1")
        #expect(shift("October 31st") == "November 1st")
        #expect(shift("Oct 30–31", 1, from: day(31)) == "Oct 31–Nov 1")
        #expect(shift("2026-10-31") == "2026-11-01")
        #expect(shift("Dec 31, 2026", 1, from: day(31, month: 12)) == "Jan 1, 2027")
        #expect(shift("Nov 2", -3, from: day(3, month: 11)) == "Oct 30")
        #expect(shift("the 1st", -1, from: day(2, month: 11)) == "the 31st")
        #expect(shift("Sunday", -1) == "Saturday")
    }

    @Test func leavesTheRestAlone() {
        let untouched = [
            "May I ask where it itches?",
            "the 3rd night in a row",
            "Up 3 nights in a row · last night 41 min (usual 12)",
            "Brightwell Ocean Breeze Body Wash, 18 fl oz",
            "Midterm exams (CS 61B, Math 54)",
            "Oct 2026",
            "Go back to your old body wash for 5 nights.",
            "toolu_01CZFkpCZ4y9S7r9zocSzWAh",
            "the 2nd of those questions",
        ]
        for text in untouched { #expect(shift(text) == text) }
        #expect(shift("Oct 20 - 3 nights later") == "Oct 21 - 3 nights later")
        #expect(shift("Oct 20", 0) == "Oct 20")
    }
}

// MARK: - The conversation the app ships with

@Suite struct BundledChatTests {
    @Test func shipsACompleteConversationWithClaude() throws {
        let t = try #require(ChatArchive.bundled)
        #expect(t.model.hasPrefix("anthropic/"))
        #expect(t.isComplete)
        let calls = t.messages.flatMap(\.toolCalls)
        // The MI story: Claude asks only what the data can't tell (one or two questions).
        #expect((1...2).contains(calls.filter { $0.name == ChatTools.question }.count))
        #expect(calls.filter { $0.name == ChatTools.conclusion }.count == 1)
        // Every call has its result, so the replay never waits on the network.
        let results = t.toolResults
        #expect(calls.allSatisfy { results[$0.id] != nil })
        #expect(t.latencies.count == t.messages.filter { $0.role == .assistant }.count)
    }

    /// The demo cache follows the recording while the question and the answers match, and lets go when they don't.
    @Test func cacheFollowsTheRecordingOnly() throws {
        let t = try #require(ChatArchive.bundled)
        let ask = t.messages[0].content
        #expect(t.cachedReply(after: [.user(ask)]) == t.messages[1])
        #expect(t.cachedReply(after: [.user(ask.uppercased() + "  ")]) == t.messages[1])
        #expect(t.cachedReply(after: [.user("How did I sleep this week?")]) == nil)
        #expect(t.cachedReply(after: []) == nil)
        // Every assistant reply comes back when the conversation is the recording up to it.
        for (i, m) in t.messages.enumerated() where m.role == .assistant && i > 0 {
            #expect(t.cachedReply(after: Array(t.messages[..<i])) == m)
        }
        // A different answer to Claude's question goes live.
        let qi = try #require(t.messages.firstIndex { $0.role == .tool && ($0.content.contains("\"answer\"")) })
        var other = Array(t.messages[...qi])
        other[qi] = .tool(other[qi].toolCallID ?? "", ChatTools.answerResult("Yes, regularly"))
        #expect(t.cachedReply(after: other) == nil)
        // Data results may differ (another day): still cached.
        if let di = t.messages.firstIndex(where: { $0.role == .tool && !$0.content.contains("\"answer\"") && !$0.content.contains("shown") }) {
            var moved = Array(t.messages[...di]); moved[di] = .tool(moved[di].toolCallID ?? "", "{}")
            #expect(t.cachedReply(after: moved) == t.messages[di + 1] || t.messages[di + 1].role != .assistant)
        }
        // The end of the recording: nothing more.
        #expect(t.cachedReply(after: t.messages) == nil)
    }

    /// Moved to another day, the saved tool results are exactly what the story's tools say on that day: the
    /// replay's dates match Today and Trends.
    @Test func movedToAnotherDayItMatchesTheStoryOfThatDay() throws {
        let t = try #require(ChatArchive.bundled)
        for target in [day(25, 9), day(26, 20), day(31, 7)] {
            let moved = t.moved(toDayOf: target, calendar: cal)
            #expect(cal.isDate(moved.startedAt, inSameDayAs: target))
            let results = moved.toolResults
            for call in moved.messages.flatMap(\.toolCalls) where ChatTools.kind(of: call.name) == .data {
                let saved = try #require(results[call.id])
                let fresh = StageStory.runToolJSON(name: call.name, argumentsJSON: call.arguments, now: target, calendar: cal)
                #expect(object(saved) == object(fresh), "\(call.name) on \(StageStory.iso(target, calendar: cal))")
            }
            // The cards land on the same nights, and Claude's words name that day's dates.
            let timeline = try #require(moved.messages.flatMap(\.toolCalls).first { $0.name == ChatTools.timeline })
            // One marker per flare: the day each new product was ordered (shampoo, hand soap, detergent sample, body wash).
            #expect(ChatTimeline(arguments: timeline.argumentsObject, now: moved.startedAt, calendar: cal).markers.map(\.night) == [-47, -28, -5, 9])
            let product = try #require(moved.messages.flatMap(\.toolCalls).first { $0.name == ChatTools.product })
            let card = ChatProduct(arguments: product.argumentsObject, now: moved.startedAt, calendar: cal)
            #expect(card.firstTime && card.title == StageStory.bodyWashItem)
            #expect(card.ingredients.filter { !$0.flagged }.map(\.name).allSatisfy(StageStory.bodyWashIngredients.contains))
            let order = StageStory.bodyWashOrder(now: target, calendar: cal)
            #expect(card.ordered == "Ordered \(StageStory.weekday(order.date, short: true, calendar: cal)) \(StageStory.monthDay(order.date, calendar: cal))")
            // The finding is Claude's own words: the shared preservative.
            #expect(moved.messages.contains { $0.content.localizedCaseInsensitiveContains("methylisothiazolinone") })
        }
        // Replayed the day it was recorded, nothing moves.
        #expect(t.moved(toDayOf: t.startedAt.addingTimeInterval(3600), calendar: cal) == t)
    }
}

// MARK: - Keeping and choosing the conversation to replay

@Suite struct ChatArchiveTests {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("chat-archive-\(UUID().uuidString)")

    func transcript(_ model: String = "anthropic/claude-sonnet-5.5", at start: Date = day(24), complete: Bool) -> ChatTranscript {
        var calls = [ChatToolCall(id: "a", name: ChatTools.timeline), ChatToolCall(id: "b", name: ChatTools.product),
                     ChatToolCall(id: "c", name: ChatTools.question), ChatToolCall(id: "d", name: ChatTools.question)]
        let ruled: [[String: String]] = complete ? [["item": "Detergent", "reason": "Same one."], ["item": "Stress", "reason": "Calm then."]] : []
        calls.append(ChatToolCall(id: "e", name: ChatTools.conclusion, arguments: ChatWire.json(["cause": "The new body wash", "ruled_out": ruled])))
        let messages: [ChatMessage] = [.user("Why?"), ChatMessage(role: .assistant, content: "", toolCalls: calls)]
            + calls.map { .tool($0.id, ChatTools.shownResult) }
        return ChatTranscript(model: model, startedAt: start, messages: messages, latencies: [900])
    }

    @Test func completeness() {
        #expect(transcript(complete: true).isComplete)
        #expect(!transcript(complete: false).isComplete)
        #expect(!ChatTranscript(model: "m", startedAt: day(24), messages: [.user("hi")], latencies: []).isComplete)
    }

    @Test func aLesserConversationNeverReplacesAComplete() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let good = transcript(at: day(24, 10), complete: true)
        let worse = transcript(at: day(24, 11), complete: false)
        let better = transcript(at: day(24, 12), complete: true)
        #expect(try ChatArchive.keep(worse, in: dir), "nothing saved yet: anything is kept")
        #expect(try ChatArchive.keep(good, in: dir))
        #expect(try !ChatArchive.keep(worse, in: dir))
        #expect(ChatArchive.load(in: dir) == good)
        #expect(try ChatArchive.keep(better, in: dir))
        #expect(ChatArchive.load(in: dir) == better)
    }

    @Test func theShippedConversationStandsInForMissingOrLesserOnes() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let shipped = transcript(at: day(20), complete: true)
        #expect(ChatArchive.load(in: dir, fallback: shipped) == shipped, "a phone with nothing saved")
        #expect(ChatArchive.load(in: dir) == nil)
        let lesser = transcript(at: day(24), complete: false)
        try ChatArchive.save(lesser, in: dir)
        #expect(ChatArchive.load(in: dir, fallback: shipped) == shipped)
        #expect(ChatArchive.load(in: dir) == lesser)
        let complete = transcript("anthropic/claude-opus-5.5", at: day(24, 16), complete: true)
        try ChatArchive.save(complete, in: dir)
        #expect(ChatArchive.load(in: dir, fallback: shipped) == complete)
        // A development model asked for by name still wins.
        let dev = transcript("deepseek/deepseek-v4.1-flash", at: day(24, 17), complete: false)
        try ChatArchive.save(dev, in: dir)
        #expect(ChatArchive.load(preferring: "deepseek/deepseek-v4.1-flash", in: dir, fallback: shipped) == dev)
    }
}

// MARK: - Small rules

@Suite struct ChatSmallRuleTests {
    @Test func atMostEightCallsLikeTheServer() {
        let calls = (0..<11).map { ChatToolCall(id: "c\($0)", name: "scratch_history", arguments: "{}") }
        let tidy = ChatWire.tidy(ChatMessage(role: .assistant, content: "", toolCalls: calls), round: 2)
        #expect(tidy.toolCalls.map(\.id) == (0..<8).map { "c\($0)" })
    }

    @Test func failureReasonsNeverShowACode() {
        #expect(ChatFailure.server(405).reason == "The server had a problem.")
        #expect(ChatFailure.server(0).reason == "The server had a problem.")
        #expect(ChatFailure.unreachable.reason == "Couldn't reach Claude.")
        #expect(ChatFailure.offline.reason == "Your phone is offline.")
    }

    @Test func onlyAPhoneWithoutInternetIsOffline() {
        func failure(_ code: URLError.Code) -> ChatFailure? { ChatClient.failure(for: URLError(code), timeout: 45) as? ChatFailure }
        #expect(failure(.notConnectedToInternet) == .offline)
        #expect(failure(.dataNotAllowed) == .offline)
        #expect(failure(.cannotConnectToHost) == .unreachable)
        #expect(failure(.cannotFindHost) == .unreachable)
        #expect(failure(.dnsLookupFailed) == .unreachable)
        #expect(failure(.networkConnectionLost) == .unreachable)
        #expect(failure(.secureConnectionFailed) == .unreachable)
        #expect(failure(.timedOut) == .timedOut(45))
        #expect(failure(.badServerResponse) == .server(0))
    }
}
