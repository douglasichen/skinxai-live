import Foundation

/// App-wide notifications of the stage build.
extension Notification.Name {
    /// Hidden control "Reset tonight's count": `LiveSession` sets tonight's count back to 0.
    static let twinResetTonight = Notification.Name("et.twinResetTonight")
    /// Hidden control "Replay last Claude chat (offline)": Insight replays the last saved conversation
    /// without the network. It is posted just before the shell switches to the Insight tab, so listen
    /// from an object that outlives the Insight screen.
    static let twinReplayChat = Notification.Name("et.twinReplayChat")
    /// Shows a HUD toast from anywhere: `userInfo["text"]` is the text. `RootView` shows it.
    static let twinToast = Notification.Name("et.twinToast")
}

extension NotificationCenter {
    /// Posts `.twinToast` with `text`, e.g. "Good morning, Douglas · last night is ready".
    func postTwinToast(_ text: String) {
        post(name: .twinToast, object: nil, userInfo: ["text": text])
    }
}
