import Foundation

/// Streaming scratch detector (SPEC §5).
///
/// Feed it 50 Hz accelerometer samples (g, gravity included) one at a time or in batches; every
/// 1.5 s it scores the last 3 s with the personal `ScratchModel` and turns the window verdicts into
/// episodes. Not thread-safe: use it from one queue.
///
///     let detector = ScratchDetector(model: model)
///     for event in detector.process(samples) { ... }
///     let tail = detector.finish()
public final class ScratchDetector {
    public let config: DetectorConfig
    public let source: EpisodeSource
    public private(set) var model: ScratchModel
    /// Windows scored so far.
    public private(set) var windowCount = 0
    /// Windows that passed the movement gate so far.
    public private(set) var movingCount = 0

    private let extractor: FeatureExtractor
    private var tracker: EpisodeTracker
    private var xs: [Double] = []
    private var ys: [Double] = []
    private var zs: [Double] = []
    private var ts: [TimeInterval] = []
    private var lastT: TimeInterval?
    /// Slow gravity estimate and the last time the wrist moved (for `quietSecondsToEnd`).
    private var gravity: (Double, Double, Double)?
    private var lastMotionT: TimeInterval?
    /// After a stillness end: windows starting before this reach back into the finished bout.
    private var noStartBefore: TimeInterval = -.infinity

    public init(model: ScratchModel = ScratchModel(), config: DetectorConfig = .standard, source: EpisodeSource = .live,
                lastAlert: Date? = nil) {
        self.model = model
        self.config = config
        self.source = source
        extractor = FeatureExtractor(config: config)
        tracker = EpisodeTracker(config: config, source: source, lastAlert: lastAlert)
        let n = config.windowLength
        xs.reserveCapacity(n); ys.reserveCapacity(n); zs.reserveCapacity(n); ts.reserveCapacity(n)
    }

    /// Use the latest personal model for the next windows (after the user answered a prompt).
    public func updateModel(_ model: ScratchModel) { self.model = model }

    /// true while an episode is open.
    public var isInEpisode: Bool { tracker.isInEpisode }

    /// Where to read the data again from when the stream is cut here and picked up later (batch
    /// analysis in pieces): the first window of an open episode, or of a lone scratch window that
    /// may still start one. Re-reading from there keeps one bout of scratching one episode.
    /// nil when nothing is pending.
    public var pendingSince: Date? { tracker.pendingSince.map { Date(timeIntervalSinceReferenceDate: $0) } }

    @discardableResult
    public func process(_ sample: MotionSample) -> [DetectorEvent] {
        var events: [DetectorEvent] = []
        if let last = lastT {
            if sample.t <= last { return [] }                       // duplicate or out of order
            if sample.t - last > config.maxSampleGap {              // hole in the data: start over
                events += tracker.finish()
                clearBuffer()
            }
        }
        lastT = sample.t
        if config.quietSecondsToEnd.isFinite {
            let g = gravity.map { ($0.0 + (sample.x - $0.0) * 0.04, $0.1 + (sample.y - $0.1) * 0.04, $0.2 + (sample.z - $0.2) * 0.04) }
                ?? (sample.x, sample.y, sample.z)
            gravity = g
            let dx = sample.x - g.0, dy = sample.y - g.1, dz = sample.z - g.2
            if (dx * dx + dy * dy + dz * dz).squareRoot() > config.stillLevel || lastMotionT == nil { lastMotionT = sample.t }
            if tracker.isInEpisode, let m = lastMotionT, sample.t - m >= config.quietSecondsToEnd {
                events += tracker.endNow()
                noStartBefore = sample.t - config.hopSeconds
            }
        }
        xs.append(sample.x); ys.append(sample.y); zs.append(sample.z); ts.append(sample.t)
        if xs.count == config.windowLength {
            let f = extractor.features(x: xs, y: ys, z: zs, start: ts[0])
            let p = model.probability(f)
            let result = WindowResult(features: f, probability: p,
                                     isScratch: f.moving && p >= config.threshold && f.strength <= config.maxStrength
                                         && (f.kurtosis ?? 0) <= config.maxKurtosis
                                         && (f.impulsiveness ?? 0) <= config.maxImpulsiveness)
            windowCount += 1
            if f.moving { movingCount += 1 }
            events.append(.window(result))
            if result.isScratch, f.start < noStartBefore, !tracker.isInEpisode {
                // Mostly the bout that just ended: show the window, but don't restart that bout.
                events += tracker.feed(WindowResult(features: f, probability: p, isScratch: false))
            } else {
                events += tracker.feed(result)
            }
            let hop = min(config.hopLength, xs.count)
            xs.removeFirst(hop); ys.removeFirst(hop); zs.removeFirst(hop); ts.removeFirst(hop)
        }
        return events
    }

    @discardableResult
    public func process<S: Sequence>(_ samples: S) -> [DetectorEvent] where S.Element == MotionSample {
        var events: [DetectorEvent] = []
        for s in samples { events += process(s) }
        return events
    }

    /// End of the data: closes an open episode.
    @discardableResult
    public func finish() -> [DetectorEvent] {
        clearBuffer()
        lastT = nil
        return tracker.finish()
    }

    private func clearBuffer() {
        xs.removeAll(keepingCapacity: true); ys.removeAll(keepingCapacity: true)
        zs.removeAll(keepingCapacity: true); ts.removeAll(keepingCapacity: true)
        gravity = nil; lastMotionT = nil
    }

    /// Batch analysis (e.g. one hour of `CMSensorRecorder` data): every finished episode, no alerts.
    public static func episodes<S: Sequence>(in samples: S, model: ScratchModel, config: DetectorConfig = .standard,
                                             source: EpisodeSource = .recorded) -> [DetectedEpisode] where S.Element == MotionSample {
        let detector = ScratchDetector(model: model, config: config, source: source)
        let events = detector.process(samples) + detector.finish()
        return events.compactMap { if case let .episodeEnded(e) = $0 { return e } else { return nil } }
    }
}

public extension Array where Element == DetectorEvent {
    var windows: [WindowResult] { compactMap { if case let .window(w) = $0 { return w } else { return nil } } }
    var starts: [EpisodeStart] { compactMap { if case let .episodeStarted(s) = $0 { return s } else { return nil } } }
    var episodes: [DetectedEpisode] { compactMap { if case let .episodeEnded(e) = $0 { return e } else { return nil } } }
}
