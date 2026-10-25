import SwiftUI

/// One night in quarter hours (Today's "Last night" card): thin bars from bedtime to morning that
/// grow in one after another with a spring. Quarter hours above `hotAbove` minutes are orange with an
/// ink edge (the bad stretch of the night); the rest are 15% ink. An empty quarter hour keeps a 2 pt
/// stub, so the night still reads as one line. Under the bars: a hairline and the clock labels.
struct QuarterHourChart: View {
    /// A clock label under the bars at `at` (0 = left edge … 1 = right edge). The first label starts
    /// at the left edge, the last one ends at the right edge, the others are centered on their spot.
    struct AxisLabel: Hashable {
        var text: String
        var at: Double
    }

    /// Minutes of scratching per quarter hour, oldest first.
    var values: [Double]
    var hotAbove: Double
    var labels: [AxisLabel] = []
    var plotHeight: CGFloat = 86
    var gap: CGFloat = 2
    var delay: Double = 0.18
    var stagger: Double = 0.022

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale
    @State private var grown = false

    private var top: Double { max(values.max() ?? 0, 0.001) }

    /// On whole pixels, so every bar ends exactly on the baseline (see `NightsChart.height`).
    private func snapped(_ h: CGFloat) -> CGFloat {
        displayScale > 0 ? (h * displayScale).rounded() / displayScale : h
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(spacing: 0) {
                HStack(alignment: .bottom, spacing: gap) {
                    ForEach(values.indices, id: \.self) { i in bar(i) }
                }
                .frame(height: plotHeight, alignment: .bottom)
                Rectangle().fill(Twin.Palette.hairline).frame(height: Twin.Stroke.hairline)
            }
            if !labels.isEmpty { axis }
        }
        .onAppear {
            if reduceMotion {
                withAnimation(.easeOut(duration: 0.35).delay(delay)) { grown = true }
            } else {
                grown = true   // each bar carries its own delayed spring (see `bar`)
            }
        }
        .accessibilityElement(children: .ignore)
    }

    private func bar(_ i: Int) -> some View {
        let v = values[i]
        let hot = v > hotAbove
        let full = snapped(max(2, CGFloat(v / top) * plotHeight))
        let shape = UnevenRoundedRectangle(topLeadingRadius: 1.5, topTrailingRadius: 1.5, style: .continuous)
        // The layout never changes: each bar grows out of the baseline as a render transform, so the
        // spring only overshoots its own height a little (animating the frame inside a bottom-aligned
        // stack made bars shoot far past their height). Not grown yet = not there. Reduce Motion: fade only.
        return shape
            .fill(hot ? Twin.Palette.orange : Twin.Palette.ink.opacity(0.15))
            .overlay { if hot { shape.strokeBorder(Twin.Palette.ink, lineWidth: 1) } }
            .frame(maxWidth: .infinity)
            .frame(height: full)
            .scaleEffect(x: 1, y: (grown || reduceMotion) ? 1 : 0.001, anchor: .bottom)
            .opacity(grown ? 1 : 0)
            .animation(reduceMotion ? nil : Twin.Motion.bouncy.delay(delay + Double(i) * stagger), value: grown)
    }

    private var axis: some View {
        GeometryReader { g in
            ZStack(alignment: .topLeading) {
                ForEach(labels, id: \.self) { label in
                    let alignment: Alignment = label.at <= 0 ? .leading : (label.at >= 1 ? .trailing : .center)
                    Text(label.text)
                        .font(Twin.Typeface.mono(10))
                        .foregroundStyle(Twin.Palette.inkHint)
                        .fixedSize()
                        .frame(width: 0, alignment: alignment)
                        .offset(x: CGFloat(min(max(label.at, 0), 1)) * g.size.width)
                }
            }
        }
        .frame(height: 13)
        .accessibilityHidden(true)
    }
}
