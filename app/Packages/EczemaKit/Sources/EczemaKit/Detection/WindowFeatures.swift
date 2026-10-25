import Foundation

/// What one 3-second window of wrist motion looks like.
public struct WindowFeatures: Sendable, Hashable, Codable {
    /// Window start, seconds since the reference date.
    public var start: TimeInterval
    /// SD of each axis after removing the window mean (gravity), g.
    public var axisSD: [Double]
    /// Overall motion strength: SD of the motion vector, g.
    public var strength: Double
    /// Passed the movement gate (largest per-axis SD above the gate).
    public var moving: Bool
    /// Axis with the most motion (0 = x, 1 = y, 2 = z).
    public var axis: Int
    /// Back-and-forth rate of the dominant axis, Hz (0 = no rhythm found).
    public var dominantHz: Double
    /// Height of the autocorrelation peak at the dominant rate (0...1).
    public var periodicity: Double
    /// Share of motion power inside the scratch band (2.5–7 Hz), 0...1.
    public var inBand: Double
    /// Zero-crossing rate of the dominant axis, expressed in Hz (crossings / 2 / second).
    public var crossingHz: Double
    /// log10(strength / movement gate), clamped to 0...1.5.
    public var logStrength: Double
    /// How scratch-like the crossing rate is, 0...1 (1 inside 2.5–7.5 Hz, fading to 0 at 1.5 and 12 Hz).
    public var crossingScore: Double
    /// Kurtosis of the dominant axis: about 1.5–3 for a smooth back-and-forth (scratching), well above 5
    /// for a train of impacts (patting a thigh, tapping). nil in data saved before it existed.
    public var kurtosis: Double?
    /// Kurtosis of the dominant axis measured only where the wrist is moving: the median over 0.6 s
    /// pieces that carry real motion. A short scratch inside a quiet window stays low (about 2–4),
    /// a train of pats stays high (5–10). nil in data saved before it existed.
    public var impulsiveness: Double?

    public init(start: TimeInterval, axisSD: [Double], strength: Double, moving: Bool, axis: Int, dominantHz: Double,
                periodicity: Double, inBand: Double, crossingHz: Double, logStrength: Double, crossingScore: Double,
                kurtosis: Double? = nil, impulsiveness: Double? = nil) {
        self.start = start; self.axisSD = axisSD; self.strength = strength; self.moving = moving; self.axis = axis
        self.dominantHz = dominantHz; self.periodicity = periodicity; self.inBand = inBand; self.crossingHz = crossingHz
        self.logStrength = logStrength; self.crossingScore = crossingScore; self.kurtosis = kurtosis
        self.impulsiveness = impulsiveness
    }

    /// Inputs of the logistic model, in `ScratchModel.featureNames` order.
    public var inputs: [Double] { [periodicity, inBand, logStrength, crossingScore] }

    public var startDate: Date { Date(timeIntervalSinceReferenceDate: start) }
}

/// Turns a window of raw samples into `WindowFeatures` (SPEC §5).
///
/// - Gravity is removed by subtracting each axis mean in the window.
/// - Movement gate: largest per-axis SD > 0.02 g (Lilly 2023).
/// - The axis with the most motion is analysed: its normalised autocorrelation is searched for
///   peaks in the 1.5–10 Hz band; the dominant rate is the *first* peak that is at least 0.85x the
///   highest one, and periodicity is that peak's height.
/// - In-band score: share of the (Hann-windowed) power spectrum between 2.5 and 7 Hz.
/// - Zero-crossing rate with a small hysteresis so sensor noise does not count.
public struct FeatureExtractor: Sendable {
    public let config: DetectorConfig
    private let n: Int
    private let hann: [Double]
    private let bandCos: [Double]
    private let bandSin: [Double]
    private let bandCount: Int
    private let minLag: Int
    private let maxLag: Int

