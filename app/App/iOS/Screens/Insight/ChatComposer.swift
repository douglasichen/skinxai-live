import SwiftUI
import UIKit
import EczemaKit

/// The box pinned above the tab bar: "Ask Claude…" and the pink send button, with the small print under it.
/// A white fade above it lets the thread slide under softly.
struct ChatComposer: View {
    @ObservedObject var session: ChatSession
    @ObservedObject var draft: ChatDraft
    var typing: FocusState<Bool>.Binding
    /// Space under the box: the tab bar's height, or the keyboard's.
    var bottom: CGFloat

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: Twin.Radius.control, style: .continuous) }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                TextField("", text: $draft.text,
                          prompt: Text(session.placeholder).foregroundStyle(Twin.Palette.inkHint))
                    .font(Twin.Typeface.sans(15))
                    .foregroundStyle(Twin.Palette.ink)
                    .tint(Twin.Palette.ink)
                    .submitLabel(.send)
                    .onSubmit(send)
                    .focused(typing)
                    .disabled(session.replaying)
                    .accessibilityLabel("Message to Claude")
                Button(action: send) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Twin.Palette.ink)
                        .frame(width: 34, height: 34)
                        .background(Twin.Palette.pink, in: shape)
                        .overlay(shape.strokeBorder(Twin.Palette.ink, lineWidth: Twin.Stroke.ink))
                }
                .buttonStyle(ChatPressStyle())
                .accessibilityLabel("Send")
            }
            .padding(.leading, 12)
            .padding(.trailing, 6)
            .padding(.vertical, 6)
            .background(Twin.Palette.paper, in: shape)
            .overlay(shape.strokeBorder(Twin.Palette.ink, lineWidth: Twin.Stroke.ink))

            Text("POWERED BY CLAUDE · NOT A DIAGNOSIS")
                .font(Twin.Typeface.mono(9))
                .tracking(0.6)
                .foregroundStyle(Twin.Palette.inkHint)
                .accessibilityLabel("Powered by Claude. Not a diagnosis.")
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, bottom)
        .background {
            LinearGradient(stops: [.init(color: Twin.Palette.paper.opacity(0), location: 0),
                                   .init(color: Twin.Palette.paper, location: 0.3)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: .bottom)
        }
    }

    /// Sends what's in the box. With nothing to send, the tap opens the keyboard instead.
    private func send() {
        guard !session.replaying else { return }
        if draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            typing.wrappedValue = true
            return
        }
        guard session.canSend else { return }
        typing.wrappedValue = false
        session.submitDraft()
    }
}

/// Where the keyboard's top edge is (window points), nil while it is down. The app's root ignores the keyboard,
/// so the composer lifts itself.
@MainActor
final class KeyboardWatcher: ObservableObject {
    @Published private(set) var top: CGFloat?
    private var tokens: [NSObjectProtocol] = []

    init() {
        let center = NotificationCenter.default
        tokens.append(center.addObserver(forName: UIResponder.keyboardWillChangeFrameNotification, object: nil, queue: .main) { [weak self] note in
            guard let end = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
            let screen = (note.object as? UIScreen)?.bounds.height ?? end.maxY
            let duration = note.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.25
            MainActor.assumeIsolated {
                withAnimation(.easeOut(duration: max(0.15, duration))) { self?.top = end.minY < screen - 1 ? end.minY : nil }
            }
        })
        tokens.append(center.addObserver(forName: UIResponder.keyboardWillHideNotification, object: nil, queue: .main) { [weak self] note in
            let duration = note.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.25
            MainActor.assumeIsolated {
                withAnimation(.easeOut(duration: max(0.15, duration))) { self?.top = nil }
            }
        })
    }

    deinit {
        for token in tokens { NotificationCenter.default.removeObserver(token) }
    }
}
