import SwiftUI

/// Raft segmented control for chart ranges ("7 days · 14 days · All").
/// An ink-edged track; the selected option sits on a yellow sticker that slides between options
/// (matchedGeometryEffect). Taps squash and give a haptic (PressableStyle).
struct ChartRangePicker<Option: Hashable>: View {
    var options: [Option]
    @Binding var selection: Option
    var title: (Option) -> String

    @Namespace private var ns

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { option in
                let on = option == selection
                Button {
                    guard option != selection else { return }
                    withAnimation(Twin.Motion.spring) { selection = option }
                } label: {
                    Text(title(option))
                        .font(Twin.Typeface.sans(14, on ? .bold : .medium))
                        .foregroundStyle(on ? Twin.Palette.ink : Twin.Palette.inkMuted)
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .background {
                            if on {
                                RoundedRectangle(cornerRadius: Twin.Radius.chip, style: .continuous)
                                    .fill(Twin.Palette.yellow)
                                    .overlay(RoundedRectangle(cornerRadius: Twin.Radius.chip, style: .continuous)
                                        .strokeBorder(Twin.Palette.ink, lineWidth: Twin.Stroke.ink))
                                    .matchedGeometryEffect(id: "range-thumb", in: ns)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Twin.Palette.paper, in: RoundedRectangle(cornerRadius: Twin.Radius.control, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Twin.Radius.control, style: .continuous)
            .strokeBorder(Twin.Palette.ink, lineWidth: Twin.Stroke.ink))
    }
}

/// Tiny bars for mini cards (e.g. the last 7 nights). The last bar is the one that matters
/// (`highlight`); the others are 15% ink. An optional dashed line marks the usual value.
/// A value of 0 or less means "not measured": its slot stays empty.
/// Each bar grows out of the baseline after `delay` (fade only with Reduce Motion).
struct SparkBars: View {
    var values: [Double]
    var highlight: Color = Twin.Palette.ink
    var usual: Double? = nil
    var delay: Double = 0.4

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var grown = false

    var body: some View {
        GeometryReader { geo in
            let top = max(values.max() ?? 1, usual ?? 0, 0.001) * 1.08
            ZStack(alignment: .bottomLeading) {
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(Array(values.enumerated()), id: \.offset) { i, v in
                        let last = i == values.count - 1
                        let full = v > 0 ? max(2, CGFloat(v / top) * geo.size.height) : 0
                        // Grows as a render transform (the layout never changes), so the spring
                        // only overshoots the bar's own height a little.
                        RoundedRectangle(cornerRadius: 1, style: .continuous)
                            .fill(last ? highlight : Twin.Palette.ink.opacity(0.15))
                            .frame(height: full)
                            .scaleEffect(x: 1, y: (grown || reduceMotion) ? 1 : 0.001, anchor: .bottom)
                            .opacity(grown ? 1 : 0)
                            .animation(reduceMotion ? .easeOut(duration: 0.3).delay(delay)
                                                    : Twin.Motion.bouncy.delay(delay + Double(i) * 0.04), value: grown)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .bottom)
                if let usual, usual > 0 {
                    ChartHLine()
                        .stroke(Twin.Palette.ink.opacity(0.55), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                        .frame(width: geo.size.width + 4, height: 1)
                        .offset(x: -2, y: -(CGFloat(usual / top) * geo.size.height - 0.5))
                        .opacity(grown ? 1 : 0)
                        .animation(.easeOut(duration: 0.4).delay(delay + 0.4), value: grown)
                }
            }
        }
        .onAppear { grown = true }
        .accessibilityHidden(true)
    }
}
