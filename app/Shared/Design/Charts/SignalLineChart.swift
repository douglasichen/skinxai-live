import SwiftUI
import Charts

/// A small line over days (Trends sleep & stress). Point i sits over bar i of a `DailyScratchChart`
/// of the same width, so a selected day lines up across charts.
/// The line draws itself from left to right; flare days get a soft orange band behind the line;
/// the selected day gets a cyan rule and a square cyan point. A `nil` value is a day without a
/// measurement: the line breaks there (a lone measured day is a dot), and the scale ignores it.
struct SignalLineChart: View {
    var values: [Double?]
    var usual: Double? = nil
    /// Days to shade (e.g. flare days). Same length as `values`.
    var shaded: [Bool] = []
    var selectedIndex: Int? = nil
    var color: Color = Twin.Palette.ink
    var height: CGFloat = 54
    var delay: Double = 0.35

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = false

    /// One measured day. `run` numbers the stretches of consecutive measured days.
    private struct Point: Identifiable { let id: Int; let value: Double; let run: Int; let alone: Bool }
    private struct Band: Identifiable { let id: Int; let from: Int; let to: Int }

    private var points: [Point] {
        var out: [Point] = []
        var run = 0
        for (i, v) in values.enumerated() {
            guard let v else { continue }
            if let last = out.last, last.id != i - 1 { run += 1 }
            let alone = (i == 0 || values[i - 1] == nil) && (i == values.count - 1 || values[i + 1] == nil)
            out.append(Point(id: i, value: v, run: run, alone: alone))
        }
        return out
    }

    private var bands: [Band] {
        var out: [Band] = []
        var start: Int?
        for i in 0...values.count {
            let on = i < values.count && i < shaded.count && shaded[i]
            if on, start == nil { start = i }
            if !on, let s = start { out.append(Band(id: s, from: s, to: i - 1)); start = nil }
        }
        return out
    }

    private var yDomain: ClosedRange<Double> {
        let measured = values.compactMap { $0 }
        let lo = min(measured.min() ?? 0, usual ?? .greatestFiniteMagnitude)
        let hi = max(measured.max() ?? 1, usual ?? -.greatestFiniteMagnitude)
        let pad = max((hi - lo) * 0.2, 0.25)
        return (lo - pad)...(hi + pad)
    }

    var body: some View {
        let domain = yDomain
        let pts = points
        Chart {
            ForEach(bands) { b in
                RectangleMark(xStart: .value("From", Double(b.from) - 0.5),
                              xEnd: .value("To", Double(b.to) + 0.5),
                              yStart: .value("Low", domain.lowerBound),
                              yEnd: .value("High", domain.upperBound))
                    .foregroundStyle(Twin.Palette.orangeSoft.opacity(0.7))
            }
            if let usual {
                RuleMark(y: .value("Usual", usual))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .foregroundStyle(Twin.Palette.ink.opacity(0.4))
            }
            ForEach(pts) { p in
                LineMark(x: .value("Day", Double(p.id)), y: .value("Value", p.value), series: .value("Run", p.run))
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .foregroundStyle(color)
            }
            // A measured day with no measured neighbour has no line: show it as a dot.
            ForEach(pts.filter(\.alone)) { p in
                PointMark(x: .value("Day", Double(p.id)), y: .value("Value", p.value))
                    .symbolSize(22)
                    .foregroundStyle(color)
            }
            if let s = selectedIndex, values.indices.contains(s) {
                RuleMark(x: .value("Selected", Double(s)))
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                    .foregroundStyle(Twin.Palette.cyan)
                if let v = values[s] {
                    PointMark(x: .value("Day", Double(s)), y: .value("Value", v))
                        .symbol {
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(Twin.Palette.cyan)
                                .overlay(RoundedRectangle(cornerRadius: 2, style: .continuous)
                                    .strokeBorder(Twin.Palette.ink, lineWidth: 1.5))
                                .frame(width: 10, height: 10)
                        }
                }
            }
        }
        .chartXScale(domain: -0.5...(Double(max(values.count, 1)) - 0.5))
        .chartYScale(domain: domain)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .frame(height: height)
        .mask(alignment: .leading) {
            GeometryReader { g in
                Rectangle().frame(width: (revealed || reduceMotion) ? g.size.width : 0)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.0).delay(delay)) { revealed = true }
        }
    }
}
