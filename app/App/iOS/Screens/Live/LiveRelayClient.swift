import Foundation
import EczemaKit

/// The WebSocket to the live relay, the same one the big-screen page uses.
///
/// Runs while the app is active (`LiveSession` starts and stops it). Says "ping" every 15 s,
/// reconnects with backoff (0.5 s, 1 s, 2 s … at most 5 s, like the page), and drops a socket that
/// went quiet (a half-open connection after a network change never reports an error itself). While
/// the watch streams, a few seconds without a batch are normal (its sends time out after 5 s and a
/// stuck one is cancelled after 6 s, then it resends at once): after 4 s the socket is asked ("ping",
/// the relay answers "pong" at once) instead of dropped, and only 10 s of nothing drops it. A drop
/// at the wrong moment would lose a batch for good: the relay keeps no backlog.
@MainActor
final class LiveRelayClient {
    static let url = URL(string: "wss://eczema-twin-live.zhongzhenyu190.workers.dev/api/live")!

    /// Every frame, parsed (`.other` for hello / pong / label).
    var onMessage: ((LiveRelayMessage) -> Void)?
    /// The relay answered on a new socket (its "hello").
    var onConnect: (() -> Void)?
    /// A socket that had answered is gone (error, silence, or `stop()`).
    var onDisconnect: (() -> Void)?
    private(set) var isConnected = false

    private let session: URLSession
    private var task: URLSessionWebSocketTask?
    /// Bumped whenever a socket is dropped, so late callbacks from it are ignored.
    private var generation = 0
    private var wanted = false
    private var retry = 0
    private var reconnectPending = false
    private var watchdog: Task<Void, Never>?
    private var connectStartedAt = Date.distantPast
    private var lastMessageAt = Date.distantPast
    private var lastBatchAt = Date.distantPast
    private var lastPingAt = Date.distantPast

    init() {
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        session = URLSession(configuration: config)
    }

    func start() {
        guard !wanted else { return }
        wanted = true
        retry = 0
        connect()
        watchdog = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                self?.check()
            }
        }
    }

    func stop() {
        wanted = false
        watchdog?.cancel()
        watchdog = nil
        close()
    }

    // MARK: - Private

    private func connect() {
        guard wanted, task == nil else { return }
        generation += 1
        let gen = generation
        let t = session.webSocketTask(with: Self.url)
        t.maximumMessageSize = 4 << 20        // a batch may carry raw motion for a test recording
        task = t
        connectStartedAt = Date()
        lastMessageAt = Date()
        t.resume()
        listen(t, gen)
    }

    private func listen(_ t: URLSessionWebSocketTask, _ gen: Int) {
        t.receive { [weak self] result in
            // Parse here, off the main thread; the rules run on the main actor.
            let message: LiveRelayMessage?
            switch result {
            case .success(.string(let text)): message = LiveRelayMessage.parse(text) ?? .other
            case .success(.data(let data)): message = LiveRelayMessage.parse(data) ?? .other
            case .success: message = .other
            case .failure: message = nil
            }
            Task { @MainActor in self?.received(message, on: t, generation: gen) }
        }
    }

    private func received(_ message: LiveRelayMessage?, on t: URLSessionWebSocketTask, generation gen: Int) {
        guard gen == generation, wanted else { return }
        guard let message else { drop(); return }
        let now = Date()
        lastMessageAt = now
        if !isConnected {
            isConnected = true
            retry = 0
            lastPingAt = now
            #if DEBUG
            print("[live] relay connected")
            #endif
            onConnect?()
        }
        if case .batch = message { lastBatchAt = now }
        onMessage?(message)
        guard gen == generation, wanted else { return }
        listen(t, gen)
    }

    /// The socket failed or went quiet: close it and try again after a pause.
    private func drop() {
        close()
        guard wanted, !reconnectPending else { return }
        reconnectPending = true
        let delay = min(5, 0.5 * pow(2, Double(retry)))
        retry += 1
        #if DEBUG
        print("[live] relay dropped, again in \(delay) s")
        #endif
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self else { return }
            self.reconnectPending = false
            self.connect()
        }
    }

    private func close() {
        generation += 1
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        if isConnected {
            isConnected = false
            onDisconnect?()
        }
    }

    /// Once a second: a hung handshake or a silent socket is dropped; "ping" every 15 s.
    private func check() {
        guard wanted, let t = task else { return }
        let now = Date()
        guard isConnected else {
            if now.timeIntervalSince(connectStartedAt) > 12 { drop() }
            return
        }
        let streaming = now.timeIntervalSince(lastBatchAt) < 15
        let quiet = now.timeIntervalSince(lastMessageAt)
        if quiet > (streaming ? 10 : 40) {
            drop()
            return
        }
        let sincePing = now.timeIntervalSince(lastPingAt)
        if (streaming && quiet > 4 && sincePing > 4) || sincePing >= 15 {
            ping(t, at: now)
        }
    }

    /// "ping": the relay answers with a "pong" right away, which proves the socket is alive.
    private func ping(_ t: URLSessionWebSocketTask, at now: Date) {
        lastPingAt = now
        let gen = generation
        t.send(.string("ping")) { [weak self] error in
            guard error != nil else { return }
            Task { @MainActor in
                guard let self, self.generation == gen else { return }
                self.drop()
            }
        }
    }
}
