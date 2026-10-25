import SwiftUI
import EczemaKit

/// The app frame: the three tab pages, the tab bar, and what floats above them ("What it can read"
/// from the avatar, the HUD toast).
struct RootView: View {
    @EnvironmentObject var app: AppState
    @StateObject private var services = ShellServices()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The page on screen. It follows `app.tab` one run-loop later so the outgoing page can pick up
    /// the new slide direction before it leaves (otherwise SwiftUI uses the stale transition).
    @State private var shown: Tab?
    @State private var direction: CGFloat = 1

    var body: some View {
        let current = shown ?? app.tab
        ZStack(alignment: .bottom) {
            Twin.Palette.paper.ignoresSafeArea()

            // A still copy of the yellow frame behind the pages: while a page slides 24 pt sideways
            // its top bar never reveals a white strip at the screen edge.
            VStack(spacing: 0) {
                TopBar(title: " ", subtitle: " ").accessibilityHidden(true)
                Spacer(minLength: 0)
            }

            // Two-page slide + crossfade: the ForEach diff plays the outgoing page's removal and
            // the incoming page's insertion together. Each page fades as one flattened layer, so
            // its white paper never washes over the still yellow frame (the bar stays solid).
            ZStack {
                ForEach([current], id: \.self) { tab in
                    page(tab)
                        .compositingGroup()
                        .transition(pageTransition)
                }
            }

            TwinTabBar()
        }
        .ignoresSafeArea(.keyboard)
        // VoiceOver stays on the permissions page while it covers the tabs.
        .accessibilityHidden(app.showPermissions)
        .overlay { PermissionsHost() }
        // Above the tab bar, never over a top bar's title or the avatar (prototype `.toast`).
        .overlay(alignment: .bottom) { ShellToastHost() }
        // A toast from anywhere (`NotificationCenter.default.postTwinToast(_:)`).
        .onReceive(NotificationCenter.default.publisher(for: .twinToast).receive(on: DispatchQueue.main)) { note in
            if let text = note.userInfo?["text"] as? String { services.toasts.show(text) }
        }
        .shellEnvironment(app, services)
        .onAppear {
            if shown == nil { shown = app.tab }
            services.attach(app)
        }
        .onChange(of: app.tab) { old, new in turnPage(from: old, to: new) }
    }

    @ViewBuilder private func page(_ tab: Tab) -> some View {
        switch tab {
        case .today: SummaryScreen()
        case .trends: TrendsScreen()
        case .insight: InsightScreen()
        }
    }

    private var pageTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .offset(x: direction * 24).combined(with: .opacity),
            removal: .offset(x: -direction * 24).combined(with: .opacity))
    }

    private func turnPage(from old: Tab, to new: Tab) {
        let all = Tab.allCases
        direction = (all.firstIndex(of: new) ?? 0) > (all.firstIndex(of: old) ?? 0) ? 1 : -1
        DispatchQueue.main.async {
            withAnimation(reduceMotion ? .easeInOut(duration: 0.22) : Twin.Motion.slide) { shown = new }
        }
    }
}

extension View {
    /// Everything the shell's screens read from the environment.
    func shellEnvironment(_ app: AppState, _ services: ShellServices) -> some View {
        self
            .environmentObject(app)
            .environmentObject(services)
            .environmentObject(services.toasts)
            .environmentObject(services.access)
            .environmentObject(services.watch)
    }
}
