import SwiftUI
import EczemaKit

// The cards Claude puts in the thread (prototype v5 "Insight"): the tool card, the timeline, the product, a
// question and the conclusion. Each plays its entrance only while it is new (`fresh`); coming back to the
// screen later shows it as it ended.

private let cardShape = RoundedRectangle(cornerRadius: Twin.Radius.card, style: .continuous)

private extension View {
    /// A card with a 1.5 pt ink edge (Claude's artifacts).
    func inkCard(_ fill: Color, padding: CGFloat = 14) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill, in: cardShape)
            .overlay(cardShape.strokeBorder(Twin.Palette.ink, lineWidth: Twin.Stroke.ink))
    }
}

/// A small sticker for card corners ("✶ FROM CLAUDE", "FIRST TIME").
private struct CornerSticker: View {
    let text: String
    /// Claude's ✶ in front of the text.
    var claude = false
    /// An emoji picture in front of the text (drawn icon if there is one).
    var icon: String? = nil
    let fill: Color
    var body: some View {
        HStack(spacing: 4) {
            if claude { ClaudeMark(size: 10) }
            if let icon { TwinIconView(emoji: icon, size: 12) }
            Text(text).font(Twin.Typeface.sans(10, .bold)).lineLimit(1)
        }
        .foregroundStyle(Twin.Palette.ink)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .sticker(fill)
    }
}

// MARK: - Tool card

/// The data Claude reads: one row per tool call on a cream card.
struct ToolListCard: View {
    let rows: [ChatToolRow]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                VStack(spacing: 0) {
                    if index > 0 { Rectangle().fill(Twin.Palette.hairline).frame(height: 1) }
                    ToolRowView(row: row)
                }
                .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 8)), removal: .opacity))
            }
        }
        .background(Twin.Palette.cream)
        .clipShape(cardShape)
        .overlay(cardShape.strokeBorder(Twin.Palette.hairline, lineWidth: Twin.Stroke.hairline))
    }
}

private struct ToolRowView: View {
    let row: ChatToolRow

