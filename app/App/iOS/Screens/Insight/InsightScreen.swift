import SwiftUI
import EczemaKit

/// Insight: ask Claude about your skin (prototype v5 "Insight"). Claude's greeting and two suggestions, then the
/// conversation: Douglas's yellow bubbles, Claude's words, the data it reads, its cards and questions, and the
/// conclusion. The composer sits above the tab bar. The conversation itself lives in `ChatSession`.
struct InsightScreen: View {
    @ObservedObject private var session = ChatSession.shared
    @StateObject private var keyboard = KeyboardWatcher()
    @FocusState private var typing: Bool
    @State private var bottomY: CGFloat = 0
    @State private var draftShown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The tab bar's height above the home indicator (the root draws it over the page).
    static let tabBarClearance: CGFloat = 60
    private static let bottomID = "chat-bottom"

    var body: some View {
        VStack(spacing: 0) {
            TopBar(title: "Insight", subtitle: "Ask about your skin") {
                ClaudeBadge(active: session.working)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: Twin.Space.m) {
                        ForEach(session.items) { item in
                            ChatItemView(item: item, session: session)
                                .id(item.id)
                                .transition(ChatItemView.transition(for: item.kind, reduceMotion: reduceMotion))
                        }
                        Color.clear.frame(height: 1).id(Self.bottomID)
                    }
                    .padding(.horizontal, Twin.Space.screen)
                    .padding(.top, Twin.Space.l)
                    .padding(.bottom, 4)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    ChatComposer(session: session, draft: session.draft, typing: $typing, bottom: composerBottom)
                }
                .onAppear { scrollDown(proxy, animated: false) }
                .onChange(of: session.scrollTick) { _, _ in scrollDown(proxy, animated: true) }
                .onChange(of: keyboard.top) { _, _ in scrollDown(proxy, animated: true) }
            }
        }
        .background(Twin.Palette.paper)
        .background {
            GeometryReader { geo in
                Color.clear
                    .onAppear { bottomY = geo.frame(in: .global).maxY }
                    .onChange(of: geo.frame(in: .global).maxY) { _, y in bottomY = y }
            }
        }
        .onAppear {
            session.appear()
            // -chatDraft <text> (hidden, development): text in the box and the keyboard up.
            if let draft = UserDefaults.standard.string(forKey: "chatDraft"), session.draft.text.isEmpty, !draftShown {
                draftShown = true
                session.draft.text = draft
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { typing = true }
            }
        }
    }

    /// Above the tab bar; above the keyboard while it is up.
    private var composerBottom: CGFloat {
        guard let top = keyboard.top else { return Self.tabBarClearance + 7 }
        return max(8, bottomY - top + 8)
    }

    /// Glides to the newest line: once on the next run loop, and once more after the layout has settled (a
    /// block that replaces another in the same update can leave the first pass short).
    private func scrollDown(_ proxy: ScrollViewProxy, animated: Bool) {
        let glide = animated && !reduceMotion
        DispatchQueue.main.async {
            if glide {
                withAnimation(.smooth(duration: 0.45)) { proxy.scrollTo(Self.bottomID, anchor: .bottom) }
            } else {
                proxy.scrollTo(Self.bottomID, anchor: .bottom)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            if glide {
                withAnimation(.smooth(duration: 0.35)) { proxy.scrollTo(Self.bottomID, anchor: .bottom) }
            } else {
                proxy.scrollTo(Self.bottomID, anchor: .bottom)
            }
        }
    }
}

// MARK: - "✶ Claude" badge

/// The pink "✶ Claude" sticker in the top bar. Claude's mark (the ✶ of Today's pink card) pulses while Claude is
/// working; it never turns (turned, it reads as a close "×" on the big screen).
struct ClaudeBadge: View {
    var active: Bool

    var body: some View {
        HStack(spacing: 5) {
            ClaudeMark(size: 12, pulsing: active)
            Text("Claude").font(Twin.Typeface.sans(13, .bold))
        }
        .foregroundStyle(Twin.Palette.ink)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .sticker(Twin.Palette.pink)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(active ? "Claude is working" : "Claude")
    }
}

/// Claude's mark, "✶" (prototype v5: the badge, the CLAUDE label, "✶ FROM CLAUDE", Today's pink card). Only the
/// Insight tab icon is the four-point sparkle. `pulsing`: it fades in and out (a fade, so also with Reduce Motion).
struct ClaudeMark: View {
    var size: CGFloat
    var pulsing = false

    var body: some View {
        let mark = Text("✶").font(.system(size: size, weight: .bold)).accessibilityHidden(true)
        if pulsing {
            mark.phaseAnimator([1.0, 0.3]) { content, opacity in
                content.opacity(opacity)
            } animation: { _ in
                .easeInOut(duration: 0.7)
            }
        } else {
            mark
        }
    }
}
