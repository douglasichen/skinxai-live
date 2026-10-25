import SwiftUI
import EczemaKit

// MARK: - Status: is my eczema normal?

/// One line that answers "Is my eczema normal?", then last night against your usual.
/// Flare: red-soft card with an ink edge and a red "!" tile. Normal: lime-soft with a lime check.
struct SummaryStatusCard: View {
    let story: SummaryStory

    private var flare: Bool { story.status == .flare }
    private var fill: Color { flare ? Twin.Palette.redSoft : Twin.Palette.limeSoft }
    private var accent: Color { flare ? Twin.Palette.red : Twin.Palette.lime }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: flare ? "exclamationmark" : "checkmark")
                    .font(.system(size: 17, weight: .heavy))
                    .foregroundStyle(Twin.Palette.ink)
                    .frame(width: 36, height: 36)
                    .sticker(accent)
                    .modifier(TodayPopIn(delay: 0.15))
                VStack(alignment: .leading, spacing: 1) {
                    Text(story.title)
                        .font(Twin.Typeface.sans(26, .bold))
                        .tracking(-0.6)
                        .foregroundStyle(Twin.Palette.ink)
                    Text(story.detail)
                        .font(Twin.Typeface.sans(16, .medium))
                        .foregroundStyle(Twin.Palette.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .offset(y: -3)
            }

            HStack(alignment: .bottom, spacing: 0) {
                number(Double(story.minutes), label: "LAST NIGHT", big: true)
                Rectangle().fill(Twin.Palette.hairline).frame(width: 1, height: 44)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 4)
                number(Double(story.usual), label: "YOUR USUAL", big: false)
                Spacer(minLength: 8)
                ratioSticker.padding(.bottom, 6)
            }
        }
        .padding(Twin.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(fill, in: RoundedRectangle(cornerRadius: Twin.Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Twin.Radius.card, style: .continuous)
            .strokeBorder(Twin.Palette.ink, lineWidth: Twin.Stroke.ink))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(story.headline). Last night \(story.minutes) minutes of scratching, your usual \(story.usual) minutes"
                            + (flare ? ", \(story.ratioText) your usual." : "."))
    }

    private func number(_ value: Double, label: String, big: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                CountUp(value: value, font: Twin.Typeface.sans(big ? 54 : 34, .bold),
                        color: big ? Twin.Palette.ink : Twin.Palette.inkMuted, delay: 0.15, duration: 1.1)
                    .tracking(big ? -2 : -1)
                Text("min")
                    .font(Twin.Typeface.sans(big ? 17 : 15, .medium))
                    .foregroundStyle(Twin.Palette.inkHint)
            }
            Text(label)
                .font(Twin.Typeface.mono(11))
                .tracking(0.4)
                .foregroundStyle(Twin.Palette.inkHint)
                .offset(y: -2)
        }
    }

    /// "▲ 3.4×" (red) or "✓ as usual" (lime): stamps in once the numbers have counted up.
    private var ratioSticker: some View {
        HStack(spacing: 5) {
            if flare {
                Image(systemName: "arrowtriangle.up.fill").font(.system(size: 11, weight: .bold))
                Text(story.ratioText).font(Twin.Typeface.sans(20, .bold)).monospacedDigit()
            } else {
                Image(systemName: "checkmark").font(.system(size: 11, weight: .heavy))
                Text("as usual").font(Twin.Typeface.sans(15, .bold))
            }
        }
        .foregroundStyle(Twin.Palette.ink)
        .lineLimit(1)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .sticker(accent)
        .modifier(TodayStamp(delay: 0.95))
    }
}

// MARK: - Getting worse? (last 7 nights)

/// The last 7 nights against the dashed "usual" line; the last three sit on a tinted band. Flare
/// nights there are red with an ink edge. One line above says where it's heading.
struct SummaryWeekCard: View {
    let story: SummaryStory

    private let plotHeight: CGFloat = 92

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var grown = false

