import SwiftUI
import WatchKit

/// Watch typography. Same faces as the phone (Space Grotesk for reading, Space Mono for what the
/// machine writes) at fixed sizes: the watch layouts are measured to the point.
enum WatchFont {
    static func sans(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom("Space Grotesk", fixedSize: size).weight(weight)
    }
    static func mono(_ size: CGFloat, bold: Bool = false) -> Font {
        .custom(bold ? "SpaceMono-Bold" : "SpaceMono-Regular", fixedSize: size)
    }
}

/// Watch haptics: off. The watch stays silent while it tracks (no buzz, no sound).
enum WatchHaptic {
    static func play(_ type: WKHapticType) {}
}

/// Press feedback without a fill (the big button draws its own).
struct WatchPressStyle: ButtonStyle {
    var scale: CGFloat = 0.96
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(Twin.Motion.bouncy, value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in if pressed { Haptics.tap() } }
    }
}

/// The app's name on the system clock's line: the big screen's two-circle mark and "SkinXAI".
struct WatchTitle: View {
    var body: some View {
        HStack(spacing: 6) {
            TwinMark(size: 12)
            Text("SkinXAI")
                .font(WatchFont.sans(17, .bold))
                .foregroundStyle(Twin.Palette.yellow)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("SkinXAI")
        .accessibilityAddTraits(.isHeader)
    }
}

/// Two overlapping circles, an outlined one and an orange one (the logo on the big screen).
struct TwinMark: View {
    var size: CGFloat = 12
    var body: some View {
        HStack(spacing: -size * 0.38) {
            Circle().strokeBorder(.white, lineWidth: size * 0.13)
                .frame(width: size, height: size)
            Circle().fill(Twin.Palette.orange)
                .frame(width: size, height: size)
        }
        .accessibilityHidden(true)
    }
}

/// A dot that breathes while something live is going on.
struct LiveDot: View {
    var size: CGFloat = 8
    var color: Color = Twin.Palette.cyan
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isLuminanceReduced) private var dimmed
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: dimmed)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let phase = (t / 1.6).truncatingRemainder(dividingBy: 1)
            ZStack {
                Circle().fill(color.opacity(reduceMotion ? 0.35 : 0.5 * (1 - phase)))
                    .scaleEffect(reduceMotion ? 1.6 : 1 + 1.4 * phase)
                Circle().fill(color)
            }
            .frame(width: size, height: size)
        }
        .accessibilityHidden(true)
    }
}

/// `.riseIn` that keeps only the fade when Reduce Motion is on.
struct WatchRise: ViewModifier {
    var delay: Double
    var distance: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        content.riseIn(delay, distance: reduceMotion ? 0 : distance)
    }
}

extension View {
    func watchRise(_ delay: Double = 0, distance: CGFloat = 10) -> some View {
        modifier(WatchRise(delay: delay, distance: distance))
    }
}
