import Foundation
import Combine
import SwiftUI
import UIKit
import EczemaKit

/// One scratching episode the watch reported tonight.
struct LiveEpisode: Identifiable, Equatable {
    /// 1, 2, 3 … in the order the episodes started tonight.
    let id: Int
    let start: Date
    /// When it ended; nil while it is still going on.
    var end: Date?
}

/// What the watch is doing right now, as the phone hears it through the live relay
/// (`wss://eczema-twin-live.zhongzhenyu190.workers.dev/api/live`).
///
/// The rules are EczemaKit's `LiveRelayState` (a port of the big-screen monitor's `take()` plus the
/// stage session rules); this object feeds it from the relay socket — or from the built-in stand-in
/// watch with `-liveSim 1` — ticks it, and publishes the result for the pill and the monitor.
/// It lives from launch (`EczemaTwinApp.init`) and listens while the app is active.
///
/// When the watch's Stop arrives (its last batch says `live: false`) he woke up: `wokeUp` fires (Today
/// replays its entrance) and an open monitor closes itself with the morning greeting
/// (`LiveMonitorPresenter.watchDidStop()`); a closed one just loses its pill. 8 s without batches is
/// not a wake-up (the Wi-Fi may have stalled in the middle of the scratch demo): the session goes quiet
/// (`running` false: the pill hides, the monitor's bars flatten and its LIVE dot rests) and carries on
/// with the same count when batches come back. If the Stop itself was lost, Done on the quiet monitor
/// is the wake-up (`greetAfterQuiet()`).
///
/// Launch arguments:
///
///     -screen live              open the monitor at launch
///     -liveSim 1                the built-in stand-in watch instead of the relay (no network)
///     -liveSimStop <seconds>    …which taps Stop that long after tracking began
///     -liveSimQuiet <seconds>   …which goes silent that long after tracking began
///     -liveSimQuietFor <secs>   …for that long (default: for good)
///     -liveDone <seconds>       (Debug) with -screen live: tap Done that long after launch
///     -liveReplay <id>          (Debug) play a relay recording instead of the relay
///     -screen livepill          (Debug) Today's top bar with the pill, see `LivePillHarness`
@MainActor
final class LiveSession: ObservableObject {
    static let shared = LiveSession()

    /// The watch is tracking sleep: a batch arrived in the last 3.5 s and it wasn't `live: false`.
    @Published private(set) var tracking = false
    /// A scratch is going on right now.
    @Published private(set) var scratching = false
    /// Scratches tonight: episodes started in this tracking session.
    @Published private(set) var count = 0
    /// When this tracking session began.
    @Published private(set) var startedAt: Date?
    /// Tonight's episodes, oldest first.
    @Published private(set) var episodes: [LiveEpisode] = []
    /// A session runs from its first batch until the watch stops (or goes quiet for 8 s). Unlike
    /// `tracking` it rides out a few seconds without batches, so the monitor's bars don't flatten and
    /// the pill doesn't blink out on a network hiccup.
    @Published private(set) var running = false

    /// The scratch stopwatch (see `IntensityMeter`): seconds tonight with the wrist-motion intensity above
    /// the scratch threshold, how many times it crossed it, and whether it is above right now.
    @Published private(set) var scratchSeconds: Double = 0
    @Published private(set) var thresholdCount = 0
    @Published private(set) var aboveThreshold = false
    private var meter = IntensityMeter()

    /// A new session began (the watch's Start, or batches after a minute of silence): count from 0.
    let sessionStarted = PassthroughSubject<Void, Never>()
    /// He woke up: the watch's Stop arrived (or Done closed a monitor that had gone quiet). Last night is ready.
    let wokeUp = PassthroughSubject<Void, Never>()

