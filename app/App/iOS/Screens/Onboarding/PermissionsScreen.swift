import SwiftUI

/// Pushes "What it can read" over the tabs (the avatar, `-screen permissions`): it slides in from the
/// right and goes back the same way, by the back button or a swipe from the left edge. With Reduce
/// Motion it fades.
struct PermissionsHost: View {
    @EnvironmentObject var app: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if app.showPermissions {
                PermissionsScreen(backTitle: app.tab.title)
                    .transition(reduceMotion ? .opacity : .move(edge: .trailing))
                    .zIndex(1)
            }
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.25) : Twin.Motion.slide, value: app.showPermissions)
    }
}

/// "What it can read": the last onboarding page. The yellow frame holds a card per source the app
/// reads, each one granted; the white paper below says it's your choice. A small version line closes
/// the page: five taps on it within 1.5 s show (or hide) the hidden controls.
struct PermissionsScreen: View {
    /// The tab under this page ("Today", "Trends"…), for the back button.
    let backTitle: String

    @EnvironmentObject var app: AppState
    @EnvironmentObject var toasts: ShellToasts
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var showControls = Self.controlsAtLaunch
    @State private var versionTaps: [Date] = []
    /// Swipe back from the left edge: how far the page follows the finger.
    @State private var drag: CGFloat = 0
    /// The cards have scrolled under the header (it then shows the frame's seam).
    @State private var scrolled = false

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                header
                ScrollViewReader { scroller in
                    ScrollView {
                        VStack(spacing: 0) {
                            cards
                            choice
                            version
                            if showControls {
                                HiddenControls(reset: resetTonight, replay: replayChat)
                                    .padding(.horizontal, 20)
                                    .padding(.top, 8)
                                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 10)))
                                    .id(Self.controlsID)
                            }
                        }
                        .padding(.bottom, 24)
                    }
                    .modifier(ScrolledUnder(scrolled: $scrolled))
                    .scrollIndicators(.hidden)
                    .scrollBounceBehavior(.basedOnSize)
                    // Still behind the scrolling content: yellow above (pull down), paper below.
                    .background {
                        VStack(spacing: 0) {
                            Twin.Palette.frame
                            Twin.Palette.paper
                        }
                    }
                    .onChange(of: showControls) { _, shown in
                        if shown { reveal(scroller, after: 0.05) }
                    }
                    .onAppear {
                        if showControls { reveal(scroller, after: 0.5) }
                    }
                }
            }
            .background(Twin.Palette.paper)
            .offset(x: drag)
            .overlay(alignment: .leading) { edgeSwipe(width: proxy.size.width) }
        }
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape, close)
    }

    // MARK: Parts

    /// Back to the tab (left) and the brand mark (right), on the frame.
    private var header: some View {
        HStack {
            Button(action: close) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left").font(.system(size: 16, weight: .semibold))
                    Text(backTitle).font(Twin.Typeface.sans(15, .semibold))
                }
                .foregroundStyle(Twin.Palette.ink)
                .padding(.trailing, 8)
                .frame(height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Back to \(backTitle)")
            Spacer()
            BrandMark()
        }
        .padding(.horizontal, 20)
        .frame(height: 44)
        .background(alignment: .bottom) {
            Twin.Palette.frame.ignoresSafeArea(edges: .top)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Twin.Palette.seam).frame(height: 1).opacity(scrolled ? 1 : 0)
        }
        .zIndex(1)
    }

    /// The cards on the yellow frame.
    private var cards: some View {
        PermissionCards()
            .frame(maxWidth: 370)
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 22)
            .frame(maxWidth: .infinity)
            .background(alignment: .bottom) {
                Twin.Palette.frame
                    .overlay(alignment: .bottom) { Rectangle().fill(Twin.Palette.seam).frame(height: 1) }
            }
    }

    /// Eyebrow, title and body on the white paper (the onboarding page's text).
    private var choice: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("YOUR CHOICE")
                .font(Twin.Typeface.eyebrow)
                .tracking(0.8)
                .foregroundStyle(Twin.Palette.inkHint)
                .riseIn(0.24, distance: reduceMotion ? 0 : 14)
            Text("You decide what it can read.")
                .font(Twin.Typeface.sans(30, .bold))
                .tracking(-0.9)
                .foregroundStyle(Twin.Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .riseIn(0.30, distance: reduceMotion ? 0 : 14)
            Text("Claude only reads what you turn on here, and only when you ask.")
                .font(Twin.Typeface.sans(16))
                .lineSpacing(3)
                .foregroundStyle(Twin.Palette.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
                .riseIn(0.36, distance: reduceMotion ? 0 : 14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .background(Twin.Palette.paper)
    }

    /// "SkinXAI 1.0 (10)", from the bundle. Also the hidden gesture's target.
    private var version: some View {
        VStack(spacing: 4) {
            Text("Making skin great again.")
                .font(Twin.Typeface.sans(13, .semibold))
                .foregroundStyle(Twin.Palette.inkMuted)
            Text(Self.versionLine)
                .font(Twin.Typeface.mono(11))
                .foregroundStyle(Twin.Palette.inkHint)
        }
            .frame(maxWidth: .infinity)
            .padding(.top, 16)
            .padding(.bottom, 4)
            .contentShape(Rectangle())
            .onTapGesture(perform: versionTapped)
            .background(Twin.Palette.paper)
            .riseIn(0.42, distance: 0)
    }

    private func edgeSwipe(width: CGFloat) -> some View {
        Color.clear
            .frame(width: 22)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 8, coordinateSpace: .global)
                    .onChanged { value in drag = max(0, value.translation.width) }
                    .onEnded { value in
                        let travel = max(value.translation.width, value.predictedEndTranslation.width)
                        if travel > width * 0.4 {
                            close()
                        } else {
                            withAnimation(Twin.Motion.spring) { drag = 0 }
                        }
                    })
            .accessibilityHidden(true)
    }

    // MARK: Actions

    private func close() {
        app.showPermissions = false
    }

    /// Brings the hidden controls into view once they are laid out.
    private func reveal(_ scroller: ScrollViewProxy, after delay: Double) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            withAnimation(Twin.Motion.spring) { scroller.scrollTo(Self.controlsID, anchor: .bottom) }
        }
    }

    private func versionTapped() {
        let now = Date()
        versionTaps = versionTaps.filter { now.timeIntervalSince($0) < 1.5 } + [now]
        guard versionTaps.count >= 5 else { return }
        versionTaps = []
        Haptics.tap()
        withAnimation(reduceMotion ? .easeInOut(duration: 0.25) : Twin.Motion.spring) { showControls.toggle() }
    }

    private func resetTonight() {
        NotificationCenter.default.post(name: .twinResetTonight, object: nil)
        toasts.show("Tonight’s count reset")
    }

    /// Insight listens from an object that lives longer than its screen, so the replay is posted
    /// before the tab changes.
    private func replayChat() {
        NotificationCenter.default.post(name: .twinReplayChat, object: nil)
        app.showPermissions = false
        app.select(.insight, haptic: false)
    }

    // MARK: Constants

    private static let controlsID = "hidden-controls"

    static var versionLine: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? ""
        return build.isEmpty ? "SkinXAI \(version)" : "SkinXAI \(version) (\(build))"
    }

    /// `-showDemoCard 1` (Debug builds only): the hidden controls show from the start (screenshots).
    private static var controlsAtLaunch: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "showDemoCard")
        #else
        false
        #endif
    }
}

