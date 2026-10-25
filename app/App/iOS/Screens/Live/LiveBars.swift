import SwiftUI

/// The live monitor's bars (prototype v5, monitor "D", `drawBars(…, "center")`): capsule bars 6 pt
/// wide with 5 pt gaps, a new one every 140 ms, scrolling right → left, mirrored around a faint
/// center line, like a voice recording.
///
/// Calm: short ink bars (7–18% of the height) that rise and fall gently. They follow the watch's
/// decision only, never raw wrist motion. While the watch says "scratching", new bars blend
/// (smoothstep of a soft level that rises in ~0.3 s and falls in ~0.6 s) to 38–78% of the height
/// and turn orange with a 1 pt ink edge, like the app's chart bars, then shrink back.
/// Before tracking starts the bars are flat dots. With Reduce Motion they stay in place and only
/// change height and color.
struct LiveBarsView: View {
    /// A tracking session is running (calm bars breathe; otherwise flat).
    var running: Bool
    /// The watch says scratching right now.
    var scratching: Bool

    @State private var model = LiveBarsModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                model.advance(to: timeline.date, running: running, scratching: scratching)
                model.draw(in: &context, size: size, still: reduceMotion)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Live scratching monitor")
        .accessibilityValue(scratching ? "Scratching now" : running ? "Calm" : "Waiting for your watch")
    }
}

/// The bar history behind `LiveBarsView`: a fixed ring of bars, advanced by the frame clock.
/// Nothing is allocated per frame except the two paths that draw the bars.
final class LiveBarsModel {
    static let interval: Double = 0.14          // one new bar every 140 ms
    static let barWidth: CGFloat = 6
    static let step: CGFloat = 11               // bar + 5 pt gap
    static let trailing: CGFloat = 16           // the newest bar's distance from the right edge
    private static let capacity = 128           // > the widest chart (932 pt / 11 pt)
    private static let lineShading = GraphicsContext.Shading.color(Twin.Palette.ink.opacity(0.10))
    private static let calmShading = GraphicsContext.Shading.color(Twin.Palette.ink.opacity(0.16))
    private static let hotShading = GraphicsContext.Shading.color(Twin.Palette.orange)
    private static let edgeShading = GraphicsContext.Shading.color(Twin.Palette.ink)

    private var heights = [Double](repeating: 0.03, count: capacity)
    private var hot = [Bool](repeating: false, count: capacity)
    private var newest = capacity - 1
    private var stored = 0
    /// Bars made so far: the input of each bar's fixed random part.
    private var serial = 0
    /// Seconds on the model's clock (`origin`) of the newest bar and of the last frame.
    private var newestAt: Double = 0
    private var lastFrame: Double?
    /// The soft scratching level 0…1 and whether a session runs (kept for the still variant).
    private var soft = 0.0
    private var running = false
    private let origin = Date()

    func advance(to date: Date, running: Bool, scratching: Bool) {
        let t = date.timeIntervalSince(origin)
        self.running = running
        guard let last = lastFrame else {
            lastFrame = t
            // First frame: fill the chart with what the last seconds looked like (calm or flat).
            newestAt = t - Double(Self.capacity) * Self.interval
            for _ in 0..<Self.capacity {
                newestAt += Self.interval
                push(at: newestAt)
            }
            return
        }
        let dt = min(0.05, max(0, t - last))
        lastFrame = t
        let target: Double = scratching ? 1 : 0
        soft += (target - soft) * min(1, dt * (scratching ? 3.2 : 1.7))
        if t - newestAt > Double(Self.capacity) * Self.interval {
            newestAt = t - Double(Self.capacity) * Self.interval   // back from the background
        }
        while t - newestAt >= Self.interval {
            newestAt += Self.interval
            push(at: newestAt)
        }
    }

    private func push(at t: Double) {
        let i = serial
        serial += 1
        let k = running ? Self.smoothstep(soft) : 0
        let calm = running ? 0.07 + 0.06 * (0.5 + 0.5 * sin(t / 0.65)) + 0.05 * Self.hash(i) : 0.03
        let tall = 0.38 + 0.40 * Self.hash(i + 999)
        newest = (newest + 1) % Self.capacity
        heights[newest] = calm * (1 - k) + tall * k
        hot[newest] = k > 0.5
        stored = min(stored + 1, Self.capacity)
    }

    func draw(in context: inout GraphicsContext, size: CGSize, still: Bool) {
        let w = size.width, h = size.height
        guard w > 0, h > 0 else { return }
        let mid = (h / 2).rounded(.down)
        let maxHeight = max(0, h - 40)

        var line = Path()
        line.move(to: CGPoint(x: 0, y: mid + 0.5))
        line.addLine(to: CGPoint(x: w, y: mid + 0.5))
        context.stroke(line, with: Self.lineShading, lineWidth: 1)

        // Smooth scroll: the whole row slides one step left over each 140 ms.
        let frac = still ? 0 : CGFloat(min(1, max(0, ((lastFrame ?? newestAt) - newestAt) / Self.interval)))
        let k = running ? Self.smoothstep(soft) : 0
        let corner = CGSize(width: Self.barWidth / 2, height: Self.barWidth / 2)
        var calmBars = Path()
        var hotBars = Path()
        let visible = min(stored, Int((w / Self.step).rounded(.up)) + 1)
        for j in 0..<visible {
            let x = w - Self.trailing - CGFloat(j) * Self.step - frac * Self.step
            if x < -Self.barWidth { break }
            let value: Double
            let isHot: Bool
            if still {
                // Reduce Motion: fixed bars that only change height and color with the level.
                let calm = running ? 0.10 + 0.05 * Self.hash(j) : 0.03
                value = calm * (1 - k) + (0.38 + 0.40 * Self.hash(j + 999)) * k
                isHot = k > 0.5
            } else {
                let index = (newest - j + Self.capacity) % Self.capacity
                value = heights[index]
                isHot = hot[index]
            }
            let barHeight = max(4, CGFloat(value) * maxHeight)
            let rect = CGRect(x: x, y: mid - barHeight / 2, width: Self.barWidth, height: barHeight)
            if isHot {
                hotBars.addRoundedRect(in: rect, cornerSize: corner)
            } else {
                calmBars.addRoundedRect(in: rect, cornerSize: corner)
            }
        }
        context.fill(calmBars, with: Self.calmShading)
        context.fill(hotBars, with: Self.hotShading)
        context.stroke(hotBars, with: Self.edgeShading, lineWidth: 1)
    }

    private static func smoothstep(_ x: Double) -> Double { x * x * (3 - 2 * x) }

    /// The prototype's per-bar random part: fract(sin(i · 12.9898 + 78.233) · 43758.5453).
    private static func hash(_ i: Int) -> Double {
        let x = sin(Double(i) * 12.9898 + 78.233) * 43758.5453
        return x - x.rounded(.down)
    }
}
