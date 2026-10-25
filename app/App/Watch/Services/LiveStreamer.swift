import Foundation
import WatchKit
import EczemaKit

/// Streams live wrist motion and scratch events to the big-screen relay
/// (`https://<TwinLiveHost>/api/ingest`, Bearer `TwinLiveKey`), a few times a second.
///
/// Motion goes out as one number per sample (how hard the wrist moves, gravity removed, in g)
/// at 25 Hz; detector windows and episode start/end events go with it. The watch reaches the
/// internet through the paired iPhone (or Wi-Fi); a failed send keeps the events and drops old motion.
final class LiveStreamer: @unchecked Sendable {
    static let shared = LiveStreamer()

    /// What the last send did, for the badge on the watch: ok, or why not (URL error code, HTTP status, "stuck").
    struct LinkStatus: Equatable {
        var ok: Bool
        var detail: String
        var sent: Int
    }

    /// Called on the main queue after every send (and when a send is taking long).
    var onStatus: ((LinkStatus) -> Void)?
    /// What keeps detection running (workout / extendedRuntime / foreground / simulated); sent along for debugging.
    var backing: String? { get { queue.sync { _backing } } set { queue.async { self._backing = newValue } } }
    private var _backing: String?
    /// active / inactive / background, from WKApplication notifications.
    private var appState = "active"
    private var observers: [NSObjectProtocol] = []

