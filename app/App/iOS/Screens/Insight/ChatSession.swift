import SwiftUI
import EczemaKit

/// One block of the conversation on screen.
struct ChatItem: Identifiable, Equatable {
    enum Kind: Equatable {
        case greeting
        case suggestions
        case user(String)
        /// Claude's words, revealed word by word from `from` (`.distantPast`: all at once).
        case claude(ChatText, from: Date)
        case thinking
        case tools([ChatToolRow])
        case timeline(ChatTimeline)
        case product(ChatProduct)
        /// Claude's question; `answer` once Douglas answered.
        case question(ChatQuestion, answer: String?)
        case conclusion(ChatConclusion)
        /// A request failed twice: the reason and a "Try again" chip.
        case failure(String)
        /// "Go ahead": Claude stopped before its conclusion without asking anything.
        case nudge
    }

    let id: Int
    var kind: Kind
    /// When it appeared. Cards play their entrance only while they are new, not when the screen comes back.
    let born: Date

    var isFresh: Bool { Date().timeIntervalSince(born) < 1.2 }
}

/// The composer's text.
@MainActor
final class ChatDraft: ObservableObject {
    @Published var text = ""
}

/// One row of a tool card: the tool's icon and name, then its one-line result (nil while it runs).
struct ChatToolRow: Identifiable, Equatable {
    let id: Int
    let icon: String
    let title: String
    var summary: String?
}

/// The conversation with Claude (a port of the live page's `web/chat.js`): sends the conversation to our server,
/// shows each reply (its text word by word, then its tool calls in order), runs the data tools with `StageStory`,
/// draws the display tools and answers them `{"shown": true}`, waits for Douglas on `ask_user`, and sends the next
/// request once every tool call of the reply has its result. Stops at a reply without tool calls.
///
/// Lives for the whole launch (created by the app at start-up), so a conversation keeps going while another tab
/// is up, and the hidden "Replay last Claude chat" control (`.twinReplayChat`) can be heard before Insight shows.
///
/// Hidden development launch arguments (no effect unless passed):
///   -chatModel <id>   ask the server for this model ("deepseek/deepseek-v4.1-flash"); never sent otherwise
///   -chatAuto 1       sends the first suggestion (2: the second), taps the first answer of every question and "Go ahead"
///   -chatLive 1       never answers from the demo cache (the bundled recording); always asks live Claude
///   -chatReplay 1     posts .twinReplayChat when Insight first shows (replays the last saved conversation)
///   -chatEndpoint <url>  talks to another /api/chat (to see the failed-request row)
///   -chatDraft <text>    starts with this text in the box and the keyboard up
///   -nessieOrders 1      order_history reads purchases from Capital One Nessie via /api/orders (NessieOrders)
@MainActor
final class ChatSession: ObservableObject {
    static let shared = ChatSession()

    /// Seconds per word of Claude's text.
    nonisolated static let wordDelay = 0.032
    /// Every tool row spins at least this long, so it can be read.
    nonisolated static let toolMinimum = 0.6
    /// "Thinking…" never just flashes.
    nonisolated static let thinkMinimum = 0.6

    @Published private(set) var items: [ChatItem] = []
    /// Claude's turn: waiting for the server or playing a reply (also while a question waits for Douglas).
    @Published private(set) var busy = false
    /// A saved conversation is playing (no network). It looks exactly like a live one.
    @Published private(set) var replaying = false
    /// The question card waiting for Douglas.
    @Published private(set) var askingID: Int?
    /// A chip a replay or -chatAuto is pressing (drawn pressed for a moment).
    @Published private(set) var pressed: String?
    /// Bumps whenever the thread should glide to its newest line.
    @Published private(set) var scrollTick = 0
    /// The text in the composer (its own object, so typing only redraws the composer).
    let draft = ChatDraft()

    /// Claude is working on its turn (not waiting for Douglas): the ✶ badge pulses.
    var working: Bool { busy && askingID == nil }
    /// Something typed in the box can go out now: an answer to the open question, or a new message.
    var canSend: Bool { askingID != nil || !busy }
    var placeholder: String { askingID != nil ? "Type your own answer…" : "Ask Claude…" }

