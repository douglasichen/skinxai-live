import SwiftUI

/// The live monitor, sideways (prototype v5 `#live`, monitor "D"): what the watch sees tonight,
/// big enough for the screen behind the stage.
///
/// Top: "● LIVE", "Sleep tracking", the elapsed time, "APPLE WATCH · RIGHT WRIST" and Done.
/// Middle: the bars (with "✋ Scratching" while it lasts) and "SCRATCHES TONIGHT" with a big count
/// that pops and sends an orange ripple on each new episode. Bottom: the whole session, one orange
/// block per episode.
struct LiveMonitorView: View {
    /// Landscape layout (the normal case); portrait stacks the count under the bars.
    var wide: Bool
    var onDone: () -> Void

    @ObservedObject private var session = LiveSession.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// "graph" (default): the wrist-motion graph; "bars": the bars that follow the watch's decision only.
    /// Switched under the hidden controls.
    @AppStorage("liveView") private var liveView = "graph"

    var body: some View {
        VStack(spacing: 10) {
            topRow
            if wide {
                HStack(spacing: 10) {
                    chartCard
                    LiveCountCard(count: session.thresholdCount, seconds: session.scratchSeconds).frame(width: 210)
                }
            } else {
                VStack(spacing: 10) {
                    chartCard
                    LiveCountCard(count: session.thresholdCount, seconds: session.scratchSeconds).frame(height: 190)
                }
            }
        }
        .padding(.horizontal, wide ? 8 : Twin.Space.screen)
        .padding(.top, 14)
        .padding(.bottom, 8)
    }

    private var topRow: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                LiveDot(blinking: session.running)
                Text("LIVE").font(Twin.Typeface.sans(12, .bold))
            }
            .foregroundStyle(Twin.Palette.ink)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .sticker(Twin.Palette.cyan)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(session.running ? "Live" : "Waiting for your watch")

            Text("Sleep tracking")
                .font(Twin.Typeface.sans(18, .bold))
                .tracking(-0.18)
                .foregroundStyle(Twin.Palette.ink)
                .lineLimit(1)
            elapsed
            Spacer(minLength: 8)
            if wide {
                Text("APPLE WATCH · RIGHT WRIST")
                    .font(Twin.Typeface.mono(11))
                    .foregroundStyle(Twin.Palette.inkHint)
                    .lineLimit(1)
            }
            Button(action: onDone) {
                Text("Done").font(Twin.Typeface.sans(14, .bold))
            }
            .buttonStyle(TwinButtonStyle(fill: Twin.Palette.paper, height: 36, fullWidth: false))
            .accessibilityHint("Closes the live monitor")
        }
    }

    /// Time since tracking began, ticking (m:ss, then h:mm:ss).
    @ViewBuilder private var elapsed: some View {
        Group {
            if let start = session.startedAt {
                Text(timerInterval: start...Date.distantFuture, countsDown: false)
            } else {
                Text(verbatim: "0:00")
            }
        }
        .font(Twin.Typeface.mono(16))
        .foregroundStyle(Twin.Palette.inkHint)
        .lineLimit(1)
    }

    private var chartCard: some View {
        ZStack(alignment: .topLeading) {
            if liveView == "bars" {
                LiveBarsView(running: session.running, scratching: session.scratching)
            } else {
                LiveGraphView(running: session.running, scratching: session.scratching)
            }
            if session.aboveThreshold {
                Sticker(text: "Scratching", icon: "✋", fill: Twin.Palette.orange)
                    .padding(.top, 10)
                    .padding(.leading, 12)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: -6)))
            }
        }
        .animation(.timingCurve(0.22, 0.9, 0.24, 1, duration: 0.25), value: session.aboveThreshold)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Twin.Palette.paper)
        .clipShape(RoundedRectangle(cornerRadius: Twin.Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Twin.Radius.card, style: .continuous)
            .strokeBorder(Twin.Palette.hairline, lineWidth: Twin.Stroke.hairline))
    }
}

/// "SCRATCHING TONIGHT": total scratch time (seconds under a minute, then minutes + seconds) and the
/// number of scratches under it. Each new episode pops the time (bigger, orange for a moment) and
/// sends one orange ring out from behind it.
struct LiveCountCard: View {
    var count: Int
    /// Seconds above the scratch threshold tonight (the stopwatch).
    var seconds: Double = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bumped = false
    @State private var ripples: [Int] = []
    @State private var nextRipple = 0

    /// The prototype's `--spring` curve (a small overshoot).
    private static let pop = Animation.timingCurve(0.34, 1.56, 0.64, 1, duration: 0.3)

