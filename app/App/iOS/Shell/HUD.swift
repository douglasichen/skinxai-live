import SwiftUI

/// App-wide HUD toast ("Good morning, Douglas · last night is ready"). Dark Raft HUD that rises into
/// place just above the tab bar (prototype `.toast`: bottom 100 px, up 30 px). Anything can raise one
/// with `NotificationCenter.default.postTwinToast(_:)`.
@MainActor
final class ShellToasts: ObservableObject {
    struct Toast: Identifiable, Equatable {
        enum Mood: Equatable { case done, info, warning }
        let id = UUID()
        var text: String
        var mood: Mood
        /// SF Symbol shown in the tile (defaults per mood).
        var symbol: String?
    }

    @Published private(set) var current: Toast?
    private var hideTask: Task<Void, Never>?

    func show(_ text: String, mood: Toast.Mood = .done, symbol: String? = nil, seconds: Double = 2.0) {
        hideTask?.cancel()
        withAnimation(Twin.Motion.bouncy) { current = Toast(text: text, mood: mood, symbol: symbol) }
        UIAccessibility.post(notification: .announcement, argument: text)
        hideTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            withAnimation(Twin.Motion.slide) { self?.current = nil }
        }
    }

    func hide() {
        hideTask?.cancel()
        withAnimation(Twin.Motion.slide) { current = nil }
    }
}

struct ShellToastHost: View {
    @EnvironmentObject var toasts: ShellToasts
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// From the bottom of the safe area: the tab bar (~62 pt) and the prototype's 14 pt gap above it.
    static let bottomClearance: CGFloat = 76

    var body: some View {
        ZStack {
            if let toast = toasts.current {
                ToastView(toast: toast)
                    .id(toast.id)
                    .transition(reduceMotion ? .opacity : .asymmetric(
                        insertion: .offset(y: 30).combined(with: .opacity).combined(with: .scale(scale: 0.92, anchor: .bottom)),
                        removal: .offset(y: 16).combined(with: .opacity)))
                    .onTapGesture { toasts.hide() }
            }
        }
        .padding(.bottom, Self.bottomClearance)
        .frame(maxWidth: .infinity)
        .allowsHitTesting(toasts.current != nil)
    }
}

private struct ToastView: View {
    let toast: ShellToasts.Toast
    @State private var tick = false

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 2, style: .continuous).fill(tileColor)
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(Twin.Palette.ink)
                    .symbolEffect(.bounce, value: tick)
            }
            .frame(width: 18, height: 18)
            Text(toast.text)
                .font(Twin.Typeface.sans(14, .semibold))
                .foregroundStyle(Color(hex: 0xF3F3F5))
                .lineLimit(2)
        }
        .padding(.leading, 10)
        .padding(.trailing, 14)
        .padding(.vertical, 10)
        .background(Twin.Palette.hud, in: RoundedRectangle(cornerRadius: Twin.Radius.chip, style: .continuous))
        .padding(.horizontal, 24)
        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { tick.toggle() } }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }

    private var tileColor: Color {
        switch toast.mood {
        case .done: Twin.Palette.lime
        case .info: Twin.Palette.cyan
        case .warning: Twin.Palette.orange
        }
    }
    private var symbol: String {
        if let s = toast.symbol { return s }
        return switch toast.mood {
        case .done: "checkmark"
        case .info: "info"
        case .warning: "exclamationmark"
        }
    }
}
