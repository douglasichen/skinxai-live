import SwiftUI

// MARK: - Drawn icons for the "thing" emoji

/// The app's drawn color icons (App/iOS/Assets.xcassets, `icon.<name>`, vector, original colors) that stand
/// in for the emoji the data uses as small pictures (🧴 a body wash, ⌚ the watch's scratch history…).
/// The data keeps its emoji strings (tests, accessibility, the watch); only the rendering changes.
/// Brand and status marks (✶ ✓ ▲) are not emoji pictures and stay text.
enum TwinIcon {
    /// Emoji (without the U+FE0F presentation selector) -> asset name.
    static let assets: [String: String] = [
        "🧴": "icon.lotion",
        "💧": "icon.droplet",
        "📚": "icon.books",
        "👕": "icon.tshirt",
        "🧺": "icon.basket",
        "🏋": "icon.lifter",
        "😴": "icon.sleep",
        "✋": "icon.hand",
        "🏊": "icon.swimmer",
        "🧦": "icon.socks",
        "🥛": "icon.milk",
        "🥜": "icon.peanut",
        "🍤": "icon.shrimp",
        "🍞": "icon.bread",
        "🍷": "icon.wine",
        "🐶": "icon.dog",
        "🧶": "icon.yarn",
        "✈": "icon.plane",
        "✳": "icon.other",
        "⌚": "icon.watch",
        "📦": "icon.package",
        "🌤": "icon.weather",
        "📅": "icon.calendar",
        "🛏": "icon.bed",
        "🔎": "icon.search",
    ]

    /// The asset for an emoji ("🏋️" and "🏋" both match), or nil if there is no drawn icon for it.
    /// The icons live in the iPhone app's catalog only; the watch keeps the emoji.
    static func asset(for emoji: String) -> String? {
        #if os(iOS)
        let key = String(String.UnicodeScalarView(emoji.unicodeScalars.filter { $0.value != 0xFE0F }))
        return assets[key]
        #else
        return nil
        #endif
    }
}

/// An emoji picture: the drawn icon if there is one, otherwise the emoji itself.
/// `size` is the icon's square frame; the drawing has a 2/24 margin, so an icon of size s looks like an emoji
/// set at about s × 0.8 pt (an 11 pt emoji ≈ a 14 pt icon). The fallback text uses that font size.
/// Hidden from VoiceOver: the label next to it says what it is.
struct TwinIconView: View {
    let emoji: String
    var size: CGFloat = 14

    var body: some View {
        Group {
            if let asset = TwinIcon.asset(for: emoji) {
                Image(asset)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
            } else {
                Text(emoji).font(.system(size: (size * 0.8).rounded()))
            }
        }
        .accessibilityHidden(true)
    }
}
