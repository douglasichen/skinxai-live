import SwiftUI
import EczemaKit

/// Trends — the data over time, no commentary. Every number comes from `StageStory` and its longer
/// history `StageHistory` (74 nights).
///
/// - Range picker (7 nights · All time).
/// - One big chart: scratching per night as bars (All time scrolls sideways), the purchases as pink
///   icons on their dates just above the date axis, the exam weeks as a light labelled band.
/// - Overlay chips (None · Sleep · Humidity · Temp · Stress): the picked factor is drawn over the bars
///   as a bold line on its own axis at the right. Each chip shows the selected night's value.
/// - Tap a night → a cyan column and the strip under the chart (minutes, sleep, humidity, temp, HRV,
///   what he bought that day). Tap a purchase → its sheet (item, date, ingredients, the 4 nights after).
struct TrendsScreen: View {
    @EnvironmentObject var app: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// All time by default: the calm weeks make the flares stand out.
    @State private var range: TrendsRange = TodayTrendsLaunch.trendsRange ?? .all
    /// The selected night (0 = oldest of the story's 14 … 13 = last night; earlier nights negative).
    @State private var selected = StageStory.lastNightIndex
    /// The factor drawn over the bars.
    @State private var overlay: TrendsOverlay = TrendsLaunch.overlay ?? .none
    /// The event whose sheet is open.
    @State private var openEvent: TrendsEvent?
    /// Night dates are relative to now; moves on at midnight while the app stays open.
    @State private var now = Date()

    var body: some View {
        ScreenScaffold(title: "Trends", subtitle: range.subtitle) {
            UserAvatar()
        } content: {
            ScrollViewReader { proxy in
                VStack(alignment: .leading, spacing: Twin.Space.m) {
                    section(0) {
                        ChartRangePicker(options: TrendsRange.allCases, selection: rangeBinding, title: \.title)
                    }
                    section(1) { chartCard(now) }
                        .id("trends-chart")
                    section(2) {
                        TrendsNightStrip(night: TrendsStory.detail(selected, now: now)) { event in
                            Haptics.tap()
                            openEvent = event
                        }
                    }
                    Color.clear.frame(height: 1).id("trends-bottom")
                }
                .onAppear { TodayTrendsLaunch.scrollForScreenshot(proxy, bottomID: "trends-bottom") }
            }
        }
        .onNewDay { now = Date() }
        .sheet(item: $openEvent) { event in
            TrendsEventSheet(detail: TrendsEventDetail(event, now: now)) {
                app.select(.insight)
            }
        }
        .task {
            // `-trendsSelect 5` (debug): select a night after the entrance, as if it had been tapped.
            if let night = TrendsLaunch.select {
                try? await Task.sleep(for: .seconds(1.6))
                select(night)
            }
            // `-trendsEvent bodywash` (debug): open an event's sheet.
            if let id = TrendsLaunch.event, let event = TrendsEvent.find(id) {
                try? await Task.sleep(for: .seconds(1.2))
                openEvent = event
            }
        }
    }

    private func section<V: View>(_ i: Int, @ViewBuilder _ content: () -> V) -> some View {
        content().riseIn(0.05 + Double(i) * 0.1, distance: reduceMotion ? 0 : 16)
    }

    // MARK: Selection

    private var rangeBinding: Binding<TrendsRange> {
        Binding(get: { range }, set: { setRange($0) })
    }

    /// Changes the range; the selected night stays selected only while the new range shows it.
    private func setRange(_ new: TrendsRange) {
        range = new
        if !new.shows(selected) { selected = StageStory.lastNightIndex }
    }

    /// Selects night `i`, widening the range when it is not on the chart.
    private func select(_ i: Int) {
        guard TrendsStory.nightIDs.contains(i) else { return }
        withAnimation(Twin.Motion.spring) {
            if !range.shows(i) { range = .all }
            selected = i
        }
    }

    // MARK: Chart card

    private func chartCard(_ now: Date) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text("Scratching")
                if overlay != .none {
                    Text(" vs \(overlay.title.lowercased())")
                        .foregroundStyle(Twin.Palette.inkMuted)
                        .transition(.opacity)
                }
                Spacer(minLength: 0)
            }
            .font(Twin.Typeface.headline)
            .foregroundStyle(Twin.Palette.ink)
            .accessibilityAddTraits(.isHeader)
            TrendsOverlayChips(selection: $overlay, night: selected)
                .padding(.top, 10)
            OverlayBarChart(nights: TrendsStory.nights(range, overlay: overlay, now: now), overlay: overlay.chart,
                            bands: TrendsStory.bands(range), markers: TrendsStory.markers(range),
                            usual: Double(StageStory.usual), scaleTop: TrendsStory.scaleTop,
                            gridSteps: TrendsStory.gridSteps, selection: $selected, window: 22,
                            plotHeight: 236, delay: 0.25) { id in
                Haptics.tap()
                openEvent = TrendsEvent.find(id)
            }
            .id(range)
            .transition(.opacity)
            .padding(.top, 14)
            TrendsKey()
                .padding(.top, 10)
                .riseIn(0.9, distance: 0)
        }
        .twinCard(padding: 12)
    }
}
