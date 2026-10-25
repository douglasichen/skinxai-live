import Foundation

/// The chat's fixed words and the rules of a conversation (chat.js).
public enum ChatRules {
    public static let greeting = "Hi Douglas. I can read your scratching, sleep, weather, calendar and orders. Ask me anything about your skin."
    public static let suggestions = ["Why has my eczema been so bad the last few nights?", "How did I sleep this week?"]
    /// The suggested reply when Claude stops before its conclusion without asking anything.
    public static let nudge = "Go ahead"
    /// Replies Claude may take in one go before the app stops asking (a safety net; a conversation needs ~6).
    public static let maxRounds = 16

    /// Claude has shown its conclusion in this conversation.
    public static func concluded(_ messages: [ChatMessage]) -> Bool {
        messages.contains { $0.toolCalls.contains { $0.name == ChatTools.conclusion } }
    }

    /// Offer "Go ahead" after a turn that ended with `text`, until the conclusion: when Claude stopped without
    /// asking anything, or when its last sentence offers to do something ("Want me to look into it?"), which
    /// "Go ahead" answers. An open question ("Where does it itch?") is answered in the box instead.
    public static func offersNudge(after text: String, in messages: [ChatMessage]) -> Bool {
        guard !concluded(messages) else { return false }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasSuffix("?") else { return true }
        let body = trimmed.dropLast()
        let start = body.lastIndex(where: { ".!?\n".contains($0) }).map { body.index(after: $0) } ?? body.startIndex
        let last = body[start...].lowercased()
        return offers.contains { last.contains($0) }
    }

    /// The last sentence of `text` when it is a question that says what the card asks in other words ("Did you
    /// change your laundry detergent recently?" for "Have you changed your laundry detergent recently?"): it
    /// shares most of the card's meaningful words, at least two.
    static func restatedQuestion(in text: String, _ question: String) -> Range<String.Index>? {
        guard text.hasSuffix("?") else { return nil }
        let body = text[..<text.index(before: text.endIndex)]
        let start = body.lastIndex(where: { ".!?:\n".contains($0) }).map { text.index(after: $0) } ?? text.startIndex
        let sentence = text[start...]
        let asked = meaningfulWords(question), said = meaningfulWords(String(sentence))
        guard asked.count >= 2 else { return nil }
        let shared = asked.filter { a in said.contains { b in a.hasPrefix(b) || b.hasPrefix(a) } }.count
        guard shared >= 2, Double(shared) >= 0.6 * Double(asked.count) else { return nil }
        let first = sentence.firstIndex(where: { !$0.isWhitespace }) ?? start
        return first..<text.endIndex
    }

