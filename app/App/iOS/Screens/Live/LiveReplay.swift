#if DEBUG
import Foundation
import EczemaKit

/// Development only (Debug builds): `-liveReplay <recording id>` plays a labelled watch recording
/// from the relay (`GET /api/recording?id=…`, public) through the very same rules, with its
/// original timing, instead of listening to the live socket. When the recording ends, the 8 s
/// silence rule stops the "watch" like a real one that went away.
@MainActor
final class LiveReplay {
    var onBatch: ((LiveBatch) -> Void)?
    private let id: String
    private var started = false

    init(id: String) {
        self.id = id
    }

    func start() {
        guard !started else { return }
        started = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            var components = URLComponents(string: "https://eczema-twin-live.zhongzhenyu190.workers.dev/api/recording")
            components?.queryItems = [URLQueryItem(name: "id", value: self.id)]
            guard let url = components?.url,
                  let (data, _) = try? await URLSession.shared.data(from: url),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let batches = root["batches"] as? [[String: Any]],
                  let first = batches.first?["received"] as? Double else {
                print("[live] replay: recording \(self.id) not found")
                return
            }
            print("[live] replay: \(batches.count) batches")
            let start = Date().addingTimeInterval(1)
            for batch in batches {
                guard let received = batch["received"] as? Double else { continue }
                var frame = batch
                frame["type"] = "batch"
                frame["raw"] = nil
                guard let json = try? JSONSerialization.data(withJSONObject: frame),
                      case .batch(let parsed)? = LiveRelayMessage.parse(json) else { continue }
                let wait = start.addingTimeInterval(received - first).timeIntervalSinceNow
                if wait > 0 { try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) }
                self.onBatch?(parsed)
            }
            print("[live] replay: done")
        }
    }
}
#endif
