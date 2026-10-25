import Foundation

// What the chat draws for Claude's display tools and questions, read from the model's arguments. The model can
// send anything (missing fields, odd types, dates outside the 74 nights), so every field has a safe default.

/// `show_timeline`: the nights with Claude's markers on them. One marker (`marker_date`, `marker_label`) or
/// several (`markers: [{date, label}]`); the chart runs from 3 nights before the earliest marker to last night
/// (at least the story's 14, at most `StageHistory`'s 74).
public struct ChatTimeline: Hashable, Sendable {
    /// One of Claude's markers.
    public struct Marker: Hashable, Sendable {
        /// The marked night (−60 … 13, `StageHistory`'s numbering).
        public var night: Int
        /// Claude's label ("Started Brightwell body wash"; "Change" when it sent none).
        public var label: String
        /// A small picture for the label ("🧴" for a body wash), if one fits.
        public var emoji: String?
        /// "Oct 20": the marked night's date.
        public var dateLabel: String
    }

    /// The first night on the chart (−60 … 0).
    public var firstNight: Int
    /// Minutes of scratching per night, oldest first (`firstNight` … last night).
    public var minutes: [Int]
    /// Nights above 1.5 × usual (the orange bars).
    public var hot: [Bool]
    /// Claude's markers on nights of the chart, oldest first (at most `maxMarkers`).
    public var markers: [Marker]
    /// Claude's sentence about the timing.
    public var note: String?
    /// "Oct 10": the first night.
    public var startLabel: String

    /// The most markers drawn.
    public static let maxMarkers = 6

    /// The first marker's night, if any (the one-marker form).
    public var marker: Int? { markers.first?.night }
    /// The first marker's label ("Change" without markers).
    public var label: String { markers.first?.label ?? "Change" }
    /// The first marker's picture.
    public var emoji: String? { markers.first?.emoji }
    /// "Oct 20": the first marker's date.
    public var markerLabel: String? { markers.first?.dateLabel }
    /// Nights on the chart.
    public var nightCount: Int { minutes.count }
    /// The position of night `night` on the chart (0 = the first bar).
    public func index(of night: Int) -> Int? {
        let k = night - firstNight
        return minutes.indices.contains(k) ? k : nil
    }

    public init(arguments: [String: Any], now: Date = Date(), calendar: Calendar = .current) {
        var wanted: [(date: String, label: Any?)] = []
        for entry in arguments["markers"] as? [Any] ?? [] {
            guard let object = entry as? [String: Any] else { continue }
            wanted.append(((object["date"] as? String) ?? (object["marker_date"] as? String) ?? "",
                           object["label"] ?? object["marker_label"]))
        }
        if let date = arguments["marker_date"] as? String {
            wanted.insert((date, arguments["marker_label"]), at: 0)
        }
        var found: [Marker] = []
        for (date, label) in wanted {
            let day = String(date.trimmingCharacters(in: .whitespacesAndNewlines).prefix(10))
            guard let night = StageHistory.night(iso: day, now: now, calendar: calendar) else { continue }
            let text = Self.text(label) ?? "Change"
            guard !found.contains(where: { $0.night == night && $0.label == text }) else { continue }
            found.append(Marker(night: night, label: text, emoji: Self.emoji(for: text),
                                dateLabel: StageStory.monthDay(StageStory.nightDate(night, now: now, calendar: calendar), calendar: calendar)))
        }
        // Oldest first; markers on the same night keep Claude's order.
        markers = Array(found.enumerated().sorted { ($0.element.night, $0.offset) < ($1.element.night, $1.offset) }
            .map(\.element).prefix(Self.maxMarkers))

        let last = StageStory.lastNightIndex
        let earliest = markers.map(\.night).min() ?? last
        firstNight = max(StageHistory.firstNight, min(last - StageStory.nightCount + 1, earliest - 3))
        let ids = Array(firstNight...last)
        minutes = ids.map { StageHistory.night($0).minutes }
        hot = ids.map { StageHistory.night($0).flare }
        note = Self.text(arguments["note"])
        startLabel = StageStory.monthDay(StageStory.nightDate(firstNight, now: now, calendar: calendar), calendar: calendar)
    }

