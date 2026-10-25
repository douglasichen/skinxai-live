import SwiftUI

/// Minutes of scratching per day (Trends; reusable for the doctor report).
///
/// - Bars grow in one after another with a spring. Flare days are orange with an ink edge, calmer
///   days after a flare ("improving") lime, other days 16% ink.
/// - A dashed "your usual" line draws itself across the plot.
/// - Markers are sticker flags on a dotted stem above the day something started; flags that would
///   collide are stacked on rows.
/// - Tap a day to select it: a cyan outline moves to it (matchedGeometryEffect) with a selection haptic.
struct DailyScratchChart: View {
    enum Tone: Equatable { case normal, flare, improving }

    struct Bar: Identifiable, Equatable {
        var id: Date
        var value: Double
        var tone: Tone
        /// Axis text under the bar, e.g. "18".
        var label: String
        /// Optional second axis line above the label, e.g. "FRI".
        var caption: String? = nil
        var isToday = false
        /// VoiceOver description of the day.
        var accessibility: String = ""
    }

    struct Marker: Identifiable, Equatable {
        var id: String
        var barID: Date
        var emoji: String
        var text: String
        var fill: Color
    }

    var bars: [Bar]
    var usual: Double? = nil
    /// Legend name of the dashed line: "your usual", or "usual · starting estimate" while it is a guess.
    var usualLabel = "your usual"
    var markers: [Marker] = []
    @Binding var selection: Date?
    var plotHeight: CGFloat = 150
    var delay: Double = 0.15
    var showsLegend = true
    var onMarkerTap: ((Marker) -> Void)? = nil

    @Namespace private var ns
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var grown = false
    @State private var decorated = false
    @State private var measuredWidth: CGFloat = 0
    @State private var flagWidths: [String: CGFloat] = [:]

    private let rowHeight: CGFloat = 23
    private let flagHeight: CGFloat = 18

    var body: some View {
        let w = measuredWidth > 0 ? measuredWidth : 358
        let placed = Self.place(markers: markers, bars: bars, width: w, widths: flagWidths)
        let rows = (placed.map(\.row).max() ?? -1) + 1
        let band: CGFloat = rows == 0 ? 0 : CGFloat(rows) * rowHeight + 8
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                VStack(spacing: 0) {
                    Color.clear.frame(height: band)
                    plot(width: w)
                }
                ForEach(placed) { p in stem(p, width: w, band: band) }
                ForEach(placed) { p in flag(p, placed: placed, width: w, band: band) }
            }
            .frame(width: w, alignment: .topLeading)
            axis(width: w).padding(.top, 9)
            if showsLegend { legend.padding(.top, 12) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { measuredWidth = $0 }
        .sensoryFeedback(.selection, trigger: selection)
        .onAppear {
            if reduceMotion {
                withAnimation(.easeOut(duration: 0.35).delay(delay)) { grown = true; decorated = true }
            } else {
                grown = true   // each column, flag and stem carries its own delayed animation
                withAnimation(.easeInOut(duration: 0.8).delay(decorationDelay)) { decorated = true }
            }
        }
    }

    // MARK: Timing

    /// The usual line and legend appear once every bar has grown.
    private var decorationDelay: Double { delay + Double(bars.count) * 0.035 + 0.25 }
    /// A flag drops in right after its own bar has grown, riding the wave of bars.
    private func markerDelay(_ p: PlacedMarker) -> Double { delay + Double(p.index) * 0.035 + 0.4 }

    // MARK: Scale

    private var scaleTop: Double {
        max(bars.map(\.value).max() ?? 0, (usual ?? 0) * 1.6, 1)
    }

    private func step(_ w: CGFloat) -> CGFloat { w / CGFloat(max(bars.count, 1)) }

    private func barWidth(step: CGFloat) -> CGFloat {
        min(step * 0.74, bars.count <= 7 ? 32 : 26)
    }

    private func barHeight(_ value: Double) -> CGFloat {
        max(3, CGFloat(value / scaleTop) * plotHeight)
    }

    // MARK: Plot

