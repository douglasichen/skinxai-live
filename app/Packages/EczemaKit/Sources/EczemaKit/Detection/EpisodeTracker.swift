import Foundation

/// The detector's verdict on one window.
public struct WindowResult: Sendable, Hashable {
    public var features: WindowFeatures
    public var probability: Double
    public var isScratch: Bool

    public init(features: WindowFeatures, probability: Double, isScratch: Bool) {
        self.features = features; self.probability = probability; self.isScratch = isScratch
    }

    public var start: Date { features.startDate }
}

/// Sent as soon as an episode is confirmed (second scratch window), so the watch can ask right away.
public struct EpisodeStart: Sendable, Hashable, Identifiable {
    /// The id the finished `ScratchEpisode` will carry.
    public var id: UUID
    public var start: Date
    /// false when another alert went out less than `alertCooldown` seconds ago.
    public var shouldAlert: Bool
    /// Features of the scratch windows so far (to learn from the user's answer).
    public var windows: [WindowFeatures]
    public var meanHz: Double
}

/// A finished episode plus the window features it was built from.
public struct DetectedEpisode: Sendable, Hashable, Identifiable {
    public var episode: ScratchEpisode
    public var windows: [WindowFeatures]
    public var id: UUID { episode.id }
}

public enum DetectorEvent: Sendable, Hashable {
    case window(WindowResult)
    case episodeStarted(EpisodeStart)
    case episodeEnded(DetectedEpisode)
}

/// Episode logic (SPEC §5): an episode is >= 2 scratch windows in a row, allowing a 1-window gap.
/// Its ends are trimmed by half a hop (windows overlap). `intense` = mean motion SD >= 0.35 g.
struct EpisodeTracker {
    let config: DetectorConfig
    let source: EpisodeSource
    private(set) var lastAlert: TimeInterval?

    private enum State {
        case idle
        /// One scratch window seen; `gap` non-scratch windows since.
        case candidate(WindowResult, gap: Int)
        case active(id: UUID, windows: [WindowResult], gap: Int)
    }
    private var state: State = .idle

    init(config: DetectorConfig, source: EpisodeSource, lastAlert: Date? = nil) {
        self.config = config
        self.source = source
        self.lastAlert = lastAlert?.timeIntervalSinceReferenceDate
    }

    var isInEpisode: Bool {
        if case .active = state { return true }
        return false
    }

    /// Start of the first window that can still end up in an episode: the open episode's first
    /// window, or a lone scratch window waiting for a second one. nil when nothing is pending.
    var pendingSince: TimeInterval? {
        switch state {
        case .idle: return nil
        case let .candidate(first, _): return first.features.start
        case let .active(_, windows, _): return windows.first?.features.start
        }
    }

    mutating func feed(_ w: WindowResult) -> [DetectorEvent] {
        switch state {
        case .idle:
            guard w.isScratch else { return [] }
            if config.minWindows <= 1 { return begin(with: [w]) }
            state = .candidate(w, gap: 0)
            return []
        case let .candidate(first, gap):
            if w.isScratch { return begin(with: [first, w]) }
            state = gap >= 1 ? .idle : .candidate(first, gap: gap + 1)
            return []
        case let .active(id, windows, gap):
            if w.isScratch {
                state = .active(id: id, windows: windows + [w], gap: 0)
                return []
            }
            if gap + 1 >= config.quietWindowsToEnd {
                state = .idle
                return [.episodeEnded(makeEpisode(id: id, windows: windows))]
            }
            state = .active(id: id, windows: windows, gap: gap + 1)
            return []
        }
    }

    private mutating func begin(with windows: [WindowResult]) -> [DetectorEvent] {
        let id = UUID()
        state = .active(id: id, windows: windows, gap: 0)
        let start = windows[0].features.start + config.hopSeconds / 2
        let alert = lastAlert.map { start - $0 >= config.alertCooldown } ?? true
        if alert { lastAlert = start }
        return [.episodeStarted(EpisodeStart(id: id, start: Date(timeIntervalSinceReferenceDate: start), shouldAlert: alert,
                                             windows: windows.map(\.features), meanHz: Self.meanHz(windows)))]
    }

    /// The wrist went still: close an open episode now (nothing if none is open).
    mutating func endNow() -> [DetectorEvent] {
        guard case let .active(id, windows, _) = state else { return [] }
        state = .idle
        return [.episodeEnded(makeEpisode(id: id, windows: windows))]
    }

    /// End of the stream: close an open episode, forget a lone scratch window.
    mutating func finish() -> [DetectorEvent] {
        defer { state = .idle }
        if case let .active(id, windows, _) = state { return [.episodeEnded(makeEpisode(id: id, windows: windows))] }
        return []
    }

    private func makeEpisode(id: UUID, windows: [WindowResult]) -> DetectedEpisode {
        let first = windows.first!.features, last = windows.last!.features
        let start = first.start + config.hopSeconds / 2
        let end = max(start + config.hopSeconds, last.start + config.windowSeconds - config.hopSeconds / 2)
        let rms = windows.map(\.features.strength).reduce(0, +) / Double(windows.count)
        let episode = ScratchEpisode(id: id, start: Date(timeIntervalSinceReferenceDate: start),
                                     end: Date(timeIntervalSinceReferenceDate: end),
                                     meanHz: Self.meanHz(windows), meanRMS: rms, intense: rms >= config.intenseSD, source: source)
        return DetectedEpisode(episode: episode, windows: windows.map(\.features))
    }

    private static func meanHz(_ windows: [WindowResult]) -> Double {
        let rates = windows.map(\.features.dominantHz).filter { $0 > 0 }
        return rates.isEmpty ? 0 : rates.reduce(0, +) / Double(rates.count)
    }
}
