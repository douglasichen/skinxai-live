import Foundation

/// One accelerometer reading from the wrist, in g, gravity included.
public struct MotionSample: Sendable, Hashable, Codable {
    /// Seconds since the reference date (`Date.timeIntervalSinceReferenceDate`).
    public var t: TimeInterval
    public var x: Double
    public var y: Double
    public var z: Double

    public init(t: TimeInterval, x: Double, y: Double, z: Double) {
        self.t = t; self.x = x; self.y = y; self.z = z
    }

    public init(date: Date, x: Double, y: Double, z: Double) {
        self.init(t: date.timeIntervalSinceReferenceDate, x: x, y: y, z: z)
    }

    public var date: Date { Date(timeIntervalSinceReferenceDate: t) }
}

/// Settings of the scratch detector (SPEC §5). The defaults are the tuned values; tests use them too.
public struct DetectorConfig: Sendable, Hashable {
    /// Accelerometer rate the detector expects (CMMotionManager and CMSensorRecorder both give 50 Hz).
    public var sampleRate: Double = 50
    /// Analysis window and hop: 3-second windows every 1.5 seconds.
    public var windowSeconds: Double = 3
    public var hopSeconds: Double = 1.5
    /// Movement gate: the window counts as "moving" when the largest per-axis SD is above this (g).
    public var movementGate: Double = 0.02
    /// Band searched for the back-and-forth rate (autocorrelation peaks), Hz.
    public var rateBand: ClosedRange<Double> = 1.5...10
    /// Band that scratching usually lives in (in-band power score), Hz.
    public var scratchBand: ClosedRange<Double> = 2.5...7
    /// Zero-crossing rates scored 1 (scratch-like); the score fades to 0 one hertz below and at 12 Hz.
    public var crossingBand: ClosedRange<Double> = 2.5...7.5
    /// A pure rhythm also peaks at 2x and 3x its period: take the first peak at least this high
    /// relative to the highest one.
    public var peakFraction: Double = 0.85
    /// Window probability at or above which the window counts as scratching.
    public var threshold: Double = 0.5
    /// Episodes whose mean motion SD is at least this are "intense" (g).
    public var intenseSD: Double = 0.35
    /// Buzz at most once per this many seconds.
    public var alertCooldown: TimeInterval = 45
    /// A hole in the sample stream longer than this ends the current episode and restarts the windows.
    public var maxSampleGap: TimeInterval = 0.5
    /// Scratch windows in a row needed to start an episode (2 = about 4.5 s of scratching, 1 = 3 s).
    public var minWindows: Int = 2
    /// Windows moving harder than this (g) never count as scratching. Off by default: real hard
    /// scratching reaches 2.5 g, more than waving.
    public var maxStrength: Double = .infinity
    /// Windows whose dominant axis is spikier than this (kurtosis) never count: impacts such as patting
    /// a thigh (6–10 in recordings) rather than a back-and-forth (scratching 2–4.5).
    public var maxKurtosis: Double = .infinity
    /// Same idea measured only where the wrist moves (`WindowFeatures.impulsiveness`), so a short
    /// scratch inside a mostly quiet window is not mistaken for a pat.
    public var maxImpulsiveness: Double = .infinity
    /// Quiet windows in a row that end an episode (2 = the SPEC's one-window grace; 1 = end at the
    /// first quiet window, so a new scratch a few seconds later counts as a new one).
    public var quietWindowsToEnd: Int = 2
    /// End an open episode as soon as the wrist has been still this long (seconds), without waiting
    /// for the overlapping windows to go quiet; windows reaching back into that bout can't restart it.
    /// Off (infinity) by default.
    public var quietSecondsToEnd: Double = .infinity
    /// Motion (gravity removed, g) below which a sample counts as still for `quietSecondsToEnd`.
    public var stillLevel: Double = 0.04

    public init() {}

    public static let standard = DetectorConfig()

    /// Live detection on the wrist (stage demo + real use): reacts after one 3 s window. Tuned on a
    /// labelled recording from a real Apple Watch (light/normal/hard/head scratching vs patting a thigh,
    /// waving, typing, talking with hands): a stricter probability keeps typing out, and the kurtosis
    /// limit keeps patting out while hard scratching still counts.
    public static let live: DetectorConfig = {
        var c = DetectorConfig()
        c.movementGate = 0.012
        c.threshold = LiveTuning.threshold
        c.minWindows = 1
        c.maxImpulsiveness = LiveTuning.maxImpulsiveness
        c.windowSeconds = LiveTuning.windowSeconds
        c.hopSeconds = LiveTuning.hopSeconds
        c.quietWindowsToEnd = 4
        c.quietSecondsToEnd = LiveTuning.quietSecondsToEnd
        c.stillLevel = LiveTuning.stillLevel
        c.scratchBand = LiveTuning.scratchBand
        c.crossingBand = LiveTuning.crossingBand
        c.alertCooldown = 20
        return c
    }()

    /// Samples per window (150 at 50 Hz).
    public var windowLength: Int { max(8, Int((windowSeconds * sampleRate).rounded())) }
    /// Samples per hop (75 at 50 Hz).
    public var hopLength: Int { max(1, Int((hopSeconds * sampleRate).rounded())) }
}

/// The live preset's tuned numbers in one place (from labelled recordings on a real watch).
/// Short bursts spliced from that recording: every 1–3 s scratch caught about 1 s after it starts.
public enum LiveTuning {
    public static let threshold = 0.45
    public static let maxImpulsiveness = 5.0
    public static let windowSeconds = 3.0
    public static let hopSeconds = 0.5
    public static let quietSecondsToEnd = 1.0
    public static let stillLevel = 0.02
    /// Wider than the standard 2.5–7 Hz: slow strokes (~2 Hz) and fast finger scratching (~9 Hz)
    /// count too. Waving (~1.7 Hz) sometimes passes; preferred over missing a scratch.
    public static let scratchBand: ClosedRange<Double> = 1.4...10
    public static let crossingBand: ClosedRange<Double> = 1.5...10
}