    /// A picture for a change, by what it names.
    static func emoji(for label: String) -> String? {
        let l = label.lowercased()
        if l.contains("detergent") || l.contains("laundry") { return "🧺" }
        if l.contains("hand soap") { return "✋" }
        if l.contains("sweater") || l.contains("lambswool") { return "🧶" }
        if l.contains("sock") { return "🧦" }
        if l.contains("pillow") { return "🛏" }
        if l.contains("sunscreen") { return "🌤" }
        if l.contains("trip") || l.contains("travel") || l.contains("seattle") { return "✈" }
        if ["wash", "soap", "shampoo", "lotion", "cream", "gel", "cleanser", "deodorant", "product"].contains(where: l.contains) { return "🧴" }
        if l.contains("humid") || l.contains("dry") { return "💧" }
        if l.contains("exam") || l.contains("stress") || l.contains("midterm") { return "📚" }
        if l.contains("wool") { return "🧶" }
        if l.contains("shirt") || l.contains("hoodie") { return "👕" }
        return nil
    }

    static func text(_ value: Any?) -> String? {
        guard let text = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }
}

/// `show_product`: a product Claude names, matched to his orders for the date and the ingredient list (or the
/// material).
public struct ChatProduct: Hashable, Sendable {
    public struct Ingredient: Hashable, Sendable {
        public var name: String
        /// One Claude pointed at (`flagged_ingredients`).
        public var flagged: Bool
    }

    /// "Brightwell Sensitive Fragrance-Free Body Wash, 18 fl oz": the order's full item name when Claude's name
    /// matches it (the product name, its brand, or just its kind: "Body wash"), else Claude's name.
    public var title: String
    /// He had never bought it before.
    public var firstTime: Bool
    /// "Ordered Mon Oct 19".
    public var ordered: String?
    public var ingredients: [Ingredient]
    /// "100% lambswool" (clothing, the pillow).
    public var material: String?
    public var note: String?

    public var hasFlags: Bool { ingredients.contains { $0.flagged } }

