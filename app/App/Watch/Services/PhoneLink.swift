import Foundation
import WatchConnectivity
import EczemaKit

/// Sends the watch's episodes to the iPhone.
///
/// Contract (watch → iPhone): `WCSession.default.transferUserInfo(["kind": "episodes",
/// "data": <Data>])` where `<Data>` is `JSONEncoder().encode([ScratchEpisode])` with default settings.
/// transferUserInfo is queued by the system and delivered even if the phone is away right now.
/// Only real episodes go (source `.live`/`.recorded`).
final class PhoneLink: NSObject, WCSessionDelegate {
    static let shared = PhoneLink()

    /// Called on the main actor when a transfer failed, with the ids to send again later.
    var onFailed: (@MainActor ([UUID]) -> Void)?
    /// Called on the main actor once the session is active (time to send what's waiting).
    var onActivated: (@MainActor () -> Void)?

    private var activated = false

    var isAvailable: Bool { WCSession.isSupported() }
    var isActivated: Bool { activated }

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        if session.delegate == nil { session.delegate = self }
        if session.activationState != .activated { session.activate() } else { activated = true }
    }

    /// Hands the episodes to WatchConnectivity (in batches of 200, so a long offline stretch never
    /// becomes one huge transfer). Returns false when it could not (yet).
    @discardableResult
    func send(_ episodes: [ScratchEpisode]) -> Bool {
        guard !episodes.isEmpty, WCSession.isSupported() else { return false }
        let session = WCSession.default
        guard session.activationState == .activated else { activate(); return false }
        let encoder = JSONEncoder()
        var start = 0
        while start < episodes.count {
            let batch = Array(episodes[start..<min(episodes.count, start + 200)])
            guard let data = try? encoder.encode(batch) else { return false }
            session.transferUserInfo(["kind": "episodes", "data": data])
            start += 200
        }
        return true
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let ok = activationState == .activated
        Task { @MainActor in
            self.activated = ok
            if ok { self.onActivated?() }
        }
    }

    func session(_ session: WCSession, didFinish userInfoTransfer: WCSessionUserInfoTransfer, error: Error?) {
        guard error != nil,
              userInfoTransfer.userInfo["kind"] as? String == "episodes",
              let data = userInfoTransfer.userInfo["data"] as? Data,
              let episodes = try? JSONDecoder().decode([ScratchEpisode].self, from: data) else { return }
        let ids = episodes.filter { $0.source != .demo }.map(\.id)
        guard !ids.isEmpty else { return }
        Task { @MainActor in self.onFailed?(ids) }
    }
}
