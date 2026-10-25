import SwiftUI
import WatchKit
import EczemaKit

/// Watch app state: live detection on or off, tonight's scratch count, and whether the big screen
/// gets the stream.
///
/// Out of sight it keeps doing what it did: real live episodes are saved on the watch and handed
/// to the iPhone, and the all-day recording is read when the app opens and in background refreshes.
///
/// Launch argument (scripts/watchshot): `-live 1` starts live detection right away.
@MainActor
final class WatchModel: ObservableObject {
    static let shared = WatchModel()

    enum LiveState: Equatable {
        case off
        case starting
        case on(since: Date, backing: LiveMonitor.Backing)
        var isOn: Bool { if case .on = self { return true } else { return false } }
    }

    @Published private(set) var live: LiveState = .off
    /// Scratches detected tonight: counted from Start, kept after Stop until the next Start.
    @Published private(set) var scratches = 0
    /// A scratch is going on (from its detection until the wrist settles).
    @Published private(set) var scratching = false
    /// Big-screen relay: true = last send arrived, false = failing, nil = not sending.
    @Published private(set) var screenLink: Bool?
    /// Why the last send to the big screen failed (URL error code, HTTP status), or "" when it worked.
    @Published private(set) var screenDetail = ""
    @Published private(set) var screenSent = 0

    private let store = WatchStore()
    private let link = PhoneLink.shared
    private let monitor = LiveMonitor()
    private let recorder = BackgroundRecorder()
    private var analyzing = false
    private var analysisCancel: BackgroundRecorder.Cancel?

    init() {
        monitor.onEvent = { [weak self] event in self?.handle(event) }
        LiveStreamer.shared.onStatus = { [weak self] status in
            guard let self, self.live != .off else { return }
            if self.screenDetail != status.detail { self.screenDetail = status.detail }
            if self.screenSent != status.sent { self.screenSent = status.sent }
            guard self.screenLink != status.ok else { return }
            withAnimation(Twin.Motion.spring) { self.screenLink = status.ok }
        }
        link.onActivated = { [weak self] in self?.syncToPhone() }
        link.onFailed = { [weak self] ids in self?.store.markUnsent(ids) }
        link.activate()

        if UserDefaults.standard.bool(forKey: "live") {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(700))
                self?.toggleLive()
            }
        }
    }

    // MARK: - Lifecycle

    func appBecameActive() {
        monitor.appBecameActive()
        if let until = recorder.armIfNeeded(armedUntil: store.book.recorderArmedUntil) {
            store.setRecorderArmedUntil(until)
        }
        Task { await analyzeRecordings(.appOpen) }
        syncToPhone()
        scheduleBackgroundRefresh()
    }

    /// Twin left the screen: stop reading the recording (the rest waits) and save.
    func appMovedToBackground() {
        analysisCancel?.cancel()
        Task { await store.flush() }
    }

    /// Background refresh: read a little of the recording, hand new episodes to the iPhone, book
    /// the next refresh, and save before watchOS suspends the app.
    func backgroundRefresh() async {
        await analyzeRecordings(.backgroundRefresh)
        syncToPhone()
        scheduleBackgroundRefresh()
        await store.flush()
    }

    /// The background task is out of time: stop reading (what was read is kept).
    func cancelAnalysis() { analysisCancel?.cancel() }

    /// Reads the all-day recording from where the last run stopped, within `budget`.
    func analyzeRecordings(_ budget: BackgroundRecorder.Budget) async {
        guard !analyzing, BackgroundRecorder.isAvailable else { return }
        analyzing = true
        let cancel = BackgroundRecorder.Cancel()
        analysisCancel = cancel
        defer {
            analyzing = false
            analysisCancel = nil
        }
        let from = store.book.analyzedThrough ?? Date().addingTimeInterval(-BackgroundRecorder.recordingLength)
        guard let result = await recorder.analyze(from: from, model: store.model, budget: budget, cancel: cancel) else { return }
        let added = store.addRecorded(result.episodes, analyzedThrough: result.through)
        guard !added.isEmpty else { return }
        syncToPhone()
    }

    func scheduleBackgroundRefresh() {
        guard BackgroundRecorder.isAvailable else { return }
        WKApplication.shared().scheduleBackgroundRefresh(withPreferredDate: Date().addingTimeInterval(15 * 60), userInfo: nil) { _ in }
    }

    // MARK: - Live detection

    /// Start begins a new night: the count goes back to zero.
    func toggleLive() {
        switch live {
        case .off:
            WatchHaptic.play(.start)
            withAnimation(Twin.Motion.spring) {
                live = .starting
                scratches = 0
            }
            Task { await monitor.start(model: store.model, lastAlert: nil) }
        case .starting, .on:
            WatchHaptic.play(.stop)
            monitor.stop()
        }
    }

    private func handle(_ event: LiveMonitor.Event) {
        switch event {
        case let .started(backing, since):
            withAnimation(Twin.Motion.spring) { live = .on(since: since, backing: backing) }
        case let .backingChanged(backing):
            if case let .on(since, _) = live { withAnimation(Twin.Motion.spring) { live = .on(since: since, backing: backing) } }
        case .stopped:
            withAnimation(Twin.Motion.spring) {
                live = .off
                scratching = false
                screenLink = nil
                screenDetail = ""
                screenSent = 0
            }
        case .window:
            break
        case .episodeStarted:
            guard live != .off else { return }               // a late event from a run that just stopped
            WatchHaptic.play(.directionUp)                   // light: one tick up per scratch
            withAnimation(Twin.Motion.bouncy) {
                scratches += 1
                scratching = true
            }
        case let .episodeEnded(detected):
            if scratching { withAnimation(Twin.Motion.spring) { scratching = false } }
            save(detected)
        }
    }

    /// Real episodes are kept on the watch and go to the iPhone; the simulator's scripted wrist
    /// (source `.demo`) only counts on screen.
    private func save(_ detected: DetectedEpisode) {
        let e = detected.episode
        guard e.source != .demo else { return }
        store.add([e])
        store.setEvidence(detected.windows, for: e.id)
        syncToPhone()
    }

    // MARK: - iPhone

    /// Sends real episodes the iPhone hasn't had yet.
    func syncToPhone() {
        let pending = store.unsent()
        if !pending.isEmpty, link.send(pending) { store.markSent(pending.map(\.id)) }
    }
}