    private var rules = LiveRelayState()
    private let relay: LiveRelayClient?
    private let simulator: LiveSimulator?
    #if DEBUG
    private var replay: LiveReplay?
    #endif
    /// The phone can hear the watch right now (socket up, or the stand-in running).
    private var listening = false
    /// When the phone stopped hearing the relay (socket down, app in the background).
    private var deafSince: Date?
    private var ticker: Task<Void, Never>?
    private var bag = Set<AnyCancellable>()
    /// Done already greeted the morning of this quiet session, so its late Stop doesn't do it again.
    private var greeted = false

    private init() {
        let defaults = UserDefaults.standard
        #if DEBUG
        let replayID = defaults.string(forKey: "liveReplay")
        #else
        let replayID: String? = nil
        #endif
        if let sim = defaults.string(forKey: "liveSim"), !["", "0", "NO", "no", "false"].contains(sim) {
            let stop = defaults.double(forKey: "liveSimStop")
            let quiet = defaults.double(forKey: "liveSimQuiet"), quietFor = defaults.double(forKey: "liveSimQuietFor")
            simulator = LiveSimulator(stopAfter: stop > 0 ? stop : nil, quietAt: quiet > 0 ? quiet : nil,
                                      quietFor: quietFor > 0 ? quietFor : nil)
            relay = nil
        } else if replayID != nil {
            simulator = nil
            relay = nil
        } else {
            simulator = nil
            relay = LiveRelayClient()
        }
        relay?.onMessage = { [weak self] message in self?.receive(message) }
        relay?.onConnect = { [weak self] in self?.startedListening() }
        relay?.onDisconnect = { [weak self] in self?.stoppedListening() }
        simulator?.onBatch = { [weak self] batch in self?.receive(.batch(batch)) }
        #if DEBUG
        if let replayID {
            let replay = LiveReplay(id: replayID)
            replay.onBatch = { [weak self] batch in self?.receive(.batch(batch)) }
            self.replay = replay
        }
        #endif

        let center = NotificationCenter.default
        // Hidden control "Reset tonight's count".
        center.publisher(for: .twinResetTonight)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.reset() }
            .store(in: &bag)
        // Listen while the app is active (the socket closes in the background).
        center.publisher(for: UIApplication.didBecomeActiveNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.appBecameActive() }
            .store(in: &bag)
        center.publisher(for: UIApplication.didEnterBackgroundNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.relay?.stop() }
            .store(in: &bag)
        // Created after launch (first used by a screen): the app is already active, start now.
        if UIApplication.shared.applicationState == .active {
            DispatchQueue.main.async { [weak self] in self?.appBecameActive() }
        }