    public init(arguments: [String: Any], now: Date = Date(), calendar: Calendar = .current) {
        let name = ChatTimeline.text(arguments["name"]) ?? "Product"
        let purchase = String((arguments["purchase_date"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(10))
        let orders = StageStory.orders(now: now, calendar: calendar)
        let onDate = { (o: StageStory.Order) in StageStory.iso(o.date, calendar: calendar) == purchase }
        let byName = Self.best(name, in: orders, prefer: onDate)
        // No name match: the one skin-contact order of that day (a personal-care one first).
        let sameDay = orders.filter { onDate($0) && $0.skinContact }
        let order = byName ?? sameDay.first { $0.category == "personal care" } ?? (sameDay.count == 1 ? sameDay.first : nil)

        let flagged = (arguments["flagged_ingredients"] as? [Any] ?? [])
            .compactMap { ($0 as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        func matches(_ a: String, _ b: String) -> Bool {
            let x = Self.norm(a), y = Self.norm(b)
            return !x.isEmpty && !y.isEmpty && (x.contains(y) || y.contains(x))
        }
        var list = (order?.ingredients ?? []).map { ing in Ingredient(name: ing, flagged: flagged.contains { matches(ing, $0) }) }
        for f in flagged where !list.contains(where: { $0.flagged && matches($0.name, f) }) {
            list.append(Ingredient(name: f, flagged: true))
        }

        title = byName?.item ?? name
        firstTime = order?.boughtBefore == false
        let when = StageStory.date(iso: purchase, calendar: calendar) ?? order?.date
        ordered = when.map { "Ordered \(StageStory.weekday($0, short: true, calendar: calendar)) \(StageStory.monthDay($0, calendar: calendar))" }
        ingredients = list
        material = order?.material
        note = ChatTimeline.text(arguments["note"])
    }

    /// The order Claude's name names best: the most of its words in the item's name (a word inside a longer
    /// one counts: "wool" in "Lambswool"). It names it when all its words are there, or two of them, or the
    /// brand (the item's first word). Ties: the order of `prefer`'s day, then a new product, then the latest.
    static func best(_ name: String, in orders: [StageStory.Order], prefer: (StageStory.Order) -> Bool) -> StageStory.Order? {
        let scored = orders.map { (order: $0, score: score(name, $0.item)) }.filter { $0.score > 0 }
        guard let top = scored.map(\.score).max() else { return nil }
        let tied = scored.filter { $0.score == top }.map(\.order)
        return tied.last(where: prefer) ?? tied.last { !$0.boughtBefore } ?? tied.last
    }

    /// How well `name` names `item` (0: not at all). Words as `norm` writes them; "the", "new", "his"… don't count.
    static func score(_ name: String, _ item: String) -> Int {
        let asked = words(name).subtracting(fillers)
        guard !asked.isEmpty else { return 0 }
        let itemWords = item.split(whereSeparator: { !$0.isLetter }).map { norm(String($0)) }.filter { !$0.isEmpty }
        let hits = asked.filter { w in itemWords.contains { $0 == w || (w.count >= 4 && $0.contains(w)) } }
        let brand = itemWords.first.map(asked.contains) ?? false
        return hits.count == asked.count || hits.count >= 2 || brand ? hits.count : 0
    }

    static let fillers: Set<String> = ["the", "a", "an", "new", "hi", "your", "my", "of", "for", "and", "with", "from", "that", "thi"]

    /// The words of a name, each like `norm` ("Wool socks" → wool, sock).
    static func words(_ text: String) -> Set<String> {
        Set(text.split(whereSeparator: { !$0.isLetter }).map { norm(String($0)) }.filter { !$0.isEmpty })
    }

    /// chat.js `norm`: lowercase letters only, without a final "s" ("Body washes" → "bodywashe").
    static func norm(_ text: String) -> String {
        let az: ClosedRange<Unicode.Scalar> = "a"..."z"
        var letters = String(text.lowercased().unicodeScalars.filter { az.contains($0) }.map(Character.init))
        if letters.hasSuffix("s") { letters.removeLast() }
        return letters
    }
}

/// `ask_user`: one short question with 2–3 answers.
public struct ChatQuestion: Hashable, Sendable {
    public var question: String
    public var options: [String]

    public init(arguments: [String: Any]) {
        question = ChatTimeline.text(arguments["question"]) ?? "Can you tell me more?"
        options = Array((arguments["options"] as? [Any] ?? [])
            .map { ($0 as? String) ?? "\($0)" }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(4))
    }
}

/// `show_conclusion`: the most likely cause, how sure, what was ruled out and a simple test.
public struct ChatConclusion: Hashable, Sendable {
    public struct RuledOut: Hashable, Sendable {
        public var item: String
        public var reason: String?
    }

    public var cause: String
    /// "Low", "Medium", "High" (or "Medium–high").
    public var confidence: String
    /// How full the confidence bar is, 0…1.
    public var confidenceFill: Double
    public var ruledOut: [RuledOut]
    public var nextStep: String?

    public init(arguments: [String: Any]) {
        cause = ChatTimeline.text(arguments["cause"]) ?? "Not sure yet"
        let level = (arguments["confidence"] as? String ?? "").lowercased()
        switch (level.contains("low"), level.contains("medium") || level.contains("moderate"), level.contains("high")) {
        case (_, true, true): (confidence, confidenceFill) = ("Medium–high", 0.72)
        case (true, true, _): (confidence, confidenceFill) = ("Low–medium", 0.42)
        case (_, _, true): (confidence, confidenceFill) = ("High", 0.84)
        case (true, _, _): (confidence, confidenceFill) = ("Low", 0.3)
        default: (confidence, confidenceFill) = ("Medium", 0.58)
        }
        ruledOut = Array((arguments["ruled_out"] as? [Any] ?? []).compactMap { entry -> RuledOut? in
            if let item = ChatTimeline.text(entry) { return RuledOut(item: item, reason: nil) }
            guard let object = entry as? [String: Any], let item = ChatTimeline.text(object["item"]) else { return nil }
            return RuledOut(item: item, reason: ChatTimeline.text(object["reason"]))
        }.prefix(6))
        nextStep = ChatTimeline.text(arguments["next_step"])
    }
}
