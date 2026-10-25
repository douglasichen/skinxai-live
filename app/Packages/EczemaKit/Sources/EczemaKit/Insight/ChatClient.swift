import Foundation

/// Asks the server for Claude's next turn: one POST to /api/chat, at most `timeout` seconds, and one automatic
/// retry (`replyWithRetry`). The app has no key and never names a model; `model` exists only for development
/// (the hidden `-chatModel` launch argument).
public struct ChatClient: Sendable {
    public var endpoint: URL
    /// A development model ("deepseek/deepseek-v4.1-flash"). Nil: the server's choice (Claude).
    public var model: String?
    public var timeout: TimeInterval
    private let session: URLSession

    public init(endpoint: URL = ChatWire.endpoint, model: String? = nil, timeout: TimeInterval = ChatWire.timeout,
                session: URLSession? = nil) {
        self.endpoint = endpoint
        let trimmed = model?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.model = trimmed?.isEmpty == false ? trimmed : nil
        self.timeout = timeout
        self.session = session ?? Self.makeSession(timeout: timeout)
    }

    /// An ephemeral session whose requests give up after `timeout` seconds in total.
    public static func makeSession(timeout: TimeInterval) -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        config.waitsForConnectivity = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }

    /// The POST for this conversation.
    public func request(messages: [ChatMessage], today: String) throws -> URLRequest {
        var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try ChatWire.body(model: model, today: today, messages: messages)
        return request
    }

    /// Claude's next turn. Throws `ChatFailure` (or `CancellationError` when the task is cancelled).
    /// A reply with neither text nor tool calls counts as a failure (`.empty`).
    public func reply(to messages: [ChatMessage], today: String) async throws -> ChatReply {
        let request = try request(messages: messages, today: today)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw Self.failure(for: error, timeout: timeout)
        }
        try Task.checkCancellation()
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let reply = try ChatWire.reply(from: data, status: status, round: messages.count)
        if reply.message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, reply.message.toolCalls.isEmpty {
            throw ChatFailure.empty
        }
        return reply
    }

    /// `reply`, and once more after `pause` seconds if the first try failed. The second failure is thrown.
    public func replyWithRetry(to messages: [ChatMessage], today: String, pause: TimeInterval = 0.8) async throws -> ChatReply {
        do {
            return try await reply(to: messages, today: today)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try await Task.sleep(nanoseconds: UInt64(max(0, pause) * 1_000_000_000))
            return try await reply(to: messages, today: today)
        }
    }

    /// The failure for a transport error (a cancelled task stays a cancellation).
    static func failure(for error: Error, timeout: TimeInterval) -> Error {
        if error is CancellationError { return error }
        guard let url = error as? URLError else { return ChatFailure.badReply }
        switch url.code {
        case .cancelled: return CancellationError()
        case .timedOut: return ChatFailure.timedOut(Int(timeout.rounded()))
        // Only these mean the phone itself has no internet; the rest blame the way to the server, not the phone.
        case .notConnectedToInternet, .internationalRoamingOff, .dataNotAllowed:
            return ChatFailure.offline
        case .networkConnectionLost, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed, .secureConnectionFailed,
             .serverCertificateUntrusted, .serverCertificateHasBadDate, .serverCertificateNotYetValid:
            return ChatFailure.unreachable
        default: return ChatFailure.server(0)
        }
    }
}
