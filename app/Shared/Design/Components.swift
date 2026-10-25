import SwiftUI
#if os(iOS)
import UIKit
#elseif os(watchOS)
import WatchKit
#endif

// MARK: - Sticker

/// A block of brand color with a 1.5pt ink edge (Raft "sticker").
struct StickerShape: ViewModifier {
    var fill: Color
    var radius: CGFloat = Twin.Radius.sticker
    var edge: Color = Twin.Palette.ink
    func body(content: Content) -> some View {
        content
            .background(fill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(edge, lineWidth: Twin.Stroke.ink))
    }
}

extension View {
    func sticker(_ fill: Color, radius: CGFloat = Twin.Radius.sticker, edge: Color = Twin.Palette.ink) -> some View {
        modifier(StickerShape(fill: fill, radius: radius, edge: edge))
    }
}

/// Small label sticker, e.g. "▲ 3.9× your usual".
struct Sticker: View {
    var text: String
    var icon: String? = nil          // SF Symbol name or an emoji
    var fill: Color = Twin.Palette.paper
    var foreground: Color = Twin.Palette.ink
    var body: some View {
        HStack(spacing: 5) {
            if let icon {
                // SF Symbol names are plain ASCII, so anything else is an emoji, including the
                // text-style ones (🏋️ ✈️ ✳️ 🌡) that would otherwise render as a blank symbol.
                // Emoji with a drawn icon (TwinIcon) show the icon at 14 pt (≈ the 11 pt emoji).
                if TwinIcon.asset(for: icon) != nil {
                    TwinIconView(emoji: icon, size: 14)
                } else if icon.unicodeScalars.contains(where: { !$0.isASCII }) {
                    Text(icon).font(.system(size: 11))
                } else {
                    Image(systemName: icon).font(.system(size: 10, weight: .bold))
                }
            }
            Text(text).font(Twin.Typeface.sans(12, .bold)).lineLimit(1)
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .sticker(fill)
    }
}

// MARK: - Card

struct TwinCard: ViewModifier {
    var fill: Color = Twin.Palette.paper
    var border: Color = Twin.Palette.hairline
    var borderWidth: CGFloat = Twin.Stroke.hairline
    var padding: CGFloat = Twin.Space.l
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill, in: RoundedRectangle(cornerRadius: Twin.Radius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Twin.Radius.card, style: .continuous).strokeBorder(border, lineWidth: borderWidth))
    }
}

extension View {
    func twinCard(fill: Color = Twin.Palette.paper, border: Color = Twin.Palette.hairline,
                  borderWidth: CGFloat = Twin.Stroke.hairline, padding: CGFloat = Twin.Space.l) -> some View {
        modifier(TwinCard(fill: fill, border: border, borderWidth: borderWidth, padding: padding))
    }
}

/// UPPERCASE mono section label.
struct Eyebrow: View {
    var text: String
    var color: Color = Twin.Palette.inkHint
    var body: some View {
        Text(text.uppercased()).font(Twin.Typeface.eyebrow).tracking(0.8).foregroundStyle(color)
    }
}

// MARK: - Buttons

/// Raft button: ink edge, color fill. Press = ink overlay + a small spring squash + haptic.
struct TwinButtonStyle: ButtonStyle {
    var fill: Color = Twin.Palette.pink
    var foreground: Color = Twin.Palette.ink
    var height: CGFloat = 52
    var fullWidth = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Twin.Typeface.sans(16, .bold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 18)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: height)
            .background(fill, in: RoundedRectangle(cornerRadius: Twin.Radius.control, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Twin.Radius.control, style: .continuous)
                .fill(Twin.Palette.ink.opacity(configuration.isPressed ? 0.10 : 0)))
            .overlay(RoundedRectangle(cornerRadius: Twin.Radius.control, style: .continuous)
                .strokeBorder(Twin.Palette.ink, lineWidth: Twin.Stroke.ink))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Twin.Motion.bouncy, value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in if pressed { Haptics.tap() } }
    }
}

/// Plain press feedback for tappable cards and rows.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .brightness(configuration.isPressed ? -0.03 : 0)
            .animation(Twin.Motion.bouncy, value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in if pressed { Haptics.tap() } }
    }
}

