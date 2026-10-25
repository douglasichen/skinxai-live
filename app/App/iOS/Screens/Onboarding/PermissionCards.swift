import SwiftUI

// MARK: - What it can read (onboarding's permissions page)

/// What SkinXAI can read, as cards on the yellow frame. In this build every source is
/// connected, so each row shows its granted state; nothing here asks the system for permission.
struct PermissionCards: View {
    struct Source: Identifiable {
        let icon: String
        let title: String
        let detail: String
        /// The granted state: "On", or how that source says it ("Paired", "Connected").
        let status: String
        var id: String { title }
    }

    static let sources: [Source] = [
        Source(icon: "heart.fill", title: "Apple Health", detail: "Sleep, HRV, resting pulse", status: "On"),
        Source(icon: "location.fill", title: "Location", detail: "Air, humidity, pollen near you", status: "On"),
        Source(icon: "bell.fill", title: "Notifications", detail: "A heads-up when a flare starts", status: "On"),
        Source(icon: "applewatch", title: "Apple Watch", detail: "Counts scratching, even asleep", status: "Paired"),
        Source(icon: "calendar", title: "Calendar", detail: "Exams, deadlines and travel", status: "On"),
        Source(icon: "shippingbox.fill", title: "Amazon orders", detail: "What you bought, and what’s new to you",
               status: "Connected"),
    ]

    @State private var shown = false

    var body: some View {
        VStack(spacing: 10) {
            ForEach(Array(Self.sources.enumerated()), id: \.element.id) { index, source in
                PermissionRow(icon: source.icon, title: source.title, detail: source.detail) {
                    PermissionStatus(text: source.status)
                }
                .modifier(RowEntrance(index: index, shown: shown))
            }
        }
        .onAppear { shown = true }
    }
}

/// Rows rise in one after another (fade only with Reduce Motion).
private struct RowEntrance: ViewModifier {
    let index: Int
    let shown: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 22)
            .animation(Twin.Motion.spring.delay(0.1 + Double(index) * 0.08), value: shown)
    }
}

struct PermissionRow<Trailing: View>: View {
    let icon: String
    let title: String
    let detail: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Twin.Palette.ink)
                .frame(width: 40, height: 40)
                .sticker(Twin.Palette.cream)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Twin.Typeface.sans(15, .bold))
                    .foregroundStyle(Twin.Palette.ink)
                Text(detail)
                    .font(Twin.Typeface.sans(12))
                    .foregroundStyle(Twin.Palette.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            trailing()
        }
        .padding(12)
        .background(Twin.Palette.paper, in: RoundedRectangle(cornerRadius: Twin.Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Twin.Radius.card, style: .continuous).strokeBorder(Twin.Palette.ink, lineWidth: Twin.Stroke.ink))
        .accessibilityElement(children: .combine)
    }
}

/// A source the app can read: "✓ On" in lime (good). The watch says "Paired", Amazon "Connected".
struct PermissionStatus: View {
    var text = "On"

    var body: some View {
        Sticker(text: text, icon: "checkmark", fill: Twin.Palette.lime)
    }
}

/// The two-ring mark (you and your twin) and the name, as on the onboarding header.
struct BrandMark: View {
    var body: some View {
        HStack(spacing: 9) {
            ZStack {
                Circle().strokeBorder(Twin.Palette.ink, lineWidth: 2.2)
                    .frame(width: 15, height: 15)
                    .offset(x: -4.5)
                Circle().fill(Twin.Palette.orange)
                    .overlay(Circle().strokeBorder(Twin.Palette.ink, lineWidth: 2.2))
                    .frame(width: 15, height: 15)
                    .offset(x: 4.5)
            }
            .frame(width: 24, height: 16)
            Text("SkinXAI")
                .font(Twin.Typeface.sans(17, .bold))
                .tracking(-0.3)
                .foregroundStyle(Twin.Palette.ink)
        }
        .accessibilityElement(children: .combine)
    }
}
