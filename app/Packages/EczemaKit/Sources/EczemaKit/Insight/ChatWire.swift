import Foundation

// The /api/chat protocol of the Eczema Twin server (a port of the live page's `web/chat.js`).
//
// The app sends the whole conversation, OpenAI style, with today's date:
//     POST /api/chat  {"today": "Saturday, October 24, 2026", "story": "mi", "messages": [...]}   ("model" only for development)
// and gets Claude's next turn back:
//     {"model": "...", "message": {"role": "assistant", "content": "...", "tool_calls": [...]}}
// `story` picks the server's scenario prompt (always "mi": the four-flare story of `StageHistory`).
// The server adds the instructions and the tool list and holds the key. The app runs the data tools itself
// (`StageStory`), draws the display tools and answers every tool call before it sends the next request.

/// One tool call in Claude's reply.
public struct ChatToolCall: Codable, Hashable, Sendable {
    public var id: String
    public var name: String
    /// The arguments as JSON object text, e.g. `{"nights":14}`.
    public var arguments: String

    public init(id: String, name: String, arguments: String = "{}") {
        self.id = id
        self.name = name
        self.arguments = arguments
    }

    /// The arguments object (malformed or not an object: empty).
    public var argumentsObject: [String: Any] { ChatWire.object(fromJSON: arguments) }

    private enum CodingKeys: String, CodingKey { case id, type, function }
    private enum FunctionKeys: String, CodingKey { case name, arguments }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(String.self, forKey: .id)) ?? ""
        let f = try c.nestedContainer(keyedBy: FunctionKeys.self, forKey: .function)
        name = (try? f.decodeIfPresent(String.self, forKey: .name)) ?? ""
        arguments = (try? f.decodeIfPresent(String.self, forKey: .arguments)) ?? "{}"
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode("function", forKey: .type)
        var f = c.nestedContainer(keyedBy: FunctionKeys.self, forKey: .function)
        try f.encode(name, forKey: .name)
        try f.encode(arguments, forKey: .arguments)
    }
}

/// One message of the conversation: Douglas (`user`), Claude (`assistant`, maybe with tool calls) or a tool
/// result (`tool`, answering one call by its id).
public struct ChatMessage: Codable, Hashable, Sendable {
    public enum Role: String, Codable, Sendable { case user, assistant, tool }

    public var role: Role
    public var content: String
    /// Claude's tool calls (assistant messages only; empty when there are none).
    public var toolCalls: [ChatToolCall]
    /// The call a tool message answers.
    public var toolCallID: String?

    public init(role: Role, content: String, toolCalls: [ChatToolCall] = [], toolCallID: String? = nil) {
        self.role = role
        self.content = content
        self.toolCalls = toolCalls
        self.toolCallID = toolCallID
    }

    public static func user(_ text: String) -> ChatMessage { ChatMessage(role: .user, content: text) }

    public static func tool(_ callID: String, _ content: String) -> ChatMessage {
        ChatMessage(role: .tool, content: content, toolCallID: callID)
    }

    private enum CodingKeys: String, CodingKey {
        case role, content
        case toolCalls = "tool_calls"
        case toolCallID = "tool_call_id"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        role = try c.decode(Role.self, forKey: .role)
        content = (try? c.decodeIfPresent(String.self, forKey: .content)) ?? ""
        toolCalls = (try? c.decodeIfPresent([ChatToolCall].self, forKey: .toolCalls)) ?? []
        toolCallID = try? c.decodeIfPresent(String.self, forKey: .toolCallID)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(role, forKey: .role)
        try c.encode(content, forKey: .content)
        if !toolCalls.isEmpty { try c.encode(toolCalls, forKey: .toolCalls) }
        if let toolCallID { try c.encode(toolCallID, forKey: .toolCallID) }
    }
}

/// Claude's next turn, as the server returned it (already tidied, see `ChatWire.tidy`).
public struct ChatReply: Hashable, Sendable {
    /// The model that answered (the server's choice unless a development model was asked for).
    public var model: String?
    public var message: ChatMessage

    public init(model: String?, message: ChatMessage) {
        self.model = model
        self.message = message
    }
}

/// Why a request didn't bring a usable reply.
public enum ChatFailure: Error, Equatable, Sendable {
    /// The phone has no connection to the internet.
    case offline
    /// The phone is online but the server can't be reached (no route, DNS, TLS, a dropped connection).
    case unreachable
    /// No answer within the time limit (seconds).
    case timedOut(Int)
    /// The server answered with an error (its HTTP status, 0 if unknown; kept for the logs, never shown).
    case server(Int)
    /// The answer wasn't a reply the app can read.
    case badReply
    /// A reply without text and without tool calls.
    case empty