        // `-screen live` opens the monitor at launch (after this object exists: the presenter reads it).
        if defaults.string(forKey: "screen") == "live" {
            let waitForTracking = relay == nil
            DispatchQueue.main.async {
                LiveMonitorPresenter.shared.openWhenReady(waitForTracking: waitForTracking)
            }
            #if DEBUG
            let done = defaults.double(forKey: "liveDone")
            if done > 0 {
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: UInt64(done * 1_000_000_000))
                    LiveMonitorPresenter.shared.close()
                }
            }
            #endif
        }
        #if DEBUG
        DispatchQueue.main.async { LivePillHarness.presentIfRequested() }
        #endif
    }

    /// Sets tonight's count back to zero (the hidden control, or the relay's `reset` message).
    func reset() {
        rules.reset(at: Date())
        LiveMotionFeed.shared.clear()
        resetStopwatch()
        publish()
    }

    /// Runs the meter over a batch's wrist motion (25 values a second, 0.04 s each).
    private func runStopwatch(_ motion: [Double]) {
        guard !motion.isEmpty else { return }
        var seconds = scratchSeconds, count = thresholdCount
        for m in motion {
            if meter.add(m) { count += 1 }
            if meter.above { seconds += 0.04 }
        }
        if seconds != scratchSeconds { scratchSeconds = seconds }
        if count != thresholdCount { thresholdCount = count }
        if meter.above != aboveThreshold { aboveThreshold = meter.above }
    }

    private func resetStopwatch() {
        meter.reset()
        scratchSeconds = 0
        thresholdCount = 0
        aboveThreshold = false
    }

    // MARK: - Input

    private func appBecameActive() {
        relay?.start()
        if let simulator {
            simulator.start()
            if !listening { startedListening() }
        }
        #if DEBUG
        if let replay {
            replay.start()
            if !listening { startedListening() }
        }
        #endif
    }

    private func startedListening() {
        let now = Date()
        if let deafSince { rules.notListening(from: deafSince, to: now) }
        deafSince = nil
        listening = true
    }

    private func stoppedListening() {
        listening = false
        deafSince = Date()
    }

    private func receive(_ message: LiveRelayMessage) {
        let now = Date()
        switch message {
        case .batch(let batch):
            let changes = rules.take(batch, at: now)
            if changes.contains(.sessionStarted) { LiveMotionFeed.shared.clear(); resetStopwatch() }
            if batch.live != false {
                LiveMotionFeed.shared.append(batch.motion)   // for the live graph
                runStopwatch(batch.motion)
            } else if aboveThreshold {
                aboveThreshold = false
            }
            if batch.live != false { greeted = false }        // the watch is (still) tracking
            publish(now)
            #if DEBUG
            for change in changes { print("[live] \(change) · count \(rules.count)") }
            #endif
            if changes.contains(.sessionStarted) { sessionStarted.send() }
            if changes.contains(.watchStopped) { watchStopped() }
            startTicking()
        case .reset:
            rules.reset(at: now)
            publish(now)
        case .other:
            break
        }
    }

    // MARK: - Time

    /// Ten times a second while anything can still change with time (the 1.2 s scratch hold,
    /// tracking's 3.5 s, the 8 s quiet rule); idle otherwise.
    private func startTicking() {
        guard ticker == nil else { return }
        ticker = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 100_000_000)
                guard let self else { return }
                if !self.tick() {
                    self.ticker = nil
                    return
                }
            }
        }
    }

    /// Returns false when nothing is left to change.
    private func tick() -> Bool {
        let now = Date()
        // Silence only counts while the phone can hear the relay. Going quiet is not a wake-up: the
        // pill and the monitor follow `running`, nothing closes or greets.
        let changes = listening ? rules.tick(at: now) : []
        publish(now)
        #if DEBUG
        for change in changes { print("[live] \(change) (silence)") }
        #endif
        return rules.isRunning || tracking || scratching
    }

    /// The watch's Stop: last night is ready.
    private func watchStopped() {
        defer { greeted = false }
        guard !greeted else { return }
        wokeUp.send()
        LiveMonitorPresenter.shared.watchDidStop()
    }

    /// Done on the monitor while the session is quiet (the watch's Stop never reached the phone): that was
    /// the wake-up. Fires `wokeUp` and returns true so the monitor greets the morning as it closes.
    func greetAfterQuiet() -> Bool {
        guard rules.isQuiet, !greeted else { return false }
        greeted = true
        wokeUp.send()
        return true
    }

    /// Copies the rules' state into the published properties (only what changed, so views redraw
    /// only when something did). The pill comes and goes with a spring.
    private func publish(_ now: Date = Date()) {
        let isTracking = rules.isTracking(at: now)
        if isTracking != tracking {
            withAnimation(isTracking ? Twin.Motion.bouncy : Twin.Motion.slide) { tracking = isTracking }
        }
        let isScratching = rules.isScratching(at: now)
        if isScratching != scratching { scratching = isScratching }
        if rules.count != count { count = rules.count }
        if rules.startedAt != startedAt { startedAt = rules.startedAt }
        // The pill shows while tracking or running: both come and go with a spring.
        if rules.isRunning != running {
            withAnimation(rules.isRunning ? Twin.Motion.bouncy : Twin.Motion.slide) { running = rules.isRunning }
        }
        let list = rules.episodes.map { LiveEpisode(id: $0.id, start: $0.start, end: $0.end) }
        if list != episodes { episodes = list }
    }
}