    var body: some View {
        HStack(spacing: 10) {
            TwinIconView(emoji: row.icon, size: 17)
                .frame(width: 26, height: 26)
                .sticker(Twin.Palette.paper)
            VStack(alignment: .leading, spacing: 1) {
                Text(row.title)
                    .font(Twin.Typeface.sans(13, .bold))
                    .foregroundStyle(Twin.Palette.ink)
                Text(row.summary ?? ChatTools.reading)
                    .font(Twin.Typeface.sans(12))
                    .foregroundStyle(Twin.Palette.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            ZStack {
                if row.summary == nil {
                    RingSpinner().transition(.opacity)
                } else {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(Twin.Palette.ink)
                        .frame(width: 18, height: 18)
                        .sticker(Twin.Palette.lime)
                        .transition(.scale(scale: 0.3).combined(with: .opacity))
                }
            }
            .frame(width: 18, height: 18)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .animation(Twin.Motion.bouncy, value: row.summary)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(row.title). \(row.summary ?? "Reading")")
    }
}

/// A 14 pt ring with an ink quarter that turns (the tool is running).
private struct RingSpinner: View {
    var body: some View {
        TimelineView(.animation) { context in
            let turn = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 0.7) / 0.7
            ZStack {
                Circle().stroke(Twin.Palette.hairline, lineWidth: 2)
                Circle()
                    .trim(from: 0, to: 0.25)
                    .stroke(Twin.Palette.ink, style: StrokeStyle(lineWidth: 2, lineCap: .butt))
                    .rotationEffect(.degrees(turn * 360 - 90))
            }
        }
        .frame(width: 14, height: 14)
    }
}

// MARK: - Timeline

/// `show_timeline`: the nights (hot ones orange) from a little before Claude's earliest marker to last night,
/// with one labelled pin per marker. Pins that would collide stack in lanes above the bars.
struct TimelineCardView: View {
    let card: ChatTimeline
    let fresh: Bool
    @State private var grown: Bool
    @State private var pinned: Bool
    /// The chart's width, as last laid out (the lanes of pins depend on it).
    @State private var width: CGFloat = 330
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let chartHeight: CGFloat = 92
    private let laneHeight: CGFloat = 23
    /// Labels longer than this are cut with "…".
    private static let maxLabel = 24

    init(card: ChatTimeline, fresh: Bool) {
        self.card = card
        self.fresh = fresh
        _grown = State(initialValue: !fresh)
        _pinned = State(initialValue: !fresh)
    }

    private var top: CGFloat { CGFloat(max(44, (card.minutes.max() ?? 0) + 3)) }
    /// Thinner gaps when there are many nights.
    private var gap: CGFloat { card.nightCount > 40 ? 1 : (card.nightCount > 20 ? 2 : 3) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                Eyebrow(text: "Your nights · last \(card.nightCount)")
                Spacer(minLength: 8)
                CornerSticker(text: "FROM CLAUDE", claude: true, fill: Twin.Palette.pink)
            }
            GeometryReader { geo in chart(width: geo.size.width, pins: pins(width: geo.size.width)) }
                .frame(height: pinSpace + chartHeight)
                .padding(.top, 6)
                .background(GeometryReader { geo in
                    Color.clear
                        .onAppear { width = geo.size.width }
                        .onChange(of: geo.size.width) { _, w in width = w }
                })
            GeometryReader { geo in axis(width: geo.size.width) }
                .frame(height: 14)
                .padding(.top, 6)
            if let note = card.note {
                Text(note)
                    .font(Twin.Typeface.sans(13))
                    .foregroundStyle(Twin.Palette.inkMuted)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
            }
        }
        .inkCard(Twin.Palette.paper)
        .onAppear {
            guard !grown else { return }
            DispatchQueue.main.async {
                grown = true
                withAnimation(reduceMotion ? .easeOut(duration: 0.3) : Twin.Motion.bouncy.delay(0.75)) { pinned = true }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    // MARK: Geometry

    private func barWidth(_ width: CGFloat) -> CGFloat {
        let n = CGFloat(max(card.nightCount, 1))
        return max(1, (width - gap * (n - 1)) / n)
    }

    private func center(of k: Int, width: CGFloat) -> CGFloat {
        let w = barWidth(width)
        return CGFloat(k) * (w + gap) + w / 2
    }

    private func barHeight(_ minutes: Int) -> CGFloat {
        max(2, CGFloat(minutes) / top * chartHeight)
    }

    /// A pin: its marker, its bar, its lane (0 = right above the bars) and where its label sits.
    private struct Pin {
        let marker: ChatTimeline.Marker
        let index: Int
        let x: CGFloat
        let lane: Int
        /// The label's planned edges (its real width may differ a little: it stays centered on them).
        let left: CGFloat
        let right: CGFloat
        let text: String
    }

    private func labelText(_ label: String) -> String {
        label.count > Self.maxLabel ? String(label.prefix(Self.maxLabel - 1)).trimmingCharacters(in: .whitespaces) + "…" : label
    }

    /// The pins, oldest first, each in the lowest lane where its label doesn't touch another label and its
    /// stem doesn't cross one (a pin on the same night may share the stem). A label sits centered over its
    /// stem, or reaches right or left from it; in the bottom lane, only where it leaves the stems of the pins
    /// still to come clear.
    private func pins(width: CGFloat) -> [Pin] {
        let all = card.markers.compactMap { m in card.index(of: m.night).map { (marker: m, index: $0, x: center(of: $0, width: width)) } }
        var placed: [Pin] = []
        for (n, item) in all.enumerated() {
            let text = labelText(item.marker.label)
            // Space Grotesk 10 bold ≈ 5.9 pt a letter, the sticker's padding, the icon.
            let w = min(width, CGFloat(text.count) * 5.9 + 14 + (item.marker.emoji == nil ? 0 : 16))
            let x = item.x
            let lefts = [x - w / 2, x - 10, x + 10 - w].map { min(max($0, 0), max(0, width - w)) }
            let later = all.dropFirst(n + 1).filter { $0.marker.night != item.marker.night }.map(\.x)
            func fits(_ left: CGFloat, lane: Int, strict: Bool) -> Bool {
                let right = left + w
                let free = placed.filter { $0.lane == lane }.allSatisfy { $0.right + 4 <= left || $0.left >= right + 4 }
                let overStems = placed.filter { $0.lane > lane }.allSatisfy {
                    $0.marker.night == item.marker.night || $0.x + 3 < left || $0.x - 3 > right
                }
                let stemClear = placed.filter { $0.lane < lane }.allSatisfy {
                    $0.marker.night == item.marker.night || $0.right + 3 < x || $0.left - 3 > x
                }
                // In the bottom lane a label must leave later stems clear (nothing can go under it); higher
                // up, a later pin can still take a lane below.
                let leavesRoom = !strict || lane > 0 || later.allSatisfy { $0 + 3 < left || $0 - 3 > right }
                return free && overStems && stemClear && leavesRoom
            }
            var spot: (lane: Int, left: CGFloat)?
            search: for strict in [true, false] {
                for lane in 0..<ChatTimeline.maxMarkers {
                    if let left = lefts.first(where: { fits($0, lane: lane, strict: strict) }) {
                        spot = (lane, left)
                        break search
                    }
                }
            }
            let chosen = spot ?? ((placed.map(\.lane).max() ?? -1) + 1, lefts[0])
            placed.append(Pin(marker: item.marker, index: item.index, x: x, lane: chosen.lane, left: chosen.left,
                              right: chosen.left + w, text: text))
        }
        return placed
    }

    /// Room above the bars for the lanes of pins (at least one lane).
    private var pinSpace: CGFloat {
        let lanes = (pins(width: width).map(\.lane).max() ?? -1) + 1
        return CGFloat(max(lanes, 1)) * laneHeight + 10
    }

    private func laneY(_ lane: Int) -> CGFloat { pinSpace - 10 - CGFloat(lane + 1) * laneHeight }

    @ViewBuilder
    private func chart(width: CGFloat, pins: [Pin]) -> some View {
        let w = barWidth(width)
        ZStack(alignment: .topLeading) {
            // Bars on a hairline baseline.
            HStack(alignment: .bottom, spacing: gap) {
                ForEach(Array(card.minutes.enumerated()), id: \.offset) { i, minutes in
                    let hot = card.hot.indices.contains(i) && card.hot[i]
                    let marked = pins.contains { $0.index == i }
                    let shape = UnevenRoundedRectangle(topLeadingRadius: min(1.5, w / 2), bottomLeadingRadius: 0,
                                                       bottomTrailingRadius: 0, topTrailingRadius: min(1.5, w / 2), style: .continuous)
                    shape
                        .fill(hot ? Twin.Palette.orange : Twin.Palette.ink.opacity(marked ? 0.4 : 0.15))
                        .overlay { if hot && w >= 3 { shape.strokeBorder(Twin.Palette.ink, lineWidth: w >= 5 ? 1 : 0.5) } }
                        .frame(width: w, height: grown ? barHeight(minutes) : 0)
                        .animation(reduceMotion ? .easeOut(duration: 0.3)
                                   : .spring(response: 0.6, dampingFraction: 0.7).delay(0.12 + Double(i) * min(0.035, 0.7 / Double(card.nightCount))),
                                   value: grown)
                }
            }
            .frame(width: width, height: chartHeight, alignment: .bottomLeading)
            .offset(y: pinSpace)
            Rectangle()
                .fill(Twin.Palette.hairline)
                .frame(width: width, height: 1)
                .offset(y: pinSpace + chartHeight - 1)

            // Dotted stems from each pin down to the top of its night's bar (behind the labels).
            ForEach(Array(pins.enumerated()), id: \.offset) { k, pin in
                let barTop = pinSpace + chartHeight - barHeight(card.minutes[pin.index])
                let from = laneY(pin.lane) + 18
                Path { p in
                    p.move(to: CGPoint(x: pin.x, y: from))
                    p.addLine(to: CGPoint(x: pin.x, y: max(from, barTop - 3)))
                }
                .trim(from: 0, to: pinned ? 1 : 0)
                .stroke(Twin.Palette.ink.opacity(0.55), style: StrokeStyle(lineWidth: 1.2, dash: [1.5, 2.5]))
                .animation(reduceMotion ? .easeOut(duration: 0.3) : Twin.Motion.bouncy.delay(0.75 + Double(k) * 0.12), value: pinned)
            }
            ForEach(Array(pins.enumerated()), id: \.offset) { k, pin in
                CornerSticker(text: pin.text, icon: pin.marker.emoji, fill: Twin.Palette.pink)
                    .fixedSize()
                    .alignmentGuide(.leading) { d in -min(max(pin.left + (pin.right - pin.left - d.width) / 2, 0), max(0, width - d.width)) }
                    .offset(y: laneY(pin.lane))
                    .scaleEffect(pinned || reduceMotion ? 1 : 0.6, anchor: .bottom)
                    .opacity(pinned ? 1 : 0)
                    .animation(reduceMotion ? .easeOut(duration: 0.3) : Twin.Motion.bouncy.delay(0.75 + Double(k) * 0.12), value: pinned)
            }
        }
        .frame(width: width, height: pinSpace + chartHeight, alignment: .topLeading)
    }

    @ViewBuilder
    private func axis(width: CGFloat) -> some View {
        let font = Twin.Typeface.mono(10)
        // Space Mono: 0.6 em a letter.
        let startEnd = CGFloat(card.startLabel.count) * 6 + 8, lastStart = width - 60 - 8
        let dates: [(x: CGFloat, text: String)] = {
            var out: [(x: CGFloat, text: String)] = []
            var right = startEnd
            for marker in card.markers {
                guard let k = card.index(of: marker.night), !out.contains(where: { $0.text == marker.dateLabel }) else { continue }
                let x = center(of: k, width: width), half = CGFloat(marker.dateLabel.count) * 6 / 2
                // Under its bar, when it doesn't run into the labels at the ends or the date before it.
                guard x - half > right, x + half < lastStart else { continue }
                out.append((x, marker.dateLabel))
                right = x + half + 8
            }
            return out
        }()
        ZStack(alignment: .topLeading) {
            Text(card.startLabel).font(font).foregroundStyle(Twin.Palette.inkHint)
            Text("last night").font(font).foregroundStyle(Twin.Palette.inkHint)
                .frame(width: width, alignment: .trailing)
            ForEach(Array(dates.enumerated()), id: \.offset) { _, date in
                Text(date.text).font(Twin.Typeface.mono(10, bold: true)).foregroundStyle(Twin.Palette.ink)
                    .fixedSize()
                    .alignmentGuide(.leading) { d in -(date.x - d.width / 2) }
            }
        }
        .frame(width: width, alignment: .topLeading)
    }

    private var accessibilityText: String {
        var parts = ["Your nights, last \(card.nightCount). Last night \(card.minutes.last ?? 0) minutes."]
        for marker in card.markers { parts.append("Marked \(marker.dateLabel): \(marker.label).") }
        if let note = card.note { parts.append(note) }
        return parts.joined(separator: " ")
    }
}

// MARK: - Product

/// `show_product`: a plain pump bottle, the order and its ingredients (or material), the ones Claude flagged lit.
struct ProductCardView: View {
    let card: ChatProduct
    let fresh: Bool
    @State private var lit: Bool
    @State private var shown: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(card: ChatProduct, fresh: Bool) {
        self.card = card
        self.fresh = fresh
        _lit = State(initialValue: !fresh)
        _shown = State(initialValue: !fresh)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                PumpBottle()
                    .scaleEffect(shown || reduceMotion ? 1 : 0.7, anchor: .bottom)
                    .rotationEffect(.degrees(shown || reduceMotion ? 0 : -8), anchor: .bottom)
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .center, spacing: 8) {
                        Eyebrow(text: "From your orders")
                        Spacer(minLength: 4)
                        if card.firstTime { CornerSticker(text: "FIRST TIME", fill: Twin.Palette.yellow) }
                    }
                    Text(card.title)
                        .font(Twin.Typeface.sans(19, .bold))
                        .foregroundStyle(Twin.Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 5)
                    if let ordered = card.ordered {
                        Text(card.firstTime ? "\(ordered) · first time you bought it" : ordered)
                            .font(Twin.Typeface.sans(13))
                            .foregroundStyle(Twin.Palette.inkMuted)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 2)
                    }
                }
            }
            if !card.ingredients.isEmpty {
                ChatFlow(spacing: 5, lineSpacing: 5) {
                    ForEach(Array(card.ingredients.enumerated()), id: \.offset) { index, ingredient in
                        IngredientChip(name: ingredient.name, flagged: ingredient.flagged && lit)
                            .animation(reduceMotion ? .easeOut(duration: 0.2)
                                       : Twin.Motion.bouncy.delay(0.55 + Double(flagIndex(index)) * 0.22), value: lit)
                    }
                }
                .padding(.top, 10)
            }
            if let material = card.material {
                (Text("Material: ").font(Twin.Typeface.sans(13, .bold)) + Text(material).font(Twin.Typeface.sans(13)))
                    .foregroundStyle(Twin.Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
            }
            if card.hasFlags {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Twin.Palette.orange)
                        .overlay(RoundedRectangle(cornerRadius: 2, style: .continuous).strokeBorder(Twin.Palette.ink, lineWidth: Twin.Stroke.ink))
                        .frame(width: 10, height: 10)
                    Text("flagged by Claude")
                        .font(Twin.Typeface.sans(12))
                        .foregroundStyle(Twin.Palette.inkMuted)
                }
                .padding(.top, 9)
            }
            if let note = card.note {
                Text(note)
                    .font(Twin.Typeface.sans(13))
                    .foregroundStyle(Twin.Palette.inkMuted)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
            }
        }
        .inkCard(Twin.Palette.yellowSoft)
        .onAppear {
            guard !lit else { return }
            withAnimation(reduceMotion ? .easeOut(duration: 0.3) : Twin.Motion.bouncy.delay(0.12)) { shown = true }
            DispatchQueue.main.async { lit = true }
        }
        .accessibilityElement(children: .combine)
    }

    /// The order among the flagged ingredients (they light up one after another).
    private func flagIndex(_ index: Int) -> Int {
        card.ingredients.prefix(index).filter(\.flagged).count
    }
}