    private var messages: [ChatMessage] = []
    private var latencies: [Int] = []
    private var startedAt: Date?
    /// The model that answered, as the server says (saved with the conversation).
    private var model: String?
    /// Bumps on a wipe; work from an older conversation checks it and stops.
    private var generation = 0
    private var work: Task<Void, Never>?
    private var answer: CheckedContinuation<String?, Never>?
    private var nextID = 0
    private let client: ChatClient
    private let devModel: String?
    private let autoPlay: Bool
    /// Which suggestion -chatAuto sends: 1 (default) or 2.
    private let autoSuggestion: Int
    private var autoStarted = false
    private var autoNudges = 0
    private var devReplayStarted = false
    private var replayObserver: NSObjectProtocol?

    private var reduceMotion: Bool { UIAccessibility.isReduceMotionEnabled }

    init() {
        let defaults = UserDefaults.standard
        let dev = defaults.string(forKey: "chatModel")?.trimmingCharacters(in: .whitespacesAndNewlines)
        devModel = dev?.isEmpty == false ? dev : nil
        let endpoint = defaults.string(forKey: "chatEndpoint").flatMap(URL.init(string:))
        client = ChatClient(endpoint: endpoint ?? ChatWire.endpoint, model: devModel)
        autoPlay = defaults.integer(forKey: "chatAuto") > 0 || defaults.bool(forKey: "chatAuto")
        autoSuggestion = defaults.integer(forKey: "chatAuto") == 2 ? 1 : 0
        items = opening()
        #if DEBUG
        if let cards = defaults.string(forKey: "chatCards") {
            let all = Self.sampleCards(now: Date())
            items += (cards == "timeline" ? Array(all.prefix(1)) : all).map { ChatItem(id: newID(), kind: $0, born: .distantPast) }
        }
        #endif
        replayObserver = NotificationCenter.default.addObserver(forName: .twinReplayChat, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.replay() }
        }
    }

    // MARK: - Intents

    /// Insight is on screen.
    func appear() {
        if autoPlay, !autoStarted, messages.isEmpty, !busy, !replaying {
            autoStarted = true
            let gen = generation
            Task { [weak self] in
                await Self.pause(1.4)
                guard let self, gen == self.generation, self.messages.isEmpty, !self.busy, !self.replaying,
                      ChatRules.suggestions.indices.contains(self.autoSuggestion) else { return }
                let suggestion = ChatRules.suggestions[self.autoSuggestion]
                await self.press(suggestion)
                self.send(suggestion)
            }
        }
        if UserDefaults.standard.bool(forKey: "chatReplay"), !devReplayStarted {
            devReplayStarted = true
            Task {
                await Self.pause(1.0)
                // The same way the hidden "Replay last Claude chat" control asks for it.
                NotificationCenter.default.post(name: .twinReplayChat, object: nil)
            }
        }
    }

    /// Douglas asks something (a suggestion, "Go ahead" or the box).
    func send(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !busy, !replaying else { return }
        // Busy at once, not when the task starts: a chip tap and the return key in the same moment send once.
        busy = true
        if messages.isEmpty { startedAt = Date() }
        clearPrompts()
        addUser(text)
        messages.append(.user(text))
        let gen = generation
        work = Task { [weak self] in await self?.converse(gen, lead: 0.35) }
    }

    /// The send button / return key: an answer to the open question, or a new message.
    func submitDraft() {
        let text = draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !replaying else { return }
        if askingID != nil, answer != nil {
            draft.text = ""
            resolve(text)
        } else if !busy {
            draft.text = ""
            send(text)
        }
    }

    /// Douglas taps an answer on a question card.
    func tapOption(_ option: String, in itemID: Int) {
        guard !replaying, askingID == itemID else { return }
        resolve(option)
    }

    /// "Try again" after a failed request: asks again with the same conversation.
    func retry() {
        guard !busy, !replaying else { return }
        busy = true
        removeAll { if case .failure = $0 { true } else { false } }
        let gen = generation
        work = Task { [weak self] in await self?.converse(gen, lead: 0.2) }
    }

    /// "Go ahead".
    func nudge() {
        guard !busy, !replaying else { return }
        send(ChatRules.nudge)
    }

    /// The hidden "Replay last Claude chat (offline)": plays the last finished conversation again with the
    /// same rhythm, from the saved messages and tool results. No network. A phone with none saved yet plays the
    /// conversation the app ships with. Either way its dates move to today, so they match Today and Trends.
    func replay() {
        guard let saved = ChatArchive.load(preferring: devModel, fallback: ChatArchive.bundled)?.moved(toDayOf: Date()) else {
            NotificationCenter.default.postTwinToast("No saved conversation yet")
            return
        }
        wipe()
        let gen = generation
        work = Task { [weak self] in await self?.play(saved, gen: gen) }
    }

    /// A new night (the watch started a session): back to Claude's greeting and the suggestions, so step 6 of the
    /// stage opens on a fresh conversation, whatever a rehearsal left behind (a finished thread, a question still
    /// waiting, a failed request). Whatever was going on stops.
    func startOver() {
        let fresh = messages.isEmpty && !busy && !replaying && items.count == 2
        guard !fresh else { return }
        wipe()
    }

    // MARK: - The conversation

    /// Sends the conversation, shows the reply, runs its tools, sends the results; stops at a reply without
    /// tools. `lead`: Douglas's bubble is still landing, so "Thinking…" waits for it (the request doesn't).
    private func converse(_ gen: Int, lead: Double = 0) async {
        busy = true
        var said = ""
        var lead = lead
        for _ in 0..<ChatRules.maxRounds {
            let started = Date()
            let conversation = messages, today = StageStory.todayLong(), client = client
            // Demo cache: while the conversation follows the bundled real-Claude recording, its next reply comes
            // after about 2 seconds; anything else goes to live Claude. -chatLive 1 turns the cache off.
            let cached = UserDefaults.standard.bool(forKey: "chatLive") ? nil
                : ChatArchive.bundled?.moved(toDayOf: Date()).cachedReply(after: conversation)
            let cacheModel = ChatArchive.bundled?.model
            async let asked: ChatReply = {
                if let cached {
                    try? await Task.sleep(nanoseconds: UInt64(Double.random(in: 1.7...2.3) * 1_000_000_000))
                    return ChatReply(model: cacheModel, message: cached)
                }
                return try await client.replyWithRetry(to: conversation, today: today)
            }()
            if lead > 0 {
                await Self.pause(lead)
                lead = 0
            }
            guard gen == generation else { return }
            let thinking = add(.thinking)
            let reply: ChatReply
            do {
                reply = try await asked
            } catch {
                guard gen == generation else { return }
                #if DEBUG
                print("[chat] request failed: \(error)")
                #endif
                remove(thinking)
                add(.failure((error as? ChatFailure ?? .badReply).reason))
                busy = false
                return
            }
            guard gen == generation else { return }
            latencies.append(Int(Date().timeIntervalSince(started) * 1000))
            if let name = reply.model { model = name }
            await Self.pause(Self.thinkMinimum - Date().timeIntervalSince(started))
            guard gen == generation else { return }
            remove(thinking, animated: false)
            messages.append(reply.message)
            said = reply.message.content
            guard let results = await play(reply.message, gen: gen, recorded: nil) else { return }
            if reply.message.toolCalls.isEmpty { break }
            messages.append(contentsOf: results)
            // The conclusion card is the end: its "Try this" is the one call to action, nothing after it.
            if reply.message.toolCalls.contains(where: { $0.name == ChatTools.conclusion }) { break }
        }
        busy = false
        save()
        offerNudge(after: said, in: messages, gen: gen)
    }

    /// One reply on screen: its text, then its tool calls in order. Returns the tool messages (nil if the
    /// conversation was wiped meanwhile). `recorded`: a replay's saved results by call id.
    private func play(_ message: ChatMessage, gen: Int, recorded: [String: String]?) async -> [ChatMessage]? {
        let text = ChatRules.shownText(message)
        if !text.isEmpty { await say(text) }
        var results: [ChatMessage] = []
        for call in message.toolCalls {
            guard gen == generation else { return nil }
            let saved = recorded?[call.id]
            let content: String
            switch ChatTools.kind(of: call.name) {
            case .data:
                content = await runData(call, recorded: saved)
            case .question:
                guard let reply = await ask(call, gen: gen, recorded: saved.flatMap(ChatTools.answer(fromResult:))) else { return nil }
                content = ChatTools.answerResult(reply)
            case .display:
                await show(call)
                content = ChatTools.shownResult
            case .unknown:
                content = ChatTools.unknownResult(call.name)
            }
            results.append(.tool(call.id, content))
        }
        return gen == generation ? results : nil
    }

    private func say(_ text: String) async {
        let words = ChatText(markdown: text)
        guard words.wordCount > 0 else { return }
        add(.claude(words, from: reduceMotion ? .distantPast : Date()))
        await Self.pause(reduceMotion ? 0.15 : Double(words.wordCount) * Self.wordDelay + 0.25)
    }

    /// A data tool: a row on the tool card (a new card unless the last block is one), the tool runs, the row
    /// shows its result after at least `toolMinimum`.
    private func runData(_ call: ChatToolCall, recorded: String?) async -> String {
        let info = ChatTools.row(name: call.name, argumentsJSON: call.arguments)
        let row = ChatToolRow(id: newID(), icon: info.icon, title: info.title, summary: nil)
        if let last = items.last, case .tools(let rows) = last.kind {
            update(last.id) { $0.kind = .tools(rows + [row]) }
        } else {
            add(.tools([row]))
        }
        let started = Date()
        var live: String? = nil
        if recorded == nil { live = await NessieOrders.result(for: call) }   // -nessieOrders 1: orders from Capital One Nessie
        let result = recorded ?? live ?? StageStory.runToolJSON(name: call.name, argumentsJSON: call.arguments, now: startedAt ?? Date())
        await Self.pause(Self.toolMinimum - Date().timeIntervalSince(started))
        let line = ChatTools.summary(name: call.name, resultJSON: result)
        if let owner = items.first(where: { if case .tools(let rows) = $0.kind { rows.contains { $0.id == row.id } } else { false } }),
           case .tools(var rows) = owner.kind, let k = rows.firstIndex(where: { $0.id == row.id }) {
            rows[k].summary = line
            update(owner.id, scroll: false) { $0.kind = .tools(rows) }
        }
        await Self.pause(0.2)
        return result
    }

    /// A display tool: its card in the thread, then a moment for its entrance to play. The thread keeps one card
    /// per thing (a model sometimes repeats a call, and the replay plays what was saved): a second conclusion, a
    /// timeline marking the same night again or the same product again updates the card already there.
    private func show(_ call: ChatToolCall) async {
        let args = call.argumentsObject
        let now = startedAt ?? Date()
        let kind: ChatItem.Kind
        switch call.name {
        case ChatTools.timeline: kind = .timeline(ChatTimeline(arguments: args, now: now))
        case ChatTools.product: kind = .product(ChatProduct(arguments: args, now: now))
        default: kind = .conclusion(ChatConclusion(arguments: args))
        }
        if let old = items.last(where: { Self.sameCard($0.kind, kind) }) {
            if old.kind != kind { update(old.id) { $0.kind = kind } }
            await Self.pause(0.2)
            return
        }
        add(kind)
        switch kind {
        case .timeline: await Self.pause(reduceMotion ? 0.4 : 1.5)
        case .product: await Self.pause(reduceMotion ? 0.4 : 1.4)
        default:
            Haptics.success()
            await Self.pause(reduceMotion ? 0.4 : 1.8)
        }
    }

    /// `ask_user`: the question card, then Douglas's answer (a chip or the box) as his bubble. Nil if wiped.
    /// `recorded`: a replay's answer, pressed for him after a moment. A replay always moves on (it takes no
    /// input): without a saved answer it presses the first option.
    private func ask(_ call: ChatToolCall, gen: Int, recorded: String?) async -> String? {
        let question = ChatQuestion(arguments: call.argumentsObject)
        let id = add(.question(question, answer: nil))
        await Self.pause(0.3)
        guard gen == generation else { return nil }
        askingID = id
        let fallback = autoPlay || replaying ? question.options.first ?? (replaying ? "Not sure" : nil) : nil
        if let pick = recorded ?? fallback {
            Task { [weak self] in
                await Self.pause(1.8)
                guard let self, gen == self.generation, self.askingID == id else { return }
                if question.options.contains(pick) {
                    await self.press(pick)
                } else {
                    await self.typeIn(pick, gen: gen)
                }
                guard gen == self.generation, self.askingID == id else { return }
                self.resolve(pick)
            }
        }
        let reply = await withCheckedContinuation { (waiter: CheckedContinuation<String?, Never>) in answer = waiter }
        guard gen == generation, let reply else { return nil }
        askingID = nil
        update(id) { $0.kind = .question(question, answer: reply) }
        await Self.pause(0.26)
        guard gen == generation else { return nil }
        addUser(reply)
        await Self.pause(reduceMotion ? 0.1 : 0.45)
        return gen == generation ? reply : nil
    }

    /// Hands Douglas's answer to the waiting question.
    private func resolve(_ text: String) {
        guard let waiter = answer else { return }
        answer = nil
        waiter.resume(returning: text)
    }

    private func offerNudge(after text: String, in conversation: [ChatMessage], gen: Int) {
        guard gen == generation, ChatRules.offersNudge(after: text, in: conversation) else { return }
        add(.nudge)
        guard autoPlay, !replaying, autoNudges < 3 else { return }
        autoNudges += 1
        Task { [weak self] in
            await Self.pause(1.6)
            guard let self, gen == self.generation, !self.busy else { return }
            await self.press(ChatRules.nudge)
            self.nudge()
        }
    }

    // MARK: - Save and replay

    /// Keeps the conversation once Claude has shown its conclusion (never over a complete one with a lesser one).
    private func save() {
        guard !replaying, ChatRules.concluded(messages), let startedAt else { return }
        let transcript = ChatTranscript(model: model ?? devModel ?? "anthropic/claude", startedAt: startedAt,
                                        messages: messages, latencies: latencies)
        try? ChatArchive.keep(transcript)
    }

    private func play(_ saved: ChatTranscript, gen: Int) async {
        replaying = true
        busy = true
        startedAt = saved.startedAt
        model = saved.model
        let results = saved.toolResults
        var reply = 0
        await Self.pause(0.7)
        for (i, message) in saved.messages.enumerated() {
            guard gen == generation else { return }
            switch message.role {
            case .user:
                let chip = (i == 0 && ChatRules.suggestions.contains(message.content))
                    || (message.content == ChatRules.nudge && items.contains { $0.kind == .nudge })
                if chip {
                    await Self.pause(0.9)
                    await press(message.content)
                } else {
                    await typeIn(message.content, gen: gen)
                }
                guard gen == generation else { return }
                clearPrompts()
                addUser(message.content)
            case .assistant:
                await Self.pause(0.35)
                guard gen == generation else { return }
                let thinking = add(.thinking)
                let ms = reply < saved.latencies.count ? saved.latencies[reply] : 1500
                reply += 1
                await Self.pause(min(3.5, max(Self.thinkMinimum + 0.2, Double(ms) / 1000)))
                guard gen == generation else { return }
                remove(thinking, animated: false)
                guard await play(message, gen: gen, recorded: results) != nil else { return }
                if message.toolCalls.isEmpty, i < saved.messages.count - 1 {
                    offerNudge(after: message.content, in: Array(saved.messages[...i]), gen: gen)
                }
            case .tool:
                continue
            }
        }
        guard gen == generation else { return }
        messages = saved.messages
        latencies = saved.latencies
        replaying = false
        busy = false
    }

    /// A chip drawn pressed for a moment (a replay or -chatAuto taps it).
    private func press(_ text: String) async {
        pressed = text
        Haptics.tap()
        await Self.pause(0.18)
        pressed = nil
    }

    /// A replay's typed message: it appears in the box letter by letter, then goes out.
    private func typeIn(_ text: String, gen: Int) async {
        for k in 1...max(1, text.count) {
            guard gen == generation else { return }
            draft.text = String(text.prefix(k))
            await Self.pause(1.0 / 32)
        }
        await Self.pause(0.3)
        if gen == generation { draft.text = "" }
    }

    /// Back to the greeting: everything from the old conversation stops.
    private func wipe() {
        generation += 1
        work?.cancel()
        work = nil
        if let waiter = answer {
            answer = nil
            waiter.resume(returning: nil)
        }
        askingID = nil
        pressed = nil
        messages = []
        latencies = []
        startedAt = nil
        model = nil
        busy = false
        replaying = false
        draft.text = ""
        withAnimation(.easeOut(duration: 0.2)) { items = opening() }
        scrollTick += 1
    }

    #if DEBUG
    /// `-chatCards 1` (debug, screenshots): cards drawn from sample arguments under the greeting: a timeline
    /// with a marker on each flare's new product, the shampoo and the sweater (`-chatCards timeline`: the
    /// timeline only). No conversation.
    static func sampleCards(now: Date) -> [ChatItem.Kind] {
        let day = { (night: Int) in StageStory.iso(StageStory.nightDate(night, now: now)) }
        let markers: [[String: Any]] = [
            ["date": day(-47), "label": "Summit Peak shampoo"], ["date": day(-28), "label": "Lumen hand soap"],
            ["date": day(-5), "label": "FreshMeadow detergent"], ["date": day(-5), "label": "Northfield sweater"],
            ["date": day(9), "label": "Brightwell body wash"],
        ]
        return [
            .timeline(ChatTimeline(arguments: ["markers": markers, "note": "Each rise began the night after one of these arrived."], now: now)),
            .product(ChatProduct(arguments: ["name": "Summit Peak shampoo", "flagged_ingredients": ["Methylisothiazolinone"]], now: now)),
            .product(ChatProduct(arguments: ["name": "Northfield sweater"], now: now)),
        ]
    }
    #endif

    // MARK: - The thread

    private func opening() -> [ChatItem] {
        [ChatItem(id: newID(), kind: .greeting, born: .distantPast), ChatItem(id: newID(), kind: .suggestions, born: .distantPast)]
    }

    private func newID() -> Int {
        nextID += 1
        return nextID
    }

    /// Two display cards about the same thing: conclusions, timelines marking the same night, the same product.
    private static func sameCard(_ a: ChatItem.Kind, _ b: ChatItem.Kind) -> Bool {
        switch (a, b) {
        case (.conclusion, .conclusion): true
        case let (.timeline(x), .timeline(y)): x.markers.map(\.night) == y.markers.map(\.night)
        case let (.product(x), .product(y)): x.title == y.title
        default: false
        }
    }

    private var motion: Animation { reduceMotion ? .easeOut(duration: 0.25) : Twin.Motion.spring }

    @discardableResult
    private func add(_ kind: ChatItem.Kind) -> Int {
        let id = newID()
        withAnimation(motion) { items.append(ChatItem(id: id, kind: kind, born: Date())) }
        scrollTick += 1
        return id
    }

    private func addUser(_ text: String) {
        add(.user(text))
    }

    private func update(_ id: Int, scroll: Bool = true, _ change: (inout ChatItem) -> Void) {
        guard let k = items.firstIndex(where: { $0.id == id }) else { return }
        withAnimation(motion) { change(&items[k]) }
        if scroll { scrollTick += 1 }
    }

    /// Takes a block out of the thread; `animated: false` for the thinking row Claude's words replace.
    private func remove(_ id: Int, animated: Bool = true) {
        if animated {
            withAnimation(.easeOut(duration: 0.18)) { items.removeAll { $0.id == id } }
        } else {
            var instant = Transaction()
            instant.disablesAnimations = true
            withTransaction(instant) { items.removeAll { $0.id == id } }
        }
    }

    private func removeAll(where match: (ChatItem.Kind) -> Bool) {
        guard items.contains(where: { match($0.kind) }) else { return }
        withAnimation(.easeOut(duration: 0.2)) { items.removeAll { match($0.kind) } }
    }

    /// The suggestions, "Go ahead" and an old "Try again" go once Douglas says something.
    private func clearPrompts() {
        removeAll {
            switch $0 {
            case .suggestions, .nudge, .failure: true
            default: false
            }
        }
    }

    private static func pause(_ seconds: Double) async {
        guard seconds > 0 else { return }
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }
}
