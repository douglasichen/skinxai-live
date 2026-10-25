import SwiftUI
import EczemaKit

/// Summary — is my eczema normal, is it getting worse, what might be behind it (STAGE-SPEC §3,
/// redesigned for a 3-second read). Every number comes from `StageStory`.
///
/// Top to bottom: the status card (flare in red, normal in lime), the last 7 nights against your
/// usual, the possible triggers with the way to Insight (flare only), the factors as six tiles, and
/// last night in quarter hours. The top bar has the live pill (only while the watch tracks sleep)
/// next to the avatar.
///
/// Sections rise in one after another, numbers count up, the bars grow. When he wakes up (the
/// watch's Stop, `LiveSession.wokeUp`), the sections play their entrance again once Summary is back
/// on screen: last night is ready. A few seconds of network silence never do that.
struct SummaryScreen: View {
    @EnvironmentObject var app: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Bumped to play the entrance again.
    @State private var entrance = 0
    /// Summary is on screen (not covered by the live monitor, not on another tab).
    @State private var onScreen = false
    /// He woke up while the live monitor covered Summary: replay when Summary is back.
    @State private var replayWhenBack = false
    /// Hides the sections while they wait for that replay, so the monitor dissolves into an empty
    /// page that fills in, not into last night's card that then blanks and starts over.
    @State private var heldForReplay = false
    /// The date in the top bar; moves on at midnight while the app stays open.
    @State private var now = Date()

    var body: some View {
        ScreenScaffold(title: "Summary", subtitle: TodayStory.topBarDate(now)) {
            HStack(spacing: 10) {
                LivePill()
                UserAvatar()
            }
        } content: {
            ScrollViewReader { proxy in
                VStack(alignment: .leading, spacing: 0) {
                    Color.clear.frame(height: 0).id("today-top")
                    sections
                        .id(entrance)
                        .opacity(heldForReplay ? 0 : 1)
                    // No height: the last card keeps the prototype's 26 pt above the tab bar.
                    Color.clear.frame(height: 0).id("today-bottom")
                }
                .onAppear {
                    onScreen = true
                    TodayTrendsLaunch.scrollForScreenshot(proxy, bottomID: "today-bottom")
                    if replayWhenBack {
                        replayWhenBack = false
                        // The monitor is already gone and the phone upright (the presenter turns it
                        // back before it dismisses): rise in while the page dissolves in.
                        replay(proxy, after: 0.05)
                    }
                }
                .onDisappear { onScreen = false }
                .onNewDay { now = Date() }
                // Only the watch's Stop is waking up (a Wi-Fi stall in the night is not).
                .onReceive(LiveSession.shared.wokeUp) { _ in
                    // He woke up: last night is ready.
                    if onScreen {
                        replay(proxy, after: 0.9)
                    } else {
                        replayWhenBack = true
                        heldForReplay = true
                        // Safety: never leave Summary blank if it doesn't get its onAppear back
                        // (the monitor takes about 1 s to close).
                        Task { @MainActor in
                            try? await Task.sleep(for: .seconds(3))
                            guard heldForReplay, replayWhenBack else { return }
                            replayWhenBack = false
                            replay(proxy, after: 0)
                        }
                    }
                }
            }
        }
    }

    private var sections: some View {
        let story = SummaryStory.current(now: now)
        return VStack(alignment: .leading, spacing: Twin.Space.m) {
            section(0) { SummaryStatusCard(story: story) }
            section(1) { SummaryWeekCard(story: story) }
            if story.status == .flare {
                section(2) {
                    // The things that changed; Claude narrows them down on Insight.
                    SummaryTriggersCard(story: story) { app.select(.insight) }
                }
                .id("summary-triggers")
            }
            section(3) { SummaryFactorsCard(story: story) }
                .id("summary-factors")
            if story.hasNightDetail {
                section(4) { SummaryNightCard() }
            }
        }
    }

    /// Entrance choreography: each section rises in after the previous one (fade only with Reduce Motion).
    private func section<V: View>(_ i: Int, @ViewBuilder _ content: () -> V) -> some View {
        content().riseIn(0.05 + Double(i) * 0.1, distance: reduceMotion ? 0 : 16)
    }

    /// Plays the entrance again (from the top) after `delay`, once the monitor is gone and the phone is upright.
    private func replay(_ proxy: ScrollViewProxy, after delay: Double) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            proxy.scrollTo("today-top", anchor: .top)
            entrance += 1
            heldForReplay = false        // the new sections start hidden and rise in
        }
    }
}