private struct IngredientChip: View {
    let name: String
    let flagged: Bool
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Twin.Radius.chip, style: .continuous)
        Text(name)
            .font(Twin.Typeface.sans(11, flagged ? .bold : .regular))
            .foregroundStyle(flagged ? Twin.Palette.ink : Twin.Palette.inkMuted)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(flagged ? Twin.Palette.orange : Color.clear, in: shape)
            .overlay(shape.strokeBorder(flagged ? Twin.Palette.ink : Twin.Palette.hairline,
                                        lineWidth: flagged ? Twin.Stroke.ink : Twin.Stroke.hairline))
            .scaleEffect(flagged ? 1 : 0.98)
    }
}

/// A plain pump bottle drawn with shapes: pink body, white label, no brand (prototype `.bottle`).
struct PumpBottle: View {
    var body: some View {
        let ink = Twin.Palette.ink, edge = Twin.Stroke.ink
        let shell = UnevenRoundedRectangle(topLeadingRadius: 8, bottomLeadingRadius: 6, bottomTrailingRadius: 6,
                                           topTrailingRadius: 8, style: .continuous)
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(ink)
                .frame(width: 26, height: 7)
                .offset(x: 14, y: 5)
            Rectangle()
                .fill(Twin.Palette.paper)
                .overlay(Rectangle().strokeBorder(ink, lineWidth: edge))
                .frame(width: 12, height: 12)
                .offset(x: 22, y: 10)
            shell
                .fill(Twin.Palette.pink)
                .overlay(shell.strokeBorder(ink, lineWidth: edge))
                .frame(width: 40, height: 56)
                .offset(x: 8, y: 20)
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Twin.Palette.paper)
                .overlay(RoundedRectangle(cornerRadius: 2, style: .continuous).strokeBorder(ink, lineWidth: edge))
                .frame(width: 30, height: 26)
                .offset(x: 13, y: 38)
        }
        .frame(width: 56, height: 76, alignment: .topLeading)
        .accessibilityHidden(true)
    }
}