    var body: some View {
        let card = RoundedRectangle(cornerRadius: Twin.Radius.card, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow(text: "Scratching tonight")
            Group {
                VStack(spacing: 6) {
                    scratchTime()
                        .foregroundStyle(bumped ? Twin.Palette.orange : Twin.Palette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.4)
                        .scaleEffect(bumped && !reduceMotion ? 1.18 : 1)
                    Text(count == 1 ? "1 scratch" : "\(count) scratches")
                        .font(Twin.Typeface.mono(13))
                        .foregroundStyle(Twin.Palette.inkHint)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay {
            GeometryReader { geo in
                ZStack {
                    ForEach(ripples, id: \.self) { _ in LiveRipple(still: reduceMotion) }
                }
                .position(x: geo.size.width / 2, y: geo.size.height * 0.56)
            }
            .allowsHitTesting(false)
        }
        .background(Twin.Palette.paper)
        .clipShape(card)
        .overlay(card.strokeBorder(Twin.Palette.hairline, lineWidth: Twin.Stroke.hairline))
        .onChange(of: count) { old, new in
            if new > old { popAndRipple() }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Scratching tonight")
        .accessibilityValue("\(Int(seconds)) seconds, \(count) scratches")
    }

    /// "45 s" under a minute, then "1 min 23 s": big numbers, small units.
    private func scratchTime() -> Text {
        let total = Int(seconds)
        let big = Twin.Typeface.sans(64, .bold), small = Twin.Typeface.sans(22, .bold)
        if total < 60 {
            return Text("\(total)").font(big).tracking(-3) + Text(" s").font(small)
        }
        return Text("\(total / 60)").font(big).tracking(-3) + Text(" min ").font(small)
            + Text("\(total % 60)").font(big).tracking(-3) + Text(" s").font(small)
    }

    private func popAndRipple() {
        withAnimation(Self.pop) { bumped = true }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 320_000_000)
            withAnimation(Self.pop) { bumped = false }
        }
        let id = nextRipple
        nextRipple += 1
        ripples.append(id)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_250_000_000)
            ripples.removeAll { $0 == id }
        }
    }
}

/// One orange ring that grows from behind the count and fades (prototype `.ripple`: 110 pt,
/// 5 pt orange edge, scale 0.7 → 2.2 over 1.1 s). With Reduce Motion it only fades.
struct LiveRipple: View {
    var still: Bool
    @State private var fired = false

    private struct Frame {
        var scale = 0.7
        var opacity = 0.0           // hidden until it fires
    }

    private static let slide = UnitCurve.bezier(startControlPoint: UnitPoint(x: 0.22, y: 0.9),
                                                endControlPoint: UnitPoint(x: 0.24, y: 1))

    var body: some View {
        let still = still
        Circle()
            .strokeBorder(Twin.Palette.orange, lineWidth: 5)
            .frame(width: 110, height: 110)
            .keyframeAnimator(initialValue: Frame(), trigger: fired) { content, frame in
                content
                    .scaleEffect(still ? 1 : frame.scale)
                    .opacity(frame.opacity)
            } keyframes: { _ in
                KeyframeTrack(\.scale) {
                    MoveKeyframe(0.7)
                    LinearKeyframe(2.2, duration: 1.1, timingCurve: Self.slide)
                }
                KeyframeTrack(\.opacity) {
                    MoveKeyframe(1)
                    LinearKeyframe(0.8, duration: 0.385, timingCurve: Self.slide)
                    LinearKeyframe(0, duration: 0.715, timingCurve: Self.slide)
                }
            }
            .onAppear { fired = true }
            .accessibilityHidden(true)
    }
}

/// The whole session left → right, one orange block (ink edges) per episode; at least 30 s wide,
/// so the first minutes don't fill it at once.
struct LiveSessionStrip: View {
    var startedAt: Date?
    var episodes: [LiveEpisode]

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Twin.Radius.chip, style: .continuous)
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: startedAt == nil || episodes.isEmpty)) { timeline in
            Canvas { context, size in
                guard let start = startedAt, size.width > 0 else { return }
                let now = timeline.date
                let span = max(30, now.timeIntervalSince(start))
                let w = size.width
                let bounds = CGRect(origin: .zero, size: size)
                var blocks = Path()
                var edges = Path()
                for episode in episodes {
                    let x = CGFloat(episode.start.timeIntervalSince(start) / span) * w
                    let length = max(0.006 * w, CGFloat((episode.end ?? now).timeIntervalSince(episode.start) / span) * w)
                    let rect = CGRect(x: x, y: 0, width: length, height: size.height).intersection(bounds)
                    guard !rect.isNull, rect.width > 0 else { continue }
                    blocks.addRect(rect)
                    edges.addRect(CGRect(x: rect.minX, y: 0, width: 1, height: size.height))
                    edges.addRect(CGRect(x: rect.maxX - 1, y: 0, width: 1, height: size.height))
                }
                context.fill(blocks, with: .color(Twin.Palette.orange))
                context.fill(edges, with: .color(Twin.Palette.ink))
            }
        }
        .background(Twin.Palette.fill)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Twin.Palette.hairline, lineWidth: Twin.Stroke.hairline))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Tonight so far")
        .accessibilityValue(episodes.count == 1 ? "1 scratch" : "\(episodes.count) scratches")
    }
}

/// The ink dot of the "Live" stickers: blinks while the watch tracks, rests faded otherwise.
struct LiveDot: View {
    var blinking = true

    var body: some View {
        let dot = Circle().fill(Twin.Palette.ink).frame(width: 8, height: 8)
        if blinking {
            dot.phaseAnimator([1.0, 0.25]) { content, opacity in
                content.opacity(opacity)
            } animation: { _ in
                .easeInOut(duration: 0.6)
            }
        } else {
            dot.opacity(0.35)
        }
    }
}
