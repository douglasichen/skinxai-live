import Foundation

/// Deterministic synthetic wrist accelerometer signals (50 Hz, g, gravity included).
///
/// Used by the unit tests (scratching vs walking, typing, stillness, a roll-over) and by the watch
/// simulator, which has no accelerometer, to run the real detector end to end.
///
///     var b = SyntheticMotion(start: 0)
///     b.still(5); b.scratch(10, hz: 4); b.still(5)
///     let samples = b.samples
public struct SyntheticMotion {
    public static let rate = 50.0
    public private(set) var samples: [MotionSample] = []
    public private(set) var time: TimeInterval
    private var rng: SplitMix64
    /// Current gravity direction (changes after a roll-over).
    private var gravity: (x: Double, y: Double, z: Double) = SyntheticMotion.unit(0.08, -0.22, -0.97)

    public init(start: TimeInterval = 0, seed: UInt64 = 0x5C2A_7C11) {
        time = start
        rng = SplitMix64(seed: seed)
    }

    // MARK: - Segments

    /// Wrist at rest: sensor noise and a little breathing.
    public mutating func still(_ seconds: Double) {
        let phase = rng.next() * 2 * .pi
        emit(seconds) { tt, g, rng in
            let breath = 0.003 * sin(2 * .pi * 0.25 * tt + phase)
            return (g.x + rng.gauss(0.004), g.y + breath + rng.gauss(0.004), g.z + rng.gauss(0.004))
        }
    }

    /// Back-and-forth scratching at `hz`, `amplitude` g peak on the main direction, with natural
    /// jitter in rate and strength, a second harmonic and a small cross-axis wobble.
    public mutating func scratch(_ seconds: Double, hz: Double = 4, amplitude: Double = 0.25) {
        let u = Self.unit(0.82, 0.48, 0.31)
        let v = Self.unit(-0.40, 0.85, 0.20)
        var phase = rng.next() * 2 * .pi
        let jitterPhase = rng.next() * 2 * .pi
        let rate = Self.rate
        emit(seconds) { tt, g, rng in
            let f = hz * (1 + 0.04 * sin(2 * .pi * 0.37 * tt + jitterPhase))
            phase += 2 * .pi * f / rate
            let envelope = min(1, tt / 0.25) * min(1, max(0, seconds - tt) / 0.25)
            let a = amplitude * (0.86 + 0.14 * sin(2 * .pi * 0.6 * tt)) * envelope
            let main = a * (sin(phase) + 0.25 * sin(2 * phase + 0.6))
            let wobble = 0.3 * a * sin(phase + 1.1)
            let drift = 0.02 * sin(2 * .pi * 0.21 * tt)
            return (g.x + main * u.x + wobble * v.x + drift + rng.gauss(0.012),
                    g.y + main * u.y + wobble * v.y + rng.gauss(0.012),
                    g.z + main * u.z + wobble * v.z + rng.gauss(0.012))
        }
    }

    /// Walking: arm swing at 0.9 Hz, body bounce at the 1.8 Hz step rate, a heel-strike ring per step.
    /// A small `armSwing` (hands in pockets, carrying a bag) leaves the step rhythm as the main motion.
    public mutating func walk(_ seconds: Double, armSwing: Double = 0.32) {
        emit(seconds) { tt, g, rng in
            let swing = armSwing * sin(2 * .pi * 0.9 * tt)
            let bounce = 0.10 * sin(2 * .pi * 1.8 * tt + 0.4) + 0.035 * sin(2 * .pi * 3.6 * tt + 1.0)
            let sinceStep = (tt * 1.8).truncatingRemainder(dividingBy: 1) / 1.8
            let strike = 0.12 * exp(-sinceStep * 18) * sin(2 * .pi * 9 * sinceStep)
            return (g.x + swing + rng.gauss(0.015),
                    g.y + 0.25 * swing + 0.4 * bounce + rng.gauss(0.015),
                    g.z + bounce + strike + rng.gauss(0.015))
        }
    }

    /// Typing: irregular key taps, each a short damped high-frequency ring, plus small hand shifts.
    public mutating func type(_ seconds: Double) {
        var taps: [(t: Double, amp: Double, f: Double)] = []
        var nextKey = 0.05
        let drift = rng.next() * 2 * .pi
        emit(seconds) { tt, g, rng in
            while tt >= nextKey {
                taps.append((nextKey, 0.06 + 0.09 * rng.next(), 16 + 12 * rng.next()))
                if taps.count > 4 { taps.removeFirst() }
                nextKey += 0.06 - 0.16 * log(max(1e-6, 1 - rng.next()))   // irregular gaps, ~0.22 s mean
            }
            var ring = 0.0
            for tap in taps where tt >= tap.t {
                let dt = tt - tap.t
                ring += tap.amp * exp(-dt * 30) * sin(2 * .pi * tap.f * dt)
            }
            let shift = 0.008 * sin(2 * .pi * 0.3 * tt + drift)
            return (g.x + 0.35 * ring + shift + rng.gauss(0.004),
                    g.y + 0.2 * ring + rng.gauss(0.004),
                    g.z + ring + rng.gauss(0.004))
        }
    }

    /// A single roll-over in bed: the wrist turns ~110° in `seconds` with a body bump, then rests.
    public mutating func rollOver(_ seconds: Double = 1.6) {
        let from = gravity
        let to = Self.unit(-0.86, -0.18, -0.47)
        emit(seconds) { tt, _, rng in
            let p = 0.5 - 0.5 * cos(.pi * min(1, tt / seconds))
            let g = Self.unit(from.x + (to.x - from.x) * p, from.y + (to.y - from.y) * p, from.z + (to.z - from.z) * p)
            let bump = 0.22 * sin(.pi * min(1, tt / seconds))
            return (g.x + rng.gauss(0.01), g.y + bump + rng.gauss(0.01), g.z + 0.4 * bump + rng.gauss(0.01))
        }
        gravity = to
    }

    // MARK: - Helpers

    private mutating func emit(_ seconds: Double,
                               _ value: (_ tt: Double, _ g: (x: Double, y: Double, z: Double), _ rng: inout SplitMix64) -> (Double, Double, Double)) {
        let count = Int((seconds * Self.rate).rounded())
        samples.reserveCapacity(samples.count + count)
        for i in 0..<count {
            let tt = Double(i) / Self.rate
            let (x, y, z) = value(tt, gravity, &rng)
            samples.append(MotionSample(t: time + tt, x: x, y: y, z: z))
        }
        time += Double(count) / Self.rate
    }

    static func unit(_ x: Double, _ y: Double, _ z: Double) -> (x: Double, y: Double, z: Double) {
        let n = max(1e-9, sqrt(x * x + y * y + z * z))
        return (x / n, y / n, z / n)
    }
}

extension SplitMix64 {
    /// Normal noise with the given SD (Box–Muller).
    mutating func gauss(_ sd: Double) -> Double {
        let u1 = max(1e-12, next()), u2 = next()
        return sd * sqrt(-2 * log(u1)) * cos(2 * .pi * u2)
    }
}