/// Sets `scrolled` while the content is scrolled up under the header (iOS 18 and later; on iOS 17
/// the header simply never shows its seam).
private struct ScrolledUnder: ViewModifier {
    @Binding var scrolled: Bool

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top > 1
            } action: { _, under in
                withAnimation(.easeOut(duration: 0.15)) { scrolled = under }
            }
        } else {
            content
        }
    }
}

/// The hidden controls (dashed card): reset tonight's count, replay the last Claude chat offline.
private struct HiddenControls: View {
    let reset: () -> Void
    let replay: () -> Void
    /// The live monitor's view: "graph" (wrist motion) or "bars" (the watch's decision only).
    @AppStorage("liveView") private var liveView = "graph"
    // TEMPORARY tuning knobs for the live graph (IntensityMeter).
    @AppStorage("meterWindow") private var meterWindow = 12
    @AppStorage("meterEasing") private var meterEasing = 0.15

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Neutral on purpose: the phone is mirrored to the big screen if this is ever used on stage.
            Eyebrow(text: "Advanced")
                .padding(.bottom, 6)
            row("Reset tonight’s count", button: "Reset", action: reset)
            row("Replay last Claude chat (offline)", button: "Replay", action: replay)
            row(liveView == "bars" ? "Live view: bars" : "Live view: graph",
                button: liveView == "bars" ? "Use graph" : "Use bars") {
                liveView = liveView == "bars" ? "graph" : "bars"
            }
            knob("Smoothing window", value: String(format: "%d values · %.2f s", meterWindow, Double(meterWindow) / 25)) {
                Slider(value: Binding(get: { Double(meterWindow) }, set: { meterWindow = Int($0.rounded()) }), in: 2...50, step: 1)
            }
            knob("Easing (lower = smoother)", value: String(format: "%.2f", meterEasing)) {
                Slider(value: $meterEasing, in: 0.02...0.5)
            }
            Button("Reset knobs") { meterWindow = 12; meterEasing = 0.15 }
                .font(Twin.Typeface.sans(13, .bold))
                .padding(.top, 6)
        }
        .padding(Twin.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Twin.Palette.paper, in: RoundedRectangle(cornerRadius: Twin.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Twin.Radius.card, style: .continuous)
                .strokeBorder(Twin.Palette.seam, style: StrokeStyle(lineWidth: Twin.Stroke.ink, dash: [5, 4]))
        )
    }

    private func knob<S: View>(_ title: String, value: String, @ViewBuilder slider: () -> S) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(Twin.Typeface.sans(14)).foregroundStyle(Twin.Palette.ink)
                Spacer()
                Text(value).font(Twin.Typeface.mono(12)).foregroundStyle(Twin.Palette.inkHint)
            }
            slider().tint(Twin.Palette.orange)
        }
        .padding(.vertical, 8)
        .overlay(alignment: .top) { Rectangle().fill(Twin.Palette.hairline).frame(height: 1) }
    }

    private func row(_ title: String, button: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(Twin.Typeface.sans(14))
                .foregroundStyle(Twin.Palette.ink)
            Spacer(minLength: 8)
            Button(action: action) {
                Text(button).font(Twin.Typeface.sans(14, .bold))
            }
            .buttonStyle(TwinButtonStyle(fill: Twin.Palette.paper, height: 30, fullWidth: false))
        }
        .padding(.vertical, 8)
        .overlay(alignment: .top) { Rectangle().fill(Twin.Palette.hairline).frame(height: 1) }
    }
}
