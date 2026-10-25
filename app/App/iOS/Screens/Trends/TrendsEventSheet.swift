import SwiftUI
import EczemaKit

/// What the event sheet says about one event, only what the app can read, without any judgement: a new
/// product's order (date, item, new or a repeat, its note), its ingredient list or material as printed, and
/// how scratching went in the 4 nights after the order date against his usual. Exams, the trip and late
/// workouts (calendar, Apple Health): the nights with them against the nights without, over all 74.
struct TrendsEventDetail {
    struct Fact: Identifiable {
        var id: String { label }
        let label: String
        let value: String
    }

    let event: TrendsEvent
    let title: String
    /// "PERSONAL CARE · AMAZON ORDER"
    let category: String
    /// A purchase: new (true) or a repeat (false); nil for the rest.
    let firstTime: Bool?
    let facts: [Fact]
    /// "Ingredients", "Material"
    let listTitle: String
    /// The label's list, in order (or the material).
    let ingredients: [String]
    /// Nights with the event against the nights without (not a purchase).
    let comparison: StageHistory.Comparison
    /// A purchase: the nights after its order date against his usual (instead of `comparison`).
    let purchase: TrendsPurchase?
    /// "4 NIGHTS · OCT 6–9"
    let afterText: String
    /// "Also bought that day: FreshMeadow Spring Bloom Detergent."
    let note: String?

    init(_ e: TrendsEvent, now: Date = Date()) {
        let cal = TrendsStory.calendar
        let day = { (i: Int) in TrendsStory.dayText(night: i, now: now) }
        let span: String = {
            let a = StageStory.nightDate(e.start, now: now, calendar: cal)
            let b = StageStory.nightDate(e.end, now: now, calendar: cal)
            if e.end == StageStory.lastNightIndex { return "\(StageStory.monthDay(a, calendar: cal))–now" }
            return e.start == e.end ? StageStory.monthDay(a, calendar: cal) : StageStory.monthDayRange(a, b, calendar: cal)
        }()
        let nights = e.end - e.start + 1
        let p = TrendsPurchase(e)
        event = e
        purchase = p
        afterText = p.map { p in
            let a = StageStory.nightDate(p.nights.lowerBound, now: now, calendar: cal)
            let b = StageStory.nightDate(p.nights.upperBound, now: now, calendar: cal)
            let dates = p.nights.count == 1 ? StageStory.monthDay(a, calendar: cal) : StageStory.monthDayRange(a, b, calendar: cal)
            return "\(p.nights.count) NIGHT\(p.nights.count == 1 ? "" : "S") · \(dates.uppercased())"
        } ?? ""
        note = p.flatMap { p in
            p.sameDay.isEmpty ? nil : "Also bought that day: \(p.sameDay.map(\.name).joined(separator: ", "))."
        }
        switch e.kind {
        case .purchase:
            let o = StageStory.orders(now: now, calendar: cal).first { $0.item == e.item && $0.night == e.start }
            title = e.name
            category = "\(o?.category ?? "order") · Amazon order"
            firstTime = o.map { !$0.boughtBefore }
            var facts: [Fact] = [.init(label: "Bought", value: day(e.start)),
                                 .init(label: "Item", value: o?.item ?? e.item ?? e.name)]
            if let n = o?.note { facts.append(.init(label: "Note", value: n.prefix(1).uppercased() + n.dropFirst())) }
            self.facts = facts
            if let material = o?.material {
                listTitle = "Material"
                ingredients = [material]
            } else {
                listTitle = "Ingredients"
                ingredients = o?.ingredients ?? []
            }
            comparison = StageHistory.compare { _ in false }
        case .exams:
            let midterms = StageStory.examNights == e.start...e.end
            title = midterms ? "Midterm exams" : "Exam week"
            category = "Calendar"
            firstTime = nil
            facts = [.init(label: "When", value: span),
                     .init(label: "Length", value: "\(nights) days"),
                     .init(label: "Note", value: midterms ? "CS 61B, Math 54 · stressful week" : "CS 61B, Math 54 quizzes")]
            listTitle = ""
            ingredients = []
            comparison = StageHistory.compare(\.exams)
        case .trip:
            title = "Trip to Seattle"
            category = "Calendar"
            firstTime = nil
            facts = [.init(label: "When", value: span),
                     .init(label: "Length", value: "\(nights) days"),
                     .init(label: "Note", value: "Family")]
            listTitle = ""
            ingredients = []
            comparison = StageHistory.compare(\.trip)
        case .gym:
            title = "Late workout"
            category = "Apple Health · workout"
            firstTime = nil
            facts = [.init(label: "When", value: "\(day(e.start)), evening"),
                     .init(label: "All time", value: "\(StageHistory.nights.filter(\.gym).count) late workouts in \(StageHistory.count) nights")]
            listTitle = ""
            ingredients = []
            comparison = StageHistory.compare(\.gym)
        }
    }
}

