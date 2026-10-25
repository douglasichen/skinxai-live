import Foundation
import WatchConnectivity
import EczemaKit

/// iPhone side of the watch link.
///
/// Contract (watch → iPhone): `WCSession.default.transferUserInfo(["kind": "episodes", "data": Data])`
/// where `data` is `JSONEncoder().encode([ScratchEpisode])`. The same payload is also accepted as a
/// message, an application context, or a transferred file whose metadata has `"kind": "episodes"`.
///
/// The session goes live at process start (`EczemaTwinApp.init`), not when a screen appears:
/// WatchConnectivity can wake the app in the background to deliver queued episodes, and then no
/// screen ever appears. Episodes that arrive before the app frame is attached are saved to disk
/// at once and handed over as soon as `onEpisodes` is set.
@MainActor
final class WatchInbox: NSObject, ObservableObject {
    static let shared = WatchInbox()

    enum Status: Equatable {
        case unsupported            // iPad / no WatchConnectivity
        case connecting
        case notPaired
        case paired(appInstalled: Bool)
    }

    @Published private(set) var status: Status = .connecting
    @Published private(set) var lastSync: Date?

    /// Called on the main actor with every batch of decoded episodes (and, once set, with the
    /// batches that arrived before).
    var onEpisodes: (([ScratchEpisode]) -> Void)? {
        didSet { deliverPending() }
    }
    /// Episodes received before anyone listened (already saved to disk).
    private var pending: [ScratchEpisode] = []

    func activate() {
        guard WCSession.isSupported() else { status = .unsupported; return }
        let session = WCSession.default
        session.delegate = self
        if session.activationState == .activated {
            refresh(session)
        } else {
            session.activate()
        }
    }

    private func refresh(_ session: WCSession) {
        status = session.isPaired ? .paired(appInstalled: session.isWatchAppInstalled) : .notPaired
    }

    fileprivate func deliver(_ episodes: [ScratchEpisode]) {
        guard !episodes.isEmpty else { return }
        lastSync = Date()
        if let onEpisodes {
            onEpisodes(episodes)
        } else {
            // Woken in the background: keep them even if the app is suspended again right away.
            RealStore.storeEpisodes(episodes)
            pending += episodes
        }
    }

    private func deliverPending() {
        guard onEpisodes != nil, !pending.isEmpty else { return }
        let batch = pending
        pending = []
        // Next turn of the run loop: the listener is usually still being set up.
        DispatchQueue.main.async { [weak self] in self?.onEpisodes?(batch) }
    }

    /// Decodes the contract payload. `nil` when the payload is something else.
    nonisolated static func decode(_ payload: [String: Any]) -> [ScratchEpisode]? {
        guard payload["kind"] as? String == "episodes", let data = payload["data"] as? Data else { return nil }
        return try? JSONDecoder().decode([ScratchEpisode].self, from: data)
    }
}

extension WatchInbox: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let paired = session.isPaired
        let installed = session.isWatchAppInstalled
        Task { @MainActor in
            self.status = activationState == .activated ? (paired ? .paired(appInstalled: installed) : .notPaired) : .connecting
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // The user switched watches: activate again for the new one.
        session.activate()
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        let paired = session.isPaired
        let installed = session.isWatchAppInstalled
        Task { @MainActor in self.status = paired ? .paired(appInstalled: installed) : .notPaired }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        receive(userInfo)
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        receive(message)
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        receive(message)
        replyHandler(["ok": true])
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        receive(applicationContext)
    }

    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        guard file.metadata?["kind"] as? String == "episodes",
              let data = try? Data(contentsOf: file.fileURL),
              let episodes = try? JSONDecoder().decode([ScratchEpisode].self, from: data) else { return }
        Task { @MainActor in self.deliver(episodes) }
    }

    nonisolated private func receive(_ payload: [String: Any]) {
        guard let episodes = WatchInbox.decode(payload) else { return }
        Task { @MainActor in self.deliver(episodes) }
    }
}
