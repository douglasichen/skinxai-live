import SwiftUI
import EczemaKit

/// Wrist motion waiting to be drawn: the relay's `samples` (25 a second, g, gravity removed), in
/// arrival order. `LiveSession` writes it on the main thread; the graph's Canvas reads it while it
/// draws. A lock keeps the two apart without tying the Canvas to the main actor.
final class LiveMotionFeed: @unchecked Sendable {
    static let shared = LiveMotionFeed()

    private let lock = NSLock()
    private var pending: [Double] = []

    /// Adds a batch's motion. More than 3 s waiting means the phone fell behind: the oldest goes.
    func append(_ values: [Double]) {
        guard !values.isEmpty else { return }
        lock.lock(); defer { lock.unlock() }
        pending.append(contentsOf: values)
        if pending.count > 75 { pending.removeFirst(pending.count - 75) }
    }

    /// How many values are waiting.
    var count: Int {
        lock.lock(); defer { lock.unlock() }
        return pending.count
    }

    /// Takes up to `n` of the oldest values.
    func take(_ n: Int) -> [Double] {
        lock.lock(); defer { lock.unlock() }
        let k = min(n, pending.count)
        guard k > 0 else { return [] }
        let out = Array(pending.prefix(k))
        pending.removeFirst(k)
        return out
    }

    func clear() {
        lock.lock(); defer { lock.unlock() }
        pending.removeAll()
    }
}

/// Scratch intensity from wrist motion, one value at a time (25 a second), and the scratch threshold:
///
///     R(n) = √( mean of m² over the last 12 values )   (0.48 s)
///     I(n) = I(n−1) + 0.15 · (R(n) − I(n−1))
///     scratching starts when I ≥ 0.75 g and stops when I < 0.60 g (a small gap so it doesn't flicker)
///
/// The graph draws I and colors it orange while above the threshold; `LiveSession` runs the same meter
/// on every value the relay delivers to time the scratching (the stopwatch) and count the scratches.
struct IntensityMeter {
    static let startAt = 0.75
    static let stopAt = 0.60
    /// TEMPORARY tuning knobs (hidden Advanced card): the RMS window in values (25 a second) and the easing.
    static let windowKey = "meterWindow", easingKey = "meterEasing"
    static let defaultWindow = 12, defaultEasing = 0.15, maxWindow = 50
    static var window: Int {
        let v = UserDefaults.standard.integer(forKey: windowKey)
        return v > 0 ? min(max(v, 2), maxWindow) : defaultWindow
    }
    static var smoothing: Double {
        let v = UserDefaults.standard.double(forKey: easingKey)
        return v > 0 ? min(max(v, 0.01), 1) : defaultEasing
    }

    private var recent = [Double](repeating: 0, count: 50)
    private var index = 0
    private(set) var level = 0.0
    private(set) var above = false

    /// Adds one wrist-motion value; returns true when this value starts a scratch.
    @discardableResult
    mutating func add(_ m: Double) -> Bool {
        recent[index] = m
        let w = Self.window
        var squares = 0.0
        for k in 0..<w { let v = recent[(index - k + Self.maxWindow) % Self.maxWindow]; squares += v * v }
        index = (index + 1) % Self.maxWindow
        level += Self.smoothing * ((squares / Double(w)).squareRoot() - level)
        if !above, level >= Self.startAt { above = true; return true }
        if above, level < Self.stopAt { above = false }
        return false
    }

    /// No data for a moment: let the level settle.
    mutating func settle() {
        level *= 0.92
        if above, level < Self.stopAt { above = false }
    }

    mutating func reset() { self = IntensityMeter() }
}