    public init(config: DetectorConfig = .standard) {
        self.config = config
        let n = config.windowLength
        self.n = n
        hann = (0..<n).map { 0.5 - 0.5 * cos(2 * Double.pi * Double($0) / Double(n - 1)) }
        let df = config.sampleRate / Double(n)
        let bins = (1..<(n / 2)).filter { k in
            let f = Double(k) * df
            return f >= config.scratchBand.lowerBound - 1e-9 && f <= config.scratchBand.upperBound + 1e-9
        }
        var c: [Double] = [], s: [Double] = []
        c.reserveCapacity(bins.count * n); s.reserveCapacity(bins.count * n)
        for k in bins {
            for i in 0..<n {
                let a = 2 * Double.pi * Double(k * i) / Double(n)
                c.append(cos(a)); s.append(sin(a))
            }
        }
        bandCos = c; bandSin = s; bandCount = bins.count
        minLag = max(2, Int((config.sampleRate / config.rateBand.upperBound).rounded(.down)))
        maxLag = min(n - 3, Int((config.sampleRate / config.rateBand.lowerBound).rounded(.up)))
    }

    /// Features of one window. The three arrays must hold `config.windowLength` samples.
    public func features(x: [Double], y: [Double], z: [Double], start: TimeInterval) -> WindowFeatures {
        precondition(x.count == n && y.count == n && z.count == n, "window length")
        var demeaned: [[Double]] = []
        var sds: [Double] = []
        for axis in [x, y, z] {
            let mean = axis.reduce(0, +) / Double(n)
            let d = axis.map { $0 - mean }
            demeaned.append(d)
            sds.append(sqrt(d.reduce(0) { $0 + $1 * $1 } / Double(n)))
        }
        let maxSD = sds.max() ?? 0
        let axis = sds.firstIndex(of: maxSD) ?? 0
        let strength = sqrt(sds.reduce(0) { $0 + $1 * $1 })
        let moving = maxSD > config.movementGate
        let logStrength = min(1.5, max(0, log10(max(strength, config.movementGate) / config.movementGate)))
        guard moving else {
            return WindowFeatures(start: start, axisSD: sds, strength: strength, moving: false, axis: axis, dominantHz: 0,
                                  periodicity: 0, inBand: 0, crossingHz: 0, logStrength: logStrength, crossingScore: 0)
        }
        let d = demeaned[axis]
        let rate = dominantRate(d)
        let inBand = bandShare(d)
        let crossingHz = crossingRate(d, sd: maxSD)
        return WindowFeatures(start: start, axisSD: sds, strength: strength, moving: true, axis: axis,
                              dominantHz: rate.hz, periodicity: rate.height, inBand: inBand, crossingHz: crossingHz,
                              logStrength: logStrength, crossingScore: Self.crossingScore(crossingHz, band: config.crossingBand),
                              kurtosis: Self.kurtosis(d),
                              impulsiveness: Self.impulsiveness(d, piece: max(8, Int((0.6 * config.sampleRate).rounded())),
                                                                gate: config.movementGate))
    }

    /// Median kurtosis over overlapping pieces (`piece` samples, half-piece steps) whose RMS is at
    /// least the movement gate and 30% of the busiest piece.
    public static func impulsiveness(_ d: [Double], piece: Int, gate: Double) -> Double {
        guard d.count >= piece else { return kurtosis(d) }
        var rms: [Double] = [], ks: [Double] = []
        var s = 0
        while s + piece <= d.count {
            let slice = Array(d[s..<(s + piece)])
            let mean = slice.reduce(0, +) / Double(piece)
            let b = slice.map { $0 - mean }
            let r = (b.reduce(0) { $0 + $1 * $1 } / Double(piece)).squareRoot()
            rms.append(r); ks.append(kurtosis(b))
            s += max(1, piece / 2)
        }
        let floor = max(gate, 0.3 * (rms.max() ?? 0))
        let active = zip(rms, ks).filter { $0.0 >= floor }.map(\.1).sorted()
        guard !active.isEmpty else { return 0 }
        let m = active.count / 2
        return active.count % 2 == 1 ? active[m] : (active[m - 1] + active[m]) / 2
    }

    /// Fourth moment over the squared second moment of an already de-meaned signal.
    public static func kurtosis(_ d: [Double]) -> Double {
        guard !d.isEmpty else { return 0 }
        var m2 = 0.0, m4 = 0.0
        for v in d { let q = v * v; m2 += q; m4 += q * q }
        m2 /= Double(d.count); m4 /= Double(d.count)
        return m2 > 1e-12 ? m4 / (m2 * m2) : 0
    }