    /// One short sentence for the error row under "Claude didn't answer". Never a status code: the phone
    /// may be on the big screen.
    public var reason: String {
        switch self {
        case .offline: return "Your phone is offline."
        case .unreachable: return "Couldn't reach Claude."
        case .timedOut(let seconds): return "No answer after \(seconds) s."
        case .server: return "The server had a problem."
        case .badReply: return "The reply came back garbled."
        case .empty: return "The reply came back empty."
        }
    }
}

public enum ChatWire {
    /// The chat endpoint on our server.
    public static let endpoint = URL(string: "https://eczema-twin-live.zhongzhenyu190.workers.dev/api/chat")!
    /// Seconds to wait for one reply.
    public static let timeout: TimeInterval = 45
    /// The scenario the server's prompt is written for, sent with every request.
    public static let story = "mi"

    /// The request body: `{"model"?, "today", "story", "messages"}`. `model` is only sent when given
    /// (development); `story` always (`ChatWire.story`).
    public static func body(model: String?, today: String, messages: [ChatMessage]) throws -> Data {
        struct Body: Encodable {
            var model: String?
            var today: String
            var messages: [ChatMessage]
            enum CodingKeys: String, CodingKey { case model, today, story, messages }
            func encode(to encoder: Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)
                try c.encodeIfPresent(model, forKey: .model)
                try c.encode(today, forKey: .today)
                try c.encode(ChatWire.story, forKey: .story)
                try c.encode(messages, forKey: .messages)
            }
        }
        let trimmed = model?.trimmingCharacters(in: .whitespacesAndNewlines)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        return try encoder.encode(Body(model: trimmed?.isEmpty == false ? trimmed : nil, today: today, messages: messages))
    }

    /// Reads the server's answer. `round` numbers the reply (the conversation's length) for calls without an id.
    /// Throws `ChatFailure.server` for an error answer and `.badReply` for anything unreadable.
    public static func reply(from data: Data, status: Int, round: Int) throws -> ChatReply {
        let ok = (200..<300).contains(status)
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ok ? ChatFailure.badReply : ChatFailure.server(status)
        }
        guard ok, let message = object["message"] as? [String: Any] else {
            // The server's own errors: {"error": "...", "status": <upstream status>} with HTTP 4xx/5xx.
            if !ok || object["error"] != nil { throw ChatFailure.server((object["status"] as? Int) ?? (ok ? 0 : status)) }
            throw ChatFailure.badReply
        }
        let calls = (message["tool_calls"] as? [[String: Any]] ?? []).compactMap { call -> ChatToolCall? in
            guard let function = call["function"] as? [String: Any],
                  let name = function["name"] as? String, !name.isEmpty else { return nil }
            let id = (call["id"] as? String) ?? (call["id"].map { "\($0)" } ?? "")
            let arguments: String
            if let text = function["arguments"] as? String { arguments = text }
            else if let object = function["arguments"] as? [String: Any] { arguments = json(object) }
            else { arguments = "{}" }
            return ChatToolCall(id: id, name: name, arguments: arguments)
        }
        let raw = ChatMessage(role: .assistant, content: message["content"] as? String ?? "", toolCalls: calls)
        return ChatReply(model: object["model"] as? String, message: tidy(raw, round: round))
    }

    /// Tool calls the server forwards per assistant message (worker `tool_calls.slice(0, 8)`). The app runs and
    /// answers only these: a result for a call the server dropped would make every later request fail.
    public static let maxToolCalls = 8

    /// The reply as it goes back into the conversation (chat.js `tidy`): string content, a usable id on every
    /// call (`call_<round>_<k>` when the model sent none), arguments that parse (malformed ones become `{}`),
    /// and at most `maxToolCalls` calls.
    public static func tidy(_ message: ChatMessage, round: Int) -> ChatMessage {
        let calls = message.toolCalls.filter { !$0.name.isEmpty }.prefix(maxToolCalls).enumerated().map { k, call in
            ChatToolCall(id: call.id.isEmpty ? "call_\(round)_\(k)" : call.id, name: call.name,
                         arguments: json(object(fromJSON: call.arguments)))
        }
        return ChatMessage(role: .assistant, content: message.content, toolCalls: calls)
    }

    /// A JSON object from text (malformed or not an object: empty).
    public static func object(fromJSON text: String?) -> [String: Any] {
        guard let data = text?.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return object
    }

    /// Compact JSON text of an object (keys sorted, so it is stable).
    public static func json(_ object: [String: Any]) -> String {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes]),
              let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }
}