    private func plot(width w: CGFloat) -> some View {
        let s = step(w)
        let bw = barWidth(step: s)
        return ZStack(alignment: .bottomLeading) {
            HStack(alignment: .bottom, spacing: 0) {
                ForEach(Array(bars.enumerated()), id: \.element.id) { i, bar in
                    column(bar, index: i, step: s, barWidth: bw)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.3, anchor: .bottom)),
                            removal: .opacity))
                }
            }
            if let usual, usual > 0 {
                ChartHLine()
                    .trim(from: 0, to: decorated ? 1 : 0)
                    .stroke(Twin.Palette.ink.opacity(0.55), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    .frame(width: w, height: 2)
                    .offset(y: -(barHeight(usual) - 1))
                    .allowsHitTesting(false)
            }
        }
        .frame(width: w, height: plotHeight, alignment: .bottomLeading)
    }

    private func column(_ bar: Bar, index i: Int, step: CGFloat, barWidth bw: CGFloat) -> some View {
        let selected = selection == bar.id
        let full = barHeight(bar.value)
        // Not grown yet = not there (no 3 pt stub with an ink edge on the baseline): each bar grows
        // out of the baseline as a render transform (its layout never changes, so the spring only
        // overshoots its own height a little) and fades in on its beat; the selection outline grows
        // with it. Reduce Motion: full height, fade only.
        return ZStack(alignment: .bottom) {
            barShape(bar.tone)
                .frame(width: bw, height: full)
            if selected {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(Twin.Palette.cyan, lineWidth: 2.5)
                    .frame(width: bw + 9, height: full + 9)
                    .matchedGeometryEffect(id: "selected-day", in: ns)
                    .offset(y: 4.5)
            }
        }
        .scaleEffect(x: 1, y: (grown || reduceMotion) ? 1 : 0.001, anchor: .bottom)
        .opacity(grown ? 1 : 0)
        .animation(reduceMotion ? nil : Twin.Motion.bouncy.delay(delay + Double(i) * 0.035), value: grown)
        .frame(width: step, height: plotHeight, alignment: .bottom)
        .contentShape(Rectangle())
        .onTapGesture { select(bar.id) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(bar.accessibility.isEmpty ? bar.label : bar.accessibility)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { select(bar.id) }
    }

    @ViewBuilder private func barShape(_ tone: Tone) -> some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: 3, topTrailingRadius: 3, style: .continuous)
        switch tone {
        case .normal:
            shape.fill(Twin.Palette.ink.opacity(0.16))
        case .flare:
            shape.fill(Twin.Palette.orange).overlay(shape.strokeBorder(Twin.Palette.ink, lineWidth: 1))
        case .improving:
            shape.fill(Twin.Palette.lime).overlay(shape.strokeBorder(Twin.Palette.ink, lineWidth: 1))
        }
    }

    private func select(_ id: Date) {
        guard selection != id else { return }
        withAnimation(Twin.Motion.spring) { selection = id }
    }

    // MARK: Markers

    struct PlacedMarker: Identifiable {
        let marker: Marker
        let index: Int
        let row: Int
        let flipped: Bool
        var id: String { marker.id }
    }

    /// Greedy row assignment, right to left so flags further left sit higher: a flag never
    /// overlaps another flag on its row, never covers the stem of a flag above it, and its own
    /// stem never crosses a flag below it (flags on the same day share a stem).
    static func place(markers: [Marker], bars: [Bar], width: CGFloat, widths: [String: CGFloat] = [:]) -> [PlacedMarker] {
        let n = max(bars.count, 1)
        let step = width / CGFloat(n)
        let items: [(Marker, Int)] = markers
            .compactMap { m in bars.firstIndex(where: { $0.id == m.barID }).map { (m, $0) } }
            .sorted { $0.1 > $1.1 }
        var placed: [(p: PlacedMarker, lo: CGFloat, hi: CGFloat, stem: CGFloat)] = []
        for (m, i) in items {
            let x = (CGFloat(i) + 0.5) * step
            let fw = widths[m.id] ?? flagWidth(m)
            let flipped = x + fw > width
            let lo = flipped ? x - fw : x
            let hi = flipped ? x : x + fw
            var chosen: Int?
            for row in 0..<3 {
                let ok = placed.allSatisfy { other in
                    if other.p.row == row { return other.hi + 6 < lo || hi + 6 < other.lo }
                    if abs(other.stem - x) < 1 { return true }
                    if other.p.row > row { return !(other.stem >= lo - 4 && other.stem <= hi + 4) }
                    return !(x >= other.lo - 4 && x <= other.hi + 4)
                }
                if ok { chosen = row; break }
            }
            guard let row = chosen else { continue }
            placed.append((PlacedMarker(marker: m, index: i, row: row, flipped: flipped), lo, hi, x))
        }
        return placed.map(\.p)
    }

    /// Flag width estimate until the real width is measured.
    static func flagWidth(_ m: Marker) -> CGFloat {
        28 + CGFloat(m.text.count) * 5.6
    }

    private func rowTop(_ row: Int, band: CGFloat) -> CGFloat {
        band - 8 - CGFloat(row + 1) * rowHeight + (rowHeight - flagHeight)
    }

    private func stem(_ p: PlacedMarker, width w: CGFloat, band: CGFloat) -> some View {
        let x = (CGFloat(p.index) + 0.5) * step(w)
        let top = rowTop(p.row, band: band) + flagHeight
        let barTop = band + plotHeight - barHeight(bars.indices.contains(p.index) ? bars[p.index].value : 0)
        let length = max(0, barTop - top - 3)
        return ChartVLine()
            .trim(from: 0, to: decorated ? 1 : 0)
            .stroke(Twin.Palette.ink.opacity(0.6), style: StrokeStyle(lineWidth: 1.25, lineCap: .round, dash: [1, 3]))
            .frame(width: 2, height: length)
            .offset(x: x - 1, y: top)
            .allowsHitTesting(false)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.4).delay(markerDelay(p) + 0.12), value: decorated)
    }

    /// Horizontal extent of a placed flag.
    private func span(_ p: PlacedMarker, width w: CGFloat) -> ClosedRange<CGFloat> {
        let x = (CGFloat(p.index) + 0.5) * step(w)
        let fw = flagWidths[p.id] ?? Self.flagWidth(p.marker)
        return p.flipped ? (x - fw)...x : x...(x + fw)
    }

    /// The 18 pt flag's tap area grows 8 pt up and down, unless a stacked flag sits right there:
    /// then only half the 5 pt gap between rows, so a flag never takes a neighbour's taps.
    /// Sideways 3 pt (flags on one row are at least 6 pt apart).
    private func flagTapArea(_ p: PlacedMarker, placed: [PlacedMarker], width w: CGFloat) -> TapAreaShape {
        let mine = span(p, width: w)
        func stacked(_ row: Int) -> Bool {
            placed.contains { q in q.row == row && q.id != p.id && span(q, width: w).overlaps(mine) }
        }
        let half = (rowHeight - flagHeight) / 2
        return TapAreaShape(top: stacked(p.row + 1) ? half : 8, leading: 3,
                            bottom: p.row > 0 && stacked(p.row - 1) ? half : 8, trailing: 3)
    }

    private func flag(_ p: PlacedMarker, placed: [PlacedMarker], width w: CGFloat, band: CGFloat) -> some View {
        let x = (CGFloat(p.index) + 0.5) * step(w)
        let m = p.marker
        return Button {
            select(m.barID)
            onMarkerTap?(m)
        } label: {
            HStack(spacing: 3) {
                TwinIconView(emoji: m.emoji, size: 12)
                Text(m.text).font(Twin.Typeface.sans(10, .bold)).lineLimit(1)
            }
            .foregroundStyle(Twin.Palette.ink)
            .padding(.horizontal, 5)
            .frame(height: flagHeight)
            .sticker(m.fill)
            .fixedSize()
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { flagWidths[m.id] = $0 }
            .contentShape(flagTapArea(p, placed: placed, width: w))
        }
        .buttonStyle(PressableStyle())
        .scaleEffect(decorated || reduceMotion ? 1 : 0.6, anchor: p.flipped ? .bottomTrailing : .bottomLeading)
        .opacity(decorated ? 1 : 0)
        .animation(reduceMotion ? .easeOut(duration: 0.3) : Twin.Motion.bouncy.delay(markerDelay(p)), value: decorated)
        .frame(width: 0, alignment: p.flipped ? .trailing : .leading)
        .offset(x: p.flipped ? x + 1 : x - 1, y: rowTop(p.row, band: band))
        .accessibilityLabel("\(m.text) started")
    }

    // MARK: Axis and legend

    private func axis(width w: CGFloat) -> some View {
        let s = step(w)
        let small = bars.count > 16
        return HStack(alignment: .bottom, spacing: 0) {
            ForEach(bars) { bar in
                let on = bar.id == selection
                VStack(spacing: 1) {
                    if let caption = bar.caption {
                        Text(caption)
                            .font(Twin.Typeface.mono(9, bold: on))
                            .foregroundStyle(on ? Twin.Palette.ink : Twin.Palette.inkHint)
                    }
                    Text(bar.label)
                        .font(Twin.Typeface.mono(small ? 9 : 10, bold: on || bar.isToday))
                        .foregroundStyle(on || bar.isToday ? Twin.Palette.ink : Twin.Palette.inkHint)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(width: s)
                .contentShape(Rectangle())
                .onTapGesture { select(bar.id) }
            }
        }
        .accessibilityHidden(true)
    }

    private var legend: some View {
        HStack(spacing: 14) {
            if bars.contains(where: { $0.tone == .flare }) {
                legendItem(swatch: AnyView(swatch(Twin.Palette.orange)), text: "flare")
            }
            if bars.contains(where: { $0.tone == .improving }) {
                legendItem(swatch: AnyView(swatch(Twin.Palette.lime)), text: "improving")
            }
            if let usual, usual > 0 {
                legendItem(swatch: AnyView(
                    ChartHLine()
                        .stroke(Twin.Palette.ink.opacity(0.55), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                        .frame(width: 16, height: 2)),
                    text: "\(usualLabel) · \(Int(usual.rounded())) min")
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .opacity(decorated ? 1 : 0)
        .animation(.easeOut(duration: 0.4).delay(reduceMotion ? 0 : decorationDelay), value: decorated)
        .accessibilityElement(children: .combine)
    }

    private func swatch(_ fill: Color) -> some View {
        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
            .fill(fill)
            .overlay(RoundedRectangle(cornerRadius: 1.5, style: .continuous).strokeBorder(Twin.Palette.ink, lineWidth: 1))
            .frame(width: 10, height: 10)
    }

    private func legendItem(swatch: AnyView, text: String) -> some View {
        HStack(spacing: 5) {
            swatch
            Text(text).font(Twin.Typeface.mono(10)).foregroundStyle(Twin.Palette.inkHint)
        }
    }
}