    private var flare: Bool { story.status == .flare }
    private var top: Double {
        let maxV = story.week.map { StageStory.nights[$0] }.max() ?? 1
        return Double(max(maxV, story.usual * 2)) * 1.12
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Eyebrow(text: "Getting worse?")
                Spacer(minLength: 8)
                Text("LAST 7 NIGHTS")
                    .font(Twin.Typeface.meta).tracking(0.4).foregroundStyle(Twin.Palette.inkHint)
            }
            (Text(story.trend.lead + " ").font(Twin.Typeface.sans(16, .bold)).foregroundColor(Twin.Palette.ink)
                + Text(story.trend.values).font(Twin.Typeface.sans(16)).foregroundColor(Twin.Palette.inkMuted))
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)

            chart.padding(.top, 14)
            legend.padding(.top, 12)
        }
        .twinCard()
        .onAppear {
            if reduceMotion { withAnimation(.easeOut(duration: 0.35).delay(0.3)) { grown = true } } else { grown = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var chart: some View {
        let nights = Array(story.week)
        return VStack(spacing: 6) {
            GeometryReader { g in
                let slot = g.size.width / CGFloat(nights.count)
                ZStack(alignment: .topLeading) {
                    // The last three nights: a soft band behind their columns.
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(flare ? Twin.Palette.redSoft : Twin.Palette.limeSoft)
                        .frame(width: slot * 3 - 2, height: g.size.height)
                        .offset(x: slot * CGFloat(nights.count - 3) + 1)
                        .opacity(grown ? 1 : 0)
                        .animation(.easeOut(duration: 0.4).delay(0.55), value: grown)

                    HStack(alignment: .bottom, spacing: 0) {
                        ForEach(Array(nights.enumerated()), id: \.element) { k, i in
                            column(i, k: k, slot: slot, recent: k >= nights.count - 3)
                        }
                    }
                    .frame(height: g.size.height, alignment: .bottom)

                    usualLine(width: g.size.width, height: g.size.height)
                }
            }
            .frame(height: plotHeight + 22)
            Rectangle().fill(Twin.Palette.hairline).frame(height: Twin.Stroke.hairline).padding(.top, -6)
            HStack(spacing: 0) {
                ForEach(nights, id: \.self) { i in
                    let isLast = i == story.last
                    Text(isLast ? "LAST" : story.weekday(i))
                        .font(Twin.Typeface.mono(10, bold: isLast))
                        .foregroundStyle(isLast ? Twin.Palette.ink : Twin.Palette.inkHint)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    /// "- - - YOUR USUAL · 12 MIN   ■ ABOVE 1.5×"
    private var legend: some View {
        HStack(spacing: 14) {
            HStack(spacing: 6) {
                ChartHLine()
                    .stroke(Twin.Palette.seam, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    .frame(width: 18, height: 2)
                Text("YOUR USUAL · \(story.usual) MIN")
            }
            if flare {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(Twin.Palette.red)
                        .overlay(RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                            .strokeBorder(Twin.Palette.ink, lineWidth: 1))
                        .frame(width: 10, height: 10)
                    Text("FLARE NIGHT")
                }
            }
        }
        .font(Twin.Typeface.mono(10))
        .tracking(0.3)
        .foregroundStyle(Twin.Palette.inkHint)
        .accessibilityHidden(true)
    }

    private func column(_ i: Int, k: Int, slot: CGFloat, recent: Bool) -> some View {
        let v = StageStory.nights[i]
        let hot = recent && StageStory.isFlare(i)
        let h = max(3, CGFloat(Double(v) / top) * plotHeight)
        let shape = UnevenRoundedRectangle(topLeadingRadius: 2, topTrailingRadius: 2, style: .continuous)
        let barFill: Color = hot ? Twin.Palette.red : (recent && !flare ? Twin.Palette.lime : Twin.Palette.ink.opacity(0.15))
        let edged = hot || (recent && !flare)
        let delay = 0.3 + Double(k) * 0.05
        return VStack(spacing: 3) {
            Text("\(v)")
                .font(Twin.Typeface.mono(12, bold: true))
                .foregroundStyle(Twin.Palette.ink)
                .opacity(grown && recent ? 1 : 0)
                .animation(.easeOut(duration: 0.3).delay(delay + 0.25), value: grown)
            shape.fill(barFill)
                .overlay { if edged { shape.strokeBorder(Twin.Palette.ink, lineWidth: 1) } }
                .frame(width: min(26, slot * 0.56), height: h)
                .scaleEffect(x: 1, y: (grown || reduceMotion) ? 1 : 0.001, anchor: .bottom)
                .opacity(grown ? 1 : 0)
                .animation(reduceMotion ? nil : Twin.Motion.bouncy.delay(delay), value: grown)
        }
        .frame(width: slot)
    }

    /// Dashed "usual" line with its label at the left end.
    private func usualLine(width: CGFloat, height: CGFloat) -> some View {
        let y = height - CGFloat(Double(story.usual) / top) * plotHeight
        return ZStack(alignment: .topLeading) {
            ChartHLine()
                .trim(from: 0, to: grown ? 1 : 0)
                .stroke(Twin.Palette.seam, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                .frame(width: width, height: 2)
                .offset(y: y - 1)
                .animation(.easeOut(duration: 0.6).delay(0.7), value: grown)
        }
        .allowsHitTesting(false)
    }

    private var accessibilityText: String {
        let values = story.week.map { "\(StageStory.nights[$0])" }.joined(separator: ", ")
        return "Getting worse? \(story.trend.lead) \(story.trend.values). Last 7 nights: \(values) minutes. Your usual: \(story.usual)."
    }
}

// MARK: - Possible triggers

/// What changed right before the rise, as plain rows (no elimination here), and the way to Insight.
struct SummaryTriggersCard: View {
    let story: SummaryStory
    let onAsk: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Eyebrow(text: "Possible triggers")
                Spacer(minLength: 8)
                Text("WHAT CHANGED")
                    .font(Twin.Typeface.meta).tracking(0.4).foregroundStyle(Twin.Palette.inkHint)
            }
            VStack(spacing: 0) {
                ForEach(Array(story.triggers.enumerated()), id: \.element.id) { k, t in
                    if k > 0 { Rectangle().fill(Twin.Palette.hairline).frame(height: 1) }
                    row(t)
                        .riseIn(0.45 + Double(k) * Twin.Motion.stagger, distance: 8)
                }
            }
            .padding(.top, 6)

            Button(action: onAsk) {
                HStack(spacing: 8) {
                    Text("✶").font(.system(size: 15, weight: .bold))
                    Text("Narrow it down with Claude")
                    Spacer(minLength: 4)
                    Image(systemName: "arrow.right").font(.system(size: 15, weight: .semibold))
                }
            }
            .buttonStyle(TwinButtonStyle(fill: Twin.Palette.pink, height: 48))
            .accessibilityHint("Opens Insight")
            .padding(.top, 10)
        }
        .twinCard()
    }

    private func row(_ t: SummaryStory.Trigger) -> some View {
        HStack(alignment: .center, spacing: 12) {
            TwinIconView(emoji: t.emoji, size: 22)
                .frame(width: 38, height: 38)
                .sticker(t.earlier ? Twin.Palette.fill : t.fill)
            VStack(alignment: .leading, spacing: 1) {
                Text(t.title).font(Twin.Typeface.sans(16, .bold)).foregroundStyle(Twin.Palette.ink)
                Text(t.detail).font(Twin.Typeface.subhead).foregroundStyle(Twin.Palette.inkMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(t.when)
                .font(Twin.Typeface.mono(10, bold: !t.earlier))
                .tracking(0.3)
                .foregroundStyle(t.earlier ? Twin.Palette.inkHint : Twin.Palette.ink)
                .lineLimit(1)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(t.earlier ? Color.clear : Twin.Palette.yellowSoft,
                            in: RoundedRectangle(cornerRadius: Twin.Radius.sticker, style: .continuous))
        }
        .padding(.vertical, 10)
        .opacity(t.earlier ? 0.5 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(t.title), \(t.detail), \(t.when.lowercased())")
    }
}

// MARK: - Factors

/// Six tiles: icon, one word, the value, a status sticker. What's off your usual is orange and comes
/// first; what's fine is white with a lime (good) or plain (normal) sticker.
struct SummaryFactorsCard: View {
    let story: SummaryStory

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    var body: some View {
        let factors = story.factors
        let off = factors.filter { $0.level == .bad }.count
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Eyebrow(text: "Factors · last night / yesterday")
                Spacer(minLength: 8)
                Text(off == 0 ? "ALL NORMAL" : "\(off) OFF USUAL")
                    .font(Twin.Typeface.mono(11, bold: off > 0))
                    .tracking(0.4)
                    .foregroundStyle(off > 0 ? Twin.Palette.ink : Twin.Palette.inkHint)
            }
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(Array(factors.enumerated()), id: \.element.id) { k, f in
                    tile(f).modifier(TodayPopIn(delay: 0.5 + Double(k) * 0.06))
                }
            }
        }
        .twinCard()
    }

    private func tile(_ f: SummaryStory.Factor) -> some View {
        let bad = f.level == .bad
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 0) {
                Image(systemName: f.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Twin.Palette.ink)
                    .frame(width: 28, height: 28)
                    .sticker(bad ? Twin.Palette.orange : Twin.Palette.paper)
                Spacer(minLength: 4)
                Text(f.status)
                    .font(Twin.Typeface.sans(11, .bold))
                    .foregroundStyle(Twin.Palette.ink)
                    .lineLimit(1)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .sticker(bad ? Twin.Palette.orange : (f.level == .good ? Twin.Palette.lime : Twin.Palette.paper))
            }
            Text(f.word)
                .font(Twin.Typeface.sans(13, .medium))
                .foregroundStyle(Twin.Palette.inkMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .padding(.top, 2)
            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(f.value)
                    .font(Twin.Typeface.sans(24, .bold))
                    .tracking(-0.8)
                    .foregroundStyle(Twin.Palette.ink)
                if !f.unit.isEmpty {
                    Text(f.unit)
                        .font(Twin.Typeface.sans(12, .medium))
                        .foregroundStyle(Twin.Palette.inkHint)
                        .lineLimit(1)
                }
            }
            .minimumScaleFactor(0.8)
            .lineLimit(1)
            .offset(y: -4)
        }
        .padding(10)
        .padding(.bottom, -4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(bad ? Twin.Palette.orangeSoft : Twin.Palette.cream,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .strokeBorder(bad ? Twin.Palette.ink : Twin.Palette.hairline, lineWidth: bad ? Twin.Stroke.ink : Twin.Stroke.hairline))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(f.accessibility)
    }
}

// MARK: - Small motion pieces

/// Pops a view in (scale + fade) after `delay`; fade only with Reduce Motion.
struct TodayPopIn: ViewModifier {
    var delay: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(shown || reduceMotion ? 1 : 0.6)
            .opacity(shown ? 1 : 0)
            .onAppear {
                withAnimation(reduceMotion ? .easeOut(duration: 0.3).delay(delay) : Twin.Motion.bouncy.delay(delay)) { shown = true }
            }
    }
}

/// Stamps a sticker in with a little turn after `delay`; fade only with Reduce Motion.
struct TodayStamp: ViewModifier {
    var delay: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var stamped = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(stamped || reduceMotion ? 1 : 0.55)
            .rotationEffect(.degrees(stamped || reduceMotion ? 0 : -9))
            .opacity(stamped ? 1 : 0)
            .onAppear {
                withAnimation(reduceMotion ? .easeOut(duration: 0.3).delay(delay) : Twin.Motion.bouncy.delay(delay)) { stamped = true }
            }
    }
}
