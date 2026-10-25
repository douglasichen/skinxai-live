import SwiftUI

/// Eczema Twin design tokens. Colors, type and shapes follow the Raft design language
/// (raft-ui): a yellow frame, white paper for content, ink (#141111) for text and edges,
/// "stickers" (a block of brand color with a 1.5pt ink edge and ink text), square-ish corners.
/// Motion is our own and much richer than raft-ui (see `Twin.Motion`).
///
/// Color meanings (keep them; a color on screen always means something):
/// - yellow: you / where you are / the selected thing
/// - pink:   to do / the main call to action
/// - cyan:   this item / progress
/// - orange: warning, a flare, "above your usual"
/// - lime:   good / improving / confirmed
/// - red:    danger, see a doctor
enum Twin {
    enum Palette {
        static let ink = Color(hex: 0x141111)
        static let inkMuted = Color(hex: 0x141111, alpha: 0.68)
        static let inkHint = Color(hex: 0x141111, alpha: 0.55)
        static let inkFaint = Color(hex: 0x141111, alpha: 0.30)
        static let hairline = Color(hex: 0x141111, alpha: 0.15)
        static let seam = Color(hex: 0x141111, alpha: 0.45)

        static let frame = Color(hex: 0xFFD440)
        static let frameInk = Color(hex: 0x564919)
        static let paper = Color.white
        static let cream = Color(hex: 0xFFFAEF)
        static let fill = Color(hex: 0xF3F3F3)
        static let fillStrong = Color(hex: 0xEAEAEA)
        static let hud = Color(hex: 0x252429)

        static let yellow = Color(hex: 0xFFD440)
        static let yellowSoft = Color(hex: 0xFFF0BD)
        static let pink = Color(hex: 0xFE7DA8)
        static let pinkSoft = Color(hex: 0xFFD6E2)
        static let pinkStrong = Color(hex: 0xC00064)
        static let cyan = Color(hex: 0x27CCF3)
        static let cyanSoft = Color(hex: 0xD7F2FE)
        static let cyanStrong = Color(hex: 0x06414F)
        static let orange = Color(hex: 0xF8A16F)
        static let orangeSoft = Color(hex: 0xFDE6DE)
        static let orangeStrong = Color(hex: 0x5B310F)
        static let lime = Color(hex: 0xA9D877)
        static let limeSoft = Color(hex: 0xDCFAC1)
        static let limeStrong = Color(hex: 0x344522)
        static let red = Color(hex: 0xF97264)
        static let redSoft = Color(hex: 0xFDDEDD)
        static let redStrong = Color(hex: 0xB5321A)

        /// Watch surfaces (watchOS is dark).
        static let night = Color.black
        static let nightCard = Color(hex: 0x1C1C1E)
        static let nightTrack = Color(hex: 0x2A2A2A)
        static let nightMuted = Color.white.opacity(0.62)
    }

    enum Radius {
        static let sticker: CGFloat = 3   // avatars, badges, square tiles
        static let chip: CGFloat = 4      // chips, controls inside another frame
        static let control: CGFloat = 6   // buttons, inputs, tab sticker
        static let card: CGFloat = 10     // cards, banners, sheets' content blocks
        static let dialog: CGFloat = 16   // top corners of bottom sheets, dialogs
    }

    enum Stroke {
        static let hairline: CGFloat = 1   // lines inside content, card outlines
        static let ink: CGFloat = 1.5      // controls, stickers, fields
    }

    enum Space {
        static let xs: CGFloat = 4, s: CGFloat = 8, m: CGFloat = 12, l: CGFloat = 16, xl: CGFloat = 24, xxl: CGFloat = 32
        static let screen: CGFloat = 16    // side padding of phone screens
    }

    enum Typeface {
        /// Space Grotesk (variable font, 300–700). Use for everything people read.
        static func sans(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
            .custom("Space Grotesk", size: size).weight(weight)
        }
        /// Space Mono. Use for what machines write: times, dates, counts, units, IDs, eyebrows.
        static func mono(_ size: CGFloat, bold: Bool = false) -> Font {
            .custom(bold ? "SpaceMono-Bold" : "SpaceMono-Regular", size: size)
        }

        static let display = sans(56, .bold)       // the hero number
        static let largeTitle = sans(28, .bold)    // top bar title
        static let title = sans(22, .bold)
        static let headline = sans(17, .bold)
        static let body = sans(16)
        static let callout = sans(15)
        static let subhead = sans(14)
        static let footnote = sans(13)
        static let caption = sans(12)
        static let eyebrow = mono(11, bold: true)  // UPPERCASE section labels
        static let meta = mono(11)                 // dates, units
    }

    enum Motion {
        /// Default UI spring (cards, chips, selection).
        static let spring = Animation.spring(response: 0.5, dampingFraction: 0.8)
        /// Playful pop (stickers, FAB, confirmations).
        static let bouncy = Animation.spring(response: 0.42, dampingFraction: 0.6)
        /// Slides and sheets (raft-ui ease-slide curve).
        static let slide = Animation.timingCurve(0.22, 0.9, 0.24, 1, duration: 0.38)
        /// Rings and big bars filling.
        static let fill = Animation.timingCurve(0.22, 0.9, 0.24, 1, duration: 1.3)
        /// Stagger step between items appearing one after another.
        static let stagger: Double = 0.07
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: alpha)
    }
}