    private let queue = DispatchQueue(label: "com.jackyzhong.eczematwin.streamer")
    private let endpoint: URL?
    private let key: String?
    private var samples: [[Double]] = []
    /// Raw accelerometer at 50 Hz, [t, x, y, z] in g, for recording labelled test sessions on the big screen.
    private var raw: [[Double]] = []
    private var windows: [[String: Any]] = []
    private var events: [[String: Any]] = []
    private var gravity: (Double, Double, Double)?
    private var decimate = false
    private var timer: DispatchSourceTimer?
    private var inFlight = false
    private var inFlightSince: Date?
    /// Stop came while a batch was on its way: the final "live: false" batch goes out as soon as that send finishes,
    /// so the phone learns about Stop within a second instead of waiting for its 8-second silence rule.
    private var finalPending = false
    private var task: URLSessionDataTask?
    private var sent = 0
    private var running = false
    private let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 5
        c.timeoutIntervalForResource = 8
        c.waitsForConnectivity = false
        c.allowsCellularAccess = true
        c.allowsExpensiveNetworkAccess = true
        c.allowsConstrainedNetworkAccess = true
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        c.urlCache = nil
        return URLSession(configuration: c)
    }()

    /// Seconds between Apple's reference date (2001) and the Unix epoch.
    private static let unixOffset: TimeInterval = 978_307_200

    init() {
        let info = Bundle.main.infoDictionary ?? [:]
        let host = (info["TwinLiveHost"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
        let k = (info["TwinLiveKey"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
        #if targetEnvironment(simulator)
        // A simulator never streams to the real big screen unless launched with -stream (its sensor is scripted).
        let allowed = ProcessInfo.processInfo.arguments.contains("-stream")
        #else
        let allowed = true
        #endif
        endpoint = !allowed || host.isEmpty || host.hasPrefix("$(") ? nil : URL(string: "https://\(host)/api/ingest")
        key = !allowed || k.isEmpty || k.hasPrefix("$(") ? nil : k
        let nc = NotificationCenter.default
        for (name, state) in [(WKApplication.didBecomeActiveNotification, "active"),
                              (WKApplication.willResignActiveNotification, "inactive"),
                              (WKApplication.didEnterBackgroundNotification, "background"),
                              (WKApplication.willEnterForegroundNotification, "inactive")] {
            observers.append(nc.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
                guard let self else { return }
                self.queue.async { self.appState = state }
            })
        }
    }

    var isConfigured: Bool { endpoint != nil && key != nil }

    func start() {
        queue.async {
            guard self.isConfigured else {
                print("[live] not configured: no TwinLiveHost / TwinLiveKey")
                self.report(LinkStatus(ok: false, detail: "NO KEY", sent: 0))
                return
            }
            guard !self.running else { return }
            self.running = true
            self.finalPending = false
            self.sent = 0
            self.samples.removeAll(); self.raw.removeAll(); self.windows.removeAll(); self.events.removeAll(); self.gravity = nil
            print("[live] start → \(self.endpoint?.absoluteString ?? "-")")
            let t = DispatchSource.makeTimerSource(queue: self.queue)
            t.schedule(deadline: .now() + 0.3, repeating: .milliseconds(300), leeway: .milliseconds(40))
            t.setEventHandler { [weak self] in self?.flush() }
            t.resume()
            self.timer = t
        }
    }

    func stop() {
        queue.async {
            guard self.running else { return }
            self.timer?.cancel()
            self.timer = nil
            self.running = false
            // flush() skips while a send is in flight (one every 0.3 s), so the final batch could be lost.
            if self.inFlight { self.finalPending = true } else { self.flush(force: true) }
        }
    }

    // MARK: - Input (any thread)

    func add(_ sample: MotionSample) {
        queue.async { self.take(sample) }
    }

    func add(_ batch: [MotionSample]) {
        queue.async { for s in batch { self.take(s) } }
    }

    func add(_ events: [DetectorEvent]) {
        queue.async {
            guard self.running else { return }
            for e in events {
                switch e {
                case let .window(w):
                    let f = w.features
                    self.windows.append(["t": f.start + Self.unixOffset, "p": round3(w.probability), "scratch": w.isScratch,
                                         "strength": round3(f.strength), "hz": round3(f.dominantHz), "moving": f.moving,
                                         "periodicity": round3(f.periodicity), "inBand": round3(f.inBand), "crossingHz": round3(f.crossingHz),
                                         "kurtosis": round3(f.kurtosis ?? 0), "impulsiveness": round3(f.impulsiveness ?? 0)])
                case let .episodeStarted(s):
                    self.events.append(["type": "start", "id": s.id.uuidString, "t": s.start.timeIntervalSince1970,
                                        "hz": round3(s.meanHz), "intense": false])
                case let .episodeEnded(d):
                    let ep = d.episode
                    self.events.append(["type": "end", "id": ep.id.uuidString, "t": ep.start.timeIntervalSince1970,
                                        "end": ep.end.timeIntervalSince1970, "seconds": round3(ep.duration),
                                        "intense": ep.intense, "hz": round3(ep.meanHz)])
                }
            }
        }
    }

    // MARK: - Private (on `queue`)

    private func take(_ s: MotionSample) {
        guard running else { return }
        raw.append([round3(s.t + Self.unixOffset), round4(s.x), round4(s.y), round4(s.z)])
        if raw.count > 50 * 20 { raw.removeFirst(raw.count - 50 * 20) }
        // Slow gravity estimate; what is left is the wrist's own motion.
        if let g = gravity {
            gravity = (g.0 + (s.x - g.0) * 0.04, g.1 + (s.y - g.1) * 0.04, g.2 + (s.z - g.2) * 0.04)
        } else {
            gravity = (s.x, s.y, s.z)
        }
        decimate.toggle()
        guard decimate, let g = gravity else { return }          // 50 Hz in, 25 Hz out
        let dx = s.x - g.0, dy = s.y - g.1, dz = s.z - g.2
        let m = (dx * dx + dy * dy + dz * dz).squareRoot()
        samples.append([round3(s.t + Self.unixOffset), round4(m)])
        if samples.count > 25 * 20 { samples.removeFirst(samples.count - 25 * 20) }   // keep 20 s at most
    }

    private func flush(force: Bool = false) {
        guard let endpoint, let key else { return }
        if inFlight {
            // A send that hangs (the watch can hold requests while it switches links) must not block the stream.
            if let since = inFlightSince {
                let waited = Date().timeIntervalSince(since)
                if waited > 6 { print("[live] send stuck \(Int(waited)) s, cancelling"); task?.cancel() }
                else if waited > 1.5 { report(LinkStatus(ok: false, detail: "WAIT \(Int(waited))s", sent: sent), pending: true) }
            }
            return
        }
        guard !samples.isEmpty || !events.isEmpty || force else { return }
        let sendSamples = samples, sendRaw = raw, sendWindows = windows, sendEvents = events
        samples.removeAll(keepingCapacity: true); raw.removeAll(keepingCapacity: true); windows.removeAll(); events.removeAll()
        let body: [String: Any] = ["device": "watch", "live": running && !force, "sentAt": Date().timeIntervalSince1970,
                                   "samples": sendSamples, "raw": sendRaw, "windows": sendWindows, "events": sendEvents,
                                   "backing": _backing ?? "-", "appState": appState]
        guard JSONSerialization.isValidJSONObject(body), let data = try? JSONSerialization.data(withJSONObject: body) else {
            print("[live] could not encode a batch (\(sendSamples.count) samples)")
            report(LinkStatus(ok: false, detail: "JSON", sent: sent))
            return
        }
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.setValue("Bearer \(key)", forHTTPHeaderField: "authorization")
        req.httpBody = data
        inFlight = true
        inFlightSince = Date()
        let t = session.dataTask(with: req) { [weak self] _, response, error in
            guard let self else { return }
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            let ok = error == nil && code == 200
            let detail: String
            if let e = error as? URLError { detail = e.code == .cancelled ? "STUCK" : "\(e.code.rawValue)" }
            else if let e = error { detail = "\((e as NSError).code)" }
            else { detail = "HTTP \(code)" }
            self.queue.async {
                self.inFlight = false
                self.inFlightSince = nil
                self.task = nil
                if ok { self.sent += 1 } else {
                    self.events = sendEvents + self.events      // keep events; old motion is useless
                    print("[live] send failed: \(detail) \(error.map { String(describing: $0) } ?? "")")
                }
                if self.sent == 1 && ok { print("[live] first batch reached the relay") }
                self.report(LinkStatus(ok: ok, detail: ok ? "" : detail, sent: self.sent))
                if self.finalPending && !self.running {
                    self.finalPending = false
                    self.flush(force: true)
                }
            }
        }
        task = t
        t.resume()
    }

    /// Only from `queue`.
    private func report(_ status: LinkStatus, pending: Bool = false) {
        DispatchQueue.main.async { self.onStatus?(status) }
    }
}

private func round3(_ v: Double) -> Double { (v * 1000).rounded() / 1000 }
private func round4(_ v: Double) -> Double { (v * 10000).rounded() / 10000 }
