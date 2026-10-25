import SwiftUI

/// Yellow frame top bar of a top-level page (Raft: yellow only on the frame).
struct TopBar<Trailing: View>: View {
    var title: String
    var subtitle: String?
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Twin.Typeface.largeTitle).foregroundStyle(Twin.Palette.ink)
                if let subtitle {
                    Text(subtitle.uppercased()).font(Twin.Typeface.meta).tracking(0.6).foregroundStyle(Twin.Palette.frameInk)
                }
            }
            Spacer(minLength: 12)
            trailing()
        }
        .padding(.horizontal, Twin.Space.screen + 4)
        .padding(.top, 6)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity)
        .background(alignment: .bottom) {
            Twin.Palette.frame
                .overlay(alignment: .bottom) { Rectangle().fill(Twin.Palette.seam).frame(height: 1) }
                .ignoresSafeArea(edges: .top)
        }
    }
}

extension TopBar where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

/// Standard top-level page: frame top bar + scrolling paper content that clears the tab bar.
struct ScreenScaffold<Trailing: View, Content: View>: View {
    var title: String
    var subtitle: String?
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            TopBar(title: title, subtitle: subtitle, trailing: trailing)
            ScrollView {
                VStack(alignment: .leading, spacing: Twin.Space.m) { content() }
                    .padding(.horizontal, Twin.Space.screen)
                    .padding(.top, Twin.Space.l)
                    // The tab bar (~60 pt above the home indicator) + the prototype's 26 pt gap.
                    .padding(.bottom, 86)
            }
            .scrollIndicators(.hidden)
        }
        .background(Twin.Palette.paper)
    }
}

/// Square initial avatar (the user, Douglas), used in top bars. Opens "What it can read".
struct UserAvatar: View {
    @EnvironmentObject var app: AppState
    /// The person whose skin this is (the greeting, the toasts and the avatar all say Douglas).
    static let name = "Douglas"

    var body: some View {
        Button { app.showPermissions = true } label: {
            Text(String(Self.name.prefix(1)))
                .font(Twin.Typeface.sans(15, .bold))
                .foregroundStyle(Twin.Palette.ink)
                .frame(width: 36, height: 36)
                .sticker(Twin.Palette.pink)
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(Self.name)
        .accessibilityHint("Shows what SkinXAI can read")
    }
}