/// The live monitor's graph: how hard the wrist moves over the last 15 seconds, drawn as a line with
/// the area under it, scrolling right → left with "now" on the right.
///
/// Input: the watch's wrist motion `m` (g, gravity removed, 25 values a second, see `LiveStreamer` on
/// the watch). Each value is smoothed a little before it is drawn:
///
///     R(n) = √( mean of m² over the last 12 values )   (0.48 s window: one value per stroke cycle,
///                                                       so the back-and-forth wiggle disappears)
///     I(n) = I(n−1) + 0.15 · (R(n) − I(n−1))           (then about 0.25 s of easing)
///
/// and the line is drawn as a smooth curve through the points.
///
/// The y axis is linear, 0 to 1.6 g; values above the top are drawn at the top. A still wrist sits near
/// 0; moving the hand back and forth lifts the line (light scratching is about 0.3–0.9 g, hard about 2 g).
/// Stretches where the watch has decided "scratch" (its own detector, the same that counts episodes)
/// are orange; the rest is ink.
struct LiveGraphView: View {
    /// A tracking session is running (otherwise the line rests at 0).
    var running: Bool
    /// The watch says scratching right now.
    var scratching: Bool

    @State private var model = LiveGraphModel()

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                model.advance(to: timeline.date, running: running, scratching: scratching)
                model.draw(in: &context, size: size)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Wrist motion graph")
        .accessibilityValue(scratching ? "Scratching now" : running ? "Live" : "Waiting for your watch")
    }
}

final class LiveGraphModel {
    static let rate = 25.0                      // values per second, as the watch sends them
    static let seconds = 15.0                   // seconds on screen
    static let capacity = Int(rate * seconds) + 2
    static let top = 1.6                        // g at the top of the plot
    private var meter = IntensityMeter()
    private static let gridLevels: [Double] = [0, 0.5, 1.0, 1.5]

    private var values = [Double](repeating: 0, count: capacity)
    private var hot = [Bool](repeating: false, count: capacity)
    private var newest = capacity - 1
    /// Values the clock owes the graph (fractional), and how long the feed has been empty.
    private var owed = 0.0
    private var starved = 0
    private var lastFrame: Double?
    private let origin = Date()

    func advance(to date: Date, running: Bool, scratching: Bool) {
        let t = date.timeIntervalSince(origin)
        guard let last = lastFrame else { lastFrame = t; return }
        let dt = min(0.25, max(0, t - last))
        lastFrame = t
        owed += dt * Self.rate
        var n = Int(owed)
        owed -= Double(n)
        guard n > 0 else { return }

        let feed = LiveMotionFeed.shared
        guard running else {
            feed.clear()
            for _ in 0..<n { meter.settle(); push(meter.level, hot: false) }
            return
        }
        // Keep about 0.3 s of motion in hand (batches come every 0.3 s): catch up when more waits.
        let waiting = feed.count
        if waiting > 12 { n += min(waiting - 8, 4) }
        let got = feed.take(n)
        for i in 0..<n {
            if i < got.count {
                starved = 0
                meter.add(got[i])
            } else {
                // Nothing arrived yet: hold the line for half a second, then let it settle.
                starved += 1
                if starved > 12 { meter.settle() }
            }
            push(meter.level, hot: meter.above)
        }
    }

    private func push(_ value: Double, hot isHot: Bool) {
        newest = (newest + 1) % Self.capacity
        values[newest] = max(0, value)
        hot[newest] = isHot
    }

