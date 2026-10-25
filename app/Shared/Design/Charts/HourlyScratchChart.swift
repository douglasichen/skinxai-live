import SwiftUI

/// One day, hour by hour (Today hero card, today's episodes sheet).
///
/// 24 bars grow in one after another with a spring. The worst hours (`hot`) are drawn in `accent`
/// with an ink edge, the rest in 14% ink. For today pass `now` (hours since midnight, e.g. 15.5):
/// the hours after it stay empty behind a dashed "rest of the day" line, and a yellow "now"
/// marker drops in once the bars have grown. Axis: 12a · 6a · 12p · 6p · now.
struct HourlyScratchChart: View {
    /// Minutes of scratching per hour, index 0 = midnight (24 values).
    var minutes: [Double]
    var hot: Set<Int> = []
    var accent: Color = Twin.Palette.orange
    /// Hours since midnight when the chart shows today; nil for a finished day.
    var now: Double? = nil
    /// Top of the y scale in minutes. Defaults to the busiest hour.
    var scaleMax: Double? = nil
    var plotHeight: CGFloat = 92
    var delay: Double = 0.25
    var showsAxis = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var grown = false
    @State private var nowShown = false

    private let gap: CGFloat = 3
    private let axisHeight: CGFloat = 13
    private let axisGap: CGFloat = 7

    private var top: Double { max(scaleMax ?? 0, minutes.max() ?? 0, 0.1) }

    var body: some View {
        GeometryReader { geo in
            let m = Metrics(width: geo.size.width, gap: gap)
            VStack(alignment: .leading, spacing: axisGap) {
                ZStack(alignment: .bottomLeading) {
                    if let now { restOfDay(m, now: now) }
                    HStack(alignment: .bottom, spacing: gap) {
                        ForEach(0..<24, id: \.self) { h in bar(h) }
                    }
                    .frame(height: plotHeight, alignment: .bottom)
                    if let now { nowMarker(m, now: now) }
                }
                .frame(width: geo.size.width, height: plotHeight, alignment: .bottomLeading)
                if showsAxis { axis(m) }
            }
        }
        .frame(height: plotHeight + (showsAxis ? axisGap + axisHeight : 0))
        .onAppear {
            if reduceMotion {
                withAnimation(.easeOut(duration: 0.35).delay(delay)) { grown = true; nowShown = true }
            } else {
                grown = true   // each bar carries its own delayed spring (see `bar`)
                withAnimation(Twin.Motion.bouncy.delay(delay + 24 * 0.03 + 0.15)) { nowShown = true }
            }
        }
    }

    // MARK: Pieces

    private func isFuture(_ h: Int) -> Bool {
        guard let now else { return false }
        return Double(h) > now.rounded(.down)
    }

    private func bar(_ h: Int) -> some View {
        let v = h < minutes.count ? minutes[h] : 0
        let future = isFuture(h)
        let isHot = hot.contains(h) && !future
        let full = future ? 0 : max(2, CGFloat(v / top) * plotHeight)
        // A bar that has not grown yet is not there at all (no 2 pt stub with an ink edge waiting
        // on the baseline): it grows out of the baseline (a render transform, so the spring only
        // overshoots its own height a little) and fades in on its own beat.
        // Reduce Motion: full height, fade only.
        let shape = UnevenRoundedRectangle(topLeadingRadius: 2, topTrailingRadius: 2, style: .continuous)
        return shape
            .fill(isHot ? accent : Twin.Palette.ink.opacity(0.14))
            .overlay { if isHot && full >= 4 { shape.strokeBorder(Twin.Palette.ink, lineWidth: 1) } }
            .frame(maxWidth: .infinity)
            .frame(height: full)
            .scaleEffect(x: 1, y: (grown || reduceMotion) ? 1 : 0.001, anchor: .bottom)
            .opacity(grown ? 1 : 0)
            .animation(reduceMotion ? nil : Twin.Motion.bouncy.delay(delay + Double(h) * 0.03), value: grown)
    }

