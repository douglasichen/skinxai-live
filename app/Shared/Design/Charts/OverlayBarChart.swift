#if os(iOS)
import SwiftUI

/// One big chart (Trends): minutes of scratching per night as bars, with one factor (sleep, humidity…)
/// drawn over them as a bold line on its own axis at the right, so the two can be read against each
/// other night by night.
///
/// - Bars: flare nights orange with an ink edge, the rest 15% ink. A dashed line marks the usual.
/// - Left axis: minutes. Right axis: the overlay's values with their unit (empty with no overlay).
///   Both share the same gridlines.
/// - Bands: a light labelled column behind a run of nights (an exam week).
/// - Markers: a sticker with an icon on its night just above the date axis (a purchase), with a thin
///   dashed guide up through the bars. Markers that would touch (the same night, or nights close together)
///   spread out side by side around their nights, in order. Tap one → `onMarker`.
/// - Tap a night anywhere in its column: a cyan band highlights it.
/// - More than `window` nights scroll sideways; the chart opens on the newest night (right edge). The
///   month of the first night on screen stays pinned at the left of the date axis.
struct OverlayBarChart: View {
    struct Night: Identifiable, Equatable {
        var id: Int
        var minutes: Double
        var hot: Bool
        /// "20"
        var day: String
        /// "OCT"
        var month: String
        var startsMonth = false
        var isLast = false
        /// The overlay's value that night (nil: no overlay or no data).
        var overlay: Double?
        var accessibility = ""
    }

    struct Overlay: Equatable {
        /// "sleep": the line redraws when it changes.
        var id: String
        /// "SLEEP · HOURS"
        var title: String
        var domain: ClosedRange<Double>
        /// One label per gridline, bottom to top ("4h" … "9h").
        var ticks: [String]
    }

    struct Band: Identifiable, Equatable {
        var id: String
        var start: Int
        var end: Int
        /// "EXAMS"
        var label: String
        var emoji: String
    }

    struct Marker: Identifiable, Equatable {
        var id: String
        var night: Int
        /// Order among the markers on the same night: they sit side by side, centered on the night.
        var row = 0
        var emoji: String
        var fill: Color
        var accessibility = ""
    }

    var nights: [Night]
    var overlay: Overlay?
    var bands: [Band] = []
    var markers: [Marker] = []
    var usual: Double
    /// Minutes at the top gridline (0 at the bottom); `gridSteps` equal steps between.
    var scaleTop: Double
    var gridSteps = 5
    @Binding var selection: Int
    /// The most nights that share the width; with more, the chart scrolls.
    var window = 22
    var gap: CGFloat = 3
    var maxBar: CGFloat = 30
    var plotHeight: CGFloat = 250
    var delay: Double = 0.2
    var onMarker: (String) -> Void = { _ in }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale
    @State private var grown = false
    @State private var decorated = false
    @State private var spot: OverlaySpot?

    // MARK: Layout (top to bottom)

    static let leftAxis: CGFloat = 24
    static let rightAxis: CGFloat = 38
    /// Room on both sides of the plot so the selection band never clips.
    static let inset: CGFloat = 3
    private let plotTop: CGFloat = 8
    private let rowHeight: CGFloat = 28
    private var baseline: CGFloat { plotTop + plotHeight }
    private var rows: Int { markers.isEmpty ? 0 : 1 }
    private var laneTop: CGFloat { baseline + 6 }
    private var laneEnd: CGFloat { laneTop + CGFloat(rows) * rowHeight }
    private var dayY: CGFloat { laneEnd + (rows > 0 ? 4 : 2) }
    private var monthY: CGFloat { dayY + 14 }
    private var totalHeight: CGFloat { monthY + 12 }

