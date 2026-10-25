import Foundation
import Testing
@testable import EczemaKit

/// Berkeley time on Saturday, October 24, 2026 (the first demo day).
private let cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "America/Los_Angeles")!; return c }()
private let now = cal.date(from: DateComponents(year: 2026, month: 10, day: 24, hour: 15))!

private func object(_ data: Data) -> [String: Any] {
    (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
}

// MARK: - Wire

@Suite struct ChatWireTests {
    @Test func requestBodyCarriesTodayAndMessagesAndNoModel() throws {
        let messages: [ChatMessage] = [
            .user("Why has my eczema been so bad the last few nights?"),
            ChatMessage(role: .assistant, content: "Let me look.", toolCalls: [ChatToolCall(id: "c1", name: "scratch_history", arguments: #"{"nights":14}"#)]),
            .tool("c1", #"{"usual_minutes_per_night":12}"#),
        ]
        let body = object(try ChatWire.body(model: nil, today: "Saturday, October 24, 2026", messages: messages))
        #expect(body["model"] == nil)
        #expect(body["today"] as? String == "Saturday, October 24, 2026")
        #expect(body["story"] as? String == "mi")
        let sent = try #require(body["messages"] as? [[String: Any]])
        #expect(sent.count == 3)
        #expect(sent[0]["role"] as? String == "user" && sent[0]["tool_calls"] == nil && sent[0]["tool_call_id"] == nil)
        let call = try #require((sent[1]["tool_calls"] as? [[String: Any]])?.first)
        #expect(call["id"] as? String == "c1" && call["type"] as? String == "function")
        let function = try #require(call["function"] as? [String: Any])
        #expect(function["name"] as? String == "scratch_history" && function["arguments"] as? String == #"{"nights":14}"#)
        #expect(sent[2]["role"] as? String == "tool" && sent[2]["tool_call_id"] as? String == "c1")
        #expect(sent[2]["content"] as? String == #"{"usual_minutes_per_night":12}"#)
    }

    /// The server picks the MI scenario's prompt from `story`: every request names it, a development one too.
    @Test func everyRequestNamesTheStory() throws {
        #expect(ChatWire.story == "mi")
        for model in [nil, "deepseek/deepseek-v4.1-flash", " "] {
            let body = object(try ChatWire.body(model: model, today: "x", messages: [.user("hi")]))
            #expect(body["story"] as? String == "mi")
            #expect(Set(body.keys).subtracting(["model"]) == ["today", "story", "messages"])
        }
    }

    @Test func modelOnlyWhenGiven() throws {
        let dev = object(try ChatWire.body(model: "deepseek/deepseek-v4.1-flash", today: "x", messages: [.user("hi")]))
        #expect(dev["model"] as? String == "deepseek/deepseek-v4.1-flash")
        let blank = object(try ChatWire.body(model: "  ", today: "x", messages: [.user("hi")]))
        #expect(blank["model"] == nil)
    }

    @Test func readsAReplyAndTidiesItsCalls() throws {
        let json = #"""
        {"model":"anthropic/claude-sonnet-5.5","message":{"role":"assistant","content":"Let me pull up your data.\n\n","tool_calls":[
          {"type":"function","index":0,"id":"toolu_1","function":{"name":"scratch_history","arguments":"{\"nights\": 14}"}},
          {"type":"function","function":{"name":"order_history","arguments":{"days":120}}},
          {"type":"function","id":"toolu_3","function":{"name":"weather_history","arguments":"{not json"}},
          {"type":"function","id":"toolu_4","function":{"name":"","arguments":"{}"}}
        ]}}
        """#
        let reply = try ChatWire.reply(from: Data(json.utf8), status: 200, round: 3)
        #expect(reply.model == "anthropic/claude-sonnet-5.5")
        #expect(reply.message.role == .assistant)
        #expect(reply.message.content == "Let me pull up your data.\n\n")
        let calls = reply.message.toolCalls
        #expect(calls.map(\.name) == ["scratch_history", "order_history", "weather_history"])
        #expect(calls.map(\.id) == ["toolu_1", "call_3_1", "toolu_3"])
        #expect(calls[0].arguments == #"{"nights":14}"#)
        #expect(calls[1].arguments == #"{"days":120}"#)
        #expect(calls[2].arguments == "{}")
    }

    @Test func replyWithoutToolsHasNone() throws {
        let reply = try ChatWire.reply(from: Data(#"{"model":"m","message":{"content":"Done.","tool_calls":[]}}"#.utf8), status: 200, round: 0)
        #expect(reply.message.toolCalls.isEmpty && reply.message.content == "Done.")
        // Encoded back without a tool_calls key.
        let encoded = object(try JSONEncoder().encode(reply.message))
        #expect(encoded["tool_calls"] == nil && encoded["content"] as? String == "Done.")
    }

    @Test func serverErrorsAndGarbage() {
        #expect(throws: ChatFailure.server(429)) {
            try ChatWire.reply(from: Data(#"{"error":"no reply","status":429}"#.utf8), status: 502, round: 0)
        }
        #expect(throws: ChatFailure.server(503)) {
            try ChatWire.reply(from: Data(#"{"error":"no key"}"#.utf8), status: 503, round: 0)
        }
        #expect(throws: ChatFailure.server(502)) {
            try ChatWire.reply(from: Data("<html>Bad gateway</html>".utf8), status: 502, round: 0)
        }
        #expect(throws: ChatFailure.badReply) {
            try ChatWire.reply(from: Data("not json".utf8), status: 200, round: 0)
        }
        #expect(throws: ChatFailure.badReply) {
            try ChatWire.reply(from: Data(#"{"model":"m"}"#.utf8), status: 200, round: 0)
        }
    }

    @Test func messagesRoundTrip() throws {
        let m = ChatMessage(role: .assistant, content: "Hi", toolCalls: [ChatToolCall(id: "a", name: "ask_user", arguments: #"{"question":"Q?"}"#)])
        let back = try JSONDecoder().decode(ChatMessage.self, from: JSONEncoder().encode(m))
        #expect(back == m)
        let tool = try JSONDecoder().decode(ChatMessage.self, from: Data(#"{"role":"tool","content":null,"tool_call_id":"a"}"#.utf8))
        #expect(tool.content == "" && tool.toolCallID == "a" && tool.toolCalls.isEmpty)
    }
}

// MARK: - Client (a stubbed server)

final class ChatStub: URLProtocol {
    /// Status and body per request, in order; status -1 fails with a timeout, -2 with "offline".
    static var replies: [(Int, String)] = []
    static var bodies: [[String: Any]] = []
    static let lock = NSLock()

    static func reset(_ replies: [(Int, String)]) {
        lock.lock(); defer { lock.unlock() }
        self.replies = replies
        bodies = []
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.bodies.append(object(Self.body(of: request)))
        let (status, text) = Self.replies.isEmpty ? (500, "{}") : Self.replies.removeFirst()
        Self.lock.unlock()
        if status < 0 {
            client?.urlProtocol(self, didFailWithError: URLError(status == -1 ? .timedOut : .notConnectedToInternet))
            return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
                                       headerFields: ["content-type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(text.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    static func body(of request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open(); defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let n = stream.read(&buffer, maxLength: buffer.count)
            if n <= 0 { break }
            data.append(buffer, count: n)
        }
        return data
    }

    static var session: URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ChatStub.self]
        return URLSession(configuration: config)
    }
}

@Suite(.serialized) struct ChatClientTests {
    let ok = #"{"model":"anthropic/claude-sonnet-5.5","message":{"role":"assistant","content":"Hello.","tool_calls":[]}}"#

    @Test func sendsTheConversationAndReadsTheReply() async throws {
        ChatStub.reset([(200, ok)])
        let client = ChatClient(session: ChatStub.session)
        let reply = try await client.reply(to: [.user("hi")], today: "Saturday, October 24, 2026")
        #expect(reply.message.content == "Hello." && reply.model == "anthropic/claude-sonnet-5.5")
        let body = try #require(ChatStub.bodies.first)
        #expect(body["model"] == nil, "the app never names a model unless asked to for development")
        #expect(body["today"] as? String == "Saturday, October 24, 2026")
        #expect(body["story"] as? String == "mi")
        #expect((body["messages"] as? [[String: Any]])?.first?["content"] as? String == "hi")
    }

    @Test func devModelIsSent() async throws {
        ChatStub.reset([(200, ok)])
        _ = try await ChatClient(model: "deepseek/deepseek-v4.1-flash", session: ChatStub.session).reply(to: [.user("hi")], today: "t")
        #expect(ChatStub.bodies.first?["model"] as? String == "deepseek/deepseek-v4.1-flash")
    }

    @Test func emptyReplyIsAFailure() async {
        ChatStub.reset([(200, #"{"message":{"content":"  ","tool_calls":[]}}"#)])
        await #expect(throws: ChatFailure.empty) {
            try await ChatClient(session: ChatStub.session).reply(to: [.user("hi")], today: "t")
        }
    }

    @Test func retriesOnce() async throws {
        ChatStub.reset([(502, #"{"error":"chat failed"}"#), (200, ok)])
        let reply = try await ChatClient(session: ChatStub.session).replyWithRetry(to: [.user("hi")], today: "t", pause: 0)
        #expect(reply.message.content == "Hello.")
        #expect(ChatStub.bodies.count == 2)
    }

    @Test func secondFailureIsThrown() async {
        ChatStub.reset([(-2, ""), (-1, ""), (200, ok)])
        await #expect(throws: ChatFailure.timedOut(45)) {
            try await ChatClient(session: ChatStub.session).replyWithRetry(to: [.user("hi")], today: "t", pause: 0)
        }
        #expect(ChatStub.bodies.count == 2, "one automatic retry, no more")
    }

    @Test func offlineIsNamed() async {
        ChatStub.reset([(-2, "")])
        await #expect(throws: ChatFailure.offline) {
            try await ChatClient(session: ChatStub.session).reply(to: [.user("hi")], today: "t")
        }
    }
}

// MARK: - Tools

@Suite struct ChatToolTests {
    func summary(_ name: String, _ args: String = "{}") -> String {
        ChatTools.summary(name: name, resultJSON: StageStory.runToolJSON(name: name, argumentsJSON: args, now: now, calendar: cal), calendar: cal)
    }

    @Test func kinds() {
        for name in StageStory.dataTools { #expect(ChatTools.kind(of: name) == .data) }
        #expect(ChatTools.kind(of: "show_timeline") == .display)
        #expect(ChatTools.kind(of: "show_product") == .display)
        #expect(ChatTools.kind(of: "show_conclusion") == .display)
        #expect(ChatTools.kind(of: "ask_user") == .question)
        #expect(ChatTools.kind(of: "delete_everything") == .unknown)
        #expect(ChatTools.unknownResult("x") == #"{"error":"There is no tool called x."}"#)
        #expect(ChatTools.shownResult == #"{"shown":true}"#)
        #expect(ChatTools.answerResult("No, same one") == #"{"answer":"No, same one"}"#)
        #expect(ChatTools.answer(fromResult: #"{"answer":"Hands"}"#) == "Hands")
    }

    @Test func rowNames() {
        #expect(ChatTools.row(name: "scratch_history", argumentsJSON: #"{"nights":14}"#).title == "Scratch history · 14 nights")
        #expect(ChatTools.row(name: "scratch_history", argumentsJSON: #"{"nights":1}"#).title == "Scratch history · 1 night")
        #expect(ChatTools.row(name: "scratch_history", argumentsJSON: "{}").title == "Scratch history · 14 nights")
        #expect(ChatTools.row(name: "scratch_history", argumentsJSON: #"{"nights":30}"#).title == "Scratch history · 30 nights")
        #expect(ChatTools.row(name: "order_history", argumentsJSON: #"{"days":120}"#).title == "Amazon orders · 120 days")
        #expect(ChatTools.row(name: "order_history", argumentsJSON: #"{"days":"30"}"#).title == "Amazon orders · 30 days")
        #expect(ChatTools.row(name: "weather_history", argumentsJSON: "{}").title == "Weather · Berkeley")
        #expect(ChatTools.row(name: "calendar_events", argumentsJSON: "{}").title == "Calendar")
        #expect(ChatTools.row(name: "sleep_history", argumentsJSON: "{}").title == "Sleep · Apple Health")
    }

    @Test func summariesComeFromTheResults() {
        #expect(summary("scratch_history", #"{"nights":14}"#) == "Up 3 nights in a row · last night 41 min (usual 12)")
        #expect(summary("scratch_history", #"{"nights":1}"#) == "Last night 41 min · usual 12")
        #expect(summary("order_history", #"{"days":120}"#) == "30 orders · 6 personal-care items you never bought before")
        #expect(summary("weather_history", #"{"days":14}"#) == "Humidity 46–55% most days · 29% last night")
        #expect(summary("calendar_events") == "Midterm exams Oct 11–13 · stressful week")
        #expect(summary("sleep_history", #"{"nights":7}"#) == "5.1 h last night · woke up 2×")
        #expect(ChatTools.summary(name: "weather_history", resultJSON: #"{"error":"x"}"#) == "Couldn't read this data")
        #expect(ChatTools.summary(name: "order_history", resultJSON: #"{"orders":[]}"#) == "No orders in that time")
    }

    @Test func recentOrdersStillFindTheBodyWash() {
        // The body wash was ordered 5 days ago: a 14-day window has it too.
        let line = summary("order_history", #"{"days":14}"#)
        #expect(line.hasSuffix("1 personal-care item you never bought before"))
    }
}

// MARK: - Cards

@Suite struct ChatCardTests {
    @Test func timelineMarksTheNight() {
        let t = ChatTimeline(arguments: ["marker_date": "2026-10-20", "marker_label": "Started new body wash",
                                         "note": "Scratching rose from that night on."], now: now, calendar: cal)
        #expect(t.marker == StageStory.bodyWashNight)
        #expect(t.label == "Started new body wash" && t.emoji == "🧴")
        #expect(t.note == "Scratching rose from that night on.")
        #expect(t.startLabel == "Oct 10" && t.markerLabel == "Oct 20")
        #expect(t.minutes == StageStory.nights && t.hot.filter { $0 }.count == 3 && t.hot.last == true)
        #expect(t.firstNight == 0 && t.markers.count == 1 && t.index(of: 10) == 10)
    }

    @Test func timelineWithSeveralMarkers() throws {
        let markers: [Any] = [
            ["date": "2026-10-19", "label": "Brightwell body wash"],
            ["date": "2026-08-24", "label": "Summit Peak shampoo"],
            ["date": "2026-09-12", "label": "Lumen hand soap"],
            ["date": "2026-10-05", "label": "FreshMeadow detergent"],
            ["date": "2026-10-05", "label": "Lambswool sweater"],
            ["date": "2026-07-01", "label": "Too early"],
            ["label": "No date"],
            "not a marker",
        ]
        let t = ChatTimeline(arguments: ["markers": markers, "note": "Four flares."], now: now, calendar: cal)
        // Oldest first, one per item; same-night ones keep Claude's order; dates outside the 74 nights dropped.
        #expect(t.markers.map(\.night) == [-47, -28, -5, -5, 9])
        #expect(t.markers.map(\.label) == ["Summit Peak shampoo", "Lumen hand soap", "FreshMeadow detergent", "Lambswool sweater",
                                           "Brightwell body wash"])
        #expect(t.markers.map(\.dateLabel) == ["Aug 24", "Sep 12", "Oct 5", "Oct 5", "Oct 19"])
        #expect(t.markers.map(\.emoji) == ["🧴", "✋", "🧺", "🧶", "🧴"])
        // From 3 nights before the earliest marker to last night.
        #expect(t.firstNight == -50 && t.nightCount == 64 && t.startLabel == "Aug 21")
        #expect(t.minutes == (-50...13).map { StageHistory.night($0).minutes })
        #expect(t.hot.count == 64 && t.hot.last == true)
        #expect(t.index(of: -47) == 3 && t.index(of: 13) == 63 && t.index(of: -51) == nil)
        // The one-marker fields read the first (oldest) marker.
        #expect(t.marker == -47 && t.label == "Summit Peak shampoo" && t.markerLabel == "Aug 24")
        #expect(t.note == "Four flares.")
        // marker_date still works next to markers, and duplicates go.
        let both = ChatTimeline(arguments: ["marker_date": "2026-10-20", "marker_label": "Body wash",
                                            "markers": [["date": "2026-10-20", "label": "Body wash"], ["date": "2026-08-11", "label": "First night"]]],
                                now: now, calendar: cal)
        #expect(both.markers.map(\.night) == [-60, 10] && both.firstNight == -60 && both.nightCount == 74)
        // At most six markers.
        let many = (1...9).map { ["date": "2026-09-0\($0)", "label": "M\($0)"] }
        #expect(ChatTimeline(arguments: ["markers": many], now: now, calendar: cal).markers.count == ChatTimeline.maxMarkers)
    }

    @Test func timelineSurvivesOddArguments() {
        let t = ChatTimeline(arguments: ["marker_date": "2026-07-01", "marker_label": 7], now: now, calendar: cal)
        #expect(t.marker == nil && t.markerLabel == nil && t.label == "Change" && t.note == nil)
        #expect(t.firstNight == 0 && t.minutes == StageStory.nights)
        let unlabeled = ChatTimeline(arguments: ["marker_date": "2026-09-01", "marker_label": 7], now: now, calendar: cal)
        #expect(unlabeled.marker == -39 && unlabeled.label == "Change" && unlabeled.firstNight == -42)
        let order = ChatTimeline(arguments: ["marker_date": "2026-10-19T00:00:00Z", "marker_label": "Ordered body wash"], now: now, calendar: cal)
        #expect(order.marker == StageStory.bodyWashNight - 1)
    }

    @Test func productMatchesTheOrder() {
        let p = ChatProduct(arguments: ["name": "Body wash", "purchase_date": "2026-10-19",
                                        "flagged_ingredients": ["fragrance", "Methylisothiazolinone (MIT)"]], now: now, calendar: cal)
        #expect(p.title == "Brightwell Sensitive Fragrance-Free Body Wash, 18 fl oz")
        #expect(p.firstTime)
        #expect(p.ordered == "Ordered Mon Oct 19")
        // The label's list, then what Claude flagged that isn't on it.
        #expect(p.ingredients.map(\.name) == StageStory.bodyWashIngredients + ["fragrance"])
        #expect(p.ingredients.filter(\.flagged).map(\.name) == ["Methylisothiazolinone", "fragrance"])
        #expect(p.hasFlags && p.material == nil)
        // Nothing flagged unless Claude flags it.
        let plain = ChatProduct(arguments: ["name": "Body wash"], now: now, calendar: cal)
        #expect(!plain.hasFlags && plain.ingredients.map(\.name) == StageStory.bodyWashIngredients)
    }

    @Test func productByNameAndUnknownFlags() {
        let p = ChatProduct(arguments: ["name": "body wash", "flagged_ingredients": ["Limonene", " "]], now: now, calendar: cal)
        #expect(p.title == StageStory.bodyWashItem && p.firstTime && p.ordered == "Ordered Mon Oct 19")
        #expect(p.ingredients.last == ChatProduct.Ingredient(name: "Limonene", flagged: true))
        let other = ChatProduct(arguments: ["name": "Scented candle"], now: now, calendar: cal)
        #expect(other.title == "Scented candle" && !other.firstTime && other.ordered == nil && other.ingredients.isEmpty)
        // The brand, the full name or part of it: the order's full item name.
        for name in ["Brightwell body wash", "Brightwell Sensitive Fragrance-Free Body Wash", "Fragrance-free body wash",
                     "the new body wash", "Brightwell", "Ocean Breeze body wash"] {
            #expect(ChatProduct(arguments: ["name": name], now: now, calendar: cal).title == StageStory.bodyWashItem)
        }
        let socks = ChatProduct(arguments: ["name": "Wool socks"], now: now, calendar: cal)
        #expect(socks.title == "Darn Tough Merino Wool Socks, 3 pairs" && socks.firstTime)
        #expect(socks.material == "54% merino wool, 43% nylon, 3% spandex" && socks.ingredients.isEmpty)
    }

    @Test func productFindsEveryNewProductByNameWords() {
        func title(_ name: String, _ date: String? = nil) -> String {
            var args: [String: Any] = ["name": name]
            if let date { args["purchase_date"] = date }
            return ChatProduct(arguments: args, now: now, calendar: cal).title
        }
        typealias P = StageStory.Product
        #expect(title("Summit Peak shampoo") == P.summitShampoo.item)
        #expect(title("Mint shampoo") == P.summitShampoo.item)
        #expect(title("travel shampoo") == P.summitShampoo.item)
        #expect(title("Shampoo") == P.summitShampoo.item, "the new one before the one he always buys")
        #expect(title("Riverstone shampoo") == P.riverstoneShampoo.item)
        #expect(title("Shampoo", "2026-09-24") == P.riverstoneShampoo.item)
        #expect(title("Lumen hand soap") == P.lumenHandSoap.item)
        #expect(title("Citrus foaming hand soap") == P.lumenHandSoap.item)
        #expect(title("hand soap") == P.lumenHandSoap.item)
        #expect(title("Willow hand soap") == P.willowHandSoap.item)
        #expect(title("FreshMeadow detergent") == P.freshMeadowDetergent.item)
        #expect(title("detergent trial size") == P.freshMeadowDetergent.item)
        #expect(title("Spring Bloom detergent sample") == P.freshMeadowDetergent.item)
        #expect(title("Everclean detergent") == P.evercleanDetergent.item)
        #expect(title("Wool sweater") == P.northfieldSweater.item)
        #expect(title("Northfield sweater") == P.northfieldSweater.item)
        #expect(title("Mineral sunscreen") == P.coastlineSunscreen.item)
        #expect(title("Cedar deodorant") == P.alderPineDeodorant.item)
        #expect(title("Oat lotion") == P.harborOatLotion.item)
        #expect(title("Memory foam pillow") == P.cloudrestPillow.item)
        #expect(title("Ceramide cream") == P.dermacalmCream.item)
        #expect(title("Hoodie") == P.baylineHoodie.item)
        // By date when the name names nothing: the day's one skin-contact order (a personal-care one first).
        let byDate = ChatProduct(arguments: ["name": "That new thing", "purchase_date": "2026-08-24"], now: now, calendar: cal)
        #expect(byDate.title == "That new thing" && byDate.ingredients.map(\.name) == P.summitShampoo.ingredients)
        let twoThatDay = ChatProduct(arguments: ["name": "That new thing", "purchase_date": "2026-10-05"], now: now, calendar: cal)
        #expect(twoThatDay.ingredients.isEmpty && twoThatDay.material == nil && twoThatDay.ordered == "Ordered Mon Oct 5")
        // The sweater: its material, no ingredients.
        let sweater = ChatProduct(arguments: ["name": "Lambswool sweater"], now: now, calendar: cal)
        #expect(sweater.material == "100% lambswool" && sweater.ingredients.isEmpty && sweater.firstTime)
        #expect(sweater.ordered == "Ordered Mon Oct 5")
        // Repeat purchases aren't "first time".
        #expect(!ChatProduct(arguments: ["name": "Everclean Free & Clear detergent"], now: now, calendar: cal).firstTime)
    }

    @Test func question() {
        let q = ChatQuestion(arguments: ["question": " Did you change your laundry detergent? ", "options": ["No, same one", " Yes ", "", 3, "a", "b"]])
        #expect(q.question == "Did you change your laundry detergent?")
        #expect(q.options == ["No, same one", "Yes", "3", "a"])
        #expect(ChatQuestion(arguments: [:]).question == "Can you tell me more?")
    }

    @Test func conclusion() {
        let c = ChatConclusion(arguments: [
            "cause": "The new body wash", "confidence": "high",
            "ruled_out": [["item": "Laundry detergent", "reason": "Same one for two years."], "Stress", ["reason": "no item"]],
            "next_step": "Go back to your old soap for 5 nights.",
        ])
        #expect(c.cause == "The new body wash" && c.confidence == "High" && c.confidenceFill > 0.7)
        #expect(c.ruledOut == [.init(item: "Laundry detergent", reason: "Same one for two years."), .init(item: "Stress", reason: nil)])
        #expect(c.nextStep == "Go back to your old soap for 5 nights.")
        #expect(ChatConclusion(arguments: ["confidence": "medium"]).confidence == "Medium")
        #expect(ChatConclusion(arguments: ["confidence": "Medium-high"]).confidence == "Medium–high")
        #expect(ChatConclusion(arguments: ["confidence": "low"]).confidence == "Low")
        #expect(ChatConclusion(arguments: [:]).cause == "Not sure yet")
    }
}

// MARK: - Rules, text, saving

@Suite struct ChatRuleTests {
    @Test func nudgeOnlyBeforeTheConclusionAndNotAfterAQuestion() {
        let open: [ChatMessage] = [.user("hi"), ChatMessage(role: .assistant, content: "I'll check your sleep next.")]
        #expect(ChatRules.offersNudge(after: "I'll check your sleep next.", in: open))
        #expect(!ChatRules.offersNudge(after: "Did you change anything?  ", in: open))
        let done = open + [ChatMessage(role: .assistant, content: "", toolCalls: [ChatToolCall(id: "c", name: "show_conclusion")])]
        #expect(ChatRules.concluded(done) && !ChatRules.offersNudge(after: "Take care.", in: done))
        // An offer is answered by "Go ahead"; an open question is not.
        #expect(ChatRules.offersNudge(after: "Your sleep dropped too. Want me to look into what changed a few days back?", in: open))
        #expect(ChatRules.offersNudge(after: "Shall I check your orders?", in: open))
        #expect(!ChatRules.offersNudge(after: "Want me to check? Where does it itch most?", in: open))
        #expect(!ChatRules.offersNudge(after: "Want me to look into it?", in: done))
    }

    @Test func questionShownOnce() {
        let m = ChatMessage(role: .assistant, content: "Got it. Has this week been more stressful than usual?",
                            toolCalls: [ChatToolCall(id: "q", name: "ask_user", arguments: #"{"question":"Has this week been more stressful than usual?","options":["Yes","No"]}"#)])
        #expect(ChatRules.shownText(m) == "Got it.")
        // The model's own wording: another case, a lead-in left dangling.
        func shown(_ text: String, _ question: String) -> String {
            ChatRules.shownText(ChatMessage(role: .assistant, content: text, toolCalls: [
                ChatToolCall(id: "q", name: "ask_user", arguments: ChatWire.json(["question": question, "options": ["Yes", "No"]]))]))
        }
        #expect(shown("Before I settle on that, let me rule out a few other things. First: have you changed your laundry detergent recently?\n\n",
                      "Have you changed your laundry detergent recently?")
                == "Before I settle on that, let me rule out a few other things.")
        #expect(shown("That fits. Last question: where is the itch worst right now?", "Where is the itch worst right now?") == "That fits.")
        #expect(shown("Got it. Next one — has this week been stressful", "Has this week been stressful?") == "Got it.")
        #expect(shown("First: where does it itch?", "Where does it itch?") == "")
        // The question inside a longer sentence: the whole sentence goes, nothing dangles ("Next: for you?").
        #expect(shown("That rules out detergent — your order history shows the same fragrance-free one every month for two years. Next: has this week been more stressful than usual for you?",
                      "Has this week been more stressful than usual?")
                == "That rules out detergent — your order history shows the same fragrance-free one every month for two years.")
        #expect(shown("That fits. Next, I'd like to know: has this week been more stressful than usual?", "Has this week been more stressful than usual?")
                == "That fits.")
        #expect(shown("Your orders agree: same detergent for two years.", "Has this week been stressful?")
                == "Your orders agree: same detergent for two years.")
        // The same question in other words.
        #expect(shown("Before I settle on that, I want to rule out a few other things. Did you change your laundry detergent recently?",
                      "Have you changed your laundry detergent recently?")
                == "Before I settle on that, I want to rule out a few other things.")
        #expect(shown("That rules out detergent. Next: was this week more stressful than usual for you?", "Has this week been more stressful than usual?")
                == "That rules out detergent.")
        // A different question stays.
        #expect(shown("Your scratching rose after the wash. Want me to dig deeper?", "Where is the itch worst?")
                == "Your scratching rose after the wash. Want me to dig deeper?")
        #expect(shown("Did the itch start on your hands?", "Has this week been more stressful than usual?")
                == "Did the itch start on your hands?")
    }

    @Test func richText() {
        let t = ChatText(markdown: "## Plan\nHere is **what I found**:\n\n- first *thing*\n2) second\n\n\n`done`")
        #expect(t.plain == "Plan\nHere is what I found:\n\n• first thing\n2. second\n\ndone")
        #expect(t.runs.filter(\.bold).map(\.text) == ["what I found"])
        #expect(t.wordCount == 12)
        #expect(t.visibleLength(words: 0) == 0)
        #expect(t.visibleLength(words: 1) == 4)
        #expect(t.visibleLength(words: 99) == t.plain.count)
        #expect(ChatText(markdown: "**unclosed bold").plain == "unclosed bold")
    }

    @Test func savesAndLoadsTheLastConversation() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("chat-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(ChatArchive.load(in: dir) == nil)
        let messages: [ChatMessage] = [.user("hi"), ChatMessage(role: .assistant, content: "", toolCalls: [ChatToolCall(id: "c", name: "scratch_history")]),
                                       .tool("c", #"{"nights":[]}"#)]
        let claude = ChatTranscript(model: "anthropic/claude-sonnet-5.5", startedAt: now, messages: messages, latencies: [1200])
        let dev = ChatTranscript(model: "deepseek/deepseek-v4.1-flash", startedAt: now.addingTimeInterval(60), messages: messages, latencies: [800])
        try ChatArchive.save(claude, in: dir)
        try ChatArchive.save(dev, in: dir)
        #expect(ChatArchive.load(in: dir) == claude, "the stage replays Claude's conversation")
        #expect(ChatArchive.load(preferring: "deepseek/deepseek-v4.1-flash", in: dir) == dev)
        #expect(ChatArchive.load(preferring: "other/model", in: dir) == claude)
        #expect(claude.toolResults == ["c": #"{"nights":[]}"#])
    }
}