/// The sheet behind a purchase icon on the chart (or an event, by launch argument).
struct TrendsEventSheet: View {
    let detail: TrendsEventDetail
    let onAsk: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var grown = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Twin.Space.m) {
                header.riseIn(0.05, distance: reduceMotion ? 0 : 12)
                facts.riseIn(0.12, distance: reduceMotion ? 0 : 12)
                if !detail.ingredients.isEmpty {
                    ingredients.riseIn(0.19, distance: reduceMotion ? 0 : 12)
                }
                Group {
                    if let p = detail.purchase { afterPurchase(p) } else { withAndWithout }
                }
                .riseIn(0.26, distance: reduceMotion ? 0 : 12)
                ask.riseIn(0.33, distance: reduceMotion ? 0 : 12)
            }
            .padding(.horizontal, Twin.Space.screen)
            .padding(.top, 24)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .background(Twin.Palette.paper)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(Twin.Radius.dialog)
        .presentationBackground(Twin.Palette.paper)
        .onAppear { grown = true }
    }

    // MARK: Sections

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            TwinIconView(emoji: detail.event.emoji, size: 32)
                .frame(width: 54, height: 54)
                .sticker(detail.event.isProduct ? Twin.Palette.pink : Twin.Palette.cream, radius: Twin.Radius.control)
            VStack(alignment: .leading, spacing: 4) {
                Eyebrow(text: detail.category)
                Text(detail.title)
                    .font(Twin.Typeface.title)
                    .foregroundStyle(Twin.Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let first = detail.firstTime {
                    Group {
                        if first {
                            Sticker(text: "First time", icon: "sparkles", fill: Twin.Palette.yellow)
                        } else {
                            Sticker(text: "Bought before", icon: "arrow.triangle.2.circlepath", fill: Twin.Palette.paper)
                        }
                    }
                    .padding(.top, 2)
                    .modifier(TodayStamp(delay: 0.35))
                }
            }
            Spacer(minLength: 8)
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Twin.Palette.ink)
                    .frame(width: 32, height: 32)
                    .sticker(Twin.Palette.paper, radius: Twin.Radius.control)
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Close")
        }
    }

    private var facts: some View {
        VStack(spacing: 0) {
            ForEach(Array(detail.facts.enumerated()), id: \.element.id) { k, fact in
                if k > 0 { Rectangle().fill(Twin.Palette.hairline).frame(height: 1) }
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(fact.label.uppercased())
                        .font(Twin.Typeface.mono(10, bold: true))
                        .tracking(0.4)
                        .foregroundStyle(Twin.Palette.inkHint)
                        .frame(width: 92, alignment: .leading)
                    Text(fact.value)
                        .font(Twin.Typeface.sans(15, .medium))
                        .foregroundStyle(Twin.Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 10)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.horizontal, Twin.Space.l)
        .padding(.vertical, 4)
        .twinCard(fill: Twin.Palette.cream, padding: 0)
    }

    /// The label's ingredients (or the material) as printed, all alike.
    private var ingredients: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Eyebrow(text: detail.listTitle)
                Spacer()
                if detail.ingredients.count > 1 {
                    Text("\(detail.ingredients.count) LISTED")
                        .font(Twin.Typeface.meta)
                        .foregroundStyle(Twin.Palette.inkHint)
                }
            }
            TrendsFlow(spacing: 5, lineSpacing: 5) {
                ForEach(Array(detail.ingredients.enumerated()), id: \.offset) { _, name in
                    chip(name)
                }
            }
        }
        .twinCard()
        .accessibilityElement(children: .combine)
    }

    private func chip(_ name: String) -> some View {
        let shape = RoundedRectangle(cornerRadius: Twin.Radius.chip, style: .continuous)
        return Text(name)
            .font(Twin.Typeface.sans(13))
            .foregroundStyle(Twin.Palette.ink)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .overlay(shape.strokeBorder(Twin.Palette.hairline, lineWidth: Twin.Stroke.hairline))
    }

    /// Exams, the trip, late workouts: the nights with it against the nights without.
    private var withAndWithout: some View {
        let c = detail.comparison
        let scale = max(30, max(c.withMinutes, c.withoutMinutes).rounded(.up))
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Eyebrow(text: "Scratching")
                Spacer()
                Text("MIN / NIGHT")
                    .font(Twin.Typeface.meta)
                    .foregroundStyle(Twin.Palette.inkHint)
            }
            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(signed(c.roundedDifference))
                    .font(Twin.Typeface.sans(40, .bold))
                    .tracking(-1.5)
                    .monospacedDigit()
                Text("min")
                    .font(Twin.Typeface.sans(15, .medium))
                    .foregroundStyle(Twin.Palette.inkMuted)
            }
            .foregroundStyle(Twin.Palette.ink)
            VStack(spacing: 6) {
                bar("With it", nights: "\(c.withNights) NIGHTS", value: c.withMinutes, scale: scale,
                    fill: Twin.Palette.ink.opacity(0.32), edged: false, delay: 0.4)
                bar("Without", nights: "\(c.withoutNights) NIGHTS", value: c.withoutMinutes, scale: scale,
                    fill: Twin.Palette.ink.opacity(0.15), edged: false, delay: 0.5)
            }
            Text("Average minutes per night, over all \(StageHistory.count) nights.")
                .font(Twin.Typeface.mono(10))
                .foregroundStyle(Twin.Palette.inkHint)
                .fixedSize(horizontal: false, vertical: true)
        }
        .twinCard()
        .accessibilityElement(children: .combine)
    }

    /// A bought item: "4 nights after buying: 25 min vs usual 12" and the two bars.
    private func afterPurchase(_ p: TrendsPurchase) -> some View {
        let scale = max(30, max(p.afterMinutes, Double(p.usual)).rounded(.up))
        let after = Int(p.afterMinutes.rounded())
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Eyebrow(text: "After buying it")
                Spacer()
                Text("MIN / NIGHT")
                    .font(Twin.Typeface.meta)
                    .foregroundStyle(Twin.Palette.inkHint)
            }
            HStack(alignment: .center, spacing: 10) {
                HStack(alignment: .lastTextBaseline, spacing: 3) {
                    Text(signed(p.difference))
                        .font(Twin.Typeface.sans(40, .bold))
                        .tracking(-1.5)
                        .monospacedDigit()
                    Text("min")
                        .font(Twin.Typeface.sans(15, .medium))
                        .foregroundStyle(Twin.Palette.inkMuted)
                }
                .foregroundStyle(Twin.Palette.ink)
                Spacer(minLength: 6)
            }
            (Text("\(p.nights.count) nights after buying: ").font(Twin.Typeface.sans(15, .bold))
                + Text("\(after) min vs usual \(p.usual)").font(Twin.Typeface.sans(15)))
                .foregroundStyle(Twin.Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 6) {
                bar("After", nights: detail.afterText, value: p.afterMinutes, scale: scale,
                    fill: p.overFlareLine ? Twin.Palette.orange : Twin.Palette.ink.opacity(0.32),
                    edged: p.overFlareLine, delay: 0.4, labelWidth: 112)
                bar("Usual", nights: "YOUR NORMAL", value: Double(p.usual), scale: scale,
                    fill: Twin.Palette.ink.opacity(0.15), edged: false, delay: 0.5, labelWidth: 112)
            }
            if let note = detail.note {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "bag")
                        .font(.system(size: 11, weight: .bold))
                        .padding(.top, 2)
                    Text(note)
                        .font(Twin.Typeface.sans(13))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(Twin.Palette.ink)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Twin.Palette.cream, in: RoundedRectangle(cornerRadius: Twin.Radius.chip, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Twin.Radius.chip, style: .continuous)
                    .strokeBorder(Twin.Palette.hairline, lineWidth: Twin.Stroke.hairline))
            }
            Text("Average of the \(p.nights.count) nights after the order date.")
                .font(Twin.Typeface.mono(10))
                .foregroundStyle(Twin.Palette.inkHint)
                .fixedSize(horizontal: false, vertical: true)
        }
        .twinCard()
        .accessibilityElement(children: .combine)
    }

    private func bar(_ label: String, nights: String, value: Double, scale: Double, fill: Color, edged: Bool, delay: Double,
                     labelWidth: CGFloat = 66) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                Text(label)
                    .font(Twin.Typeface.sans(13, .bold))
                    .foregroundStyle(Twin.Palette.ink)
                Text(nights)
                    .font(Twin.Typeface.mono(9))
                    .foregroundStyle(Twin.Palette.inkHint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(width: labelWidth, alignment: .leading)
            GeometryReader { g in
                let shape = UnevenRoundedRectangle(bottomTrailingRadius: 2, topTrailingRadius: 2, style: .continuous)
                HStack(spacing: 6) {
                    shape.fill(fill)
                        .overlay { if edged { shape.strokeBorder(Twin.Palette.ink, lineWidth: 1) } }
                        .frame(width: max(3, CGFloat(value / scale) * (g.size.width - 34)))
                        .scaleEffect(x: grown || reduceMotion ? 1 : 0.001, y: 1, anchor: .leading)
                        .animation(reduceMotion ? nil : Twin.Motion.spring.delay(delay), value: grown)
                    Text("\(Int(value.rounded()))")
                        .font(Twin.Typeface.mono(12, bold: true))
                        .foregroundStyle(Twin.Palette.ink)
                        .fixedSize()
                }
            }
            .frame(height: 16)
        }
    }

    private var ask: some View {
        Button {
            dismiss()
            onAsk()
        } label: {
            HStack(spacing: 8) {
                Text("✶").font(.system(size: 15, weight: .bold))
                Text("Ask Claude about this")
                Spacer(minLength: 4)
                Image(systemName: "arrow.right").font(.system(size: 15, weight: .semibold))
            }
        }
        .buttonStyle(TwinButtonStyle(fill: Twin.Palette.pink))
        .accessibilityHint("Opens Insight")
    }

    private func signed(_ n: Int) -> String { n > 0 ? "+\(n)" : (n < 0 ? "−\(-n)" : "±0") }
}