// MARK: - Ring

/// Progress ring that fills from zero with a spring when it appears.
struct RingView: View {
    var progress: Double                // 0...1 (values above 1 are clamped)
    var lineWidth: CGFloat = 16
    var color: Color = Twin.Palette.orange
    var track: Color = Twin.Palette.fill
    var delay: Double = 0.1
    @State private var shown: Double = 0

    var body: some View {
        ZStack {
            Circle().stroke(track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(shown, 0), 1))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                .rotationEffect(.degrees(-90))
        }
        .padding(lineWidth / 2)
        .onAppear {
            withAnimation(Twin.Motion.fill.delay(delay)) { shown = progress }
        }
        .onChange(of: progress) { _, new in withAnimation(Twin.Motion.fill) { shown = new } }
    }
}

// MARK: - Numbers that count up

/// Text that animates its number (use with `withAnimation`).
struct CountingText: View, Animatable {
    var value: Double
    var decimals: Int = 0
    var font: Font = Twin.Typeface.display
    var color: Color = Twin.Palette.ink
    var animatableData: Double {
        get { value }
        set { value = newValue }
    }
    var body: some View {
        Text(value, format: .number.precision(.fractionLength(decimals)).grouping(.never))
            .font(font)
            .foregroundStyle(color)
            .monospacedDigit()
    }
}

/// A number that counts up from 0 when it appears.
struct CountUp: View {
    var value: Double
    var decimals: Int = 0
    var font: Font = Twin.Typeface.display
    var color: Color = Twin.Palette.ink
    var delay: Double = 0.1
    var duration: Double = 1.1
    @State private var shown: Double = 0
    var body: some View {
        CountingText(value: shown, decimals: decimals, font: font, color: color)
            .onAppear { withAnimation(.easeOut(duration: duration).delay(delay)) { shown = value } }
            .onChange(of: value) { _, new in withAnimation(.easeOut(duration: duration)) { shown = new } }
    }
}

// MARK: - Entrance

/// Rises 14pt and fades in after `delay`. Use `index * Twin.Motion.stagger` for sequences.
struct RiseIn: ViewModifier {
    var delay: Double
    var distance: CGFloat = 14
    @State private var shown = false
    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : distance)
            .onAppear { withAnimation(Twin.Motion.spring.delay(delay)) { shown = true } }
    }
}

extension View {
    func riseIn(_ delay: Double = 0, distance: CGFloat = 14) -> some View { modifier(RiseIn(delay: delay, distance: distance)) }
}

// MARK: - Pixel spinner (the only looping "status" animation; stop it when loading ends)

struct PixelSpinner: View {
    var pixel: CGFloat = 5
    var color: Color = Twin.Palette.ink
    @State private var phase = 0
    private let order = [0, 1, 2, 5, 8, 7, 6, 3]   // clockwise around a 3x3 grid
    var body: some View {
        let grid = Array(0..<9)
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(pixel), spacing: 2), count: 3), spacing: 2) {
            ForEach(grid, id: \.self) { i in
                Rectangle()
                    .fill(color)
                    .frame(width: pixel, height: pixel)
                    .opacity(i == 4 ? 0 : opacity(for: i))
            }
        }
        .frame(width: pixel * 3 + 4, height: pixel * 3 + 4)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 110_000_000)
                withAnimation(.linear(duration: 0.1)) { phase = (phase + 1) % order.count }
            }
        }
    }
    private func opacity(for i: Int) -> Double {
        guard let pos = order.firstIndex(of: i) else { return 0.15 }
        let d = (phase - pos + order.count) % order.count
        return d < 3 ? [1, 0.55, 0.3][d] : 0.15
    }
}

// MARK: - Haptics

/// iPhone only: the watch stays silent (no buzz, no sound).
enum Haptics {
    /// When `tap()` last fired. Lets an action that follows a button's press tap (for example a
    /// tab change started from a card) skip a second tap for the same touch.
    private(set) static var lastTapAt: Date = .distantPast

    static func tap() {
        lastTapAt = Date()
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }
    static func soft() {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        #endif
    }
    static func success() {
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }
    static func warning() {
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        #endif
    }
}