    /// Lowercased words of four letters or more, without the small ones every question has.
    static func meaningfulWords(_ text: String) -> [String] {
        let common: Set<String> = ["have", "been", "your", "this", "that", "what", "where", "when", "which", "with",
                                   "does", "were", "there", "they", "them", "than", "from", "into", "about", "would", "could"]
        return text.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init)
            .filter { $0.count >= 4 && !common.contains($0) }
    }

    /// How an offer starts ("Want me to…?", "Shall I…?").
    static let offers = ["want me to", "like me to", "shall i", "should i", "can i ", "may i ", "ok if i", "okay if i",
                         "shall we", "should we", "want to dig", "want to look", "want to find", "ready for me to"]

    /// The text of Claude's reply as shown: trimmed, without a question it also asks on a question card (any
    /// case, with or without its "?"), and without the lead-in it leaves dangling ("… other things. First:").
    public static func shownText(_ message: ChatMessage) -> String {
        var text = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        for call in message.toolCalls where call.name == ChatTools.question {
            let question = (call.argumentsObject["question"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !question.isEmpty else { continue }
            var range = text.range(of: question, options: .caseInsensitive)
            if range == nil, question.hasSuffix("?"), question.count > 12,
               let bare = text.range(of: String(question.dropLast()), options: .caseInsensitive) {
                // Up to the end of its sentence: "… than usual for you?" must not leave "for you?" behind.
                var next = bare.upperBound
                if let end = text[bare.upperBound...].firstIndex(where: { "?.!\n".contains($0) }), text[end] == "?",
                   text.distance(from: bare.upperBound, to: end) <= 40 {
                    next = text.index(after: end)
                }
                range = bare.lowerBound..<next
            }
            if range == nil { range = restatedQuestion(in: text, question) }
            guard let range else { continue }
            text.removeSubrange(range)
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if let lead = text.range(of: #"(?:^|(?<=[.!?…]))\s*[A-Za-z][A-Za-z'’ ,]{0,32}[:,–—-]$"#, options: .regularExpression) {
                text.removeSubrange(lead)
                text = text.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return text
    }
}

/// A finished conversation as it is saved and replayed: every message (tool results included), when it began
/// (the dates its cards use) and how long each reply took (the rhythm of a replay).
public struct ChatTranscript: Codable, Hashable, Sendable {
    public var version: Int
    /// The model that answered.
    public var model: String
    public var startedAt: Date
    public var messages: [ChatMessage]
    /// Milliseconds per assistant reply, in order.
    public var latencies: [Int]

    public init(model: String, startedAt: Date, messages: [ChatMessage], latencies: [Int]) {
        version = 1
        self.model = model
        self.startedAt = startedAt
        self.messages = messages
        self.latencies = latencies
    }

    /// The saved result of each tool call, by call id.
    public var toolResults: [String: String] {
        var results: [String: String] = [:]
        for m in messages where m.role == .tool { if let id = m.toolCallID { results[id] = m.content } }
        return results
    }

    /// The demo cache: when the conversation so far is this recording's beginning (the same question, the same
    /// answers to Claude's questions), the recorded next reply; nil as soon as it differs, so a different question
    /// or answer goes to live Claude. Data-tool results aren't compared (the app recomputes them for the day).
    public func cachedReply(after conversation: [ChatMessage]) -> ChatMessage? {
        guard !conversation.isEmpty, conversation.count < messages.count,
              messages[conversation.count].role == .assistant else { return nil }
        var names: [String: String] = [:]
        for m in messages { for call in m.toolCalls { names[call.id] = call.name } }
        func same(_ a: String, _ b: String) -> Bool {
            let norm = { (s: String) in s.lowercased().filter { $0.isLetter || $0.isNumber } }
            return norm(a) == norm(b)
        }
        for (have, want) in zip(conversation, messages) {
            guard have.role == want.role else { return nil }
            switch have.role {
            case .user:
                guard same(have.content, want.content) else { return nil }
            case .assistant:
                guard have.toolCalls.map(\.id) == want.toolCalls.map(\.id) else { return nil }
            case .tool:
                guard have.toolCallID == want.toolCallID else { return nil }
                if let id = want.toolCallID, ChatTools.kind(of: names[id] ?? "") == .question,
                   !same(have.content, want.content) { return nil }
            }
        }
        return messages[conversation.count]
    }

    /// Claude showed everything a full answer has: the timeline, the product, at least one question, and a
    /// conclusion with at least two things it ruled out.
    public var isComplete: Bool {
        let calls = messages.flatMap(\.toolCalls)
        let names = Set(calls.map(\.name))
        guard names.isSuperset(of: [ChatTools.timeline, ChatTools.product, ChatTools.conclusion]),
              calls.filter({ $0.name == ChatTools.question }).count >= 1,
              let conclusion = calls.last(where: { $0.name == ChatTools.conclusion }) else { return false }
        return ChatConclusion(arguments: conclusion.argumentsObject).ruledOut.count >= 2
    }
}

/// Where the last finished conversation of each model is kept: one JSON file per model. The offline replay is the
/// stage's plan B, so a complete conversation is never replaced by a lesser one, and the app ships with one.
public enum ChatArchive {
    /// Application Support/Chat.
    public static var defaultDirectory: URL {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Chat", isDirectory: true)
    }

    static func fileName(for model: String) -> String {
        let safe = model.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" }
        return "chat-\(String(safe)).json"
    }

    /// Saves `transcript` as the last conversation of its model.
    public static func save(_ transcript: ChatTranscript, in directory: URL = defaultDirectory) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let data = try encoder.encode(transcript)
        try data.write(to: directory.appendingPathComponent(fileName(for: transcript.model)), options: .atomic)
    }

    /// Saves `transcript` unless that would replace a complete conversation of its model with one that isn't
    /// (a rehearsal where Claude skipped the product or the ruled-out list doesn't become the stage's replay).
    /// Returns whether it was saved.
    @discardableResult
    public static func keep(_ transcript: ChatTranscript, in directory: URL = defaultDirectory) throws -> Bool {
        if !transcript.isComplete, let old = read(directory.appendingPathComponent(fileName(for: transcript.model))),
           old.isComplete {
            return false
        }
        try save(transcript, in: directory)
        return true
    }

    /// The conversation to replay: the newest one with `model` (a development model); else the newest complete
    /// one with Claude; else `fallback` (the conversation the app ships with); else the newest one with Claude;
    /// else the newest one at all.
    public static func load(preferring model: String? = nil, in directory: URL = defaultDirectory,
                            fallback: ChatTranscript? = nil) -> ChatTranscript? {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        let all = files
            .filter { $0.lastPathComponent.hasPrefix("chat-") && $0.pathExtension == "json" }
            .compactMap(read)
            .sorted { $0.startedAt > $1.startedAt }
        if let model, let match = all.first(where: { $0.model == model }) { return match }
        let claude = all.filter { $0.model.hasPrefix("anthropic/") }
        return claude.first(where: \.isComplete) ?? fallback ?? claude.first ?? all.first
    }

    /// The conversation the app ships with: a real one with Claude (Sonnet 5.5) about this story, recorded on the
    /// stage build. A phone with nothing saved yet replays this one (moved to today, see `moved(toDayOf:)`).
    public static let bundled: ChatTranscript? = Bundle.module.url(forResource: "stage-chat", withExtension: "json").flatMap(read)

    private static func read(_ url: URL) -> ChatTranscript? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        guard let data = try? Data(contentsOf: url),
              let t = try? decoder.decode(ChatTranscript.self, from: data), t.version == 1, !t.messages.isEmpty else { return nil }
        return t
    }
}