    /// The y of a fraction of the plot (0 = baseline, 1 = top gridline).
    private func y(_ fraction: Double) -> CGFloat { baseline - CGFloat(min(max(fraction, 0), 1.04)) * plotHeight }
    private func gridY(_ step: Int) -> CGFloat { y(Double(step) / Double(gridSteps)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            axisTitles
            HStack(alignment: .top, spacing: 0) {
                leftLabels.frame(width: Self.leftAxis, height: totalHeight, alignment: .topLeading)
                GeometryReader { g in
                    let m = Metrics(viewport: g.size.width - Self.inset * 2, count: nights.count, window: window, gap: gap, maxBar: maxBar)
                    ZStack(alignment: .topLeading) {
                        grid(width: g.size.width)
                        ScrollViewReader { proxy in
                            ScrollView(.horizontal) {
                                plot(m)
                                    .frame(width: m.contentWidth, height: totalHeight, alignment: .topLeading)
                                    .background(alignment: .bottomLeading) { anchors(m) }
                                    .padding(.horizontal, Self.inset)
                            }
                            .scrollIndicators(.hidden)
                            .scrollDisabled(!m.scrollable)
                            .defaultScrollAnchor(.trailing)
                            .modifier(OverlaySpotReader(step: m.slot + gap, count: nights.count, spot: $spot))
                            .mask { edgeFade(m) }
                            .overlay(alignment: .topLeading) { pinnedMonth(m).offset(x: Self.inset) }
                            .onChange(of: selection) { _, id in
                                guard m.scrollable, let k = index(of: id) else { return }
                                let left = spot?.left ?? (nights.count - m.fit)
                                guard k < left || k >= left + m.fit else { return }
                                withAnimation(Twin.Motion.slide) { proxy.scrollTo("n\(id)", anchor: .center) }
                            }
                        }
                    }
                }
                .frame(height: totalHeight)
                rightLabels.frame(width: Self.rightAxis, height: totalHeight, alignment: .topLeading)
            }
            .frame(height: totalHeight)
        }
        .sensoryFeedback(.selection, trigger: selection)
        .onAppear {
            if reduceMotion {
                withAnimation(.easeOut(duration: 0.35).delay(delay)) { grown = true; decorated = true }
            } else {
                grown = true
                withAnimation(.easeInOut(duration: 0.6).delay(decorationDelay)) { decorated = true }
            }
        }
    }

    // MARK: Geometry

    private struct Metrics {
        let viewport: CGFloat
        let count: Int
        let window: Int
        let gap: CGFloat
        let maxBar: CGFloat
        var fit: Int { max(1, min(count, window)) }
        var slot: CGFloat { max(1, (viewport - gap * CGFloat(fit - 1)) / CGFloat(fit)) }
        var bar: CGFloat { min(slot, maxBar) }
        var scrollable: Bool { count > window }
        var contentWidth: CGFloat { scrollable ? CGFloat(count) * (slot + gap) - gap : viewport }
        func slotX(_ k: Int) -> CGFloat { CGFloat(k) * (slot + gap) }
        func center(_ k: Int) -> CGFloat { slotX(k) + slot / 2 }
        /// Few enough nights to write each value.
        var roomy: Bool { slot >= 28 }
    }

    private func index(of id: Int) -> Int? { nights.firstIndex { $0.id == id } }

    /// The first night that grows in: the first one on screen.
    private var entranceFirst: Int { max(0, nights.count - window) }
    private func beat(_ k: Int) -> Double { delay + Double(max(k - entranceFirst, 0)) * stagger }
    private var stagger: Double { nights.count - entranceFirst > 10 ? 0.025 : 0.05 }
    private var decorationDelay: Double { delay + Double(nights.count - entranceFirst) * stagger + 0.1 }

    private func barHeight(_ value: Double) -> CGFloat {
        let h = max(3, CGFloat(value / max(scaleTop, 0.001)) * plotHeight)
        return displayScale > 0 ? (h * displayScale).rounded() / displayScale : h
    }

    private func overlayY(_ v: Double, _ o: Overlay) -> CGFloat {
        y((v - o.domain.lowerBound) / (o.domain.upperBound - o.domain.lowerBound))
    }

    // MARK: Axes

