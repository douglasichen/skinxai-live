import SwiftUI
import EczemaKit

// The pieces of the conversation thread (prototype v5 "Insight"): Claude's label and words, Douglas's yellow
// bubbles, chips, the thinking row, "Go ahead" and the failed-request row.

/// One block of the thread.
struct ChatItemView: View {
    let item: ChatItem
    @ObservedObject var session: ChatSession

    private static let greeting = ChatText(markdown: ChatRules.greeting)

    var body: some View {
        switch item.kind {
        case .greeting:
            ClaudeWords(text: Self.greeting, from: .distantPast)
                .riseIn(0.04)
        case .suggestions:
            SuggestionChips(session: session)
        case .user(let text):
            UserBubble(text: text)
        case .claude(let text, let from):
            ClaudeWords(text: text, from: from, fresh: item.isFresh)
        case .thinking:
            ThinkingRow()
        case .tools(let rows):
            ToolListCard(rows: rows)
        case .timeline(let card):
            TimelineCardView(card: card, fresh: item.isFresh)
        case .product(let card):
            ProductCardView(card: card, fresh: item.isFresh)
        case .question(let card, let answer):
            QuestionCardView(card: card, answer: answer, open: session.askingID == item.id,
                             pressed: session.pressed) { session.tapOption($0, in: item.id) }
        case .conclusion(let card):
            ConclusionCardView(card: card, fresh: item.isFresh)
        case .failure(let reason):
            FailureRow(reason: reason, busy: session.busy) { session.retry() }
        case .nudge:
            HStack {
                ChatChip(text: ChatRules.nudge, icon: "arrow.turn.down.right", pressedByScript: session.pressed == ChatRules.nudge) {
                    session.nudge()
                }
                Spacer(minLength: 0)
            }
            .accessibilityHint("Lets Claude carry on")
        }
    }

    /// How a block enters and leaves the thread.
    static func transition(for kind: ChatItem.Kind, reduceMotion: Bool) -> AnyTransition {
        if reduceMotion { return .opacity }
        switch kind {
        case .user:
            return .asymmetric(insertion: .opacity.combined(with: .offset(y: 10)).combined(with: .scale(scale: 0.94, anchor: .bottomTrailing)),
                               removal: .opacity)
        case .claude:
            // Claude's words pop in by themselves (they often replace the thinking row in the same update).
            return .asymmetric(insertion: .identity, removal: .opacity)
        case .greeting, .nudge, .failure:
            return .asymmetric(insertion: .opacity.combined(with: .offset(y: 10)), removal: .opacity)
        case .suggestions:
            return .asymmetric(insertion: .opacity, removal: .opacity.combined(with: .scale(scale: 0.96, anchor: .topLeading)))
        case .thinking:
            return .opacity
        case .tools, .timeline, .product, .question, .conclusion:
            return .asymmetric(insertion: .modifier(active: CardEntrance(progress: 0), identity: CardEntrance(progress: 1)),
                               removal: .opacity)
        }
    }
}

/// Cards rise 24 pt and grow from 97% as they come in (prototype `@keyframes card`).
struct CardEntrance: ViewModifier {
    var progress: Double
    func body(content: Content) -> some View {
        content
            .opacity(progress)
            .scaleEffect(0.97 + 0.03 * progress, anchor: .top)
            .offset(y: 24 * (1 - progress))
    }
}

// MARK: - Claude

/// "✶ CLAUDE" above Claude's words.
struct ClaudeLabel: View {
    var body: some View {
        HStack(spacing: 6) {
            ClaudeMark(size: 11)
                .foregroundStyle(Twin.Palette.ink)
                .frame(width: 20, height: 20)
                .sticker(Twin.Palette.pink)
            Text("CLAUDE")
                .font(Twin.Typeface.mono(11, bold: true))
                .tracking(0.66)
                .foregroundStyle(Twin.Palette.inkHint)
        }
        .padding(.bottom, 4)
        .accessibilityHidden(true)
    }
}