    func draw(in context: inout GraphicsContext, size: CGSize) {
        let left: CGFloat = 46, right: CGFloat = 16, top: CGFloat = 40, bottom: CGFloat = 30
        let plot = CGRect(x: left, y: top, width: max(0, size.width - left - right),
                          height: max(0, size.height - top - bottom))
        guard plot.width > 0, plot.height > 0 else { return }
        func y(_ g: Double) -> CGFloat { plot.maxY - CGFloat(min(g, Self.top) / Self.top) * plot.height }
        let count = Self.capacity - 1
        func x(_ j: Int) -> CGFloat { plot.maxX - CGFloat(j) / CGFloat(count) * plot.width }   // j = 0 is now

        // Grid and labels: g on the left, seconds below.
        let grid = GraphicsContext.Shading.color(Twin.Palette.ink.opacity(0.08))
        for level in Self.gridLevels {
            var line = Path()
            line.move(to: CGPoint(x: plot.minX, y: y(level) + 0.5))
            line.addLine(to: CGPoint(x: plot.maxX, y: y(level) + 0.5))
            context.stroke(line, with: grid, lineWidth: 1)
            let label = level == 0 ? "0" : String(format: "%.1f g", level)
            context.draw(Text(label).font(Twin.Typeface.mono(10)).foregroundColor(Twin.Palette.inkHint),
                         at: CGPoint(x: plot.minX - 8, y: y(level)), anchor: .trailing)
        }
        for (seconds, label) in [(15.0, "15 s ago"), (10.0, "10 s"), (5.0, "5 s"), (0.0, "now")] {
            let px = plot.maxX - CGFloat(seconds / Self.seconds) * plot.width
            context.draw(Text(label).font(Twin.Typeface.mono(10)).foregroundColor(Twin.Palette.inkHint),
                         at: CGPoint(x: px, y: plot.maxY + 8),
                         anchor: seconds == 15 ? .topLeading : seconds == 0 ? .topTrailing : .top)
        }
        // The scratch threshold.
        var threshold = Path()
        threshold.move(to: CGPoint(x: plot.minX, y: y(IntensityMeter.startAt)))
        threshold.addLine(to: CGPoint(x: plot.maxX, y: y(IntensityMeter.startAt)))
        context.stroke(threshold, with: .color(Color(red: 0.886, green: 0.451, blue: 0.227).opacity(0.7)),
                       style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
        context.draw(Text("SCRATCH THRESHOLD").font(Twin.Typeface.mono(9)).foregroundColor(Color(red: 0.886, green: 0.451, blue: 0.227)),
                     at: CGPoint(x: plot.minX + 4, y: y(IntensityMeter.startAt) - 4), anchor: .bottomLeading)
        context.draw(Text("WRIST MOTION").font(Twin.Typeface.mono(10)).foregroundColor(Twin.Palette.inkHint),
                     at: CGPoint(x: plot.maxX, y: 14), anchor: .topTrailing)

        // The line and the area under it, in runs of the same color (ink, or orange while scratching).
        var j = 0
        while j < count {
            let index = (newest - j + Self.capacity) % Self.capacity
            let isHot = hot[index]
            var end = j
            while end + 1 <= count {
                let nextIndex = (newest - end - 1 + Self.capacity) % Self.capacity
                if hot[nextIndex] != isHot { break }
                end += 1
            }
            // Include one point of the next run so the runs join without a gap.
            let last = min(end + 1, count)
            var line = Path()
            var area = Path()
            var previous = CGPoint.zero
            for k in j...last {
                let v = values[(newest - k + Self.capacity) % Self.capacity]
                let point = CGPoint(x: x(k), y: y(v))
                if k == j {
                    line.move(to: point)
                    area.move(to: CGPoint(x: point.x, y: plot.maxY))
                    area.addLine(to: point)
                } else {
                    // A smooth curve: through the midpoints, bending at each value.
                    let mid = CGPoint(x: (previous.x + point.x) / 2, y: (previous.y + point.y) / 2)
                    line.addQuadCurve(to: mid, control: previous)
                    area.addQuadCurve(to: mid, control: previous)
                    if k == last {
                        line.addLine(to: point)
                        area.addLine(to: point)
                    }
                }
                previous = point
            }
            area.addLine(to: CGPoint(x: x(last), y: plot.maxY))
            area.closeSubpath()
            context.fill(area, with: .color(isHot ? Twin.Palette.orange.opacity(0.35) : Twin.Palette.ink.opacity(0.06)))
            context.stroke(line, with: .color(isHot ? Color(red: 0.886, green: 0.451, blue: 0.227) : Twin.Palette.ink),
                           style: StrokeStyle(lineWidth: isHot ? 2.6 : 2, lineCap: .round, lineJoin: .round))
            j = end + 1
        }

        // Now: a dot at the newest value.
        let v = values[newest]
        let dot = CGRect(x: plot.maxX - 4.5, y: y(v) - 4.5, width: 9, height: 9)
        context.fill(Path(ellipseIn: dot), with: .color(hot[newest] ? Color(red: 0.886, green: 0.451, blue: 0.227) : Twin.Palette.ink))
    }
}
