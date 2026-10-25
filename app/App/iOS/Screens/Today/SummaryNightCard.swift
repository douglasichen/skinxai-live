import SwiftUI
import EczemaKit

/// Last night in detail (small): when he slept, the worst hours and episodes, and the night in 32
/// quarter-hour bars that grow in one after another (the bad stretch orange).
struct SummaryNightCard: View {
    private typealias Last = StageStory.LastNight

    /// A quarter hour with more than this many minutes is part of the bad stretch (orange).
    static let hotQuarterHour = 2.2

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Eyebrow(text: "Last night")
                Spacer(minLength: 8)
                Text("\(Last.asleep) – \(Last.awake)")
                    .font(Twin.Typeface.eyebrow)
                    .tracking(0.3)
                    .foregroundStyle(Twin.Palette.inkHint)
                    .lineLimit(1)
            }

            (Text("Worst ").foregroundColor(Twin.Palette.inkMuted)
                + Text(Last.worst).font(Twin.Typeface.sans(15, .bold)).foregroundColor(Twin.Palette.ink)
                + Text(" · \(Last.episodes)\u{00A0}episodes, \(Last.intense)\u{00A0}intense · woke\u{00A0}up\u{00A0}\(Last.wakeUps)×")
                    .foregroundColor(Twin.Palette.inkMuted))
                .font(Twin.Typeface.sans(15))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)

            QuarterHourChart(values: Last.quarterHours, hotAbove: Self.hotQuarterHour,
                             labels: Self.labels, plotHeight: 58, delay: 0.4)
                .padding(.top, 12)
        }
        .twinCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Last night, \(Last.asleep) to \(Last.awake): worst \(Last.worst). "
                            + "\(Last.episodes) episodes, \(Last.intense) intense. Woke up \(Last.wakeUps) times.")
    }

    /// "11p 1a 3a 5a 7a": every two hours from bedtime to the end of the last hour.
    private static var labels: [QuarterHourChart.AxisLabel] {
        let hours = Last.minutesPerHour.count
        return stride(from: 0, through: hours, by: 2).map { k in
            let h = (Last.firstHour + k) % 24
            let h12 = h % 12 == 0 ? 12 : h % 12
            return QuarterHourChart.AxisLabel(text: "\(h12)\(h < 12 ? "a" : "p")", at: Double(k) / Double(hours))
        }
    }
}