// MARK: - Question

/// `ask_user`: Claude's question with its answers. The chosen one turns yellow, the others dim.
struct QuestionCardView: View {
    let card: ChatQuestion
    let answer: String?
    /// Waiting for Douglas.
    let open: Bool
    let pressed: String?
    let choose: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(card.question)
                .font(Twin.Typeface.sans(15, .bold))
                .foregroundStyle(Twin.Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            if !card.options.isEmpty {
                ChatFlow(spacing: 6, lineSpacing: 6) {
                    ForEach(Array(card.options.enumerated()), id: \.offset) { _, option in
                        let picked = answer == option
                        ChatChip(text: option, fill: picked ? Twin.Palette.yellow : Twin.Palette.paper,
                                 dimmed: answer != nil && !picked, pressedByScript: pressed == option) { choose(option) }
                            .disabled(!open)
                            .accessibilityAddTraits(picked ? .isSelected : [])
                    }
                }
            }
        }
        .inkCard(Twin.Palette.cream, padding: 12)
    }
}

// MARK: - Conclusion

/// `show_conclusion`: the most likely cause, how sure, what was ruled out and the 5-night test.
struct ConclusionCardView: View {
    let card: ChatConclusion
    let fresh: Bool
    @State private var revealed: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(card: ChatConclusion, fresh: Bool) {
        self.card = card
        self.fresh = fresh
        _revealed = State(initialValue: !fresh)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 8) {
                Eyebrow(text: "Most likely cause")
                Spacer(minLength: 8)
                Sticker(text: card.confidence, fill: Twin.Palette.yellow)
            }
            Text(card.cause)
                .font(Twin.Typeface.sans(card.cause.count > 40 ? 21 : 26, .bold))
                .tracking(-0.5)
                .foregroundStyle(Twin.Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous).fill(Twin.Palette.fill)
                    RoundedRectangle(cornerRadius: 2, style: .continuous).fill(Twin.Palette.cyan)
                        .frame(width: geo.size.width * (revealed ? card.confidenceFill : 0))
                }
            }
            .frame(height: 6)
            .padding(.top, 10)
            .animation(reduceMotion ? .easeOut(duration: 0.3) : Twin.Motion.fill.delay(0.3), value: revealed)
            .accessibilityHidden(true)

            if !card.ruledOut.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(card.ruledOut.enumerated()), id: \.offset) { index, ruled in
                        ruledLine(ruled)
                            .opacity(revealed ? 1 : 0)
                            .offset(y: revealed || reduceMotion ? 0 : 6)
                            .animation(Twin.Motion.spring.delay(0.45 + Double(index) * 0.18), value: revealed)
                    }
                }
                .padding(.top, 12)
            }
            if let next = card.nextStep {
                (Text("Try this: ").font(Twin.Typeface.sans(14, .bold)) + Text(next).font(Twin.Typeface.sans(14)))
                    .foregroundStyle(Twin.Palette.ink)
                    .lineSpacing(2.5)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Twin.Palette.limeSoft, in: RoundedRectangle(cornerRadius: Twin.Radius.control, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Twin.Radius.control, style: .continuous)
                        .strokeBorder(Twin.Palette.ink, lineWidth: Twin.Stroke.ink))
                    .padding(.top, 12)
                    .opacity(revealed ? 1 : 0)
                    .scaleEffect(revealed || reduceMotion ? 1 : 0.96, anchor: .top)
                    .animation(Twin.Motion.bouncy.delay(0.5 + Double(card.ruledOut.count) * 0.18), value: revealed)
            }
            Text("Not a diagnosis.")
                .font(Twin.Typeface.sans(11))
                .foregroundStyle(Twin.Palette.inkHint)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
        }
        .inkCard(Twin.Palette.paper)
        .onAppear {
            guard !revealed else { return }
            DispatchQueue.main.async { revealed = true }
        }
        .accessibilityElement(children: .combine)
    }

    private func ruledLine(_ ruled: ChatConclusion.RuledOut) -> some View {
        var line = Text(ruled.item)
            .font(Twin.Typeface.sans(13, .bold))
            .foregroundStyle(Twin.Palette.ink)
            .strikethrough(true, color: Twin.Palette.ink)
        if let reason = ruled.reason {
            line = line + Text(" — \(reason)").font(Twin.Typeface.sans(13)).foregroundStyle(Twin.Palette.inkMuted)
        }
        return line
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