    /// 1 inside 2.5–7.5 Hz, fading linearly to 0 at 1.5 Hz and at 12 Hz (sensor noise crosses ~12 Hz).
    /// 1 inside `band`, fading linearly to 0 one hertz below it and at 12 Hz (or 4.5 Hz above it if higher).
    public static func crossingScore(_ hz: Double, band: ClosedRange<Double>) -> Double {
        if band == 2.5...7.5 { return crossingScore(hz) }
        let lo = band.lowerBound, hi = band.upperBound, top = max(12, hi + 1)
        if hz < lo - 1 { return 0 }
        if hz < lo { return hz - (lo - 1) }
        if hz <= hi { return 1 }
        if hz < top { return (top - hz) / (top - hi) }
        return 0
    }

    public static func crossingScore(_ hz: Double) -> Double {
        switch hz {
        case ..<1.5: return 0
        case ..<2.5: return hz - 1.5
        case ...7.5: return 1
        case ..<12: return (12 - hz) / 4.5
        default: return 0
        }
    }

    // MARK: - Pieces

    /// First autocorrelation peak in the rate band that is >= peakFraction x the highest peak.
    private func dominantRate(_ d: [Double]) -> (hz: Double, height: Double) {
        let energy = d.reduce(0) { $0 + $1 * $1 } / Double(n)
        guard energy > 0 else { return (0, 0) }
        var r = [Double](repeating: 0, count: maxLag + 2)
        for k in (minLag - 1)...(maxLag + 1) {
            var s = 0.0
            for i in 0..<(n - k) { s += d[i] * d[i + k] }
            r[k] = max(-1, min(1, (s / Double(n - k)) / energy))
        }
        var peaks: [(lag: Double, height: Double)] = []
        for k in minLag...maxLag where r[k] > 0 && r[k] > r[k - 1] && r[k] >= r[k + 1] {
            let a = r[k - 1], b = r[k], c = r[k + 1]
            let denom = a - 2 * b + c
            var delta = 0.0
            if denom < 0 { delta = max(-0.5, min(0.5, 0.5 * (a - c) / denom)) }
            let lag = Double(k) + delta
            let height = min(1, b - 0.25 * (a - c) * delta)
            let hz = config.sampleRate / lag
            if config.rateBand.contains(hz) { peaks.append((lag, height)) }
        }
        guard let highest = peaks.map(\.height).max(), highest > 0 else { return (0, 0) }
        guard let first = peaks.first(where: { $0.height >= config.peakFraction * highest }) else { return (0, 0) }
        return (config.sampleRate / first.lag, max(0, first.height))
    }

    /// Share of power (DC excluded) between 2.5 and 7 Hz, from a Hann-windowed DFT of the band bins
    /// and Parseval's theorem for the total.
    private func bandShare(_ d: [Double]) -> Double {
        var xw = [Double](repeating: 0, count: n)
        var sumSq = 0.0, dc = 0.0
        for i in 0..<n {
            let v = d[i] * hann[i]
            xw[i] = v; sumSq += v * v; dc += v
        }
        let total = Double(n) * sumSq - dc * dc
        guard total > 1e-12 else { return 0 }
        var band = 0.0
        for j in 0..<bandCount {
            var re = 0.0, im = 0.0
            let base = j * n
            for i in 0..<n {
                re += xw[i] * bandCos[base + i]
                im -= xw[i] * bandSin[base + i]
            }
            band += 2 * (re * re + im * im)
        }
        return min(1, max(0, band / total))
    }

    /// Zero crossings with hysteresis (10% of the SD), expressed as a rate in Hz.
    private func crossingRate(_ d: [Double], sd: Double) -> Double {
        let h = max(0.1 * sd, 0.002)
        var crossings = 0
        var side = 0
        for v in d {
            if v > h {
                if side < 0 { crossings += 1 }
                side = 1
            } else if v < -h {
                if side > 0 { crossings += 1 }
                side = -1
            }
        }
        let seconds = Double(n) / config.sampleRate
        return Double(crossings) / (2 * seconds)
    }
}
