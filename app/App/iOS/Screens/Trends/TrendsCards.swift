import SwiftUI
import EczemaKit

// MARK: - Overlay chips

/// The row under the chart title: None · Sleep · Humidity · Temp · Stress. The picked one (yellow) is
/// drawn over the scratch bars; each chip shows the selected night's value.
struct TrendsOverlayChips: View {
    @Binding var selection: TrendsOverlay
    /// The selected night.
    let night: Int

    var body: some View {
        HStack(spacing: 5) {
            ForEach(TrendsOverlay.allCases) { o in
                chip(o)
                    .frame(maxWidth: o == .none ? 54 : .infinity)
            }
        }
    }

    private func chip(_ o: TrendsOverlay) -> some View {
        let on = o == selection
        let shape = RoundedRectangle(cornerRadius: Twin.Radius.chip, style: .continuous)
        let value = o.value(night).map(o.text)
        return Button {
            guard !on else { return }
            withAnimation(Twin.Motion.spring) { selection = o }
        } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(o.title)
                    .font(Twin.Typeface.sans(14, .bold))
                    .foregroundStyle(Twin.Palette.ink)
                if let value {
                    Text(value)
                        .font(Twin.Typeface.mono(11, bold: on))
                        .foregroundStyle(on ? Twin.Palette.ink : Twin.Palette.inkMuted)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 7)
            .frame(maxWidth: .infinity, minHeight: 46, alignment: o == .none ? .center : .leading)
            .background(on ? Twin.Palette.yellow : Twin.Palette.paper, in: shape)
            .overlay(shape.strokeBorder(on ? Twin.Palette.ink : Twin.Palette.inkFaint,
                                        lineWidth: on ? Twin.Stroke.ink : Twin.Stroke.hairline))
            .contentShape(shape)
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(o == .none ? "No overlay" : "\(o.title)\(value.map { ", \($0)" } ?? "")")
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

// MARK: - The selected night

/// Cyan strip under the chart ("this item"): the selected night's numbers in a row (minutes, sleep,
/// humidity, temperature, HRV) and what he bought that day (tap one → its sheet). Numbers roll when
/// the selection moves.
struct TrendsNightStrip: View {
    let night: TrendsNight
    var onPurchase: (TrendsEvent) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(night.eyebrow)
                .font(Twin.Typeface.eyebrow)
                .tracking(0.8)
                .foregroundStyle(Twin.Palette.ink.opacity(0.62))
                .lineLimit(1)
            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(night.metrics.enumerated()), id: \.element.id) { k, metric in
                    if k > 0 {
                        Rectangle().fill(Twin.Palette.ink.opacity(0.12)).frame(width: 1, height: 36)
                            .padding(.horizontal, 7)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(metric.label.uppercased())
                            .font(Twin.Typeface.mono(9, bold: true))
                            .tracking(0.3)
                            .foregroundStyle(Twin.Palette.ink.opacity(0.6))
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text(metric.value)
                                .font(Twin.Typeface.sans(k == 0 ? 22 : 19, .bold))
                                .tracking(-0.4)
                                .monospacedDigit()
                                .contentTransition(.numericText())
                            Text(metric.unit)
                                .font(Twin.Typeface.sans(12, .medium))
                                .foregroundStyle(Twin.Palette.inkMuted)
                        }
                        .foregroundStyle(Twin.Palette.ink)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                }
            }
            Rectangle().fill(Twin.Palette.ink.opacity(0.12)).frame(height: 1)
            // Top-aligned: with two long product names the chips wrap, and BOUGHT stays by the first one.
            HStack(alignment: .top, spacing: 8) {
                Text("BOUGHT")
                    .font(Twin.Typeface.mono(9, bold: true))
                    .tracking(0.3)
                    .foregroundStyle(Twin.Palette.ink.opacity(0.6))
                    .frame(height: 28)
                if night.purchases.isEmpty {
                    Text("Nothing new")
                        .font(Twin.Typeface.sans(14, .medium))
                        .foregroundStyle(Twin.Palette.inkMuted)
                        .frame(minHeight: 28)
                } else {
                    TrendsFlow(spacing: 6, lineSpacing: 6) {
                        ForEach(night.purchases) { event in
                            Button { onPurchase(event) } label: {
                                HStack(spacing: 5) {
                                    TwinIconView(emoji: event.emoji, size: 16)
                                    Text(event.shortName).font(Twin.Typeface.sans(13, .bold)).lineLimit(1)
                                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold))
                                }
                                .foregroundStyle(Twin.Palette.ink)
                                .padding(.horizontal, 8)
                                .frame(height: 28)
                                .sticker(Twin.Palette.pink)
                            }
                            .buttonStyle(PressableStyle())
                            .accessibilityLabel(event.name)
                            .accessibilityHint("Shows details")
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Twin.Palette.cyanSoft, in: RoundedRectangle(cornerRadius: Twin.Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Twin.Radius.card, style: .continuous)
            .strokeBorder(Twin.Palette.cyan, lineWidth: Twin.Stroke.ink))
    }
}

/// "▇ flare night  ┄ usual 12 min  ▣ bought": the key under the chart.
struct TrendsKey: View {
    var body: some View {
        HStack(spacing: 14) {
            HStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Twin.Palette.orange)
                    .overlay(RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .strokeBorder(Twin.Palette.ink, lineWidth: 1))
                    .frame(width: 10, height: 10)
                Text("over 1.5× usual")
            }
            HStack(spacing: 5) {
                ChartHLine()
                    .stroke(Twin.Palette.ink.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    .frame(width: 16, height: 2)
                Text("usual \(StageStory.usual) min")
            }
            HStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Twin.Palette.pink)
                    .overlay(RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .strokeBorder(Twin.Palette.ink, lineWidth: 1))
                    .frame(width: 10, height: 10)
                Text("bought")
            }
            Spacer(minLength: 0)
        }
        .font(Twin.Typeface.mono(10))
        .foregroundStyle(Twin.Palette.inkMuted)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Layout

/// Left-to-right wrapping layout for chips.
struct TrendsFlow: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(ProposedViewSize(width: width.isFinite ? width : nil, height: nil))
            if x > 0, x + size.width > width {
                y += line + lineSpacing
                x = 0
                line = 0
            }
            x += size.width + spacing
            line = max(line, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: width.isFinite ? width : widest, height: y + line)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, line: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
            if x > bounds.minX, x + size.width > bounds.maxX {
                y += line + lineSpacing
                x = bounds.minX
                line = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            line = max(line, size.height)
        }
    }
}