/// Claude's words, revealed word by word from `from`. The whole text is laid out from the start (the words still
/// to come are clear), so lines never jump and nothing below moves while it "types".
struct ClaudeWords: View {
    let text: ChatText
    let from: Date
    var wordDelay = ChatSession.wordDelay
    @State private var shown: Int
    /// False until a new block has popped in (prototype `@keyframes pop`: up 10 pt and fade in).
    @State private var landed: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(text: ChatText, from: Date, fresh: Bool = false, wordDelay: Double = ChatSession.wordDelay) {
        self.text = text
        self.from = from
        self.wordDelay = wordDelay
        _shown = State(initialValue: Self.words(text, from: from, delay: wordDelay, at: Date()))
        _landed = State(initialValue: !fresh)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ClaudeLabel()
            Text(attributed)
                .font(Twin.Typeface.sans(16))
                .lineSpacing(3.5)
                .foregroundStyle(Twin.Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .opacity(landed ? 1 : 0)
        .offset(y: landed || reduceMotion ? 0 : 10)
        .onAppear {
            guard !landed else { return }
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : Twin.Motion.slide) { landed = true }
        }
        .task(id: from) {
            while !Task.isCancelled {
                let n = Self.words(text, from: from, delay: wordDelay, at: Date())
                if n != shown { shown = n }
                if n >= text.wordCount { break }
                try? await Task.sleep(nanoseconds: UInt64(wordDelay * 1_000_000_000))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Claude: \(text.plain)")
    }

    private var attributed: AttributedString {
        var out = AttributedString()
        for run in text.runs {
            var part = AttributedString(run.text)
            if run.bold { part.font = Twin.Typeface.sans(16, .bold) }
            out += part
        }
        let visible = text.visibleLength(words: shown)
        let total = out.characters.count
        if visible < total {
            let start = out.characters.index(out.startIndex, offsetBy: visible)
            out[start..<out.endIndex].foregroundColor = .clear
        }
        return out
    }

    static func words(_ text: ChatText, from: Date, delay: Double, at now: Date) -> Int {
        guard from > .distantPast, delay > 0 else { return text.wordCount }
        let elapsed = now.timeIntervalSince(from)
        return min(text.wordCount, max(0, Int(elapsed / delay) + 1))
    }
}

/// "Thinking…" with the pixel spinner.
struct ThinkingRow: View {
    var body: some View {
        HStack(spacing: 10) {
            PixelSpinner()
            Text("Thinking…")
                .font(Twin.Typeface.sans(14))
                .foregroundStyle(Twin.Palette.inkMuted)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Claude is thinking")
    }
}

// MARK: - Douglas

/// Douglas's message: a yellow bubble with an ink edge on the right.
struct UserBubble: View {
    let text: String
    private static let shape = UnevenRoundedRectangle(topLeadingRadius: 10, bottomLeadingRadius: 10,
                                                      bottomTrailingRadius: 2, topTrailingRadius: 10, style: .continuous)
    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 64)
            Text(text)
                .font(Twin.Typeface.sans(15))
                .lineSpacing(2)
                .foregroundStyle(Twin.Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Twin.Palette.yellow, in: Self.shape)
                .overlay(Self.shape.strokeBorder(Twin.Palette.ink, lineWidth: Twin.Stroke.ink))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("You: \(text)")
    }
}

// MARK: - Chips

/// A Raft chip: paper (or yellow when chosen), ink edge, control corners. Squashes and taps when pressed.
struct ChatChip: View {
    let text: String
    var icon: String? = nil
    var fill: Color = Twin.Palette.paper
    var dimmed = false
    /// Drawn pressed (a replay or -chatAuto taps it).
    var pressedByScript = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if let icon {
                    Image(systemName: icon).font(.system(size: 12, weight: .bold))
                }
                Text(text)
                    .font(Twin.Typeface.sans(14, .semibold))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(Twin.Palette.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(fill, in: RoundedRectangle(cornerRadius: Twin.Radius.control, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Twin.Radius.control, style: .continuous)
                .strokeBorder(Twin.Palette.ink, lineWidth: Twin.Stroke.ink))
            .contentShape(RoundedRectangle(cornerRadius: Twin.Radius.control, style: .continuous))
        }
        .buttonStyle(ChatPressStyle(forced: pressedByScript))
        .opacity(dimmed ? 0.45 : 1)
        .animation(.easeOut(duration: 0.15), value: fill)
        .animation(.easeOut(duration: 0.2), value: dimmed)
    }
}

/// Press feedback for the chat's chips and send button: a small squash, a touch darker, a light tap.
struct ChatPressStyle: ButtonStyle {
    var forced = false
    func makeBody(configuration: Configuration) -> some View {
        let down = configuration.isPressed || forced
        configuration.label
            .scaleEffect(down ? 0.96 : 1)
            .brightness(down ? -0.04 : 0)
            .animation(Twin.Motion.bouncy, value: down)
            .onChange(of: configuration.isPressed) { _, pressed in if pressed { Haptics.tap() } }
    }
}

/// The two suggested questions under the greeting.
struct SuggestionChips: View {
    @ObservedObject var session: ChatSession
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(ChatRules.suggestions.enumerated()), id: \.offset) { index, text in
                ChatChip(text: text, pressedByScript: session.pressed == text) { session.send(text) }
                    .disabled(session.busy || session.replaying)
                    .riseIn(0.1 + Double(index) * Twin.Motion.stagger)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - A request that failed

/// "Claude didn't answer" with the reason and "Try again".
struct FailureRow: View {
    let reason: String
    let busy: Bool
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(Twin.Palette.ink)
                    .frame(width: 20, height: 20)
                    .sticker(Twin.Palette.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Claude didn't answer")
                        .font(Twin.Typeface.sans(15, .bold))
                        .foregroundStyle(Twin.Palette.ink)
                    Text(reason)
                        .font(Twin.Typeface.sans(13))
                        .foregroundStyle(Twin.Palette.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            ChatChip(text: "Try again", icon: "arrow.clockwise", action: retry)
                .disabled(busy)
                .padding(.leading, 30)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Twin.Palette.cream, in: RoundedRectangle(cornerRadius: Twin.Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Twin.Radius.card, style: .continuous)
            .strokeBorder(Twin.Palette.hairline, lineWidth: Twin.Stroke.hairline))
    }
}

// MARK: - Layout

/// Left-to-right wrapping layout for chips.
struct ChatFlow: Layout {
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