    /// "SCRATCH · MIN" over the left axis, "━ SLEEP · HOURS" over the right one.
    private var axisTitles: some View {
        HStack(spacing: 6) {
            HStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(Twin.Palette.ink.opacity(0.15))
                    .frame(width: 8, height: 11)
                Text("SCRATCH · MIN")
            }
            .foregroundStyle(Twin.Palette.inkHint)
            Spacer(minLength: 4)
            if let overlay {
                HStack(spacing: 5) {
                    Capsule().fill(Twin.Palette.ink).frame(width: 14, height: 3)
                    Text(overlay.title)
                }
                .foregroundStyle(Twin.Palette.ink)
                .id(overlay.id)
                .transition(.opacity)
            }
        }
        .font(Twin.Typeface.mono(10, bold: true))
        .tracking(0.4)
        .lineLimit(1)
        .accessibilityHidden(true)
    }

    private var leftLabels: some View {
        ZStack(alignment: .topLeading) {
            ForEach(0...gridSteps, id: \.self) { s in
                Text("\(Int((scaleTop * Double(s) / Double(gridSteps)).rounded()))")
                    .font(Twin.Typeface.mono(10))
                    .foregroundStyle(Twin.Palette.inkHint)
                    .monospacedDigit()
                    .frame(width: Self.leftAxis - 5, alignment: .trailing)
                    .frame(height: 14)
                    .offset(y: gridY(s) - 7)
            }
        }
        .accessibilityHidden(true)
    }

    private var rightLabels: some View {
        ZStack(alignment: .topLeading) {
            if let overlay {
                ZStack(alignment: .topLeading) {
                    ForEach(Array(overlay.ticks.enumerated()), id: \.offset) { s, tick in
                        Text(tick)
                            .font(Twin.Typeface.mono(10, bold: true))
                            .foregroundStyle(Twin.Palette.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(width: Self.rightAxis - 5, alignment: .leading)
                            .frame(height: 14)
                            .offset(x: 5, y: gridY(s) - 7)
                    }
                }
                .id(overlay.id)
                .transition(.opacity)
            }
        }
        .accessibilityHidden(true)
    }

    /// Gridlines across the visible width (they don't scroll).
    private func grid(width: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(1...gridSteps, id: \.self) { s in
                Rectangle().fill(Twin.Palette.hairline.opacity(0.7))
                    .frame(width: width, height: Twin.Stroke.hairline)
                    .offset(y: gridY(s) - 0.5)
            }
            Rectangle().fill(Twin.Palette.seam)
                .frame(width: width, height: Twin.Stroke.hairline)
                .offset(y: baseline - 0.5)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: Plot

    private func plot(_ m: Metrics) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(bands) { band in bandView(band, m: m) }
            selectionBand(m)
            ForEach(markers) { marker in guide(marker, m: m) }
            ForEach(Array(nights.enumerated()), id: \.element.id) { k, night in
                bar(night, k: k, m: m)
            }
            usualLine(m)
            if let overlay {
                OverlayLineLayer(points: nights.indices.map { k in
                    nights[k].overlay.map { CGPoint(x: m.center(k), y: overlayY($0, overlay)) }
                }, dots: m.roomy, selected: index(of: selection), show: decorated || reduceMotion,
                   reduceMotion: reduceMotion)
                    .frame(width: m.contentWidth, height: totalHeight, alignment: .topLeading)
                    .id(overlay.id)
                    .transition(.opacity)
            }
            ForEach(Array(nights.enumerated()), id: \.element.id) { k, night in
                labelsAndTap(night, k: k, m: m)
            }
            let dx = markerOffsets(m)
            ForEach(markers) { marker in markerView(marker, dx: dx[marker.id] ?? 0, m: m) }
        }
    }

    /// A light column behind a run of nights, its label at the top.
    @ViewBuilder private func bandView(_ band: Band, m: Metrics) -> some View {
        if let a = index(of: band.start), let b = index(of: band.end) {
            let x = m.slotX(a) - gap / 2
            let w = m.slotX(b) + m.slot + gap / 2 - x
            ZStack(alignment: .top) {
                Rectangle().fill(Twin.Palette.fill)
                    .overlay(alignment: .leading) { Rectangle().fill(Twin.Palette.hairline).frame(width: 1) }
                    .overlay(alignment: .trailing) { Rectangle().fill(Twin.Palette.hairline).frame(width: 1) }
                HStack(spacing: 3) {
                    TwinIconView(emoji: band.emoji, size: 13)
                    Text(band.label)
                        .font(Twin.Typeface.mono(9, bold: true))
                        .tracking(0.4)
                        .foregroundStyle(Twin.Palette.inkMuted)
                }
                .fixedSize()
                .padding(.top, 4)
            }
            .frame(width: w, height: plotHeight)
            .offset(x: x, y: plotTop)
            .opacity(grown ? 1 : 0)
            .animation(.easeOut(duration: 0.4).delay(delay), value: grown)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    /// The selected night: a cyan column from the top of the plot through the date.
    @ViewBuilder private func selectionBand(_ m: Metrics) -> some View {
        if let k = index(of: selection) {
            let w = m.slot + gap + 2
            RoundedRectangle(cornerRadius: Twin.Radius.chip, style: .continuous)
                .fill(Twin.Palette.cyanSoft)
                .overlay(RoundedRectangle(cornerRadius: Twin.Radius.chip, style: .continuous)
                    .strokeBorder(Twin.Palette.cyan, lineWidth: Twin.Stroke.ink))
                .frame(width: w, height: monthY - 1)
                .offset(x: m.center(k) - w / 2, y: 1)
                .opacity(grown ? 1 : 0)
                .animation(.easeOut(duration: 0.3).delay(delay), value: grown)
                .allowsHitTesting(false)
        }
    }

    private func bar(_ night: Night, k: Int, m: Metrics) -> some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: 2, topTrailingRadius: 2, style: .continuous)
        let h = barHeight(night.minutes)
        return VStack(spacing: 3) {
            if m.roomy {
                Text("\(Int(night.minutes.rounded()))")
                    .font(Twin.Typeface.mono(11, bold: true))
                    .foregroundStyle(night.id == selection || night.hot ? Twin.Palette.ink : Twin.Palette.inkMuted)
                    .monospacedDigit()
                    .fixedSize()
                    .padding(.horizontal, 2)
                    .background(Twin.Palette.paper, in: RoundedRectangle(cornerRadius: 2, style: .continuous))
                    .opacity(grown ? 1 : 0)
                    .animation(.easeOut(duration: 0.3).delay(beat(k) + 0.25), value: grown)
            }
            Group {
                if night.hot {
                    shape.fill(Twin.Palette.orange).overlay(shape.strokeBorder(Twin.Palette.ink, lineWidth: 1))
                } else {
                    shape.fill(Twin.Palette.ink.opacity(0.15))
                }
            }
            .frame(width: m.bar, height: h)
            .scaleEffect(x: 1, y: grown || reduceMotion ? 1 : 0.001, anchor: .bottom)
            .opacity(grown ? 1 : 0)
            .animation(reduceMotion ? nil : Twin.Motion.bouncy.delay(beat(k)), value: grown)
        }
        .frame(width: m.slot, height: plotHeight + 20, alignment: .bottom)
        .offset(x: m.slotX(k), y: plotTop - 20)
        .allowsHitTesting(false)
    }

    private func usualLine(_ m: Metrics) -> some View {
        ChartHLine()
            .trim(from: 0, to: decorated || reduceMotion ? 1 : 0)
            .stroke(Twin.Palette.ink.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            .frame(width: m.contentWidth, height: 2)
            .offset(y: baseline - barHeight(usual) - 1)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    // MARK: Markers

    private var markerY: CGFloat { laneTop + rowHeight / 2 }

    /// Center-to-center distance of markers side by side (a 24 pt sticker and a gap).
    private let markerPitch: CGFloat = 27

    /// Each marker's horizontal offset from its night's center. Markers whose stickers would overlap form a
    /// group, spread `markerPitch` apart (in night order, then `row`) around the middle of their nights;
    /// groups that then touch merge, until none do.
    private func markerOffsets(_ m: Metrics) -> [String: CGFloat] {
        let placed = markers.compactMap { mk in index(of: mk.night).map { (marker: mk, x: m.center($0)) } }
            .sorted { ($0.x, $0.marker.row) < ($1.x, $1.marker.row) }
        var groups: [[(marker: Marker, x: CGFloat)]] = placed.map { [$0] }
        func middle(_ g: [(marker: Marker, x: CGFloat)]) -> CGFloat { g.map(\.x).reduce(0, +) / CGFloat(g.count) }
        func half(_ g: [(marker: Marker, x: CGFloat)]) -> CGFloat { CGFloat(g.count - 1) / 2 * markerPitch }
        var merged = true
        while merged {
            merged = false
            for k in groups.indices.dropLast() {
                let a = groups[k], b = groups[k + 1]
                if (middle(b) - half(b)) - (middle(a) + half(a)) < markerPitch {
                    groups[k] = a + b
                    groups.remove(at: k + 1)
                    merged = true
                    break
                }
            }
        }
        var out: [String: CGFloat] = [:]
        for g in groups {
            let mid = middle(g)
            for (k, item) in g.enumerated() {
                out[item.marker.id] = mid + (CGFloat(k) - CGFloat(g.count - 1) / 2) * markerPitch - item.x
            }
        }
        return out
    }

    /// A thin dashed pink line from the marker up through the plot, on its night.
    @ViewBuilder private func guide(_ marker: Marker, m: Metrics) -> some View {
        if marker.row == 0, let k = index(of: marker.night) {
            ChartVLine()
                .stroke(Twin.Palette.pink, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                .frame(width: 2, height: markerY - plotTop)
                .offset(x: m.center(k) - 1, y: plotTop)
                .opacity(decorated ? 1 : 0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder private func markerView(_ marker: Marker, dx: CGFloat, m: Metrics) -> some View {
        if let k = index(of: marker.night) {
            Button { onMarker(marker.id) } label: {
                TwinIconView(emoji: marker.emoji, size: 17)
                    .frame(width: 24, height: 24)
                    .sticker(marker.fill)
                    .contentShape(Rectangle().inset(by: -4))
            }
            .buttonStyle(PressableStyle())
            .scaleEffect(decorated || reduceMotion ? 1 : 0.5)
            .opacity(decorated ? 1 : 0)
            .animation(reduceMotion ? .easeOut(duration: 0.3) : Twin.Motion.bouncy.delay(0.1 + Double(marker.row) * 0.08), value: decorated)
            .frame(width: 0, height: 0)
            .offset(x: m.center(k) + dx, y: markerY)
            .accessibilityLabel(marker.accessibility)
            .accessibilityAddTraits(.isButton)
        }
    }

    // MARK: Labels and taps

    /// Day numbers: every night when there's room, otherwise every other one (counting back from last
    /// night). The selected night is always labeled (its neighbors give way).
    private func showsDay(_ k: Int, m: Metrics) -> Bool {
        if m.slot + gap >= 22 { return true }
        if let s = index(of: selection) {
            if k == s { return true }
            if abs(k - s) == 1 { return false }
        }
        return (nights.count - 1 - k) % 2 == 0
    }

    private func labelsAndTap(_ night: Night, k: Int, m: Metrics) -> some View {
        let left = spot?.left ?? max(0, nights.count - m.fit)
        let strong = night.isLast || night.id == selection
        return ZStack(alignment: .topLeading) {
            if night.startsMonth && k > left {
                Text(night.month)
                    .font(Twin.Typeface.mono(9, bold: true))
                    .tracking(0.45)
                    .foregroundStyle(Twin.Palette.inkMuted)
                    .fixedSize()
                    .frame(width: 0, alignment: .leading)
                    .offset(x: m.slotX(k), y: monthY)
            }
            if showsDay(k, m: m) {
                Text(night.day)
                    .font(Twin.Typeface.mono(11, bold: strong))
                    .foregroundStyle(strong ? Twin.Palette.ink : Twin.Palette.inkHint)
                    .lineLimit(1)
                    .fixedSize()
                    .frame(width: m.slot + gap)
                    .offset(x: m.slotX(k) - gap / 2, y: dayY)
            }
            Color.clear
                .frame(width: m.slot + gap, height: totalHeight)
                .contentShape(Rectangle())
                .offset(x: m.slotX(k) - gap / 2)
                .onTapGesture { select(night.id) }
                .accessibilityElement()
                .accessibilityLabel(night.accessibility)
                .accessibilityAddTraits(selection == night.id ? [.isButton, .isSelected] : .isButton)
                .accessibilityAction { select(night.id) }
        }
    }

    /// The month of the first night on screen, pinned at the left ("‹ OCT" while older nights hide there).
    private func pinnedMonth(_ m: Metrics) -> some View {
        let left = m.scrollable ? min(max(spot?.left ?? (nights.count - m.fit), 0), max(nights.count - 1, 0)) : 0
        let soon = (left + 1...left + 2).contains { nights.indices.contains($0) && nights[$0].startsMonth }
        let more = m.scrollable && left > 0
        let month = nights.indices.contains(left) ? nights[left].month : ""
        return Text(soon ? (more ? "‹" : "") : (more ? "‹ \(month)" : month))
            .font(Twin.Typeface.mono(9, bold: true))
            .tracking(0.45)
            .foregroundStyle(Twin.Palette.inkMuted)
            .fixedSize()
            .padding(.trailing, 4)
            .background(Twin.Palette.paper)
            .offset(y: monthY)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    // MARK: Scrolling

    private func anchors(_ m: Metrics) -> some View {
        HStack(spacing: 0) {
            ForEach(nights) { night in
                Color.clear.frame(width: m.slot, height: 1).id("n\(night.id)").padding(.trailing, gap)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func edgeFade(_ m: Metrics) -> some View {
        let fadeLeft = m.scrollable && spot?.atStart != true
        let fadeRight = m.scrollable && spot?.atEnd == false
        return HStack(spacing: 0) {
            LinearGradient(colors: [.black.opacity(fadeLeft ? 0 : 1), .black], startPoint: .leading, endPoint: .trailing)
                .frame(width: 14)
            Rectangle().fill(.black)
            LinearGradient(colors: [.black, .black.opacity(fadeRight ? 0 : 1)], startPoint: .leading, endPoint: .trailing)
                .frame(width: 14)
        }
        .animation(.easeOut(duration: 0.25), value: fadeLeft)
        .animation(.easeOut(duration: 0.25), value: fadeRight)
    }

    private func select(_ id: Int) {
        guard selection != id else { return }
        withAnimation(Twin.Motion.spring) { selection = id }
    }
}

// MARK: - Overlay line

/// The overlay as a bold ink line that draws in from the left when it appears. Dots on every night when
/// there's room; the selected night's point is a cyan dot.
private struct OverlayLineLayer: View {
    var points: [CGPoint?]
    var dots: Bool
    var selected: Int?
    var show: Bool
    var reduceMotion: Bool

    @State private var drawn = false

    var body: some View {
        let on = (drawn && show) || reduceMotion
        ZStack(alignment: .topLeading) {
            OverlayLine(points: points)
                .trim(from: 0, to: on ? 1 : 0)
                .stroke(Twin.Palette.paper, style: StrokeStyle(lineWidth: 5.5, lineCap: .round, lineJoin: .round))
            OverlayLine(points: points)
                .trim(from: 0, to: on ? 1 : 0)
                .stroke(Twin.Palette.ink, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            if dots {
                ForEach(Array(points.enumerated()), id: \.offset) { k, p in
                    if let p, k != selected {
                        Circle()
                            .fill(Twin.Palette.paper)
                            .overlay(Circle().strokeBorder(Twin.Palette.ink, lineWidth: 2))
                            .frame(width: 9, height: 9)
                            .offset(x: p.x - 4.5, y: p.y - 4.5)
                            .opacity(on ? 1 : 0)
                    }
                }
            }
            if let k = selected, points.indices.contains(k), let p = points[k] {
                Circle()
                    .fill(Twin.Palette.cyan)
                    .overlay(Circle().strokeBorder(Twin.Palette.ink, lineWidth: 2))
                    .frame(width: 12, height: 12)
                    .offset(x: p.x - 6, y: p.y - 6)
                    .opacity(on ? 1 : 0)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.7), value: on)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { drawn = true }
    }
}

// MARK: - Helpers

private struct OverlaySpot: Equatable {
    var left: Int
    var atStart: Bool
    var atEnd: Bool
}

private struct OverlaySpotReader: ViewModifier {
    let step: CGFloat
    let count: Int
    @Binding var spot: OverlaySpot?

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollGeometryChange(for: OverlaySpot.self) { geo in
                let x = geo.contentOffset.x + geo.contentInsets.leading
                let maxX = geo.contentSize.width - geo.containerSize.width
                let left = Int(((x - 2) / max(step, 1)).rounded(.up))
                return OverlaySpot(left: min(max(left, 0), max(count - 1, 0)), atStart: x <= 1, atEnd: x >= maxX - 1)
            } action: { _, new in
                spot = new
            }
        } else {
            content
        }
    }
}

/// A line through the points (a gap where a night has no value).
private struct OverlayLine: Shape {
    var points: [CGPoint?]
    func path(in rect: CGRect) -> Path {
        var p = Path()
        var open = false
        for point in points {
            guard let point else { open = false; continue }
            if open { p.addLine(to: point) } else { p.move(to: point); open = true }
        }
        return p
    }
}
#endif