    private func restOfDay(_ m: Metrics, now: Double) -> some View {
        let x0 = m.x(now)
        return ChartHLine()
            .stroke(Twin.Palette.inkFaint, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [1.5, 4]))
            .frame(width: max(0, m.width - x0 - 4), height: 2)
            .offset(x: x0 + 4, y: -0.5)
            .opacity(nowShown ? 1 : 0)
    }

    private func nowMarker(_ m: Metrics, now: Double) -> some View {
        let x = m.x(now)
        return ZStack(alignment: .top) {
            Rectangle()
                .fill(Twin.Palette.seam)
                .frame(width: 1.5)
                .padding(.top, 4)
                .scaleEffect(x: 1, y: nowShown ? 1 : 0, anchor: .bottom)
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Twin.Palette.yellow)
                .overlay(RoundedRectangle(cornerRadius: 2, style: .continuous).strokeBorder(Twin.Palette.ink, lineWidth: Twin.Stroke.ink))
                .frame(width: 10, height: 10)
                .scaleEffect(nowShown ? 1 : 0.2)
                .opacity(nowShown ? 1 : 0)
        }
        .frame(width: 12, height: plotHeight + 8)
        .offset(x: x - 6)
        .accessibilityHidden(true)
    }

    private struct AxisMark: Identifiable { let hour: Int; let text: String; var id: Int { hour } }

    private func axis(_ m: Metrics) -> some View {
        let marks = [AxisMark(hour: 0, text: "12a"), AxisMark(hour: 6, text: "6a"),
                     AxisMark(hour: 12, text: "12p"), AxisMark(hour: 18, text: "6p")]
        let nowX = now.map { m.x($0) }
        return ZStack(alignment: .topLeading) {
            ForEach(marks) { mark in
                let x = m.boundary(mark.hour)
                if nowX.map({ abs($0 - x) > 26 }) ?? true {
                    Text(mark.text)
                        .font(Twin.Typeface.mono(10))
                        .foregroundStyle(Twin.Palette.inkHint)
                        .frame(width: 40, alignment: mark.hour == 0 ? .leading : .center)
                        .offset(x: mark.hour == 0 ? 0 : x - 20)
                }
            }
            if let nowX {
                Text("now")
                    .font(Twin.Typeface.mono(10, bold: true))
                    .foregroundStyle(Twin.Palette.ink)
                    .frame(width: 40)
                    .offset(x: min(max(nowX - 20, -6), m.width - 34))
                    .opacity(nowShown ? 1 : 0)
            }
        }
        .frame(width: m.width, height: axisHeight, alignment: .topLeading)
        .accessibilityHidden(true)
    }

    // MARK: Geometry

    private struct Metrics {
        let width: CGFloat
        let gap: CGFloat
        var barWidth: CGFloat { max(1, (width - gap * 23) / 24) }
        var step: CGFloat { barWidth + gap }
        /// x of a time of day (hours, fractional) inside its hour's bar.
        func x(_ t: Double) -> CGFloat {
            let clamped = min(max(t, 0), 23.999)
            let h = Int(clamped)
            return CGFloat(h) * step + CGFloat(clamped - Double(h)) * barWidth
        }
        /// x of the start of an hour (middle of the gap before it).
        func boundary(_ h: Int) -> CGFloat { h == 0 ? 0 : CGFloat(h) * step - gap / 2 }
    }
}

/// A horizontal line through the middle of its frame.
struct ChartHLine: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return p
    }
}

/// A vertical line through the middle of its frame.
struct ChartVLine: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        return p
    }
}

/// The frame grown on each side. Use with `.contentShape(_:)` to give a small sticker or chip a
/// bigger tap area (HIG: 44 pt) without changing layout or looks.
struct TapAreaShape: Shape {
    var top: CGFloat
    var leading: CGFloat
    var bottom: CGFloat
    var trailing: CGFloat

    init(dx: CGFloat, dy: CGFloat) {
        self.init(top: dy, leading: dx, bottom: dy, trailing: dx)
    }

    init(top: CGFloat, leading: CGFloat, bottom: CGFloat, trailing: CGFloat) {
        self.top = top; self.leading = leading; self.bottom = bottom; self.trailing = trailing
    }

    func path(in rect: CGRect) -> Path {
        Path(CGRect(x: rect.minX - leading, y: rect.minY - top,
                    width: rect.width + leading + trailing, height: rect.height + top + bottom))
    }
}
