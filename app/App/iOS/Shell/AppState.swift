import SwiftUI
import EczemaKit

enum Tab: String, CaseIterable, Identifiable {
    case today, trends, insight
    var id: String { rawValue }
    var title: String {
        switch self { case .today: "Summary"; case .trends: "Trends"; case .insight: "Insight" }
    }
    /// SF Symbol for the tab bar.
    var icon: String {
        switch self {
        case .today: "heart.text.square.fill"
        case .trends: "chart.bar.fill"
        case .insight: "sparkle"
        }
    }
}

/// App-wide state. Screens read `dataset` and call the intents below.
///
/// Launch arguments (used by scripts/shot):
///   -screen today|trends|insight|permissions
///   -showDemoCard 1     Debug builds: "What it can read" opens with its hidden controls showing
@MainActor
final class AppState: ObservableObject {
    @Published var tab: Tab = .today
    /// Direction of the last tab change (for slide transitions): +1 = to the right.
    @Published private(set) var tabDirection: Int = 1
    /// "What it can read" (the avatar): the permissions page, pushed over the tabs.
    @Published var showPermissions = false
    @Published private(set) var dataset: TwinDataset

    init() {
        let now = Date()
        dataset = DemoData.make(today: now, revealThroughHour: DemoData.storyRevealHour(at: now))
        if let screen = UserDefaults.standard.string(forKey: "screen") { route(screen) }
    }

    func route(_ screen: String) {
        switch screen {
        case "today", "trends", "insight": tab = Tab(rawValue: screen)!
        case "permissions": showPermissions = true
        default: break
        }
    }

    /// Switches tabs. `haptic: false` when the caller already gave feedback (a success haptic, or a
    /// button that tapped on press). Even with `haptic: true` a touch only taps once: if a button's
    /// press tap just fired for this touch, it stands in for the tab tap.
    func select(_ new: Tab, haptic: Bool = true) {
        guard new != tab else { return }
        let all = Tab.allCases
        tabDirection = (all.firstIndex(of: new)! > all.firstIndex(of: tab)!) ? 1 : -1
        if haptic { tapOncePerTouch() }
        withAnimation(Twin.Motion.slide) { tab = new }
    }

    /// The press tap that last stood in for a tab tap (each press tap is used once).
    private var absorbedTap: Date = .distantPast

    private func tapOncePerTouch() {
        let last = Haptics.lastTapAt
        if Date().timeIntervalSince(last) < 0.5, last != absorbedTap {
            absorbedTap = last
            return
        }
        Haptics.tap()
        absorbedTap = Haptics.lastTapAt
    }

    /// Replace the dataset.
    func update(_ change: (inout TwinDataset) -> Void) {
        var d = dataset
        change(&d)
        withAnimation(Twin.Motion.spring) { dataset = d }
    }
}
